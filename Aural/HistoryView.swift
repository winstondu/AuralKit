import SwiftUI
import AuralKit

struct HistoryView: View {
    @EnvironmentObject var manager: TranscriptionManager
    @State private var searchText = ""
    
    var filteredHistory: [TranscriptionRecord] {
        if searchText.isEmpty {
            return manager.transcriptionHistory
        } else {
            return manager.transcriptionHistory.filter { record in
                record.text.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if manager.transcriptionHistory.isEmpty {
                    ContentUnavailableView {
                        Label("No Transcriptions", systemImage: "doc.text")
                    } description: {
                        Text("Your transcription history will appear here")
                    }
                } else {
                    List {
                        ForEach(filteredHistory) { record in
                            NavigationLink {
                                TranscriptionDetailView(record: record)
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text(record.language?.displayName ?? record.languageCode)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 2)
                                            .background(Color.blue.opacity(0.1))
                                            .cornerRadius(4)
                                        
                                        Spacer()
                                        
                                        Text(record.timestamp, style: .relative)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Text(record.text)
                                        .lineLimit(3)
                                        .font(.body)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                manager.deleteRecord(filteredHistory[index])
                            }
                        }
                    }
                    .searchable(text: $searchText, prompt: "Search transcriptions")
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if !manager.transcriptionHistory.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            manager.clearHistory()
                        } label: {
                            Text("Clear All")
                                .foregroundColor(.red)
                        }
                    }
                }
            }
        }
    }
}