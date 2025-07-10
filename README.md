# AuralKit

A lightweight Swift library for speech-to-text transcription using Apple's Speech framework.

## Support

Love this project? Check out my books to explore more of AI and iOS development:
- [Exploring AI for iOS Development](https://academy.rudrank.com/product/ai)
- [Exploring AI-Assisted Coding for iOS Development](https://academy.rudrank.com/product/ai-assisted-coding)

Your support helps to keep this project growing!

## Installation

### Swift Package Manager

Add AuralKit to your project through Xcode:
1. File → Add Package Dependencies
2. Enter: `https://github.com/rryam/AuralKit`
3. Click Add Package

Or add it to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/rryam/AuralKit", from: "0.0.1")
]
```

## Quick Start

AuralKit provides a simple API to transcribe speech to text. Here's how to get started:

### Basic Usage

```swift
import AuralKit

// Start transcribing and get the complete text when done
let text = try await AuralKit.startTranscribing()
print("You said: \(text)")
```

### Choosing Implementation

AuralKit supports multiple speech recognition implementations. By default, it automatically selects the best one for your OS version:

```swift
// Automatic selection (recommended)
let auralKit = AuralKit()

// Force modern implementation (iOS 26+/macOS 26+)
let modernKit = AuralKit(implementation: .modern)

// Force legacy implementation (iOS 17+/macOS 14+)
let legacyKit = AuralKit(implementation: .legacy)
```

### Live Transcription

For continuous transcription, use the AsyncStream-based API:

```swift
import AuralKit

let auralKit = AuralKit()

// Start live transcription
let stream = try await auralKit.startLiveTranscription()

// Process results as they arrive
for await result in stream {
    print("Text: \(result.text)")
    print("Confidence: \(result.confidence)")
    print("Is partial: \(result.isPartial)")
}

// Stop when done
try await auralKit.stopTranscription()
```

### Live Transcription with SwiftUI

```swift
import SwiftUI
import AuralKit

struct ContentView: View {
    @State private var auralKit = AuralKit()
    @State private var isTranscribing = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text(auralKit.currentText.isEmpty ? "Tap to start speaking..." : auralKit.currentText)
                .padding()
                .frame(maxWidth: .infinity, minHeight: 100)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)
            
            Button(action: toggleTranscription) {
                HStack {
                    Image(systemName: isTranscribing ? "stop.circle.fill" : "mic.circle.fill")
                    Text(isTranscribing ? "Stop" : "Start")
                }
                .padding()
                .background(isTranscribing ? Color.red : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
        }
        .padding()
    }
    
    func toggleTranscription() {
        Task {
            do {
                if isTranscribing {
                    try await auralKit.stopTranscription()
                    isTranscribing = false
                } else {
                    isTranscribing = true
                    let stream = try await auralKit.startLiveTranscription()
                    
                    // Process transcription results as they arrive
                    for await result in stream {
                        // currentText is automatically updated by AuralKit
                        // You can also access result properties directly:
                        // result.text, result.confidence, result.isPartial
                    }
                }
            } catch {
                print("Error: \(error)")
                isTranscribing = false
            }
        }
    }
}
```

## Requirements

- iOS 17.0+ / macOS 14.0+ / visionOS 1.1+
- Swift 6.0+
- Microphone permission
- Speech recognition permission

## Permissions

Add these keys to your `Info.plist`:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>This app needs microphone access to transcribe speech.</string>

<key>NSSpeechRecognitionUsageDescription</key>
<string>This app needs speech recognition to convert your speech to text.</string>
```

## Error Handling

```swift
do {
    let text = try await AuralKit.startTranscribing()
} catch AuralError.permissionDenied {
    // Handle permission denied
} catch AuralError.recognitionFailed {
    // Handle recognition failure
} catch {
    // Handle other errors
}
```


## License

MIT License. See LICENSE file for details.