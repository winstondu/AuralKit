import SwiftUI
import AuralKit

struct SettingsView: View {
    @EnvironmentObject var manager: TranscriptionManager
    @State private var showingAbout = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Transcription Options") {
                    Toggle("Include Partial Results", isOn: $manager.includePartialResults)
                    Toggle("Include Timestamps", isOn: $manager.includeTimestamps)
                        .disabled(true)
                        .overlay(alignment: .trailing) {
                            Text("iOS 26+")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.trailing, 40)
                        }
                }
                
                Section("Default Language") {
                    NavigationLink {
                        LanguageListView(selectedLanguage: $manager.selectedLanguage)
                    } label: {
                        HStack {
                            Text("Language")
                            Spacer()
                            Text(manager.selectedLanguage.displayName)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Section("About") {
                    Button {
                        showingAbout = true
                    } label: {
                        HStack {
                            Text("About AuralKit")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .foregroundColor(.primary)
                    
                    Link(destination: URL(string: "https://github.com/rryam/AuralKit")!) {
                        HStack {
                            Label("View on GitHub", systemImage: "link")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption)
                        }
                    }
                }
                
                Section {
                    VStack(spacing: 8) {
                        Text("AuralKit Demo")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Version 1.0.0")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showingAbout) {
                AboutView()
            }
        }
    }
}