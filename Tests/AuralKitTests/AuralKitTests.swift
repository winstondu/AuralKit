import Testing
@testable import AuralKit

@Suite("AuralKit Tests")
struct AuralKitTests {
    
    @MainActor
    private func createTestSetup() -> (auralKit: AuralKit, mockEngine: MockAuralKitEngine, mockSpeechAnalyzer: MockSpeechAnalyzer, mockAudioEngine: MockAudioEngine, mockModelManager: MockModelManager) {
        let mockSpeechAnalyzer = MockSpeechAnalyzer()
        let mockAudioEngine = MockAudioEngine()
        let mockModelManager = MockModelManager()
        
        let mockEngine = MockAuralKitEngine(
            speechAnalyzer: mockSpeechAnalyzer,
            audioEngine: mockAudioEngine,
            modelManager: mockModelManager
        )
        
        let auralKit = AuralKit(engine: mockEngine)
        
        return (auralKit, mockEngine, mockSpeechAnalyzer, mockAudioEngine, mockModelManager)
    }
    
    @Test("AuralKit initialization")
    @MainActor
    func auralKitInitialization() {
        let auralKit = AuralKit()
        #expect(auralKit.isTranscribing == false)
        #expect(auralKit.currentText == "")
        #expect(auralKit.downloadProgress == 0.0)
        #expect(auralKit.error == nil)
    }
    
    @Test("Start transcribing success")
    @MainActor
    func startTranscribingSuccess() async throws {
        let setup = createTestSetup()
        let auralKit = setup.auralKit
        let mockSpeechAnalyzer = setup.mockSpeechAnalyzer
        
        await mockSpeechAnalyzer.setMockResults([
            AuralResult(text: "Hello", isPartial: false),
            AuralResult(text: "Hello world", isPartial: false),
            AuralResult(text: "Hello world!", isPartial: false)
        ])
        
        let result = try await auralKit.startTranscribing()
        #expect(result == "Hello world!")
        #expect(auralKit.isTranscribing == false)
    }
    
    @Test("Start transcribing with failure")
    @MainActor
    func startTranscribingFailure() async throws {
        let setup = createTestSetup()
        let auralKit = setup.auralKit
        let mockSpeechAnalyzer = setup.mockSpeechAnalyzer
        
        await mockSpeechAnalyzer.setShouldThrowOnStart(true)
        
        do {
            _ = try await auralKit.startTranscribing()
            Issue.record("Expected recognition failed error")
        } catch let error as AuralError {
            #expect(error == .recognitionFailed)
        }
    }
    
    @Test("Start transcribing when already transcribing")
    @MainActor
    func startTranscribingWhenAlreadyTranscribing() async throws {
        let setup = createTestSetup()
        let auralKit = setup.auralKit
        let mockSpeechAnalyzer = setup.mockSpeechAnalyzer
        
        await mockSpeechAnalyzer.setMockResults([
            AuralResult(text: "Test", isPartial: false)
        ])
        
        // Disable auto-yielding so the first transcription stays active
        await mockSpeechAnalyzer.setAutoYieldResults(false)
        
        Task {
            try? await auralKit.startTranscribing()
        }
        
        try? await Task.sleep(for: .milliseconds(100))
        
        do {
            _ = try await auralKit.startTranscribing()
            Issue.record("Expected recognition failed error")
        } catch let error as AuralError {
            #expect(error == .recognitionFailed)
        }
    }
    
    @Test("Start live transcription success")
    @MainActor
    func startLiveTranscriptionSuccess() async throws {
        actor ResultsCollector {
            private var results: [AuralResult] = []
            
            func add(_ result: AuralResult) {
                results.append(result)
            }
            
            func getResults() -> [AuralResult] {
                return results
            }
        }
        
        let setup = createTestSetup()
        let auralKit = setup.auralKit
        let mockSpeechAnalyzer = setup.mockSpeechAnalyzer
        let collector = ResultsCollector()
        
        // Disable auto-yielding for this test
        await mockSpeechAnalyzer.setAutoYieldResults(false)
        
        try await auralKit.startLiveTranscription { result in
            Task {
                await collector.add(result)
            }
        }
        
        #expect(auralKit.isTranscribing == true)
        
        await mockSpeechAnalyzer.simulateResults([
            AuralResult(text: "Hello", isPartial: false),
            AuralResult(text: "World", isPartial: false)
        ])
        
        try await Task.sleep(for: .milliseconds(100))
        
        let results = await collector.getResults()
        #expect(results.count == 2)
        #expect(results[0].text == "Hello")
        #expect(results[1].text == "World")
    }
    
    @Test("Stop transcription success")
    @MainActor
    func stopTranscriptionSuccess() async throws {
        let setup = createTestSetup()
        let auralKit = setup.auralKit
        
        try await auralKit.startLiveTranscription { _ in }
        #expect(auralKit.isTranscribing == true)
        
        try await auralKit.stopTranscription()
        #expect(auralKit.isTranscribing == false)
    }
    
    @Test("Stop transcription when not transcribing")
    @MainActor
    func stopTranscriptionWhenNotTranscribing() async throws {
        let setup = createTestSetup()
        let auralKit = setup.auralKit
        
        // Should not throw - it's idempotent
        try await auralKit.stopTranscription()
        #expect(auralKit.isTranscribing == false)
    }
}