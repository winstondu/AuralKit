import SwiftUI
import AuralKit
import Combine

@MainActor
class TranscriptionManager: ObservableObject {
    @Published var isTranscribing = false
    @Published var currentTranscript = ""
    @Published var volatileText = ""
    @Published var finalizedText = ""
    @Published var transcriptionHistory: [TranscriptionRecord] = []
    @Published var selectedLanguage: AuralLanguage = .english
    @Published var includePartialResults = true
    @Published var includeTimestamps = false
    @Published var error: String?
    
    private var transcriptionTask: Task<Void, Never>?
    
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
        
        // Try using the static method directly since init might not be public
        transcriptionTask = Task {
            do {
                for try await result in AuralKit.transcribe() {
                    if result.isFinal {
                        finalizedText += (finalizedText.isEmpty ? "" : " ") + String(result.text.characters)
                        volatileText = ""
                    } else {
                        volatileText = String(result.text.characters)
                    }
                    currentTranscript = fullTranscript
                }
            } catch {
                self.error = error.localizedDescription
                self.isTranscribing = false
            }
        }
    }
    
    func stopTranscription() {
        guard isTranscribing else { return }
        
        transcriptionTask?.cancel()
        isTranscribing = false
        
        if !currentTranscript.isEmpty {
            let record = TranscriptionRecord(
                id: UUID(),
                text: currentTranscript,
                language: selectedLanguage,
                timestamp: Date()
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
    
    var language: AuralLanguage? {
        AuralLanguage.allCases.first { $0.rawValue == languageCode }
    }
    
    init(id: UUID, text: String, language: AuralLanguage, timestamp: Date) {
        self.id = id
        self.text = text
        self.languageCode = language.rawValue
        self.timestamp = timestamp
    }
}