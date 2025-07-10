import SwiftUI
import AuralKit
import Speech

// MARK: - Sub-views

struct TranscriptContentView: View {
    let finalizedText: String
    let volatileText: String
    let currentTimeRange: String
    let currentAlternatives: [String]
    let showAlternatives: Bool
    let isTranscribing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !finalizedText.isEmpty {
                Text(finalizedText)
                    .font(.body)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
            }

            if !volatileText.isEmpty {
                VolatileTextView(
                    volatileText: volatileText,
                    currentTimeRange: currentTimeRange,
                    currentAlternatives: currentAlternatives,
                    showAlternatives: showAlternatives
                )
            }

            if finalizedText.isEmpty && volatileText.isEmpty && !isTranscribing {
                EmptyStateView()
            }
        }
        .padding()
    }
}

struct VolatileTextView: View {
    let volatileText: String
    let currentTimeRange: String
    let currentAlternatives: [String]
    let showAlternatives: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.8)
                Text(volatileText)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .italic()
            }

            if !currentTimeRange.isEmpty {
                Label(currentTimeRange, systemImage: "clock")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if !currentAlternatives.isEmpty && showAlternatives {
                AlternativesView(alternatives: currentAlternatives)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(12)
    }
}

struct AlternativesView: View {
    let alternatives: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Alternatives:")
                .font(.caption2)
                .foregroundColor(.secondary)
            ForEach(Array(alternatives.prefix(3).enumerated()), id: \.offset) { index, alternative in
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

struct EmptyStateView: View {
    var body: some View {
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

struct LanguageSelectorView: View {
    @Bindable var manager: TranscriptionManager
    let commonLanguages: [AuralLanguage]

    var body: some View {
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
    }
}

struct RecordButtonView: View {
    let isTranscribing: Bool
    let isDisabled: Bool
    let action: () -> Void
    @Binding var animationScale: CGFloat

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isTranscribing ? Color.red : Color.blue)
                    .frame(width: 80, height: 80)
                    .scaleEffect(animationScale)

                Image(systemName: isTranscribing ? "stop.fill" : "mic.fill")
                    .font(.system(size: 30))
                    .foregroundColor(.white)
            }
        }
        .disabled(isDisabled)
    }
}

struct ErrorView: View {
    let error: String

    var body: some View {
        Text(error)
            .font(.caption)
            .foregroundColor(.red)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.red.opacity(0.1))
            .cornerRadius(8)
            .padding(.horizontal)
    }
}

struct ControlsView: View {
    @Bindable var manager: TranscriptionManager
    @Binding var animationScale: CGFloat
    let commonLanguages: [AuralLanguage]

    var body: some View {
        VStack(spacing: 20) {
            LanguageSelectorView(
                manager: manager,
                commonLanguages: commonLanguages
            )

            RecordButtonView(
                isTranscribing: manager.isTranscribing,
                isDisabled: manager.error != nil,
                action: manager.toggleTranscription,
                animationScale: $animationScale
            )

            Text(manager.isTranscribing ? "Listening..." : "Tap to start")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.bottom)
        }
        .padding(.vertical)
        #if os(iOS)
        .background(Color(UIColor.systemBackground))
        #else
        .background(Color(NSColor.windowBackgroundColor))
        #endif
        .shadow(color: .black.opacity(0.1), radius: 10, y: -5)
    }
}

// MARK: - Main View

struct TranscriptionView: View {
    @Bindable var manager: TranscriptionManager
    @State private var animationScale: CGFloat = 1.0
    @State private var showAlternatives = false
    @State private var showPermissionsAlert = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Transcript Display
                ScrollView {
                    TranscriptContentView(
                        finalizedText: manager.finalizedText,
                        volatileText: manager.volatileText,
                        currentTimeRange: manager.currentTimeRange,
                        currentAlternatives: manager.currentAlternatives,
                        showAlternatives: showAlternatives,
                        isTranscribing: manager.isTranscribing
                    )
                }
                .frame(maxHeight: .infinity)

                // Error Display
                if let error = manager.error {
                    ErrorView(error: error)
                }

                // Controls
                ControlsView(
                    manager: manager,
                    animationScale: $animationScale,
                    commonLanguages: commonLanguages
                )
            }
            .navigationTitle("AuralKit Demo")
#if os(iOS)
            .navigationBarTitleDisplayMode(.large)
#endif
            .toolbar {
                ToolbarItemGroup(placement: .automatic) {
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
