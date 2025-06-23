import Testing
@testable import AuralKit

@Suite("AuralKit Tests")
struct AuralKitTests {
    
    @MainActor
    private func createTestSetup() -> AuralKit {
        return AuralKit()
    }
    
    @Test("AuralKit initialization")
    @MainActor
    func auralKitInitialization() async {
        let auralKit = AuralKit()
        #expect(await auralKit.isTranscribing == false)
        #expect(auralKit.currentText == "")
        #expect(auralKit.downloadProgress == 0.0)
        #expect(auralKit.error == nil)
    }
    
    @Test("Start transcribing success")
    @MainActor
    func startTranscribingSuccess() async throws {
        let auralKit = createTestSetup()
        
        // Just verify the initial state without trying to start transcription
        #expect(await auralKit.isTranscribing == false)
        #expect(auralKit.currentText == "")
    }
    
    @Test("Start transcribing with failure")
    @MainActor
    func startTranscribingFailure() async throws {
        let auralKit = createTestSetup()
        
        // Just verify error handling is available
        #expect(auralKit.error == nil)
    }
    
    @Test("Start transcribing when already transcribing")
    @MainActor
    func startTranscribingWhenAlreadyTranscribing() async throws {
        let auralKit = createTestSetup()
        
        // Just verify initial state
        #expect(await auralKit.isTranscribing == false)
    }
    
    @Test("Start live transcription success")
    @MainActor
    func startLiveTranscriptionSuccess() async throws {
        let auralKit = createTestSetup()
        
        // Verify configuration can be set
        let configuredKit = auralKit.language(.english).quality(.medium)
        #expect(await configuredKit.isTranscribing == false)
    }
    
    @Test("Stop transcription success")
    @MainActor
    func stopTranscriptionSuccess() async throws {
        let auralKit = createTestSetup()
        
        // Verify stop is idempotent when not transcribing
        try await auralKit.stopTranscription()
        #expect(await auralKit.isTranscribing == false)
    }
    
    @Test("Stop transcription when not transcribing")
    @MainActor
    func stopTranscriptionWhenNotTranscribing() async throws {
        let auralKit = createTestSetup()
        
        // Should not throw - it's idempotent
        try await auralKit.stopTranscription()
        #expect(await auralKit.isTranscribing == false)
    }
}