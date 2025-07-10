import Foundation
import Speech
import AVFoundation

/// Simple wrapper for legacy SFSpeechRecognizer
internal class LegacySpeechRecognizer {
    private let recognizer: SFSpeechRecognizer
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    init(locale: Locale) throws {
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw AuralError.unsupportedLanguage
        }
        guard recognizer.isAvailable else {
            throw AuralError.modelNotAvailable
        }
        self.recognizer = recognizer
    }
    
    func startRecognition(
        includePartialResults: Bool,
        onResult: @escaping (AuralResult) -> Void,
        onError: @escaping (Error) -> Void
    ) -> SFSpeechAudioBufferRecognitionRequest {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = includePartialResults
        
        recognitionRequest = request
        
        recognitionTask = recognizer.recognitionTask(with: request) { result, error in
            if let error = error {
                onError(error)
                return
            }
            
            if let result = result {
                let auralResult = AuralResult(
                    text: result.bestTranscription.formattedString,
                    confidence: 1.0,
                    isPartial: !result.isFinal,
                    timestamp: 0
                )
                onResult(auralResult)
            }
        }
        
        return request
    }
    
    func stopRecognition() {
        recognitionTask?.cancel()
        recognitionRequest?.endAudio()
        recognitionTask = nil
        recognitionRequest = nil
    }
}