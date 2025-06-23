import Foundation
@preconcurrency import AVFoundation
import Speech
import OSLog

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
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
            self.speechAnalyzer = AuralSpeechAnalyzer()
            self.audioEngine = AuralAudioEngine()
            self.modelManager = AuralModelManager()
        } else {
            // Use legacy implementations for older OS versions
            self.speechAnalyzer = LegacyAuralSpeechAnalyzer()
            self.audioEngine = LegacyAuralAudioEngine()
            self.modelManager = LegacyAuralModelManager()
        }
        self.bufferProcessor = AuralAudioBufferProcessor()
    }
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
internal actor AuralSpeechAnalyzer: SpeechAnalyzerProtocol {
    private static let logger = Logger(subsystem: "com.auralkit", category: "SpeechAnalyzer")
    
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
        Self.logger.debug("Configure starting with locale: \(configuration.language.locale.identifier)")
        
        // Request Speech recognition permission first
        try await requestSpeechPermission()
        Self.logger.debug("Speech permission obtained")
        
        // Create transcriber with the specified language
        speechTranscriber = SpeechTranscriber(
            locale: configuration.language.locale,
            transcriptionOptions: [],
            reportingOptions: configuration.includePartialResults ? [.volatileResults] : [],
            attributeOptions: configuration.includeTimestamps ? [.audioTimeRange] : []
        )
        
        guard let speechTranscriber else {
            Self.logger.error("Failed to create SpeechTranscriber")
            throw AuralError.recognitionFailed
        }
        Self.logger.debug("SpeechTranscriber created successfully")
        
        // Ensure the model is available for this language
        do {
            try await ensureModel(for: speechTranscriber, locale: configuration.language.locale)
            Self.logger.debug("Model ensured for locale")
        } catch {
            Self.logger.warning("Model check failed: \(error), proceeding without explicit model management")
            // Continue anyway - SpeechTranscriber may handle model management automatically
        }
        
        // Create analyzer with the transcriber
        speechAnalyzer = SpeechAnalyzer(modules: [speechTranscriber])
        Self.logger.debug("SpeechAnalyzer created with transcriber")
        
        // Set up input stream
        (inputSequence, inputBuilder) = AsyncStream<AnalyzerInput>.makeStream()
        Self.logger.debug("Input stream configured")
    }
    
    func startAnalysis() async throws {
        Self.logger.debug("Starting speech analysis")
        guard let speechAnalyzer, let speechTranscriber, let inputSequence else {
            Self.logger.error("Missing components - analyzer: \(self.speechAnalyzer != nil), transcriber: \(self.speechTranscriber != nil), inputSequence: \(self.inputSequence != nil)")
            throw AuralError.recognitionFailed
        }
        
        // Start the analyzer
        Self.logger.debug("Starting SpeechAnalyzer...")
        try await speechAnalyzer.start(inputSequence: inputSequence)
        Self.logger.debug("SpeechAnalyzer started successfully")
        
        // Start processing results
        recognizerTask = Task { [weak self] in
            guard let self else { return }
            
            Self.logger.debug("Starting to process speech results...")
            do {
                var resultCount = 0
                for try await result in speechTranscriber.results {
                    resultCount += 1
                    Self.logger.debug("Received speech result #\(resultCount): '\(String(result.text.characters))', isFinal: \(result.isFinal)")
                    let auralResult = AuralResult(
                        text: String(result.text.characters),
                        confidence: 1.0, // SpeechTranscriber doesn't provide confidence in the new API
                        isPartial: !result.isFinal,
                        timestamp: 0 // Will be populated if audioTimeRange is available
                    )
                    
                    await self.yieldResult(auralResult)
                }
                Self.logger.debug("Speech results processing completed after \(resultCount) results")
            } catch {
                // Handle speech recognition errors
                Self.logger.error("Speech recognition error in results loop: \(error)")
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
        Self.logger.debug("Processing audio buffer with frameLength: \(buffer.frameLength)")
        guard let inputBuilder else {
            Self.logger.error("No inputBuilder available")
            throw AuralError.audioSetupFailed
        }
        
        // Get the best available format for the speech analyzer
        guard let speechTranscriber,
              let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [speechTranscriber]) else {
            Self.logger.error("Failed to get analyzer format")
            throw AuralError.audioSetupFailed
        }
        
        Self.logger.debug("Converting buffer from \(buffer.format.sampleRate)Hz to \(analyzerFormat.sampleRate)Hz")
        
        // Convert buffer to the required format
        let convertedBuffer = try bufferConverter.convertBuffer(buffer, to: analyzerFormat)
        
        Self.logger.debug("Buffer converted successfully, yielding to speech analyzer")
        
        // Create analyzer input and yield it
        let input = AnalyzerInput(buffer: convertedBuffer)
        inputBuilder.yield(input)
        Self.logger.debug("Audio input yielded to speech analyzer successfully")
    }
    
    private func yieldResult(_ result: AuralResult) {
        continuation.yield(result)
    }
    
    /// Request Speech recognition permission - following Apple's sample
    private func requestSpeechPermission() async throws {
        // Request speech recognition permission explicitly
        let authStatus = SFSpeechRecognizer.authorizationStatus()
        
        switch authStatus {
        case .notDetermined:
            let permissionGranted = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
            if !permissionGranted {
                throw AuralError.permissionDenied
            }
        case .denied, .restricted:
            throw AuralError.permissionDenied
        case .authorized:
            break
        @unknown default:
            throw AuralError.permissionDenied
        }
    }
    
    /// Ensure the speech model is available - following Apple's sample approach
    private func ensureModel(for transcriber: SpeechTranscriber, locale: Locale) async throws {
        // Following Apple's sample pattern from SpokenWordTranscriber.ensureModel
        Self.logger.debug("Checking model availability for locale: \(locale.identifier)")
        
        guard await supported(locale: locale) else {
            Self.logger.error("Locale \(locale.identifier) is not supported")
            throw AuralError.unsupportedLanguage
        }
        Self.logger.debug("Locale \(locale.identifier) is supported")
        
        if await installed(locale: locale) {
            Self.logger.debug("Model for locale \(locale.identifier) is already installed")
            return
        } else {
            Self.logger.debug("Model for locale \(locale.identifier) not installed, attempting download")
            try await downloadIfNeeded(for: transcriber)
        }
    }
    
    private func supported(locale: Locale) async -> Bool {
        let supported = await SpeechTranscriber.supportedLocales
        let supportedIdentifiers = supported.map { $0.identifier(.bcp47) }
        let isSupported = supportedIdentifiers.contains(locale.identifier(.bcp47))
        Self.logger.debug("Supported locales: \(supportedIdentifiers), checking: \(locale.identifier(.bcp47)), supported: \(isSupported)")
        return isSupported
    }

    private func installed(locale: Locale) async -> Bool {
        let installed = await Set(SpeechTranscriber.installedLocales)
        let installedIdentifiers = installed.map { $0.identifier(.bcp47) }
        let isInstalled = installedIdentifiers.contains(locale.identifier(.bcp47))
        Self.logger.debug("Installed locales: \(installedIdentifiers), checking: \(locale.identifier(.bcp47)), installed: \(isInstalled)")
        return isInstalled
    }

    private func downloadIfNeeded(for module: SpeechTranscriber) async throws {
        Self.logger.debug("Requesting asset installation for speech transcriber")
        
        do {
            if let downloader = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
                Self.logger.debug("Asset installation request created, starting download...")
                try await downloader.downloadAndInstall()
                Self.logger.debug("Model download completed successfully")
            } else {
                Self.logger.error("No asset installation request available - model may already be installed or not needed")
            }
        } catch {
            Self.logger.error("Model download failed: \(error)")
            throw AuralError.networkError
        }
    }
}

