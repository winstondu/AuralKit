import Foundation
import AVFoundation
@testable import AuralKit

internal struct MockAuralKitEngine: AuralKitEngineProtocol {
    let speechAnalyzer: SpeechAnalyzerProtocol
    let audioEngine: AudioEngineProtocol
    let modelManager: ModelManagerProtocol
    let bufferProcessor: AudioBufferProcessorProtocol
    
    init(speechAnalyzer: SpeechAnalyzerProtocol = MockSpeechAnalyzer(),
         audioEngine: AudioEngineProtocol = MockAudioEngine(),
         modelManager: ModelManagerProtocol = MockModelManager(),
         bufferProcessor: AudioBufferProcessorProtocol = MockAudioBufferProcessor()) {
        self.speechAnalyzer = speechAnalyzer
        self.audioEngine = audioEngine
        self.modelManager = modelManager
        self.bufferProcessor = bufferProcessor
    }
}

internal class MockSpeechAnalyzer: SpeechAnalyzerProtocol, @unchecked Sendable {
    private let (stream, continuation) = AsyncStream.makeStream(of: AuralResult.self)
    
    var results: AsyncStream<AuralResult> {
        stream
    }
    
    var configureCallCount = 0
    var startAnalysisCallCount = 0
    var stopAnalysisCallCount = 0
    var finishAnalysisCallCount = 0
    
    var lastConfiguration: AuralConfiguration?
    var shouldThrowOnConfigure = false
    var shouldThrowOnStart = false
    var shouldThrowOnStop = false
    var shouldThrowOnFinish = false
    
    var mockResults: [AuralResult] = []
    
    func configure(with configuration: AuralConfiguration) async throws {
        configureCallCount += 1
        lastConfiguration = configuration
        
        if shouldThrowOnConfigure {
            throw AuralError.recognitionFailed
        }
    }
    
    func startAnalysis() async throws {
        startAnalysisCallCount += 1
        
        if shouldThrowOnStart {
            throw AuralError.recognitionFailed
        }
        
        let results = mockResults
        Task { @Sendable in
            for result in results {
                continuation.yield(result)
            }
        }
    }
    
    func stopAnalysis() async throws {
        stopAnalysisCallCount += 1
        
        if shouldThrowOnStop {
            throw AuralError.recognitionFailed
        }
    }
    
    func finishAnalysis() async throws {
        finishAnalysisCallCount += 1
        
        if shouldThrowOnFinish {
            throw AuralError.recognitionFailed
        }
        
        continuation.finish()
    }
    
    func simulateResult(_ result: AuralResult) {
        continuation.yield(result)
    }
    
    func simulateResults(_ results: [AuralResult]) {
        for result in results {
            continuation.yield(result)
        }
    }
}

internal class MockAudioEngine: AudioEngineProtocol {
    var audioFormat: AVAudioFormat?
    var isRecording = false
    
    var requestPermissionCallCount = 0
    var startRecordingCallCount = 0
    var stopRecordingCallCount = 0
    var pauseRecordingCallCount = 0
    var resumeRecordingCallCount = 0
    
    var shouldReturnPermission = true
    var shouldThrowOnStart = false
    var shouldThrowOnStop = false
    var shouldThrowOnPause = false
    var shouldThrowOnResume = false
    
    func requestPermission() async -> Bool {
        requestPermissionCallCount += 1
        return shouldReturnPermission
    }
    
    func startRecording() async throws {
        startRecordingCallCount += 1
        
        if shouldThrowOnStart {
            throw AuralError.audioSetupFailed
        }
        
        isRecording = true
    }
    
    func stopRecording() async throws {
        stopRecordingCallCount += 1
        
        if shouldThrowOnStop {
            throw AuralError.audioSetupFailed
        }
        
        isRecording = false
    }
    
    func pauseRecording() throws {
        pauseRecordingCallCount += 1
        
        if shouldThrowOnPause {
            throw AuralError.audioSetupFailed
        }
    }
    
    func resumeRecording() throws {
        resumeRecordingCallCount += 1
        
        if shouldThrowOnResume {
            throw AuralError.audioSetupFailed
        }
    }
}

internal class MockModelManager: ModelManagerProtocol {
    var isModelAvailableCallCount = 0
    var downloadModelCallCount = 0
    var getDownloadProgressCallCount = 0
    var getSupportedLanguagesCallCount = 0
    
    var lastQueriedLanguage: AuralLanguage?
    var lastDownloadLanguage: AuralLanguage?
    
    var shouldReturnModelAvailable = true
    var shouldThrowOnDownload = false
    var mockDownloadProgress: Double?
    var mockSupportedLanguages: [AuralLanguage] = [.english, .spanish, .french]
    
    func isModelAvailable(for language: AuralLanguage) async -> Bool {
        isModelAvailableCallCount += 1
        lastQueriedLanguage = language
        return shouldReturnModelAvailable
    }
    
    func downloadModel(for language: AuralLanguage) async throws {
        downloadModelCallCount += 1
        lastDownloadLanguage = language
        
        if shouldThrowOnDownload {
            throw AuralError.networkError
        }
    }
    
    func getDownloadProgress(for language: AuralLanguage) async -> Double? {
        getDownloadProgressCallCount += 1
        return mockDownloadProgress
    }
    
    func getSupportedLanguages() async -> [AuralLanguage] {
        getSupportedLanguagesCallCount += 1
        return mockSupportedLanguages
    }
}

internal class MockAudioBufferProcessor: AudioBufferProcessorProtocol {
    var processBufferCallCount = 0
    var shouldThrowOnProcess = false
    
    func processBuffer(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        processBufferCallCount += 1
        
        if shouldThrowOnProcess {
            throw AuralError.audioSetupFailed
        }
        
        return buffer
    }
}