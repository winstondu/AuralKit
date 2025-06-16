# AuralKit

A Swift library for speech-to-text transcription using Apple's new SpeechAnalyzer APIs.

## Features

- **Simple API**: Start transcribing with a single method call
- **Live Transcription**: Real-time speech recognition with partial results
- **SwiftUI Integration**: Observable class that works with SwiftUI
- **Fluent Configuration**: Chain method calls to customize behavior
- **Multiple Languages**: Support for various speech recognition languages
- **Quality Settings**: Configurable processing quality levels

## Requirements

- iOS 26.0+, macOS 26.0+, visionOS 26.0+
- Swift 6.2+

## Usage

### Simple Transcription

```swift
// One-shot transcription
let text = try await AuralKit.startTranscribing()

// With configuration
let auralKit = AuralKit()
    .language(.spanish)
    .quality(.high)
    .includePartialResults()
    .includeTimestamps()

let text = try await auralKit.startTranscribing()
```

### Live Transcription

```swift
let auralKit = AuralKit()
try await auralKit.startLiveTranscription { result in
    print("Transcribed: \(result.text)")
}
```

### SwiftUI Integration

```swift
struct ContentView: View {
    @StateObject private var auralKit = AuralKit()
    
    var body: some View {
        VStack {
            Text(auralKit.currentText)
            
            Button(auralKit.isTranscribing ? "Stop" : "Start") {
                Task {
                    try await auralKit.toggle()
                }
            }
        }
    }
}
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License. See LICENSE file for details.
