import Foundation
@preconcurrency import AVFoundation
import Speech

/// Buffer converter for audio format conversion
internal final class BufferConverter: @unchecked Sendable {
    enum Error: Swift.Error {
        case failedToCreateConverter
        case failedToCreateConversionBuffer
        case conversionFailed(NSError?)
    }
    
    private var converter: AVAudioConverter?
    
    func convertBuffer(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let inputFormat = buffer.format
        guard inputFormat != format else {
            return buffer
        }
        
        if converter == nil || converter?.outputFormat != format {
            converter = AVAudioConverter(from: inputFormat, to: format)
            converter?.primeMethod = .none
        }
        
        guard let converter else {
            throw Error.failedToCreateConverter
        }
        
        let sampleRateRatio = converter.outputFormat.sampleRate / converter.inputFormat.sampleRate
        let scaledInputFrameLength = Double(buffer.frameLength) * sampleRateRatio
        let frameCapacity = AVAudioFrameCount(scaledInputFrameLength.rounded(.up))
        guard let conversionBuffer = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: frameCapacity) else {
            throw Error.failedToCreateConversionBuffer
        }
        
        var nsError: NSError?
        
        // Simple conversion without complex closure state
        let status = converter.convert(to: conversionBuffer, error: &nsError, withInputFrom: { _, _ in
            return buffer
        })
        
        guard status != .error else {
            throw Error.conversionFailed(nsError)
        }
        
        return conversionBuffer
    }
}

internal struct AuralKitEngine: AuralKitEngineProtocol, Sendable {
    let speechAnalyzer: any SpeechAnalyzerProtocol
    let audioEngine: any AudioEngineProtocol
    let modelManager: any ModelManagerProtocol
    let bufferProcessor: any AudioBufferProcessorProtocol
    
    init() {
        self.speechAnalyzer = AuralSpeechAnalyzer()
        self.audioEngine = AuralAudioEngine()
        self.modelManager = AuralModelManager()
        self.bufferProcessor = AuralAudioBufferProcessor()
    }
}

internal actor AuralSpeechAnalyzer: SpeechAnalyzerProtocol {
    private let (stream, continuation) = AsyncStream.makeStream(of: AuralResult.self)
    private var speechAnalyzer: SpeechAnalyzer?
    private var speechTranscriber: SpeechTranscriber?
    private var inputSequence: AsyncStream<AnalyzerInput>?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var recognizerTask: Task<Void, Error>?
    private var bufferConverter = BufferConverter()
    
    nonisolated var results: AsyncStream<AuralResult> {
        stream
    }
    
    func configure(with configuration: AuralConfiguration) async throws {
        // Create transcriber with the specified language
        speechTranscriber = SpeechTranscriber(
            locale: configuration.language.locale,
            transcriptionOptions: [],
            reportingOptions: configuration.includePartialResults ? [.volatileResults] : [],
            attributeOptions: configuration.includeTimestamps ? [.audioTimeRange] : []
        )
        
        guard let speechTranscriber else {
            throw AuralError.recognitionFailed
        }
        
        // Create analyzer with the transcriber
        speechAnalyzer = SpeechAnalyzer(modules: [speechTranscriber])
        
        // Set up input stream
        (inputSequence, inputBuilder) = AsyncStream<AnalyzerInput>.makeStream()
    }
    
    func startAnalysis() async throws {
        guard let speechAnalyzer, let speechTranscriber, let inputSequence else {
            throw AuralError.recognitionFailed
        }
        
        // Start the analyzer
        try await speechAnalyzer.start(inputSequence: inputSequence)
        
        // Start processing results
        recognizerTask = Task { [weak self] in
            guard let self else { return }
            
            do {
                for try await result in speechTranscriber.results {
                    let auralResult = AuralResult(
                        text: String(result.text.characters),
                        confidence: 1.0, // SpeechTranscriber doesn't provide confidence in the new API
                        isPartial: !result.isFinal,
                        timestamp: 0 // Will be populated if audioTimeRange is available
                    )
                    
                    await self.yieldResult(auralResult)
                }
            } catch {
                // Handle speech recognition errors
                print("Speech recognition error: \(error)")
            }
        }
    }
    
    func stopAnalysis() async throws {
        recognizerTask?.cancel()
        recognizerTask = nil
        inputBuilder?.finish()
    }
    
    func finishAnalysis() async throws {
        inputBuilder?.finish()
        try await speechAnalyzer?.finalizeAndFinishThroughEndOfInput()
        recognizerTask?.cancel()
        recognizerTask = nil
        continuation.finish()
    }
    
    func processAudioBuffer(_ buffer: AVAudioPCMBuffer) async throws {
        guard let inputBuilder else {
            throw AuralError.audioSetupFailed
        }
        
        // Get the best available format for the speech analyzer
        guard let speechTranscriber,
              let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [speechTranscriber]) else {
            throw AuralError.audioSetupFailed
        }
        
        // Convert buffer to the required format
        let convertedBuffer = try bufferConverter.convertBuffer(buffer, to: analyzerFormat)
        
        // Create analyzer input and yield it
        let input = AnalyzerInput(buffer: convertedBuffer)
        inputBuilder.yield(input)
    }
    
    private func yieldResult(_ result: AuralResult) {
        continuation.yield(result)
    }
}

