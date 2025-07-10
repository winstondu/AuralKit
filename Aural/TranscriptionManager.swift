import SwiftUI
import AuralKit
import CoreMedia

@available(iOS 26.0, macOS 26.0, *)
@Observable
class TranscriptionManager {
    var isTranscribing = false
    var currentTranscript = ""
    var volatileText = ""
    var finalizedText = ""
    var transcriptionHistory: [TranscriptionRecord] = []
    var selectedLocale: Locale = .current
    var includePartialResults = true
    var includeTimestamps = true
    var includeAlternatives = true
    var error: String?
    var currentAlternatives: [String] = []
    var currentTimeRange = ""
    
    private var transcriptionTask: Task<Void, Never>?
    private var auralKit: AuralKit?
    
    init() {}
    
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
            .locale(selectedLocale)
            .includePartialResults(includePartialResults)
            .includeTimestamps(includeTimestamps)
        
        transcriptionTask = Task {
            do {
                guard let auralKit = auralKit else { return }
                
                for try await result in auralKit.transcribe() {
                    await MainActor.run {
                        handleTranscriptionResult(result)
                    }
                }
            } catch let auralError as AuralError {
                await MainActor.run {
                    self.error = auralError.errorDescription
                    self.isTranscribing = false
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isTranscribing = false
                }
            }
        }
    }
    
    private func handleTranscriptionResult(_ result: AuralResult) {
        let text = result.text.string
        if result.isFinal {
            finalizedText += (finalizedText.isEmpty ? "" : " ") + text
            volatileText = ""
        } else {
            volatileText = text
        }
        currentTranscript = fullTranscript
        
        // Clear alternatives (not supported in new API)
        currentAlternatives = []
        
        // Extract time range from AttributedString if available
        currentTimeRange = ""
        result.text.runs.forEach { run in
            if let audioRange = run.audioTimeRange {
                let start = formatTime(audioRange.start)
                let end = formatTime(audioRange.end)
                currentTimeRange = "\(start) - \(end)"
            }
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
                locale: selectedLocale,
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
    let localeIdentifier: String
    let timestamp: Date
    let alternatives: [String]
    let timeRange: String
    
    var locale: Locale {
        Locale(identifier: localeIdentifier)
    }
    
    init(id: UUID, text: String, locale: Locale, timestamp: Date, alternatives: [String] = [], timeRange: String = "") {
        self.id = id
        self.text = text
        self.localeIdentifier = locale.identifier
        self.timestamp = timestamp
        self.alternatives = alternatives
        self.timeRange = timeRange
    }
}
