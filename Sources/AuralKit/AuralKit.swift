@preconcurrency import AVFoundation
import Foundation
import Speech

@available(iOS 26.0, macOS 26.0, *)
public final class AuralKit: @unchecked Sendable {
    
    // MARK: - Properties
    private let audioEngine = AVAudioEngine()
    private var speechTranscriber: SpeechTranscriber?
    private var speechAnalyzer: SpeechAnalyzer?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var recognizerTask: Task<(), Error>?
    private let locale: Locale
    
    // MARK: - Init
    
    public init(locale: Locale = .current) {
        self.locale = locale
    }
    
    // MARK: - Public API
    
    /// Start transcribing
    public func startTranscribing() -> AsyncThrowingStream<AttributedString, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    // Request permissions
                    try await requestPermissions()
                    
                    // Configure transcriber
                    speechTranscriber = SpeechTranscriber(
                        locale: self.locale,
                        transcriptionOptions: [],
                        reportingOptions: [.volatileResults],
                        attributeOptions: [.audioTimeRange]
                    )
                    
                    guard let transcriber = speechTranscriber else {
                        throw NSError(domain: "AuralKit", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create transcriber"])
                    }
                    
                    // Create analyzer
                    speechAnalyzer = SpeechAnalyzer(modules: [transcriber])
                    
                    // Ensure model is available
                    let supported = await SpeechTranscriber.supportedLocales
                    guard supported.map({ $0.identifier(.bcp47) }).contains(self.locale.identifier(.bcp47)) else {
                        throw NSError(domain: "AuralKit", code: -2, userInfo: [NSLocalizedDescriptionKey: "Unsupported locale"])
                    }
                    
                    // Download model if needed
                    let installed = await Set(SpeechTranscriber.installedLocales)
                    if !installed.map({ $0.identifier(.bcp47) }).contains(self.locale.identifier(.bcp47)) {
                        if let downloader = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                            try await downloader.downloadAndInstall()
                        }
                    }
                    
                    // Get best audio format
                    guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
                        throw NSError(domain: "AuralKit", code: -3, userInfo: [NSLocalizedDescriptionKey: "No compatible audio format"])
                    }
                    
                    // Create input stream
                    let (inputSequence, inputBuilder) = AsyncStream<AnalyzerInput>.makeStream()
                    self.inputBuilder = inputBuilder
                    
                    // Start recognition task
                    recognizerTask = Task {
                        for try await result in transcriber.results {
                            continuation.yield(result.text)
                        }
                        continuation.finish()
                    }
                    
                    // Start analyzer
                    try await speechAnalyzer?.start(inputSequence: inputSequence)
                    
                    // Set up audio engine
                    let inputNode = audioEngine.inputNode
                    let recordingFormat = inputNode.outputFormat(forBus: 0)
                    
                    // Create converter
                    let converter = AVAudioConverter(from: recordingFormat, to: analyzerFormat)
                    converter?.primeMethod = .none
                    
                    inputNode.removeTap(onBus: 0)
                    inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { [weak self] buffer, _ in
                        guard let self = self, let converter = converter else { return }
                        
                        // Convert buffer
                        let sampleRateRatio = analyzerFormat.sampleRate / recordingFormat.sampleRate
                        let scaledInputFrameLength = Double(buffer.frameLength) * sampleRateRatio
                        let frameCapacity = AVAudioFrameCount(scaledInputFrameLength.rounded(.up))
                        
                        guard let conversionBuffer = AVAudioPCMBuffer(pcmFormat: analyzerFormat, frameCapacity: frameCapacity) else { return }
                        
                        var nsError: NSError?
                        
                        let inputBufferProvider: AVAudioConverterInputBlock = { _, outStatus in
                            outStatus.pointee = .haveData
                            return buffer
                        }
                        
                        let status = converter.convert(to: conversionBuffer, error: &nsError, withInputFrom: inputBufferProvider)
                        
                        guard status != .error else { return }
                        
                        let input = AnalyzerInput(buffer: conversionBuffer)
                        self.inputBuilder?.yield(input)
                    }
                    
                    #if os(iOS)
                    let audioSession = AVAudioSession.sharedInstance()
                    try audioSession.setCategory(.playAndRecord, mode: .spokenAudio)
                    try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
                    #endif
                    
                    audioEngine.prepare()
                    try audioEngine.start()
                    
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    /// Stop transcribing
    public func stopTranscribing() async {
        audioEngine.stop()
        audioEngine.reset()
        inputBuilder?.finish()
        try? await speechAnalyzer?.finalizeAndFinishThroughEndOfInput()
        recognizerTask?.cancel()
    }
    
    // MARK: - Private Methods
    
    private func requestPermissions() async throws {
        #if os(iOS)
        switch AVAudioApplication.shared.recordPermission {
        case .denied:
            throw NSError(domain: "AuralKit", code: -10, userInfo: [NSLocalizedDescriptionKey: "Microphone permission denied"])
        case .undetermined:
            let granted = await AVAudioApplication.requestRecordPermission()
            if !granted {
                throw NSError(domain: "AuralKit", code: -10, userInfo: [NSLocalizedDescriptionKey: "Microphone permission denied"])
            }
        case .granted:
            break
        @unknown default:
            break
        }
        #endif
        
        switch SFSpeechRecognizer.authorizationStatus() {
        case .denied:
            throw NSError(domain: "AuralKit", code: -11, userInfo: [NSLocalizedDescriptionKey: "Speech recognition permission denied"])
        case .notDetermined:
            let granted = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
            if !granted {
                throw NSError(domain: "AuralKit", code: -11, userInfo: [NSLocalizedDescriptionKey: "Speech recognition permission denied"])
            }
        case .authorized:
            break
        case .restricted:
            throw NSError(domain: "AuralKit", code: -12, userInfo: [NSLocalizedDescriptionKey: "Speech recognition restricted"])
        @unknown default:
            break
        }
    }
}