import Foundation
@preconcurrency import Speech
@preconcurrency import AVFoundation
import OSLog

/// Fixed legacy speech recognizer implementation with proper error handling and state management
internal actor LegacySpeechRecognizer: LegacySpeechRecognizerProtocol {
    internal static let logger = Logger(subsystem: "com.auralkit", category: "LegacySpeechRecognizer")
    
    // MARK: - State Management
    private enum State {
        case idle
        case configured
        case recognizing
        case stopped
    }
    
    private var state: State = .idle
    private let (stream, continuation) = AsyncStream.makeStream(of: AuralResult.self)
    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var configuration: AuralConfiguration?
    
    // Buffer ordering management
    private var bufferQueue = [AVAudioPCMBuffer]()
    private var isProcessingBuffers = false
    
    // Timeout management
    private var timeoutTask: Task<Void, Never>?
    private let defaultTimeout: TimeInterval = 300 // 5 minutes
    
    // Resource cleanup
    private var temporaryFiles = Set<URL>()
    
    init() {
        // Default initializer
    }
    
    nonisolated var results: AsyncStream<AuralResult> {
        stream
    }
    
    deinit {
        // Cancel any ongoing tasks
        timeoutTask?.cancel()
        recognitionTask?.cancel()
        
        // Finish the continuation
        continuation.finish()
        
        // Clean up any temporary files
        for url in temporaryFiles {
            try? FileManager.default.removeItem(at: url)
        }
    }
    
    // MARK: - Configuration
    
    func configure(with configuration: AuralConfiguration) async throws {
        Self.logger.debug("Configuring legacy speech recognizer with locale: \(configuration.language.locale.identifier)")
        
        // Prevent configuration during active recognition
        guard state == .idle || state == .stopped else {
            Self.logger.warning("Cannot configure during active recognition")
            throw AuralError.recognitionFailed
        }
        
        self.configuration = configuration
        
        // Request speech recognition permission
        try await requestSpeechPermission()
        
        // Create recognizer for the specified locale
        recognizer = SFSpeechRecognizer(locale: configuration.language.locale)
        
        guard let recognizer = recognizer else {
            Self.logger.error("Failed to create SFSpeechRecognizer for locale: \(configuration.language.locale.identifier)")
            throw AuralError.unsupportedLanguage
        }
        
        guard recognizer.isAvailable else {
            Self.logger.error("SFSpeechRecognizer not available")
            throw AuralError.modelNotAvailable
        }
        
        state = .configured
        Self.logger.debug("Legacy speech recognizer configured successfully")
    }
    
    // MARK: - Recognition Control
    
    func startRecognition() async throws {
        Self.logger.debug("Starting legacy speech recognition")
        
        guard state == .configured else {
            Self.logger.error("Cannot start recognition - not configured. State: \(String(describing: self.state))")
            throw AuralError.recognitionFailed
        }
        
        guard let recognizer = recognizer else {
            throw AuralError.recognitionFailed
        }
        
        // Create and configure recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        
        guard let recognitionRequest = recognitionRequest else {
            throw AuralError.recognitionFailed
        }
        
        // Configure request based on settings
        recognitionRequest.shouldReportPartialResults = configuration?.includePartialResults ?? false
        
        if #available(iOS 16, macOS 13, *) {
            recognitionRequest.addsPunctuation = true
        }
        
        // Configure quality settings
        if let quality = configuration?.quality {
            configureRequestQuality(recognitionRequest, quality: quality)
        }
        
        // If running on a device that supports on-device recognition
        if recognizer.supportsOnDeviceRecognition {
            recognitionRequest.requiresOnDeviceRecognition = true
        }
        
        state = .recognizing
        
        // Start timeout monitoring
        startTimeoutMonitoring()
        
        Self.logger.debug("Legacy speech recognition configured and ready for audio input")
    }
    
    /// Call this after audio engine is started to begin recognition
    func startRecognitionTask() async throws {
        guard state == .recognizing,
              let recognizer = recognizer,
              let recognitionRequest = recognitionRequest else {
            throw AuralError.recognitionFailed
        }
        
        // Start recognition task
        recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            // Extract data from result before passing to async context
            let resultText = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let confidence = result.map { self.extractConfidenceSync(from: $0) } ?? 1.0
            let timestamp = result.map { self.extractTimestampSync(from: $0) } ?? 0.0
            
            Task {
                await self.handleRecognitionResultData(text: resultText, confidence: confidence, isPartial: !isFinal, timestamp: timestamp, error: error)
            }
        }
        
        Self.logger.debug("Recognition task started")
    }
    
    func stopRecognition() async throws {
        Self.logger.debug("Stopping legacy speech recognition")
        
        // Cancel timeout monitoring
        timeoutTask?.cancel()
        timeoutTask = nil
        
        // Finish audio input
        recognitionRequest?.endAudio()
        
        // Cancel recognition task
        recognitionTask?.cancel()
        
        // Process any remaining buffers
        await processBufferQueue()
        
        // Clean up
        recognitionRequest = nil
        recognitionTask = nil
        state = .stopped
        
        // Don't finish the continuation here - let results complete naturally
        
        Self.logger.debug("Legacy speech recognition stopped")
    }
    
    func finishAnalysis() async throws {
        try await stopRecognition()
        continuation.finish()
    }
    
    // MARK: - Audio Processing
    
    func processAudioBuffer(_ buffer: AVAudioPCMBuffer) async throws {
        guard state == .recognizing else {
            Self.logger.warning("Ignoring audio buffer - not in recognizing state")
            return
        }
        
        // Add to queue for ordered processing
        bufferQueue.append(buffer)
        
        // Process queue if not already processing
        if !isProcessingBuffers {
            await processBufferQueue()
        }
    }
    
    private func processBufferQueue() async {
        guard !isProcessingBuffers else { return }
        isProcessingBuffers = true
        
        defer { isProcessingBuffers = false }
        
        while !bufferQueue.isEmpty {
            let buffer = bufferQueue.removeFirst()
            
            // Process buffer
            recognitionRequest?.append(buffer)
        }
    }
    
    // MARK: - File Transcription
    
    func transcribeFile(at url: URL) async throws -> String {
        Self.logger.debug("Transcribing file at: \(url.path)")
        
        // Ensure we're configured
        guard state == .configured || state == .stopped else {
            Self.logger.error("Not configured for file transcription")
            throw AuralError.recognitionFailed
        }
        
        guard let recognizer = recognizer else {
            throw AuralError.recognitionFailed
        }
        
        // Create file recognition request
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        
        if #available(iOS 16, macOS 13, *) {
            request.addsPunctuation = true
        }
        
        // Configure quality settings
        if let quality = configuration?.quality {
            configureRequestQuality(request, quality: quality)
        }
        
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        
        // Create timeout for file transcription
        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: 60_000_000_000) // 60 seconds for file
        }
        
        // Perform recognition with timeout handling
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                var recognitionTask: SFSpeechRecognitionTask?
                
                recognitionTask = recognizer.recognitionTask(with: request) { [weak recognitionTask] result, error in
                    if let error = error {
                        Self.logger.error("File transcription error: \(error)")
                        continuation.resume(throwing: AuralError.recognitionFailed)
                        return
                    }
                    
                    if let result = result {
                        if result.isFinal {
                            let transcription = result.bestTranscription.formattedString
                            Self.logger.debug("File transcription completed: \(transcription)")
                            continuation.resume(returning: transcription)
                        }
                    }
                    
                    // Handle case where recognition completes without final result
                    if let task = recognitionTask, task.state == .completed && result?.isFinal != true {
                        Self.logger.warning("Recognition completed without final result")
                        continuation.resume(returning: result?.bestTranscription.formattedString ?? "")
                    }
                }
                
                // Handle timeout
                Task {
                    _ = await timeoutTask.value
                    if let task = recognitionTask, task.state == .running {
                        Self.logger.error("File transcription timed out")
                        task.cancel()
                        continuation.resume(throwing: AuralError.recognitionFailed)
                    }
                }
            }
        } onCancel: {
            timeoutTask.cancel()
        }
    }
    
    func transcribeFile(at url: URL, onResult: @escaping @MainActor @Sendable (AuralResult) -> Void) async throws {
        Self.logger.debug("Transcribing file with callbacks at: \(url.path)")
        
        // Similar setup as above
        guard state == .configured || state == .stopped else {
            throw AuralError.recognitionFailed
        }
        
        guard let recognizer = recognizer else {
            throw AuralError.recognitionFailed
        }
        
        // Create file recognition request
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = configuration?.includePartialResults ?? false
        
        if #available(iOS 16, macOS 13, *) {
            request.addsPunctuation = true
        }
        
        if let quality = configuration?.quality {
            configureRequestQuality(request, quality: quality)
        }
        
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        
        // Create a task completion tracker
        let taskCompletion = TaskCompletionTracker()
        
        // Perform recognition with progress callbacks and timeout
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                    guard let self = self else { return }
                    
                    if let error = error {
                        Self.logger.error("File transcription error: \(error)")
                        Task {
                            await taskCompletion.complete(throwing: AuralError.recognitionFailed)
                        }
                        return
                    }
                    
                    if let result = result {
                        let text = result.bestTranscription.formattedString
                        let confidence = self.extractConfidenceSync(from: result)
                        let timestamp = self.extractTimestampSync(from: result)
                        let isFinal = result.isFinal
                        
                        let auralResult = AuralResult(
                            text: text,
                            confidence: confidence,
                            isPartial: !isFinal,
                            timestamp: timestamp
                        )
                        
                        Task { @MainActor in
                            onResult(auralResult)
                        }
                        
                        if isFinal {
                            Self.logger.debug("File transcription completed")
                            Task {
                                await taskCompletion.complete()
                            }
                        }
                    }
                }
                
                // Set up timeout
                Task {
                    try? await Task.sleep(nanoseconds: 60_000_000_000) // 60 seconds
                    let isCompleted = await taskCompletion.isCompleted
                    if !isCompleted {
                        Self.logger.error("File transcription timed out")
                        recognitionTask.cancel()
                        await taskCompletion.complete(throwing: AuralError.recognitionFailed)
                    }
                }
                
                // Wait for completion
                Task {
                    do {
                        try await taskCompletion.wait()
                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            Self.logger.debug("File transcription cancelled")
        }
    }
    
    // MARK: - Private Methods
    
    private func handleRecognitionResult(_ result: SFSpeechRecognitionResult?, error: Error?) async {
        if let error = error {
            // Check if it's a real error or just end of recognition
            let nsError = error as NSError
            if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 203 {
                // This is just "no speech detected", not a real error
                Self.logger.debug("No speech detected")
            } else {
                Self.logger.error("Recognition error: \(error)")
            }
            return
        }
        
        guard let result = result else { return }
        
        let auralResult = AuralResult(
            text: result.bestTranscription.formattedString,
            confidence: extractConfidence(from: result),
            isPartial: !result.isFinal,
            timestamp: extractTimestamp(from: result)
        )
        
        continuation.yield(auralResult)
        
        // Reset timeout on new results
        if state == .recognizing {
            resetTimeout()
        }
    }
    
    private func extractConfidence(from result: SFSpeechRecognitionResult) -> Double {
        let segments = result.bestTranscription.segments
        guard !segments.isEmpty else { return 1.0 }
        
        let totalConfidence = segments.reduce(0.0) { $0 + Double($1.confidence) }
        return totalConfidence / Double(segments.count)
    }
    
    private func extractTimestamp(from result: SFSpeechRecognitionResult) -> TimeInterval {
        if let lastSegment = result.bestTranscription.segments.last {
            return lastSegment.timestamp + lastSegment.duration
        }
        return 0.0
    }
    
    // Synchronous versions for use in non-isolated contexts
    private nonisolated func extractConfidenceSync(from result: SFSpeechRecognitionResult) -> Double {
        let segments = result.bestTranscription.segments
        guard !segments.isEmpty else { return 1.0 }
        
        let totalConfidence = segments.reduce(0.0) { $0 + Double($1.confidence) }
        return totalConfidence / Double(segments.count)
    }
    
    private nonisolated func extractTimestampSync(from result: SFSpeechRecognitionResult) -> TimeInterval {
        if let lastSegment = result.bestTranscription.segments.last {
            return lastSegment.timestamp + lastSegment.duration
        }
        return 0.0
    }
    
    private func handleRecognitionResultData(text: String?, confidence: Double, isPartial: Bool, timestamp: TimeInterval, error: Error?) async {
        if let error = error {
            // Check if it's a real error or just end of recognition
            let nsError = error as NSError
            if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 203 {
                // This is just "no speech detected", not a real error
                Self.logger.debug("No speech detected")
            } else {
                Self.logger.error("Recognition error: \(error)")
            }
            return
        }
        
        guard let text = text else { return }
        
        let auralResult = AuralResult(
            text: text,
            confidence: confidence,
            isPartial: isPartial,
            timestamp: timestamp
        )
        
        continuation.yield(auralResult)
        
        // Reset timeout on new results
        if state == .recognizing {
            resetTimeout()
        }
    }
    
    private func requestSpeechPermission() async throws {
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
    
    private func configureRequestQuality(_ request: SFSpeechRecognitionRequest, quality: AuralQuality) {
        switch quality {
        case .low:
            request.taskHint = .search
        case .medium:
            request.taskHint = .unspecified
        case .high:
            request.taskHint = .dictation
            if #available(iOS 16, macOS 13, *),
               request is SFSpeechAudioBufferRecognitionRequest {
                // For iOS 16+, we can provide custom language model data if available
                // but there's no .automatic option - this would need custom implementation
            }
        }
    }
    
    // MARK: - Timeout Management
    
    private func startTimeoutMonitoring() {
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            do {
                guard let timeout = self?.defaultTimeout else { return }
                try await Task.sleep(nanoseconds: UInt64(timeout) * 1_000_000_000)
                guard let self = self else { return }
                await self.handleTimeout()
            } catch {
                // Task was cancelled
            }
        }
    }
    
    private func resetTimeout() {
        startTimeoutMonitoring()
    }
    
    private func handleTimeout() async {
        if state == .recognizing {
            Self.logger.warning("Recognition timeout reached")
            // Don't automatically stop - let the user decide
        }
    }
    
    // MARK: - Resource Management
    
    func addTemporaryFile(_ url: URL) {
        temporaryFiles.insert(url)
    }
    
    func removeTemporaryFile(_ url: URL) {
        temporaryFiles.remove(url)
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - Helper Types

private actor TaskCompletionTracker {
    private var continuation: CheckedContinuation<Void, Error>?
    private var _isCompleted = false
    
    var isCompleted: Bool { _isCompleted }
    
    func wait() async throws {
        try await withCheckedThrowingContinuation { cont in
            if _isCompleted {
                cont.resume()
            } else {
                continuation = cont
            }
        }
    }
    
    func complete() {
        _isCompleted = true
        continuation?.resume()
        continuation = nil
    }
    
    func complete(throwing error: Error) {
        _isCompleted = true
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

// MARK: - Legacy Audio Processor

/// Fixed legacy audio processor with proper state management and buffer ordering
internal actor LegacyAudioProcessor {
    internal static let logger = Logger(subsystem: "com.auralkit", category: "LegacyAudioProcessor")
    
    private let audioEngine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var audioFileURL: URL?
    private weak var legacyRecognizer: LegacySpeechRecognizer?
    
    // Buffer ordering
    private let bufferContinuation = BufferContinuation()
    
    var audioFormat: AVAudioFormat? {
        audioEngine.inputNode.outputFormat(forBus: 0)
    }
    
    var isRecording = false
    
    init() {
        // Default initializer
    }
    
    deinit {
        // Clean up audio file
        if let url = audioFileURL {
            try? FileManager.default.removeItem(at: url)
        }
    }
    
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
    
    func startRecording(with recognizer: LegacySpeechRecognizer) async throws {
        Self.logger.debug("Starting legacy audio recording")
        guard !isRecording else { return }
        
        self.legacyRecognizer = recognizer
        
        #if os(iOS)
        try setUpAudioSession()
        #endif
        
        try setupAudioEngine()
        
        // Start the recognition FIRST (prepare it)
        try await recognizer.startRecognition()
        
        // Install tap for audio processing
        let inputFormat = audioEngine.inputNode.outputFormat(forBus: 0)
        audioEngine.inputNode.installTap(
            onBus: 0,
            bufferSize: 1024,
            format: inputFormat
        ) { [weak self, weak recognizer] buffer, _ in
            guard let self = self, let recognizer = recognizer else { return }
            
            // Use continuation for ordered processing
            Task {
                await self.bufferContinuation.enqueue(buffer, recognizer: recognizer)
            }
        }
        
        // Prepare and start audio engine with proper error handling
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
            isRecording = true
            
            // NOW start the recognition task after audio is flowing
            try await recognizer.startRecognitionTask()
            
            Self.logger.debug("Legacy audio recording started")
        } catch {
            // Remove tap on failure to prevent memory leak
            audioEngine.inputNode.removeTap(onBus: 0)
            isRecording = false
            Self.logger.error("Failed to start audio engine or recognition: \(error)")
            throw error
        }
    }
    
    func stopRecording() async throws {
        guard isRecording else { return }
        
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        
        // Process any remaining buffers
        await bufferContinuation.finish()
        
        legacyRecognizer = nil
        isRecording = false
        
        // Clean up audio file
        if let url = audioFileURL {
            audioFileURL = nil
            try? FileManager.default.removeItem(at: url)
        }
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
        
        audioFileURL = url
        
        let inputSettings = audioEngine.inputNode.inputFormat(forBus: 0).settings
        audioFile = try AVAudioFile(forWriting: url, settings: inputSettings)
        
        // Track temporary file in recognizer for cleanup
        Task { [weak legacyRecognizer] in
            await legacyRecognizer?.addTemporaryFile(url)
        }
    }
}

// MARK: - Buffer Continuation for Ordered Processing

private actor BufferContinuation {
    private var bufferStream: AsyncStream<(AVAudioPCMBuffer, LegacySpeechRecognizer)>?
    private var continuation: AsyncStream<(AVAudioPCMBuffer, LegacySpeechRecognizer)>.Continuation?
    private var processingTask: Task<Void, Never>?
    
    init() {
        let (stream, continuation) = AsyncStream<(AVAudioPCMBuffer, LegacySpeechRecognizer)>.makeStream()
        self.bufferStream = stream
        self.continuation = continuation
        
        // Start processing task after initialization
        Task {
            await self.startProcessing()
        }
    }
    
    private func startProcessing() {
        processingTask = Task { [weak self] in
            guard let self = self else { return }
            await self.processBufferStream()
        }
    }
    
    private func processBufferStream() async {
        guard let stream = self.bufferStream else { return }
        
        for await (buffer, recognizer) in stream {
            do {
                try await recognizer.processAudioBuffer(buffer)
            } catch {
                LegacyAudioProcessor.logger.error("Error processing audio buffer: \(error)")
            }
        }
    }
    
    func enqueue(_ buffer: AVAudioPCMBuffer, recognizer: LegacySpeechRecognizer) async {
        continuation?.yield((buffer, recognizer))
    }
    
    func finish() async {
        continuation?.finish()
        await processingTask?.value
    }
}