import SwiftUI
import AuralKit

struct LanguageListView: View {
    @Binding var selectedLanguage: AuralLanguage
    @Environment(\.dismiss) var dismiss
    @State private var searchText = ""
    @State private var showOnlySupported = false
    
    var filteredLanguages: [AuralLanguage] {
        let languages = showOnlySupported ? AuralLanguage.supportedLanguages : AuralLanguage.allCases
        
        if searchText.isEmpty {
            return languages
        } else {
            return languages.filter { language in
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
                            HStack(spacing: 4) {
                                Text(language.displayName)
                                    .foregroundColor(language.isSupported ? .primary : .secondary)
                                if !language.isSupported {
                                    Label("Not available", systemImage: "exclamationmark.triangle.fill")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                        .labelStyle(.iconOnly)
                                }
                            }
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
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Toggle("Supported Only", isOn: $showOnlySupported)
                        .toggleStyle(.switch)
                        .font(.caption)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}