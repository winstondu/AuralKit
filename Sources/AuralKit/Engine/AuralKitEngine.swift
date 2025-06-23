import Foundation
@preconcurrency import AVFoundation
import Speech
import OSLog

/// Buffer converter for audio format conversion - Thread-safe implementation
internal actor BufferConverter {
    enum Error: Swift.Error {
        case failedToCreateConverter
        case failedToCreateConversionBuffer
        case conversionFailed(NSError?)
    }
    
    private var converters: [String: AVAudioConverter] = [:]
    
    func convertBuffer(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) async throws -> AVAudioPCMBuffer {
        let inputFormat = buffer.format
        guard inputFormat != format else {
            return buffer
        }
        
        // Create a unique key for this conversion
        let key = "\(inputFormat.sampleRate)-\(inputFormat.channelCount)-\(format.sampleRate)-\(format.channelCount)"
        
        // Get or create converter
        let converter: AVAudioConverter
        if let existingConverter = converters[key], existingConverter.outputFormat == format {
            converter = existingConverter
        } else {
            guard let newConverter = AVAudioConverter(from: inputFormat, to: format) else {
                throw Error.failedToCreateConverter
            }
            newConverter.primeMethod = .none
            converters[key] = newConverter
            converter = newConverter
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
    private let resourceManager = ResourceManager()
    let permissionManager = PermissionManager()
    let audioHardwareMonitor = AudioHardwareMonitor()
    
    init() {
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
            self.speechAnalyzer = AuralSpeechAnalyzer(resourceManager: resourceManager)
            self.audioEngine = AuralAudioEngine(resourceManager: resourceManager)
            self.modelManager = AuralModelManager()
        } else {
            // Use legacy implementations for older OS versions
            self.speechAnalyzer = LegacyAuralSpeechAnalyzer(resourceManager: resourceManager)
            self.audioEngine = LegacyAuralAudioEngine(resourceManager: resourceManager)
            self.modelManager = LegacyAuralModelManager()
        }
        self.bufferProcessor = AuralAudioBufferProcessor()
    }
    
    /// Clean up all resources managed by this engine
    func cleanup() async {
        await resourceManager.cleanupAll()
    }
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
internal actor AuralSpeechAnalyzer: SpeechAnalyzerProtocol {
    private static let logger = Logger(subsystem: "com.auralkit", category: "SpeechAnalyzer")
    private let resourceManager: ResourceManager
    
    private let (stream, continuation) = AsyncStream.makeStream(of: AuralResult.self)
    private var speechAnalyzer: SpeechAnalyzer?
    private var speechTranscriber: SpeechTranscriber?
    private var inputSequence: AsyncStream<AnalyzerInput>?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var recognizerTask: Task<Void, Error>?
    private let bufferConverter = BufferConverter()
    
    init(resourceManager: ResourceManager) {
        self.resourceManager = resourceManager
    }
    
    deinit {
        // Ensure continuation is finished on deallocation
        continuation.finish()
    }
    
    nonisolated var results: AsyncStream<AuralResult> {
        stream
    }
    
    func configure(with configuration: AuralConfiguration) async throws {
        Self.logger.debug("Configure starting with locale: \(configuration.language.locale.identifier)")
        
        // Request Speech recognition permission first
        try await requestSpeechPermission()
        Self.logger.debug("Speech permission obtained")
        
        // Create transcriber with the specified language
        // Note: As of iOS 26, SpeechTranscriber doesn't expose direct quality settings
        // The framework automatically adjusts based on device capabilities
        
        // Ensure we use the correct locale format - try with underscore format first
        let normalizedLocale = normalizeLocaleForSpeechTranscriber(configuration.language.locale)
        
        speechTranscriber = SpeechTranscriber(
            locale: normalizedLocale,
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
        
        // Clean up any resources
        await resourceManager.cleanupAll()
    }
    
    func finishAnalysis() async throws {
        defer {
            recognizerTask?.cancel()
            recognizerTask = nil
            continuation.finish()
            Task {
                await resourceManager.cleanupAll()
            }
        }
        
        inputBuilder?.finish()
        try await speechAnalyzer?.finalizeAndFinishThroughEndOfInput()
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
        let convertedBuffer = try await bufferConverter.convertBuffer(buffer, to: analyzerFormat)
        
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
            let detailedError = DetailedError(error, context: "Model download failed")
            Self.logger.error("\(detailedError)")
            throw detailedError.toAuralError()
        }
    }
    
    /// Normalize locale for SpeechTranscriber which expects BCP-47 format
    private func normalizeLocaleForSpeechTranscriber(_ locale: Locale) -> Locale {
        let identifier = locale.identifier
        Self.logger.debug("Normalizing locale identifier: \(identifier)")
        
        // SpeechTranscriber expects BCP-47 format (e.g., en-US not en_US)
        // Use the .bcp47 identifier format
        let bcp47Identifier = locale.identifier(.bcp47)
        Self.logger.debug("Using BCP-47 locale: \(bcp47Identifier)")
        return Locale(identifier: bcp47Identifier)
    }
}

/// Dedicated audio processor that handles ALL audio operations within a single actor
/// This ensures AVAudioPCMBuffer never crosses actor boundaries, avoiding Sendable issues
@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
internal actor AuralAudioProcessor {
    private static let logger = Logger(subsystem: "com.auralkit", category: "AudioProcessor")
    
    private let audioEngine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var audioFileURL: URL?
    private var speechAnalyzer: AuralSpeechAnalyzer?
    private let bufferConverter = BufferConverter()
    private let resourceManager: ResourceManager
    
    init(resourceManager: ResourceManager) {
        self.resourceManager = resourceManager
    }
    
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
        
        // Ensure tap is removed if start fails
        do {
            try audioEngine.start()
            isRecording = true
            Self.logger.debug("Audio recording started successfully, isRecording = \(self.isRecording)")
        } catch {
            // Remove tap on failure to prevent memory leak
            audioEngine.inputNode.removeTap(onBus: 0)
            Self.logger.error("Failed to start audio engine: \(error)")
            throw error
        }
    }
    
    func stopRecording() async throws {
        guard isRecording else { return }
        
        defer {
            // Clean up resources in defer block
            speechAnalyzer = nil
            isRecording = false
            audioFile = nil
            audioFileURL = nil
            Task {
                await resourceManager.cleanupAll()
            }
        }
        
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
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
        // Create temporary file for recording with automatic cleanup  
        let url = FileManager.default.temporaryDirectory
            .appending(component: "AuralKit-\(UUID().uuidString)")
            .appendingPathExtension(for: .wav)
        audioFileURL = url
        Task {
            await resourceManager.registerTemporaryFile(url)
        }
        
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
            
            // Copy data back to buffer safely
            guard let channelData = buffer.floatChannelData else {
                Self.logger.error("Buffer has no channel data")
                return
            }
            
            data.withUnsafeBytes { bytes in
                guard let baseAddress = bytes.bindMemory(to: Float.self).baseAddress else {
                    Self.logger.error("Failed to get base address from data")
                    return
                }
                channelData[0].update(from: baseAddress, count: Int(frameLength))
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
    private let processor: AuralAudioProcessor
    
    init(resourceManager: ResourceManager) {
        self.processor = AuralAudioProcessor(resourceManager: resourceManager)
    }
    
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
    // Create a new converter for each operation to ensure thread safety
    func processBuffer(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        // For synchronous protocol compliance, we perform conversion inline
        let inputFormat = buffer.format
        guard inputFormat != format else {
            return buffer
        }
        
        guard let converter = AVAudioConverter(from: inputFormat, to: format) else {
            throw AuralError.audioSetupFailed
        }
        converter.primeMethod = .none
        
        let sampleRateRatio = converter.outputFormat.sampleRate / converter.inputFormat.sampleRate
        let scaledInputFrameLength = Double(buffer.frameLength) * sampleRateRatio
        let frameCapacity = AVAudioFrameCount(scaledInputFrameLength.rounded(.up))
        guard let conversionBuffer = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: frameCapacity) else {
            throw AuralError.audioSetupFailed
        }
        
        var nsError: NSError?
        let status = converter.convert(to: conversionBuffer, error: &nsError, withInputFrom: { _, _ in
            return buffer
        })
        
        guard status != .error else {
            throw AuralError.audioSetupFailed
        }
        
        return conversionBuffer
    }
}

// MARK: - Legacy Implementations for iOS 17+, macOS 14+

/// Legacy speech analyzer using SFSpeechRecognizer
internal actor LegacyAuralSpeechAnalyzer: SpeechAnalyzerProtocol {
    private let legacyRecognizer: LegacySpeechRecognizer
    
    init(resourceManager: ResourceManager) {
        self.legacyRecognizer = LegacySpeechRecognizer()
    }
    
    nonisolated var results: AsyncStream<AuralResult> {
        legacyRecognizer.results
    }
    
    func configure(with configuration: AuralConfiguration) async throws {
        try await legacyRecognizer.configure(with: configuration)
    }
    
    func startAnalysis() async throws {
        // Don't start recognition here - it will be started after audio is ready
        // This matches the new implementation pattern
    }
    
    func stopAnalysis() async throws {
        try await legacyRecognizer.stopRecognition()
    }
    
    func finishAnalysis() async throws {
        try await legacyRecognizer.finishAnalysis()
    }
    
    func processAudioBuffer(_ buffer: AVAudioPCMBuffer) async throws {
        try await legacyRecognizer.processAudioBuffer(buffer)
    }
    
    // Fix actor isolation: return the recognizer through an async function
    func getRecognizer() async -> LegacySpeechRecognizer {
        legacyRecognizer
    }
}

/// Legacy audio engine using AVAudioEngine directly
internal actor LegacyAuralAudioEngine: AudioEngineProtocol {
    private let processor: LegacyAudioProcessor
    
    init(resourceManager: ResourceManager) {
        self.processor = LegacyAudioProcessor()
    }
    
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
