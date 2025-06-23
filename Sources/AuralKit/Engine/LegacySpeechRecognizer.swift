import Foundation
@preconcurrency import Speech
@preconcurrency import AVFoundation
import OSLog

/// Legacy speech recognizer implementation using SFSpeechRecognizer
/// Available for iOS 17+, macOS 14+, visionOS 1.1+
internal actor LegacySpeechRecognizer: LegacySpeechRecognizerProtocol {
    private static let logger = Logger(subsystem: "com.auralkit", category: "LegacySpeechRecognizer")
    
    private let (stream, continuation) = AsyncStream.makeStream(of: AuralResult.self)
    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine?
    private var configuration: AuralConfiguration?
    
    nonisolated var results: AsyncStream<AuralResult> {
        stream
    }
    
    func configure(with configuration: AuralConfiguration) async throws {
        Self.logger.debug("Configuring legacy speech recognizer with locale: \(configuration.language.locale.identifier)")
        
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
        
        Self.logger.debug("Legacy speech recognizer configured successfully")
    }
    
    func startRecognition() async throws {
        Self.logger.debug("Starting legacy speech recognition")
        
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
        
        // If running on a device that supports on-device recognition
        if recognizer.supportsOnDeviceRecognition {
            recognitionRequest.requiresOnDeviceRecognition = true
        }
        
        // Start recognition task
        recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task { @Sendable [weak self] in
                await self?.handleRecognitionResult(result, error: error)
            }
        }
        
        Self.logger.debug("Legacy speech recognition started")
    }
    
    func stopRecognition() async throws {
        Self.logger.debug("Stopping legacy speech recognition")
        
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        
        recognitionRequest = nil
        recognitionTask = nil
        
        continuation.finish()
        
        Self.logger.debug("Legacy speech recognition stopped")
    }
    
    func processAudioBuffer(_ buffer: AVAudioPCMBuffer) async throws {
        guard let recognitionRequest = recognitionRequest else {
            throw AuralError.recognitionFailed
        }
        
        recognitionRequest.append(buffer)
    }
    
    func transcribeFile(at url: URL) async throws -> String {
        Self.logger.debug("Transcribing file at: \(url.path)")
        
        guard let recognizer = recognizer else {
            throw AuralError.recognitionFailed
        }
        
        // Create file recognition request
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        
        if #available(iOS 16, macOS 13, *) {
            request.addsPunctuation = true
        }
        
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        
        // Perform recognition
        return try await withCheckedThrowingContinuation { continuation in
            recognizer.recognitionTask(with: request) { result, error in
                if let error = error {
                    Self.logger.error("File transcription error: \(error)")
                    continuation.resume(throwing: AuralError.recognitionFailed)
                    return
                }
                
                if let result = result, result.isFinal {
                    let transcription = result.bestTranscription.formattedString
                    Self.logger.debug("File transcription completed: \(transcription)")
                    continuation.resume(returning: transcription)
                }
            }
        }
    }
    
    func transcribeFile(at url: URL, onResult: @escaping @MainActor @Sendable (AuralResult) -> Void) async throws {
        Self.logger.debug("Transcribing file with callbacks at: \(url.path)")
        
        guard let recognizer = recognizer else {
            throw AuralError.recognitionFailed
        }
        
        // Create file recognition request
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = configuration?.includePartialResults ?? false
        
        if #available(iOS 16, macOS 13, *) {
            request.addsPunctuation = true
        }
        
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        
        // Perform recognition with progress callbacks
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            recognizer.recognitionTask(with: request) { result, error in
                if let error = error {
                    Self.logger.error("File transcription error: \(error)")
                    continuation.resume(throwing: AuralError.recognitionFailed)
                    return
                }
                
                if let result = result {
                    let auralResult = AuralResult(
                        text: result.bestTranscription.formattedString,
                        confidence: self.extractConfidence(from: result),
                        isPartial: !result.isFinal,
                        timestamp: self.extractTimestamp(from: result)
                    )
                    
                    Task { @MainActor in
                        onResult(auralResult)
                    }
                    
                    if result.isFinal {
                        Self.logger.debug("File transcription completed")
                        continuation.resume()
                    }
                }
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func handleRecognitionResult(_ result: SFSpeechRecognitionResult?, error: Error?) async {
        if let error = error {
            Self.logger.error("Recognition error: \(error)")
            // Continue processing, don't finish the stream for recoverable errors
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
    }
    
    private func extractConfidence(from result: SFSpeechRecognitionResult) -> Double {
        // Calculate average confidence from segments
        let segments = result.bestTranscription.segments
        guard !segments.isEmpty else { return 1.0 }
        
        let totalConfidence = segments.reduce(0.0) { $0 + Double($1.confidence) }
        return totalConfidence / Double(segments.count)
    }
    
    private func extractTimestamp(from result: SFSpeechRecognitionResult) -> TimeInterval {
        // Get the timestamp of the last segment
        if let lastSegment = result.bestTranscription.segments.last {
            return lastSegment.timestamp + lastSegment.duration
        }
        return 0.0
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
}

// MARK: - Legacy Audio Engine Integration

/// Legacy audio processor for iOS 17+, macOS 14+
internal actor LegacyAudioProcessor {
    private static let logger = Logger(subsystem: "com.auralkit", category: "LegacyAudioProcessor")
    
    private let audioEngine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var legacyRecognizer: LegacySpeechRecognizer?
    
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
    
    func startRecording(with recognizer: LegacySpeechRecognizer) async throws {
        Self.logger.debug("Starting legacy audio recording")
        guard !isRecording else { return }
        
        self.legacyRecognizer = recognizer
        
        #if os(iOS)
        try setUpAudioSession()
        #endif
        
        try setupAudioEngine()
        
        // Install tap for legacy recognizer
        audioEngine.inputNode.installTap(
            onBus: 0,
            bufferSize: 1024,
            format: audioEngine.inputNode.outputFormat(forBus: 0)
        ) { [weak recognizer] buffer, _ in
            guard let recognizer = recognizer else { return }
            
            Task { @Sendable in
                do {
                    try await recognizer.processAudioBuffer(buffer)
                } catch {
                    Self.logger.error("Error processing audio buffer: \(error)")
                }
            }
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true
        
        Self.logger.debug("Legacy audio recording started")
    }
    
    func stopRecording() async throws {
        guard isRecording else { return }
        
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        legacyRecognizer = nil
        isRecording = false
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
}