import SwiftUI
import AuralKit
import OSLog

struct ContentView: View {
    private static let logger = Logger(subsystem: "com.auralkit.demo", category: "ContentView")
    
    @State private var auralKit = AuralKit()
    @State private var selectedLanguage: AuralLanguage = .english
    @State private var selectedQuality: AuralQuality = .medium
    @State private var includePartialResults = true
    @State private var includeTimestamps = false
    @State private var showingOneShotResult = false
    @State private var oneShotResult = ""
    @State private var showingSettings = false
    
    var body: some View {
        #if os(iOS)
        NavigationStack {
            mainContent
                .navigationTitle("AuralKit Demo")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        settingsButton
                    }
                }
        }
        #else
        NavigationStack {
            mainContent
                .navigationTitle("AuralKit Demo")
                .toolbar {
                    ToolbarItem(placement: .automatic) {
                        settingsButton
                    }
                }
        }
        #endif
    }
    
    private var mainContent: some View {
        VStack(spacing: 20) {
            // Header
            VStack {
                Image(systemName: "waveform.and.mic")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                
                Text("AuralKit Demo")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Speech-to-Text Demonstration")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top)
            
            Divider()
            
            // Live Transcription Section
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "mic.circle.fill")
                        .foregroundColor(auralKit.isTranscribing ? .red : .gray)
                        .font(.title2)
                    Text("Live Transcription")
                        .font(.headline)
                    Spacer()
                }
                
                ScrollView {
                    Text(auralKit.currentText.isEmpty ? "Tap the microphone to start speaking..." : auralKit.currentText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(.regularMaterial)
                        .cornerRadius(12)
                        .font(.body)
                }
                .frame(height: 120)
                
                Button(action: toggleLiveTranscription) {
                    HStack {
                        Image(systemName: auralKit.isTranscribing ? "stop.circle.fill" : "mic.circle.fill")
                        Text(auralKit.isTranscribing ? "Stop Listening" : "Start Listening")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(auralKit.isTranscribing ? Color.red : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .font(.headline)
                }
                .disabled(auralKit.error != nil)
            }
            
            Divider()
            
            // One-Shot Transcription Section
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "waveform")
                        .font(.title2)
                    Text("One-Shot Transcription")
                        .font(.headline)
                    Spacer()
                }
                
                Button(action: performOneShotTranscription) {
                    HStack {
                        Image(systemName: "record.circle")
                        Text("Record & Transcribe")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .font(.headline)
                }
                .disabled(auralKit.isTranscribing)
            }
            
            // Status & Error Display
            if let error = auralKit.error {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(errorMessage(for: error))
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                .padding()
                .background(.orange.opacity(0.1))
                .cornerRadius(8)
            }
            
            if auralKit.downloadProgress > 0 && auralKit.downloadProgress < 1 {
                VStack(spacing: 8) {
                    Text("Downloading language model...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    ProgressView(value: auralKit.downloadProgress)
                        .progressViewStyle(LinearProgressViewStyle())
                }
                .padding()
                .background(.blue.opacity(0.1))
                .cornerRadius(8)
            }
            
            Spacer()
        }
        .padding()
        .sheet(isPresented: $showingSettings) {
            SettingsView(
                selectedLanguage: $selectedLanguage,
                selectedQuality: $selectedQuality,
                includePartialResults: $includePartialResults,
                includeTimestamps: $includeTimestamps
            )
        }
        .alert("Transcription Result", isPresented: $showingOneShotResult) {
            Button("OK") { }
        } message: {
            Text(oneShotResult)
        }
        .onChange(of: selectedLanguage) { _, newValue in
            updateConfiguration()
        }
        .onChange(of: selectedQuality) { _, newValue in
            updateConfiguration()
        }
        .onChange(of: includePartialResults) { _, newValue in
            updateConfiguration()
        }
        .onChange(of: includeTimestamps) { _, newValue in
            updateConfiguration()
        }
    }
    
    private var settingsButton: some View {
        Button("Settings") {
            showingSettings = true
        }
    }
    
    // MARK: - Actions
    
    private func toggleLiveTranscription() {
        Task {
            do {
                Self.logger.debug("Starting toggle operation...")
                try await auralKit.toggle()
                Self.logger.debug("Toggle completed successfully")
            } catch {
                Self.logger.error("Live transcription error: \(error)")
                // Update UI with error
                await MainActor.run {
                    // Force update the UI state if there's an error
                    if auralKit.isTranscribing {
                        // Force stop if there's an issue
                        Task {
                            try? await auralKit.stopTranscription()
                        }
                    }
                }
            }
        }
    }
    
    private func performOneShotTranscription() {
        Task {
            do {
                Self.logger.debug("Starting one-shot transcription...")
                let configuredAuralKit = AuralKit()
                    .language(selectedLanguage)
                    .quality(selectedQuality)
                    .includePartialResults(includePartialResults)
                    .includeTimestamps(includeTimestamps)
                
                Self.logger.debug("Configuration set, starting transcription...")
                let result = try await configuredAuralKit.startTranscribing()
                Self.logger.debug("One-shot transcription result: '\(result)'")
                
                await MainActor.run {
                    oneShotResult = result.isEmpty ? "No speech detected" : result
                    showingOneShotResult = true
                }
            } catch {
                Self.logger.error("One-shot transcription error: \(error)")
                await MainActor.run {
                    oneShotResult = "Error: \(error.localizedDescription)"
                    showingOneShotResult = true
                }
            }
        }
    }
    
    private func updateConfiguration() {
        _ = auralKit
            .language(selectedLanguage)
            .quality(selectedQuality)
            .includePartialResults(includePartialResults)
            .includeTimestamps(includeTimestamps)
    }
    
    private func errorMessage(for error: AuralError) -> String {
        switch error {
        case .permissionDenied:
            return "Microphone permission required"
        case .recognitionFailed:
            return "Speech recognition failed"
        case .audioSetupFailed:
            return "Audio setup failed"
        case .modelNotAvailable:
            return "Language model not available"
        case .unsupportedLanguage:
            return "Language not supported"
        case .networkError:
            return "Network error downloading model"
        }
    }
}

