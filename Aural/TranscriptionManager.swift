import SwiftUI
import Speech
import AuralKit
import Combine
import AVFoundation
import CoreMedia

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
    @Published var permissionStatus: PermissionStatus = .unknown
    @Published var currentAlternatives: [String] = []
    @Published var currentTimeRange: String = ""
    @Published var isIOS26Available = false
    
    private var transcriptionTask: Task<Void, Never>?
    private var auralKit: AuralKit?
    
    enum PermissionStatus {
        case unknown
        case authorized
        case denied
        case restricted
    }
    
    init() {
        checkIOS26Availability()
        checkPermissions()
    }
    
    private func checkIOS26Availability() {
        if #available(iOS 26.0, *) {
            isIOS26Available = true
        }
    }
    
    private func checkPermissions() {
        Task {
            #if os(macOS)
            // macOS-specific: Check if Siri and Dictation are enabled
            guard SFSpeechRecognizer(locale: Locale.current)?.isAvailable == true else {
                permissionStatus = .restricted
                error = "Please enable Siri and Dictation in System Settings"
                return
            }
            #endif
            
            let audioSession = AVAudioSession.sharedInstance()
            let speechStatus = SFSpeechRecognizer.authorizationStatus()
            
            switch (audioSession.recordPermission, speechStatus) {
            case (.granted, .authorized):
                permissionStatus = .authorized
            case (.denied, _), (_, .denied):
                permissionStatus = .denied
            case (.undetermined, _), (_, .notDetermined):
                permissionStatus = .unknown
            default:
                permissionStatus = .restricted
            }
        }
    }
    
    var fullTranscript: String {
        finalizedText + (volatileText.isEmpty ? "" : " " + volatileText)
    }
    
    func startTranscription() {
        guard !isTranscribing else { return }
        guard permissionStatus == .authorized else {
            error = "Microphone or speech recognition permissions not granted"
            return
        }
        
        isTranscribing = true
        error = nil
        currentTranscript = ""
        volatileText = ""
        finalizedText = ""
        currentAlternatives = []
        currentTimeRange = ""
        
        // Check if language is supported
        #if os(macOS)
        // On macOS, also check if recognizer is available
        let recognizer = SFSpeechRecognizer(locale: selectedLanguage.locale)
        guard recognizer?.isAvailable == true else {
            error = "Speech recognition not available for \(selectedLanguage.displayName). Please check Siri and Dictation settings."
            isTranscribing = false
            return
        }
        #else
        // iOS check remains the same
        guard selectedLanguage.isSupported else {
            error = "Selected language \(selectedLanguage.displayName) is not supported on this device"
            isTranscribing = false
            return
        }
        #endif
        
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
