import Testing
@testable import AuralKit

@Suite("AuralKit Tests")
struct AuralKitTests {
    
    @MainActor
    private func createTestKit() -> AuralKit {
        return AuralKit()
    }
    
    @Test("AuralKit initialization")
    @MainActor
    func testInitialization() async {
        let kit = AuralKit()
        #expect(kit != nil)
    }
    
    @Test("Configuration fluent API")
    @MainActor
    func testConfiguration() async {
        let kit = AuralKit()
            .locale(.init(identifier: "es-ES"))
            .includePartialResults(false)
            .includeTimestamps(true)
        
        #expect(kit != nil)
    }
    
    @Test("Transcribe API availability")
    @MainActor
    func testTranscribeAPI() async {
        let kit = createTestKit()
        
        // Test instance method
        let stream1 = kit.transcribe()
        #expect(stream1 != nil)
        
        // Test static method
        let stream2 = AuralKit.transcribe()
        #expect(stream2 != nil)
        
        // Test computed property
        let stream3 = kit.transcriptions
        #expect(stream3 != nil)
    }
    
    @Test("Stop is safe to call")
    @MainActor
    func testStop() async {
        let kit = createTestKit()
        
        // Should not crash when called without transcribing
        kit.stop()
        #expect(true) // If we get here, it didn't crash
    }
}