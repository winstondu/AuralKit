# AuralKit Demo

A proper multi-platform Xcode project demonstrating AuralKit's speech-to-text capabilities on both iOS and macOS.

## Project Structure

This project was generated using **XcodeGen** and provides:

- **AuralKitDemo-iOS**: iOS app target (iOS 17.0+)
- **AuralKitDemo-macOS**: macOS app target (macOS 14.0+)
- **Shared Sources**: Common SwiftUI code with platform-specific adaptations
- **Proper Permissions**: Microphone and speech recognition permissions configured

## Features

### Live Transcription
- Real-time speech recognition with visual feedback
- Start/stop controls with status indicators
- Cross-platform UI optimizations

### One-Shot Transcription
- Single recording session with complete results
- Error handling and user feedback
- Configurable quality and language settings

### Settings Panel
- **Languages**: English, Spanish, French, German, Chinese
- **Quality Levels**: Low (fast), Medium (balanced), High (accurate)
- **Options**: Partial results, timestamps
- Platform-appropriate UI (NavigationStack vs NavigationView)

### Error Handling
- Permission management
- Network error handling for model downloads
- User-friendly error messages

## Usage

### Opening the Project

The project is already open in Xcode! You'll see:

- **Scheme Selector**: Choose between iOS and macOS targets
- **Source Files**: `App.swift` and `ContentView.swift` with platform-specific code
- **Info.plist Files**: Separate configurations for iOS and macOS

### Running the App

1. **iOS**: 
   - Select "AuralKitDemo-iOS" scheme
   - Choose iPhone simulator or physical device
   - Build and run (Cmd+R)

2. **macOS**:
   - Select "AuralKitDemo-macOS" scheme  
   - Build and run (Cmd+R)

### Permissions

Both platforms are pre-configured with microphone permissions:
- iOS: Automatically prompts for permissions
- macOS: Prompts for microphone access when first used

## Technical Details

### Dependencies
- **AuralKit**: Local package dependency (../AuralKit)
- **Swift 6.0**: With strict concurrency enabled
- **SwiftUI**: Cross-platform UI framework

### Platform Differences
The code uses conditional compilation for platform-specific UI:

```swift
#if os(iOS)
NavigationStack {
    // iOS-specific navigation
}
#else
NavigationView {
    // macOS-specific navigation
}
#endif
```

### Architecture
- **@Observable**: Modern SwiftUI state management
- **Swift Concurrency**: Async/await throughout
- **Actor Isolation**: Proper @MainActor usage
- **Error Handling**: Comprehensive error states

## Project Generation

This project was created with XcodeGen using `project.yml`:

```bash
cd AuralKitDemo
xcodegen generate
```

The configuration supports:
- Multi-platform targets
- Swift Package dependencies
- Platform-specific Info.plist files
- Proper build settings and schemes

## Testing

Both targets support:
- **iOS Simulator**: All iPhone/iPad models
- **iOS Device**: Physical iPhone/iPad (requires developer account)
- **macOS**: Native Mac application
- **Permissions**: Automatically configured for both platforms

Start speaking and watch the real-time transcription in action! 🎙️