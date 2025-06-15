import Foundation
import AVFoundation

/// Protocol defining the interface for audio recording and processing operations.
///
/// AudioEngineProtocol abstracts the audio input system, handling microphone
/// access, recording control, and audio format management. This abstraction
/// allows for different implementations including production engines using
/// AVAudioEngine and mock implementations for testing.
///
/// ## Permission Management
/// The audio engine handles microphone permission requests automatically,
/// but applications should be prepared to handle permission denial gracefully.
///
/// ## Audio Format
/// The engine provides information about the current audio format, which
/// is used by other components for proper audio processing and conversion.
///
/// ## Example
/// ```swift
/// let audioEngine: AudioEngineProtocol = ProductionAudioEngine()
/// 
/// guard await audioEngine.requestPermission() else {
///     throw AuralError.permissionDenied
/// }
/// 
/// try await audioEngine.startRecording()
/// // ... process audio ...
/// try await audioEngine.stopRecording()
/// ```
protocol AudioEngineProtocol {
    /// The current audio format being used for recording.
    ///
    /// This property provides the audio format information needed for
    /// audio processing and conversion. It may be nil before recording
    /// has been configured.
    var audioFormat: AVAudioFormat? { get }
    
    /// Whether the audio engine is currently recording.
    ///
    /// This property indicates the current recording state and can be
    /// used to prevent conflicting operations or update UI state.
    var isRecording: Bool { get }
    
    /// Requests permission to access the microphone.
    ///
    /// This method handles the system permission request for microphone
    /// access. It should be called before attempting to start recording.
    ///
    /// - Returns: `true` if permission is granted, `false` if denied
    func requestPermission() async -> Bool
    
    /// Starts audio recording from the microphone.
    ///
    /// This method configures and starts the audio recording session.
    /// The audio engine will begin capturing audio and making it available
    /// for processing by the speech recognition system.
    ///
    /// - Throws: AuralError.audioSetupFailed if recording cannot be started
    func startRecording() async throws
    
    /// Stops audio recording.
    ///
    /// This method stops the recording session and releases audio resources.
    /// Any ongoing audio processing should be completed before calling this method.
    ///
    /// - Throws: AuralError.audioSetupFailed if stopping fails
    func stopRecording() async throws
    
    /// Pauses audio recording temporarily.
    ///
    /// This method pauses recording while maintaining the recording session.
    /// Recording can be resumed using `resumeRecording()`.
    ///
    /// - Throws: AuralError.audioSetupFailed if pausing fails
    func pauseRecording() throws
    
    /// Resumes audio recording after a pause.
    ///
    /// This method resumes recording that was previously paused using
    /// `pauseRecording()`.
    ///
    /// - Throws: AuralError.audioSetupFailed if resuming fails
    func resumeRecording() throws
}