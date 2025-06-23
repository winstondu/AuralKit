import Foundation
import AVFoundation

/// Protocol for legacy speech recognition support (iOS 17+, macOS 14+)
internal protocol LegacySpeechRecognizerProtocol: Actor {
    /// Stream of recognition results
    var results: AsyncStream<AuralResult> { get }
    
    /// Configure the recognizer with the given configuration
    func configure(with configuration: AuralConfiguration) async throws
    
    /// Start speech recognition (prepares but doesn't start task)
    func startRecognition() async throws
    
    /// Start the recognition task after audio is ready
    func startRecognitionTask() async throws
    
    /// Stop speech recognition
    func stopRecognition() async throws
    
    /// Finish analysis and close the stream
    func finishAnalysis() async throws
    
    /// Process audio buffer for recognition
    func processAudioBuffer(_ buffer: AVAudioPCMBuffer) async throws
    
    /// Transcribe an audio file
    func transcribeFile(at url: URL) async throws -> String
    
    /// Transcribe an audio file with progress callbacks
    func transcribeFile(at url: URL, onResult: @escaping @MainActor @Sendable (AuralResult) -> Void) async throws
    
    /// Add a temporary file for cleanup tracking
    func addTemporaryFile(_ url: URL)
    
    /// Remove and clean up a temporary file
    func removeTemporaryFile(_ url: URL)
}