/// Dedicated audio processor that handles ALL audio operations within a single actor
/// This ensures AVAudioPCMBuffer never crosses actor boundaries, avoiding Sendable issues
internal actor AuralAudioProcessor {
    private let audioEngine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var speechAnalyzer: AuralSpeechAnalyzer?
    private let bufferConverter = BufferConverter()
    
    var audioFormat: AVAudioFormat? {
        audioEngine.inputNode.outputFormat(forBus: 0)
    }
    
    var isRecording = false
    
    func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }
    
    func startRecording(with speechAnalyzer: AuralSpeechAnalyzer) async throws {
        guard !isRecording else { return }
        
        self.speechAnalyzer = speechAnalyzer
        
        #if os(iOS)
        try setUpAudioSession()
        #endif
        
        try setupAudioEngine()
        
        // Install tap and process buffers with immediate conversion to avoid Sendable issues
        audioEngine.inputNode.installTap(
            onBus: 0,
            bufferSize: 4096,
            format: audioEngine.inputNode.outputFormat(forBus: 0)
        ) { [weak self, weak speechAnalyzer] buffer, time in
            // Convert buffer synchronously within callback to avoid actor boundary issues
            guard let self, let speechAnalyzer else { return }
            
            // Extract raw audio data synchronously to pass across boundaries
            let frameLength = buffer.frameLength
            let format = buffer.format
            
            // Copy audio data synchronously within the callback
            let data = Data(bytes: buffer.floatChannelData![0], count: Int(frameLength) * MemoryLayout<Float>.size)
            
            Task {
                await self.processAudioData(data, frameLength: frameLength, format: format, speechAnalyzer: speechAnalyzer)
            }
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true
    }
    
    func stopRecording() async throws {
        guard isRecording else { return }
        
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        speechAnalyzer = nil
        isRecording = false
    }
    
    func pauseRecording() async throws {
        guard isRecording else { return }
        audioEngine.pause()
    }
    
    func resumeRecording() async throws {
        guard isRecording else { return }
        try audioEngine.start()
    }
    
    #if os(iOS)
    private func setUpAudioSession() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .spokenAudio)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
    }
    #endif
    
    private func setupAudioEngine() throws {
        // Create temporary file for recording
        let url = FileManager.default.temporaryDirectory
            .appending(component: UUID().uuidString)
            .appendingPathExtension(for: .wav)
        
        let inputSettings = audioEngine.inputNode.inputFormat(forBus: 0).settings
        audioFile = try AVAudioFile(forWriting: url, settings: inputSettings)
        
        audioEngine.inputNode.removeTap(onBus: 0)
    }
    
    /// Process audio buffer entirely within this actor - no Sendable violations!
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) async {
        do {
            // Write to file if available
            try audioFile?.write(from: buffer)
            
            // Process the buffer for speech recognition
            // Buffer never leaves this actor, so no Sendable issues
            if let speechAnalyzer {
                try await speechAnalyzer.processAudioBuffer(buffer)
            }
        } catch {
            print("Audio buffer processing error: \(error)")
        }
    }
    
    /// Process audio data that was extracted synchronously from the callback
    func processAudioData(_ data: Data, frameLength: AVAudioFrameCount, format: AVAudioFormat, speechAnalyzer: AuralSpeechAnalyzer) async {
        do {
            // Reconstruct buffer within the actor from the copied data
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameLength) else {
                print("Failed to create audio buffer")
                return
            }
            
            buffer.frameLength = frameLength
            
            // Copy data back to buffer
            data.withUnsafeBytes { bytes in
                let floatPtr = bytes.bindMemory(to: Float.self)
                buffer.floatChannelData![0].update(from: floatPtr.baseAddress!, count: Int(frameLength))
            }
            
            // Now process within actor
            try audioFile?.write(from: buffer)
            try await speechAnalyzer.processAudioBuffer(buffer)
            
        } catch {
            print("Audio data processing error: \(error)")
        }
    }
}

