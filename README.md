# AuralKit

A simple Swift wrapper for speech-to-text transcription using Apple's Speech APIs.

## Overview

AuralKit provides a clean, minimal API for adding speech transcription to your app. It automatically uses the best available speech recognition technology:
- **iOS 26+/macOS 26+**: Uses the new `SpeechAnalyzer` and `SpeechTranscriber` APIs
- **Earlier versions**: Falls back to `SFSpeechRecognizer`

## Installation

### Swift Package Manager

Add AuralKit to your project through Xcode:
1. File → Add Package Dependencies
2. Enter: `https://github.com/rryam/AuralKit`
3. Click Add Package

Or add it to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/rryam/AuralKit", from: "1.0.0")
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

```swift
let kit = AuralKit()
    .language(.spanish)  // or .locale(Locale(identifier: "es-ES"))
    .includePartialResults(false)

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
    print("Please grant microphone and speech recognition permissions")
} catch AuralError.unsupportedLanguage {
    print("Language not supported")
} catch {
    print("Error: \(error)")
}
```

## License

MIT License. See LICENSE file for details.