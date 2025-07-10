import AVFoundation
import Foundation
import Speech

/// Simple wrapper for speech-to-text transcription using Apple's APIs
@MainActor
public final class AuralKit {
    
    // MARK: - Properties
    
    private var configuration = AuralConfiguration()
    private var audioEngine = AVAudioEngine()
    private var isTranscribing = false
    
    // For iOS 26+
    private var speechTranscriber: Any? // SpeechTranscriber
    private var speechAnalyzer: Any? // SpeechAnalyzer
    
    // For legacy
    private var legacyRecognizer: LegacySpeechRecognizer?
    
    // MARK: - Configuration
    
    public func locale(_ locale: Locale) -> Self {
        configuration = AuralConfiguration(
            locale: locale,
            includePartialResults: configuration.includePartialResults,
            includeTimestamps: configuration.includeTimestamps
        )
        return self
    }
    
    public func includePartialResults(_ include: Bool = true) -> Self {
        configuration = AuralConfiguration(
            locale: configuration.locale,
            includePartialResults: include,
            includeTimestamps: configuration.includeTimestamps
        )
        return self
    }
    
    public func includeTimestamps(_ include: Bool = true) -> Self {
        configuration = AuralConfiguration(
            locale: configuration.locale,
            includePartialResults: configuration.includePartialResults,
            includeTimestamps: include
        )
        return self
    }
    
    // MARK: - Main Transcription Method
    
    /// Start transcription and return a stream of text
    public func transcribe() -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    // Check permissions
                    try await requestPermissions()
                    
                    // Start transcription based on OS version
                    if #available(iOS 26.0, macOS 26.0, *) {
                        try await startModernTranscription(continuation: continuation)
                    } else {
                        try await startLegacyTranscription(continuation: continuation)
                    }
                    
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    /// Stop transcription
    public func stop() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        
        // Clean up legacy transcription
        legacyRecognizer?.stopRecognition()
        
        // Modern transcription will stop when audio stops
        speechAnalyzer = nil
        speechTranscriber = nil
        
        isTranscribing = false
    }
    
    // MARK: - Private Implementation
    
    @available(iOS 26.0, macOS 26.0, *)
    private func startModernTranscription(continuation: AsyncThrowingStream<String, Error>.Continuation) async throws {
        // Create transcriber
        let transcriber = SpeechTranscriber(
            locale: configuration.locale,
            transcriptionOptions: [],
            reportingOptions: configuration.includePartialResults ? [.volatileResults] : [],
            attributeOptions: configuration.includeTimestamps ? [.audioTimeRange] : []
        )
        self.speechTranscriber = transcriber
        
        // Create analyzer
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.speechAnalyzer = analyzer
        
        // Get best audio format
        let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        
        // Create audio stream
        let (audioStream, audioBuilder) = AsyncStream<AnalyzerInput>.makeStream()
        
        // Start analyzer
        try await analyzer.start(inputSequence: audioStream)
        
        // Install audio tap
        let inputNode = audioEngine.inputNode
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            let input = AnalyzerInput(buffer: buffer)
            audioBuilder.yield(input)
        }
        
        // Start audio engine
        audioEngine.prepare()
        try audioEngine.start()
        isTranscribing = true
        
        // Stream results
        Task {
            defer {
                continuation.finish()
            }
            
            for try await result in transcriber.results {
                if configuration.includePartialResults || result.isFinal {
                    continuation.yield(result.text.description)
                }
            }
        }
    }
    
    private func startLegacyTranscription(continuation: AsyncThrowingStream<String, Error>.Continuation) async throws {
        // Create legacy recognizer
        let recognizer = try LegacySpeechRecognizer(locale: configuration.locale)
        self.legacyRecognizer = recognizer
        
        // Start recognition
        let request = recognizer.startRecognition(
            includePartialResults: configuration.includePartialResults,
            onResult: { result in
                if self.configuration.includePartialResults || !result.isPartial {
                    continuation.yield(result.text)
                }
            },
            onError: { error in
                continuation.finish(throwing: error)
            }
        )
        
        // Install audio tap
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }
        
        // Start audio engine
        audioEngine.prepare()
        try audioEngine.start()
        isTranscribing = true
    }
    
    private func requestPermissions() async throws {
        // Check microphone permission
        let audioStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if audioStatus != .authorized {
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            if !granted {
                throw AuralError.permissionDenied
            }
        }
        
        // Check speech recognition permission
        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        if speechStatus != .authorized {
            let granted = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
            if !granted {
                throw AuralError.permissionDenied
            }
        }
    }
}

// MARK: - Convenience API

public extension AuralKit {
    /// Static method for quick transcription
    static func transcribe() -> AsyncThrowingStream<String, Error> {
        AuralKit().transcribe()
    }
    
    /// Computed property for cleaner syntax
    var transcriptions: AsyncThrowingStream<String, Error> {
        transcribe()
    }
}