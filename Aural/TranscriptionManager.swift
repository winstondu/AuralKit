import SwiftUI
import AuralKit
import CoreMedia

@Observable
class TranscriptionManager {
    var isTranscribing = false
    var currentTranscript = ""
    var volatileText = ""
    var finalizedText = ""
    var transcriptionHistory: [TranscriptionRecord] = []
    var selectedLanguage: AuralLanguage = .english
    var includePartialResults = true
    var includeTimestamps = false
    var error: String?
    var currentAlternatives: [String] = []
    var currentTimeRange = ""
    var isIOS26Available = false
    
    private var transcriptionTask: Task<Void, Never>?
    private var auralKit: AuralKit?
    
    init() {
        checkIOS26Availability()
    }
    
    private func checkIOS26Availability() {
        if #available(iOS 26.0, *) {
            isIOS26Available = true
        }
    }
    
    var fullTranscript: String {
        finalizedText + (volatileText.isEmpty ? "" : " " + volatileText)
    }
    
    func startTranscription() {
        guard !isTranscribing else { return }
        
        isTranscribing = true
        error = nil
        currentTranscript = ""
        volatileText = ""
        finalizedText = ""
        currentAlternatives = []
        currentTimeRange = ""
        
        
        // Create configured AuralKit instance
        auralKit = AuralKit()
            .language(selectedLanguage)
            .includePartialResults(includePartialResults)
            .includeTimestamps(includeTimestamps && isIOS26Available)
        
        transcriptionTask = Task {
            do {
                guard let auralKit = auralKit else { return }
                
                for try await result in auralKit.transcribe() {
                    handleTranscriptionResult(result)
                }
            } catch let auralError as AuralError {
                self.error = auralError.errorDescription
                self.isTranscribing = false
            } catch {
                self.error = error.localizedDescription
                self.isTranscribing = false
            }
        }
    }
    
    private func handleTranscriptionResult(_ result: AuralResult) {
        if result.isFinal {
            finalizedText += (finalizedText.isEmpty ? "" : " ") + String(result.text.characters)
            volatileText = ""
        } else {
            volatileText = String(result.text.characters)
        }
        currentTranscript = fullTranscript
        
        // Handle alternatives
        currentAlternatives = result.alternatives.map { String($0.characters) }
        
        // Handle time range if available
        if result.range.duration.seconds > 0 {
            let start = formatTime(result.range.start)
            let end = formatTime(result.range.end)
            currentTimeRange = "\(start) - \(end)"
        } else {
            currentTimeRange = ""
        }
    }
    
    private func formatTime(_ time: CMTime) -> String {
        let seconds = time.seconds
        let minutes = Int(seconds / 60)
        let remainingSeconds = Int(seconds.truncatingRemainder(dividingBy: 60))
        let milliseconds = Int((seconds.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%d:%02d.%02d", minutes, remainingSeconds, milliseconds)
    }
    
    func stopTranscription() {
        guard isTranscribing else { return }
        
        transcriptionTask?.cancel()
        auralKit?.stop()
        isTranscribing = false
        
        if !currentTranscript.isEmpty {
            let record = TranscriptionRecord(
                id: UUID(),
                text: currentTranscript,
                language: selectedLanguage,
                timestamp: Date(),
                alternatives: currentAlternatives,
                timeRange: currentTimeRange
            )
            transcriptionHistory.insert(record, at: 0)
        }
    }
    
    func toggleTranscription() {
        if isTranscribing {
            stopTranscription()
        } else {
            startTranscription()
        }
    }
    
    func clearHistory() {
        transcriptionHistory.removeAll()
    }
    
    func deleteRecord(_ record: TranscriptionRecord) {
        transcriptionHistory.removeAll { $0.id == record.id }
    }
}

struct TranscriptionRecord: Identifiable, Codable {
    let id: UUID
    let text: String
    let languageCode: String
    let timestamp: Date
    let alternatives: [String]
    let timeRange: String
    
    var language: AuralLanguage? {
        AuralLanguage.allCases.first { $0.rawValue == languageCode }
    }
    
    init(id: UUID, text: String, language: AuralLanguage, timestamp: Date, alternatives: [String] = [], timeRange: String = "") {
        self.id = id
        self.text = text
        self.languageCode = language.rawValue
        self.timestamp = timestamp
        self.alternatives = alternatives
        self.timeRange = timeRange
    }
}
