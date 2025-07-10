import SwiftUI
import AuralKit

struct TranscriptionView: View {
    @EnvironmentObject var manager: TranscriptionManager
    @State private var animationScale: CGFloat = 1.0
    
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
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text(manager.volatileText)
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .italic()
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
                
                // Error Display
                if let error = manager.error {
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
                            ForEach(commonLanguages, id: \.self) { language in
                                Button(language.displayName) {
                                    manager.selectedLanguage = language
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
                    .disabled(manager.error != nil)
                    
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
                if !manager.currentTranscript.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: manager.currentTranscript) {
                            Image(systemName: "square.and.arrow.up")
                        }
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