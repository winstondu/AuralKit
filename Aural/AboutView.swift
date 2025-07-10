import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Hero Section
                    VStack(spacing: 16) {
                        Image(systemName: "mic.circle.fill")
                            .font(.system(size: 80))
                            .foregroundStyle(.linearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                        
                        Text("AuralKit")
                            .font(.largeTitle)
                            .bold()
                        
                        Text("Simple Speech-to-Text for iOS & macOS")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical)
                    
                    // Features
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Features")
                            .font(.headline)
                        
                        FeatureRow(
                            icon: "checkmark.circle.fill",
                            title: "Simple API",
                            description: "Just one line to start transcribing"
                        )
                        
                        FeatureRow(
                            icon: "globe",
                            title: "40+ Languages",
                            description: "Support for languages worldwide"
                        )
                        
                        FeatureRow(
                            icon: "sparkles",
                            title: "Modern & Legacy",
                            description: "Works on iOS 17+ and macOS 14+ with automatic API selection"
                        )
                        
                        FeatureRow(
                            icon: "bolt.fill",
                            title: "Real-time Results",
                            description: "See transcriptions as you speak"
                        )
                    }
                    .padding(.horizontal)
                    
                    // Code Example
                    VStack(alignment: .leading, spacing: 12) {
                        Text("How Simple?")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        Text("""
                        ```swift
                        for try await result in AuralKit.transcribe() {
                            print(result.text)
                        }
                        ```
                        """)
                        .font(.system(.body, design: .monospaced))
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }
                    
                    // Links
                    VStack(spacing: 12) {
                        Link(destination: URL(string: "https://github.com/rryam/AuralKit")!) {
                            HStack {
                                Image(systemName: "doc.text")
                                Text("Documentation")
                                Spacer()
                                Image(systemName: "arrow.up.right.square")
                            }
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        
                        Link(destination: URL(string: "https://github.com/rryam/AuralKit/issues")!) {
                            HStack {
                                Image(systemName: "exclamationmark.bubble")
                                Text("Report an Issue")
                                Spacer()
                                Image(systemName: "arrow.up.right.square")
                            }
                            .padding()
                            .background(Color.gray.opacity(0.2))
                            .foregroundColor(.primary)
                            .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal)
                    
                    // Footer
                    Text("Made with SwiftUI")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top)
                }
                .padding(.vertical)
            }
            .navigationTitle("About")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
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

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}