/// Dedicated audio processor that handles ALL audio operations within a single actor
/// This ensures AVAudioPCMBuffer never crosses actor boundaries, avoiding Sendable issues
@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
internal actor AuralAudioProcessor {
    private static let logger = Logger(subsystem: "com.auralkit", category: "AudioProcessor")
    
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
        Self.logger.debug("Starting audio recording")
        guard !isRecording else { 
            Self.logger.debug("Already recording, returning")
            return 
        }
        
        self.speechAnalyzer = speechAnalyzer
        Self.logger.debug("Speech analyzer set")
        
        #if os(iOS)
        try setUpAudioSession()
        Self.logger.debug("Audio session set up")
        #endif
        
        try setupAudioEngine()
        Self.logger.debug("Audio engine set up")
        
        // Install tap and process buffers with immediate conversion to avoid Sendable issues
        audioEngine.inputNode.installTap(
            onBus: 0,
            bufferSize: 4096,
            format: audioEngine.inputNode.outputFormat(forBus: 0)
        ) { [weak self, weak speechAnalyzer] buffer, time in
            // Convert buffer synchronously within callback to avoid actor boundary issues
            guard let self, let speechAnalyzer else { 
                Task { Self.logger.error("Audio tap callback - missing self or speechAnalyzer") }
                return 
            }
            
            Task { Self.logger.debug("Audio tap callback received buffer with frameLength: \(buffer.frameLength)") }
            
            // Extract raw audio data synchronously to pass across boundaries
            let frameLength = buffer.frameLength
            let format = buffer.format
            
            guard frameLength > 0, let channelData = buffer.floatChannelData else {
                Task { Self.logger.error("Invalid audio buffer - frameLength: \(frameLength), channelData: \(buffer.floatChannelData != nil)") }
                return
            }
            
            // Copy audio data synchronously within the callback
            let data = Data(bytes: channelData[0], count: Int(frameLength) * MemoryLayout<Float>.size)
            
            Task {
                await self.processAudioData(data, frameLength: frameLength, format: format, speechAnalyzer: speechAnalyzer)
            }
        }
        
        Self.logger.debug("Preparing and starting audio engine...")
        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true
        Self.logger.debug("Audio recording started successfully, isRecording = \(self.isRecording)")
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
            Self.logger.error("Audio buffer processing error: \(error)")
        }
    }
    
    /// Process audio data that was extracted synchronously from the callback
    func processAudioData(_ data: Data, frameLength: AVAudioFrameCount, format: AVAudioFormat, speechAnalyzer: AuralSpeechAnalyzer) async {
        Self.logger.debug("Processing audio data with frameLength: \(frameLength)")
        do {
            // Reconstruct buffer within the actor from the copied data
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameLength) else {
                Self.logger.error("Failed to create audio buffer")
                return
            }
            
            buffer.frameLength = frameLength
            
            // Copy data back to buffer
            data.withUnsafeBytes { bytes in
                let floatPtr = bytes.bindMemory(to: Float.self)
                buffer.floatChannelData![0].update(from: floatPtr.baseAddress!, count: Int(frameLength))
            }
            
            Self.logger.debug("Audio buffer reconstructed, writing to file and processing...")
            
            // Now process within actor
            try audioFile?.write(from: buffer)
            try await speechAnalyzer.processAudioBuffer(buffer)
            
        } catch {
            Self.logger.error("Audio data processing error: \(error)")
        }
    }
}

