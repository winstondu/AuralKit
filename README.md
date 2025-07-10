# AuralKit

![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)
![Platforms](https://img.shields.io/badge/Platforms-iOS%2017%2B%20|%20macOS%2014%2B%20|%20visionOS%201.1%2B-blue.svg)
![License](https://img.shields.io/badge/License-MIT-green.svg)
[![GitHub release](https://img.shields.io/github/release/rryam/AuralKit.svg)](https://github.com/rryam/AuralKit/releases)

A simple, lightweight Swift wrapper for speech-to-text transcription using Apple's Speech APIs.

## ✨ Features

- 🎯 **Simple one-line API** for speech transcription
- 🔄 **Automatic API selection** based on iOS version
- 🌍 **40+ languages** supported out of the box
- ⚡ **Real-time transcription** with partial results
- 📱 **Native Apple types** - no custom wrappers
- 🧹 **Minimal footprint** - only ~450 lines of code
- 🔐 **Privacy-focused** - all processing happens on-device

## Overview

AuralKit provides a clean, minimal API for adding speech transcription to your app. It automatically uses the best available speech recognition technology:
- **iOS 26+/macOS 26+**: Uses the new `SpeechAnalyzer` and `SpeechTranscriber` APIs
- **Earlier versions**: Falls back to `SFSpeechRecognizer`

## 🚀 Quick Start

```swift
import AuralKit

// Start transcribing in one line
for try await result in AuralKit.transcribe() {
    print(result.text)
}
```

That's it! AuralKit handles permissions, audio setup, and API selection automatically.

## Installation

### Swift Package Manager

Add AuralKit to your project through Xcode:
1. File → Add Package Dependencies
2. Enter: `https://github.com/rryam/AuralKit`
3. Click Add Package

Or add it to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/rryam/AuralKit", from: "1.0.1")
]
```

## Usage

### Simple Transcription

```swift
import AuralKit

// Just one line!
for try await result in AuralKit.transcribe() {
    print(result.text)
}
```

### With Configuration

> **Note**: Configuration requires AuralKit 1.0.1+. For 1.0.0, use the static method.

```swift
let kit = AuralKit()
    .language(.spanish)  // or .locale(Locale(identifier: "es-ES"))
    .includePartialResults(false)
    .includeTimestamps(true)  // iOS 26+ only

for try await result in kit.transcribe() {
    print(result.isFinal ? "Final: \(result.text)" : "Partial: \(result.text)")
    
    // Access all properties from Apple's API:
    // result.range - Audio time range
    // result.alternatives - Alternative transcriptions
    // result.resultsFinalizationTime - Finalization timestamp
}

// Stop when needed
kit.stop()
```

## 📱 Demo App

Check out the included **Aural** demo app to see AuralKit in action! The demo showcases:

- **Live Transcription**: Real-time speech-to-text with visual distinction between partial and final results
- **Language Selection**: Switch between 40+ languages on the fly
- **History Tracking**: View and search through past transcriptions
- **Export & Share**: Share transcriptions via standard iOS share sheet
- **Beautiful UI**: Tab-based interface with smooth animations

### Running the Demo

1. Open `Aural.xcodeproj` in the `Aural` directory
2. Build and run on your iOS device or simulator
3. Grant microphone and speech recognition permissions
4. Start transcribing!

<img src="https://github.com/rryam/AuralKit/assets/demo-screenshot.png" width="300" alt="AuralKit Demo App">

### SwiftUI Example

```swift
import SwiftUI
import AuralKit

struct ContentView: View {
    @State private var kit = AuralKit()
    @State private var transcribedText = ""
    @State private var isTranscribing = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text(transcribedText.isEmpty ? "Tap to start..." : transcribedText)
                .padding()
                .frame(maxWidth: .infinity, minHeight: 100)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)
            
            Button(action: toggleTranscription) {
                Label(isTranscribing ? "Stop" : "Start", 
                      systemImage: isTranscribing ? "stop.circle.fill" : "mic.circle.fill")
                    .padding()
                    .background(isTranscribing ? Color.red : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
        .padding()
    }
    
    func toggleTranscription() {
        if isTranscribing {
            kit.stop()
            isTranscribing = false
        } else {
            isTranscribing = true
            Task {
                do {
                    for try await result in kit.transcribe() {
                        transcribedText = String(result.text.characters)
                    }
                } catch {
                    print("Error: \(error)")
                }
                isTranscribing = false
            }
        }
    }
}
```

## API Reference

### Configuration

```swift
let kit = AuralKit()
    .language(_ language: AuralLanguage)         // Set language (e.g., .spanish, .french)
    .locale(_ locale: Locale)                    // Or use custom locale
    .includePartialResults(_ include: Bool)      // Show interim results (default: true)
    .includeTimestamps(_ include: Bool)          // Include timing info (default: false)
```

### Methods

```swift
// Start transcription
func transcribe() -> AsyncThrowingStream<AuralResult, Error>

// Stop transcription  
func stop()

// Convenience property
var transcriptions: AsyncThrowingStream<AuralResult, Error>
```

### AuralResult Properties

```swift
struct AuralResult {
    let text: AttributedString           // Transcribed text
    let isFinal: Bool                   // Final (true) or volatile (false)
    let range: CMTimeRange              // Audio time range
    let alternatives: [AttributedString] // Alternative transcriptions
    let resultsFinalizationTime: CMTime // When results were finalized
}
```

**Note on Legacy API (iOS 17-25):**
When using devices running iOS 17-25, some properties have limited support:
- `text` and `isFinal` are fully supported
- `range` returns an empty/invalid `CMTimeRange()`
- `alternatives` returns an empty array
- `resultsFinalizationTime` returns `.zero`

You can check if timing data is available:
```swift
if result.range.isValid {
    // Full data from iOS 26+ API
} else {
    // Limited data from legacy API
}
```

### Supported Languages

```swift
// Major languages
.english, .spanish, .french, .german, .italian, .portuguese, .chinese, .japanese, .korean

// Regional variants
.englishUK, .englishAustralia, .spanishMexico, .frenchCanada, .chineseTraditional

// Many more including:
.arabic, .dutch, .hindi, .russian, .swedish, .turkish, .polish, .hebrew, .thai
// ... and 30+ other languages
```

## Permissions

Add to your `Info.plist`:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>This app needs microphone access to transcribe speech.</string>

<key>NSSpeechRecognitionUsageDescription</key>
<string>This app needs speech recognition to convert your speech to text.</string>
```

## Requirements

- iOS 17.0+ / macOS 14.0+ / visionOS 1.1+
- Swift 6.0+
- Microphone and speech recognition permissions

## Error Handling

```swift
do {
    for try await result in AuralKit.transcribe() {
        print(result.text)
    }
} catch AuralError.permissionDenied {
    // Handle permission denied
    print("Please grant microphone and speech recognition permissions in Settings")
} catch AuralError.unsupportedLanguage {
    // Handle unsupported language
    print("Selected language is not supported on this device")
} catch AuralError.modelNotAvailable {
    // Handle model not available
    print("Speech recognition model is not available. Please check internet connection.")
} catch {
    // Handle other errors
    print("Transcription error: \(error.localizedDescription)")
}
```

## 🔧 Troubleshooting

### Common Issues

1. **"AuralKit initializer is inaccessible"**
   - Make sure you're using AuralKit 1.0.1+ which includes the public initializer
   - For 1.0.0, use the static method: `AuralKit.transcribe()`

2. **No transcription results**
   - Ensure microphone and speech recognition permissions are granted
   - Check that the device has an active internet connection (for initial model download)
   - Verify the selected language is supported on the device

3. **Partial results not showing**
   - Some languages may not support partial results
   - Ensure `includePartialResults(true)` is set (default behavior)

4. **App crashes on start**
   - Add required permissions to Info.plist (see Permissions section)
   - Ensure minimum deployment target is iOS 17.0+

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request. For major changes, please open an issue first to discuss what you would like to change.

### Development

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

AuralKit is available under the MIT License. See the [LICENSE](LICENSE) file for more info.

## 🙏 Acknowledgments

- Built with ❤️ using Apple's Speech framework
- Inspired by the need for a simple, modern speech recognition API
- Thanks to all contributors and users of AuralKit

---

**Made by [Rudrank Riyam](https://github.com/rryam)**