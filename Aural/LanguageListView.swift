import SwiftUI
import AuralKit

struct LanguageListView: View {
    @Binding var selectedLanguage: AuralLanguage
    @Environment(\.dismiss) var dismiss
    @State private var searchText = ""
    
    var filteredLanguages: [AuralLanguage] {
        if searchText.isEmpty {
            return AuralLanguage.allCases
        } else {
            return AuralLanguage.allCases.filter { language in
                language.displayName.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            List(filteredLanguages, id: \.self) { language in
                Button {
                    selectedLanguage = language
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(language.displayName)
                                .foregroundColor(.primary)
                            Text(language.rawValue)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        if language == selectedLanguage {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.blue)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .searchable(text: $searchText, prompt: "Search languages")
            .navigationTitle("Select Language")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}