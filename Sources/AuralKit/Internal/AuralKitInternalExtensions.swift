import Foundation
import OSLog

/// Internal extensions for AuralKit to handle system events
internal extension AuralKit {
    /// Handle permission changes during active transcription
    @MainActor
    func handlePermissionChange(audio: Bool? = nil, speech: Bool? = nil) async {
        if let audioGranted = audio, !audioGranted {
            Self.logger.error("Audio permission revoked during transcription")
            error = .permissionDenied
            
            // Stop transcription if active
            if await stateManager.isTranscribing() {
                try? await stopTranscription()
            }
        }
        
        if let speechGranted = speech, !speechGranted {
            Self.logger.error("Speech recognition permission revoked during transcription")
            error = .permissionDenied
            
            // Stop transcription if active
            if await stateManager.isTranscribing() {
                try? await stopTranscription()
            }
        }
    }
    
    /// Handle audio hardware changes during active transcription
    @MainActor
    func handleAudioHardwareChange(_ change: AudioHardwareMonitor.AudioHardwareChange) async {
        switch change {
        #if os(iOS) || os(tvOS)
        case .routeChanged(_, let newRoute):
            Self.logger.info("Audio route changed during transcription")
            
            // Check if we still have a valid input
            if newRoute.inputs.isEmpty {
                Self.logger.error("No audio input available after route change")
                error = .audioSetupFailed
                
                // Stop transcription if active
                if await stateManager.isTranscribing() {
                    try? await stopTranscription()
                }
            }
        #else
        case .routeChanged:
            Self.logger.info("Audio route changed during transcription")
        #endif
            
        case .interruptionBegan:
            Self.logger.warning("Audio interruption during transcription")
            // Pause if possible, or note the interruption
            
        case .interruptionEnded(let shouldResume):
            let isTranscribing = await stateManager.isTranscribing()
            if shouldResume && isTranscribing {
                Self.logger.info("Attempting to resume after interruption")
                // Could implement resume logic here
            }
            
        case .mediaServicesReset:
            Self.logger.error("Media services reset - stopping transcription")
            error = .audioSetupFailed
            
            // Must stop and reconfigure everything
            if await stateManager.isTranscribing() {
                try? await stopTranscription()
            }
            
        case .silenceSecondaryAudioHint:
            // This is informational - we might want to adjust our audio session
            break
        }
    }
}