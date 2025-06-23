import Foundation
import OSLog

/// Centralized state manager for AuralKit to ensure proper state synchronization across actors
/// This manager provides atomic state updates and prevents race conditions
@globalActor
public actor AuralStateManager {
    public static let shared = AuralStateManager()
    
    private init() {}
}

/// State management for AuralKit operations
internal actor AuralState {
    private static let logger = Logger(subsystem: "com.auralkit", category: "StateManager")
    
    // MARK: - State Properties
    
    /// The current transcription state
    private(set) var transcriptionState: TranscriptionState = .idle
    
    /// Whether audio recording is active
    private(set) var isAudioRecording = false
    
    /// Whether speech recognition is active
    private(set) var isSpeechRecognizing = false
    
    /// Whether the system is properly initialized
    private(set) var isInitialized = false
    
    /// Current error state
    private(set) var currentError: AuralError?
    
    /// Shared singleton instance
    static let shared = AuralState()
    
    private init() {}
    
    // MARK: - State Types
    
    enum TranscriptionState: Equatable {
        case idle
        case preparing
        case recording
        case transcribing
        case stopping
        case error(AuralError)
        
        var isActive: Bool {
            switch self {
            case .recording, .transcribing:
                return true
            default:
                return false
            }
        }
    }
    
    // MARK: - State Queries
    
    /// Check if transcription is currently active
    func isTranscribing() -> Bool {
        transcriptionState.isActive
    }
    
    /// Get the current state
    func getCurrentState() -> (state: TranscriptionState, audioRecording: Bool, speechRecognizing: Bool) {
        (transcriptionState, isAudioRecording, isSpeechRecognizing)
    }
    
    // MARK: - State Transitions
    
    /// Begin preparing for transcription
    func beginPreparing() async throws {
        Self.logger.debug("State transition: beginPreparing")
        
        guard transcriptionState == .idle else {
            Self.logger.error("Cannot begin preparing from state: \(String(describing: self.transcriptionState))")
            throw AuralError.recognitionFailed
        }
        
        transcriptionState = .preparing
        currentError = nil
    }
    
    /// Mark audio recording as started
    func audioRecordingStarted() async {
        Self.logger.debug("State update: audioRecordingStarted")
        isAudioRecording = true
        
        // Transition to recording state if we're preparing
        if transcriptionState == .preparing {
            transcriptionState = .recording
        }
    }
    
    /// Mark speech recognition as started
    func speechRecognitionStarted() async {
        Self.logger.debug("State update: speechRecognitionStarted")
        isSpeechRecognizing = true
        
        // Only transition to transcribing if audio is already recording
        if isAudioRecording && transcriptionState == .recording {
            transcriptionState = .transcribing
        }
    }
    
    /// Wait for audio to be ready before starting speech recognition
    func waitForAudioReady(timeout: TimeInterval = 5.0) async throws {
        Self.logger.debug("Waiting for audio to be ready...")
        
        let startTime = Date()
        while !isAudioRecording {
            if Date().timeIntervalSince(startTime) > timeout {
                Self.logger.error("Timeout waiting for audio recording to start")
                throw AuralError.audioSetupFailed
            }
            
            // Small delay to avoid busy waiting
            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }
        
        Self.logger.debug("Audio is ready")
    }
    
    /// Begin stopping transcription
    func beginStopping() async {
        Self.logger.debug("State transition: beginStopping")
        transcriptionState = .stopping
    }
    
    /// Mark audio recording as stopped
    func audioRecordingStopped() async {
        Self.logger.debug("State update: audioRecordingStopped")
        isAudioRecording = false
    }
    
    /// Mark speech recognition as stopped
    func speechRecognitionStopped() async {
        Self.logger.debug("State update: speechRecognitionStopped")
        isSpeechRecognizing = false
    }
    
    /// Complete stop operation and return to idle
    func completeStop() async {
        Self.logger.debug("State transition: completeStop")
        isAudioRecording = false
        isSpeechRecognizing = false
        transcriptionState = .idle
        currentError = nil
    }
    
    /// Handle error state
    func handleError(_ error: AuralError) async {
        Self.logger.error("State transition: error - \(error)")
        currentError = error
        transcriptionState = .error(error)
        isAudioRecording = false
        isSpeechRecognizing = false
    }
    
    /// Reset to idle state
    func reset() async {
        Self.logger.debug("State reset to idle")
        transcriptionState = .idle
        isAudioRecording = false
        isSpeechRecognizing = false
        currentError = nil
        isInitialized = false
    }
    
    /// Mark system as initialized
    func markInitialized() async {
        Self.logger.debug("System marked as initialized")
        isInitialized = true
    }
}

/// Extension to make state observable from MainActor
extension AuralState {
    /// Get current transcription state for UI updates
    @MainActor
    func getTranscriptionStateForUI() async -> Bool {
        await isTranscribing()
    }
}