/// Simplified audio engine protocol that works with the dedicated processor
internal actor AuralAudioEngine: AudioEngineProtocol {
    private let processor = AuralAudioProcessor()
    
    var audioFormat: AVAudioFormat? {
        get async {
            await processor.audioFormat
        }
    }
    
    var isRecording: Bool {
        get async {
            await processor.isRecording
        }
    }
    
    func requestPermission() async -> Bool {
        await processor.requestPermission()
    }
    
    func startRecording() async throws {
        // This will be handled by the speech analyzer calling processor directly
        throw AuralError.audioSetupFailed
    }
    
    func stopRecording() async throws {
        try await processor.stopRecording()
    }
    
    func pauseRecording() async throws {
        try await processor.pauseRecording()
    }
    
    func resumeRecording() async throws {
        try await processor.resumeRecording()
    }
    
    /// Get access to the audio processor for direct integration
    nonisolated func getProcessor() -> AuralAudioProcessor {
        processor
    }
}

internal actor AuralModelManager: ModelManagerProtocol {
    func isModelAvailable(for language: AuralLanguage) async -> Bool {
        let installed = await Set(SpeechTranscriber.installedLocales)
        return installed.map { $0.identifier(.bcp47) }.contains(language.locale.identifier(.bcp47))
    }
    
    func downloadModel(for language: AuralLanguage) async throws {
        // Check if the locale is supported
        let supported = await SpeechTranscriber.supportedLocales
        guard supported.map({ $0.identifier(.bcp47) }).contains(language.locale.identifier(.bcp47)) else {
            throw AuralError.unsupportedLanguage
        }
        
        // Create a temporary transcriber to get the download request
        let tempTranscriber = SpeechTranscriber(
            locale: language.locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: []
        )
        
        // Check if download is needed
        if let downloader = try await AssetInventory.assetInstallationRequest(supporting: [tempTranscriber]) {
            do {
                try await downloader.downloadAndInstall()
            } catch {
                throw AuralError.networkError
            }
        }
    }
    
    func getDownloadProgress(for language: AuralLanguage) async -> Double? {
        // This would require maintaining a reference to the downloader
        // For now, return nil as the actual progress tracking would need to be 
        // implemented at a higher level
        return nil
    }
    
    func getSupportedLanguages() async -> [AuralLanguage] {
        let supportedLocales = await SpeechTranscriber.supportedLocales
        
        // Map supported locales to AuralLanguage cases
        var languages: [AuralLanguage] = []
        
        for locale in supportedLocales {
            switch locale.identifier(.bcp47) {
            case "en-US":
                languages.append(.english)
            case "es-ES":
                languages.append(.spanish)
            case "fr-FR":
                languages.append(.french)
            case "de-DE":
                languages.append(.german)
            case "zh-CN":
                languages.append(.chinese)
            default:
                languages.append(.custom(locale))
            }
        }
        
        return languages
    }
}

internal struct AuralAudioBufferProcessor: AudioBufferProcessorProtocol {
    private let converter = BufferConverter()
    
    func processBuffer(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        do {
            return try converter.convertBuffer(buffer, to: format)
        } catch {
            throw AuralError.audioSetupFailed
        }
    }
}