/// Simplified audio engine protocol that works with the dedicated processor
@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
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

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
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

// MARK: - Legacy Implementations for iOS 17+, macOS 14+

/// Legacy speech analyzer using SFSpeechRecognizer
internal actor LegacyAuralSpeechAnalyzer: SpeechAnalyzerProtocol {
    private let legacyRecognizer = LegacySpeechRecognizer()
    
    nonisolated var results: AsyncStream<AuralResult> {
        legacyRecognizer.results
    }
    
    func configure(with configuration: AuralConfiguration) async throws {
        try await legacyRecognizer.configure(with: configuration)
    }
    
    func startAnalysis() async throws {
        try await legacyRecognizer.startRecognition()
    }
    
    func stopAnalysis() async throws {
        try await legacyRecognizer.stopRecognition()
    }
    
    func finishAnalysis() async throws {
        try await legacyRecognizer.stopRecognition()
    }
    
    func processAudioBuffer(_ buffer: AVAudioPCMBuffer) async throws {
        try await legacyRecognizer.processAudioBuffer(buffer)
    }
    
    nonisolated func getLegacyRecognizer() -> LegacySpeechRecognizer {
        legacyRecognizer
    }
}

/// Legacy audio engine using AVAudioEngine directly
internal actor LegacyAuralAudioEngine: AudioEngineProtocol {
    private let processor = LegacyAudioProcessor()
    
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
        // Legacy implementation doesn't support pause/resume
        try await processor.stopRecording()
    }
    
    func resumeRecording() async throws {
        // Legacy implementation doesn't support pause/resume
        throw AuralError.audioSetupFailed
    }
    
    /// Get access to the audio processor for direct integration
    nonisolated func getProcessor() -> LegacyAudioProcessor {
        processor
    }
}

/// Legacy model manager for iOS 17+, macOS 14+
internal actor LegacyAuralModelManager: ModelManagerProtocol {
    func isModelAvailable(for language: AuralLanguage) async -> Bool {
        // Check if the language is available using SFSpeechRecognizer
        let recognizer = SFSpeechRecognizer(locale: language.locale)
        return recognizer?.isAvailable ?? false
    }
    
    func downloadModel(for language: AuralLanguage) async throws {
        // Legacy API doesn't support explicit model downloads
        // Models are managed by the system
        let recognizer = SFSpeechRecognizer(locale: language.locale)
        if recognizer?.isAvailable != true {
            throw AuralError.modelNotAvailable
        }
    }
    
    func getDownloadProgress(for language: AuralLanguage) async -> Double? {
        // Legacy API doesn't provide download progress
        return nil
    }
    
    func getSupportedLanguages() async -> [AuralLanguage] {
        // Get all supported locales from SFSpeechRecognizer
        let supportedLocales = SFSpeechRecognizer.supportedLocales()
        
        var languages: [AuralLanguage] = []
        
        for locale in supportedLocales {
            switch locale.identifier {
            case "en-US", "en_US":
                languages.append(.english)
            case "es-ES", "es_ES":
                languages.append(.spanish)
            case "fr-FR", "fr_FR":
                languages.append(.french)
            case "de-DE", "de_DE":
                languages.append(.german)
            case "zh-CN", "zh_CN", "zh-Hans-CN", "zh_Hans_CN":
                languages.append(.chinese)
            default:
                languages.append(.custom(locale))
            }
        }
        
        return languages
    }
}
