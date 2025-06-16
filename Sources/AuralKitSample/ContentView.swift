import SwiftUI
import AuralKit

struct ContentView: View {
    @State private var auralKit = AuralKit()
    @State private var selectedLanguage: AuralLanguage = .english
    @State private var selectedQuality: AuralQuality = .medium
    @State private var includePartialResults = true
    @State private var includeTimestamps = false
    @State private var showingOneShotResult = false
    @State private var oneShotResult = ""
    @State private var showingSettings = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Header
                VStack {
                    Image(systemName: "waveform.and.mic")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                    
                    Text("AuralKit Sample")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Speech-to-Text Demo")
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
                        Text("Live Transcription")
                            .font(.headline)
                        Spacer()
                    }
                    
                    ScrollView {
                        Text(auralKit.currentText.isEmpty ? "Tap the microphone to start speaking..." : auralKit.currentText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(.regularMaterial)
                            .cornerRadius(8)
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
                        .cornerRadius(10)
                    }
                    .disabled(auralKit.error != nil)
                }
                
                Divider()
                
                // One-Shot Transcription Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "waveform")
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
                        .cornerRadius(10)
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
                    .padding(.horizontal)
                }
                
                if auralKit.downloadProgress > 0 && auralKit.downloadProgress < 1 {
                    VStack {
                        Text("Downloading language model...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        ProgressView(value: auralKit.downloadProgress)
                            .progressViewStyle(LinearProgressViewStyle())
                    }
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("AuralKit Demo")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("Settings") {
                        showingSettings = true
                    }
                }
            }
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
    
    // MARK: - Actions
    
    private func toggleLiveTranscription() {
        Task {
            do {
                try await auralKit.toggle()
            } catch {
                print("Live transcription error: \(error)")
            }
        }
    }
    
    private func performOneShotTranscription() {
        Task {
            do {
                let configuredAuralKit = AuralKit()
                    .language(selectedLanguage)
                    .quality(selectedQuality)
                    .includePartialResults(includePartialResults)
                    .includeTimestamps(includeTimestamps)
                
                let result = try await configuredAuralKit.startTranscribing()
                
                await MainActor.run {
                    oneShotResult = result.isEmpty ? "No speech detected" : result
                    showingOneShotResult = true
                }
            } catch {
                await MainActor.run {
                    oneShotResult = "Error: \(error.localizedDescription)"
                    showingOneShotResult = true
                }
            }
        }
    }
    
    private func updateConfiguration() {
        // Update the live transcription instance with new configuration
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
        NavigationView {
            Form {
                Section("Language") {
                    Picker("Language", selection: $selectedLanguage) {
                        Text("English").tag(AuralLanguage.english)
                        Text("Spanish").tag(AuralLanguage.spanish)
                        Text("French").tag(AuralLanguage.french)
                        Text("German").tag(AuralLanguage.german)
                        Text("Chinese").tag(AuralLanguage.chinese)
                    }
                    .pickerStyle(MenuPickerStyle())
                }
                
                Section("Quality") {
                    Picker("Quality", selection: $selectedQuality) {
                        Text("Low").tag(AuralQuality.low)
                        Text("Medium").tag(AuralQuality.medium)
                        Text("High").tag(AuralQuality.high)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                
                Section("Options") {
                    Toggle("Include Partial Results", isOn: $includePartialResults)
                    Toggle("Include Timestamps", isOn: $includeTimestamps)
                }
                
                Section("About") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("AuralKit Sample App")
                            .font(.headline)
                        Text("Demonstrates speech-to-text capabilities using Apple's Speech framework with modern Swift concurrency.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
}