import SwiftUI
import AuralKit

struct TranscriptionView: View {
    @EnvironmentObject var manager: TranscriptionManager
    @State private var animationScale: CGFloat = 1.0
    @State private var showAlternatives = false
    @State private var showPermissionsAlert = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Transcript Display
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if !manager.finalizedText.isEmpty {
                            Text(manager.finalizedText)
                                .font(.body)
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(12)
                        }
                        
                        if !manager.volatileText.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text(manager.volatileText)
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                        .italic()
                                }
                                
                                // Show time range if available
                                if !manager.currentTimeRange.isEmpty {
                                    Label(manager.currentTimeRange, systemImage: "clock")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                // Show alternatives if available
                                if !manager.currentAlternatives.isEmpty && showAlternatives {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Alternatives:")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        ForEach(Array(manager.currentAlternatives.prefix(3).enumerated()), id: \.offset) { index, alternative in
                                            HStack {
                                                Text("\(index + 1).")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                                Text(alternative)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                                    .lineLimit(1)
                                            }
                                        }
                                    }
                                    .padding(.top, 4)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(12)
                        }
                        
                        if manager.finalizedText.isEmpty && manager.volatileText.isEmpty && !manager.isTranscribing {
                            VStack(spacing: 12) {
                                Image(systemName: "mic.circle")
                                    .font(.system(size: 60))
                                    .foregroundColor(.secondary)
                                Text("Tap the button below to start transcribing")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.top, 100)
                        }
                    }
                    .padding()
                }
                .frame(maxHeight: .infinity)
                
                // Error or Permission Display
                if manager.permissionStatus == .denied || manager.permissionStatus == .restricted {
                    VStack(spacing: 8) {
                        Label("Permissions Required", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.orange)
                        Text("Microphone and speech recognition permissions are required")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                    }
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                    .padding(.horizontal)
                } else if let error = manager.error {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                        .padding(.horizontal)
                }
                
                // Controls
                VStack(spacing: 20) {
                    // Language Selector
                    HStack {
                        Image(systemName: "globe")
                            .foregroundColor(.secondary)
                        Text("Language:")
                            .foregroundColor(.secondary)
                        Spacer()
                        Menu {
                            ForEach(commonLanguages.filter { $0.isSupported }, id: \.self) { language in
                                Button {
                                    manager.selectedLanguage = language
                                } label: {
                                    HStack {
                                        Text(language.displayName)
                                        if language == manager.selectedLanguage {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                            Divider()
                            NavigationLink("All Languages...") {
                                LanguageListView(selectedLanguage: $manager.selectedLanguage)
                            }
                        } label: {
                            HStack {
                                Text(manager.selectedLanguage.displayName)
                                    .foregroundColor(.primary)
                                if !manager.selectedLanguage.isSupported {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                                Image(systemName: "chevron.down")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                    .padding(.horizontal)
                    
                    // Record Button
                    Button(action: manager.toggleTranscription) {
                        ZStack {
                            Circle()
                                .fill(manager.isTranscribing ? Color.red : Color.blue)
                                .frame(width: 80, height: 80)
                                .scaleEffect(animationScale)
                            
                            Image(systemName: manager.isTranscribing ? "stop.fill" : "mic.fill")
                                .font(.system(size: 30))
                                .foregroundColor(.white)
                        }
                    }
                    .disabled(manager.error != nil || manager.permissionStatus != .authorized)
                    
                    // Status Text
                    Text(manager.isTranscribing ? "Listening..." : "Tap to start")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.bottom)
                }
                .padding(.vertical)
                .background(Color(UIColor.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 10, y: -5)
            }
            .navigationTitle("AuralKit Demo")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if !manager.currentTranscript.isEmpty {
                        ShareLink(item: manager.currentTranscript) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                    
                    Menu {
                        Toggle("Show Alternatives", isOn: $showAlternatives)
                            .disabled(manager.currentAlternatives.isEmpty)
                        
                        if manager.isIOS26Available {
                            Label("iOS 26+ Features Active", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else {
                            Label("iOS 26+ Features Unavailable", systemImage: "xmark.circle")
                                .foregroundColor(.secondary)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                animationScale = manager.isTranscribing ? 1.2 : 1.0
            }
        }
        .onChange(of: manager.isTranscribing) { _, isTranscribing in
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                animationScale = isTranscribing ? 1.2 : 1.0
            }
        }
    }
    
    var commonLanguages: [AuralLanguage] {
        [.english, .spanish, .french, .german, .italian, .portuguese, .chinese, .japanese, .korean]
    }
}