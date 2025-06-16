# AuralKit Sample App

A comprehensive SwiftUI demo application showcasing the capabilities of the AuralKit speech-to-text framework.

## Features

### Live Transcription
- Real-time speech recognition with continuous audio input
- Visual feedback showing transcription status
- Start/stop controls with intuitive UI

### One-Shot Transcription  
- Single recording session with complete result
- Demonstrates the simple API for quick transcription tasks

### Configuration Options
- **Language Selection**: English, Spanish, French, German, Chinese, or custom locales
- **Quality Levels**: Low (fast), Medium (balanced), High (accurate)
- **Partial Results**: Enable real-time updates during transcription
- **Timestamps**: Include timing information in results

### Error Handling
- Permission management for microphone access
- Network error handling for model downloads
- User-friendly error messages and recovery

## Usage

### Running the Sample
```bash
# Build and run the sample app
swift run AuralKitSample
```

### Code Examples

The sample app demonstrates all major AuralKit usage patterns:

#### Live Transcription
```swift
let auralKit = AuralKit()
try await auralKit.startLiveTranscription { result in
    print("Transcribed: \(result.text)")
}
```

#### One-Shot Transcription with Configuration
```swift
let auralKit = AuralKit()
    .language(.spanish)
    .quality(.high)
    .includePartialResults()
    .includeTimestamps()

let text = try await auralKit.startTranscribing()
```

#### Simple Static Usage
```swift
let text = try await AuralKit.startTranscribing()
```

## Architecture Highlights

- **Modern Swift Concurrency**: Uses `@MainActor` isolation and proper async/await patterns
- **SwiftUI Integration**: Demonstrates `@Observable` pattern for reactive UI updates
- **Real Speech Framework**: Shows integration with Apple's SpeechAnalyzer APIs
- **Cross-Platform**: Works on macOS, iOS, and visionOS

## Requirements

- macOS 15.0+ / iOS 19.0+ / visionOS 2.0+
- Swift 6.2+
- Microphone permissions for audio recording
- Network access for language model downloads

## Key Classes

- **AuralKit**: Main framework interface with fluent configuration API
- **ContentView**: Primary demo interface showing live and one-shot transcription
- **SettingsView**: Configuration panel for language, quality, and feature options

The sample app serves as both a functional demonstration and a reference implementation for integrating AuralKit into SwiftUI applications.