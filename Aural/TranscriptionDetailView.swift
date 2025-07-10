import SwiftUI
import AuralKit

struct TranscriptionDetailView: View {
    let record: TranscriptionRecord
    @State private var isCopied = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Metadata
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Language", systemImage: "globe")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(record.language?.displayName ?? record.languageCode)
                            .font(.body)
                    }
                    
                    HStack {
                        Label("Date", systemImage: "calendar")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(record.timestamp, style: .date)
                            .font(.body)
                    }
                    
                    HStack {
                        Label("Time", systemImage: "clock")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(record.timestamp, style: .time)
                            .font(.body)
                    }
                    
                    HStack {
                        Label("Word Count", systemImage: "textformat.size")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(record.text.split(separator: " ").count) words")
                            .font(.body)
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
                
                // Transcript
                VStack(alignment: .leading, spacing: 8) {
                    Text("Transcript")
                        .font(.headline)
                    
                    Text(record.text)
                        .font(.body)
                        .textSelection(.enabled)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.gray.opacity(0.05))
                        .cornerRadius(12)
                }
                
                // Actions
                HStack(spacing: 12) {
                    ShareLink(item: record.text) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    
                    Button {
                        UIPasteboard.general.string = record.text
                        isCopied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            isCopied = false
                        }
                    } label: {
                        Label(isCopied ? "Copied!" : "Copy", systemImage: isCopied ? "checkmark" : "doc.on.doc")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(isCopied ? Color.green : Color.gray.opacity(0.2))
                            .foregroundColor(isCopied ? .white : .primary)
                            .cornerRadius(12)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Transcription Details")
        .navigationBarTitleDisplayMode(.inline)
    }
}