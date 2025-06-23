# AuralKit

A Swift library for speech-to-text transcription using Apple's Speech framework, with support for both the new SpeechAnalyzer APIs (iOS 26+) and legacy SFSpeechRecognizer (iOS 17+).

## Support

Love this project? Check out my books to explore more of AI and iOS development:
- [Exploring AI for iOS Development](https://academy.rudrank.com/product/ai)
- [Exploring AI-Assisted Coding for iOS Development](https://academy.rudrank.com/product/ai-assisted-coding)

Your support helps to keep this project growing!

## Features

- **Simple API**: Start transcribing with a single method call
- **Live Transcription**: Real-time speech recognition with partial results
- **SwiftUI Integration**: Observable class that works with SwiftUI
- **Fluent Configuration**: Chain method calls to customize behavior
- **Multiple Languages**: Support for various speech recognition languages
- **Quality Settings**: Configurable processing quality levels
- **Backward Compatibility**: Works with iOS 17+, macOS 14+, visionOS 1.1+
- **Automatic API Selection**: Uses the best available Speech API for your OS version

## Requirements

- iOS 17.0+, macOS 14.0+, visionOS 1.1+
- Swift 6.2+

### Platform-Specific Features

**All Platforms (iOS 17+, macOS 14+, visionOS 1.1+):**
- Live speech recognition
- Audio file transcription
- Real-time partial results
- Multiple language support
- SwiftUI integration

**iOS 26+, macOS 26+, visionOS 26+ only:**
- Advanced SpeechAnalyzer API with better performance
- Voice Activity Detection (SpeechDetector)
- Direct AVAudioFile transcription
- Enhanced audio analysis capabilities

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

### File Transcription

```swift
// Transcribe an audio file
let audioURL = Bundle.main.url(forResource: "recording", withExtension: "wav")!
let text = try await auralKit.transcribeFile(at: audioURL)

// With progress callbacks
try await auralKit.transcribeFile(at: audioURL) { result in
    print("Progress: \(result.text)")
    print("Is partial: \(result.isPartial)")
}
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License. See LICENSE file for details.