struct SettingsView: View {
    @Binding var selectedLanguage: AuralLanguage
    @Binding var selectedQuality: AuralQuality
    @Binding var includePartialResults: Bool
    @Binding var includeTimestamps: Bool
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        #if os(iOS)
        NavigationStack {
            settingsContent
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        doneButton
                    }
                }
        }
        #else
        NavigationView {
            settingsContent
                .navigationTitle("Settings")
                .toolbar {
                    ToolbarItem(placement: .automatic) {
                        doneButton
                    }
                }
        }
        .frame(width: 400, height: 500)
        #endif
    }
    
    private var settingsContent: some View {
        Form {
            Section("Language") {
                Picker("Language", selection: $selectedLanguage) {
                    Text("English").tag(AuralLanguage.english)
                    Text("Spanish").tag(AuralLanguage.spanish)
                    Text("French").tag(AuralLanguage.french)
                    Text("German").tag(AuralLanguage.german)
                    Text("Chinese").tag(AuralLanguage.chinese)
                }
                .pickerStyle(.menu)
            }
            
            Section("Quality") {
                Picker("Quality", selection: $selectedQuality) {
                    Text("Low").tag(AuralQuality.low)
                    Text("Medium").tag(AuralQuality.medium)
                    Text("High").tag(AuralQuality.high)
                }
                .pickerStyle(.segmented)
            }
            
            Section("Options") {
                Toggle("Include Partial Results", isOn: $includePartialResults)
                Toggle("Include Timestamps", isOn: $includeTimestamps)
            }
            
            Section("About") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("AuralKit Demo")
                        .font(.headline)
                    Text("Demonstrates speech-to-text capabilities using Apple's Speech framework with modern Swift 6 concurrency patterns.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Text("Framework Version:")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("1.0.0")
                            .font(.caption2)
                            .fontWeight(.medium)
                    }
                }
            }
        }
    }
    
    private var doneButton: some View {
        Button("Done") {
            dismiss()
        }
    }
}

#Preview {
    ContentView()
}
