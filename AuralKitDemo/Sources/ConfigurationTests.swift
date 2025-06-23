import SwiftUI
import AuralKit
import AVFoundation

struct ConfigurationTestView: View {
    @State private var auralKit = AuralKit()
    @State private var testResults: [String] = []
    @State private var isRunningTests = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("AuralKit Configuration Tests")
                .font(.largeTitle)
                .padding()
            
            Button("Run Configuration Tests") {
                Task {
                    await runTests()
                }
            }
            .disabled(isRunningTests)
            .buttonStyle(.borderedProminent)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(testResults, id: \.self) { result in
                        Text(result)
                            .font(.system(.body, design: .monospaced))
                            .padding(.horizontal)
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding()
    }
    
    @MainActor
    func runTests() async {
        isRunningTests = true
        testResults = []
        
        // Test 1: Configuration changes during transcription should be blocked
        testResults.append("Test 1: Testing configuration changes during transcription...")
        do {
            // Start transcription
            let transcriptionTask = Task {
                try await auralKit.startLiveTranscription { result in
                    // Ignore results for this test
                }
            }
            
            // Wait a bit for transcription to start
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            
            // Try to change configuration (should be blocked)
            let modifiedKit = auralKit
                .language(.spanish)  // This should be ignored
                .quality(.high)      // This should be ignored
            
            // Verify we're still using the same instance
            if modifiedKit === auralKit {
                testResults.append("✅ Configuration changes were blocked during transcription")
            } else {
                testResults.append("❌ Configuration changes were not properly blocked")
            }
            
            // Stop transcription
            try await auralKit.stopTranscription()
            transcriptionTask.cancel()
            
        } catch {
            testResults.append("❌ Test 1 error: \(error)")
        }
        
        // Test 2: File transcription with configuration
        testResults.append("\nTest 2: Testing file transcription configuration...")
        do {
            // Create a test audio file
            let testURL = createTestAudioFile()
            
            // Configure and transcribe
            let result = try await AuralKit()
                .language(.english)
                .quality(.high)
                .includeTimestamps()
                .transcribeFile(at: testURL)
            
            testResults.append("✅ File transcription completed: \(result.prefix(50))...")
            
            // Clean up
            try? FileManager.default.removeItem(at: testURL)
            
        } catch {
            testResults.append("❌ Test 2 error: \(error)")
        }
        
        // Test 3: AVAudioFile transcription (works on all OS versions now)
        testResults.append("\nTest 3: Testing AVAudioFile transcription...")
        do {
            // Create a test audio file
            let testURL = createTestAudioFile()
            let audioFile = try AVAudioFile(forReading: testURL)
            
            // Transcribe using AVAudioFile
            let result = try await AuralKit()
                .language(.english)
                .quality(.medium)
                .transcribeAudioFile(audioFile)
            
            testResults.append("✅ AVAudioFile transcription completed: \(result.prefix(50))...")
            
            // Clean up
            try? FileManager.default.removeItem(at: testURL)
            
        } catch {
            testResults.append("❌ Test 3 error: \(error)")
        }
        
        // Test 4: Quality settings in legacy mode
        testResults.append("\nTest 4: Testing quality settings...")
        do {
            let testURL = createTestAudioFile()
            
            // Test different quality levels
            for quality in [AuralQuality.low, .medium, .high] {
                let _ = try await AuralKit()
                    .language(.english)
                    .quality(quality)
                    .transcribeFile(at: testURL)
                
                testResults.append("✅ Quality \(quality) transcription completed")
            }
            
            // Clean up
            try? FileManager.default.removeItem(at: testURL)
            
        } catch {
            testResults.append("❌ Test 4 error: \(error)")
        }
        
        isRunningTests = false
    }
    
    func createTestAudioFile() -> URL {
        // Create a simple test audio file
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        
        // Create silence audio file for testing
        let audioFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let audioFile = try! AVAudioFile(forWriting: tempURL, settings: audioFormat.settings)
        
        // Write some silence
        let buffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: 44100)!
        buffer.frameLength = 44100
        
        try! audioFile.write(from: buffer)
        
        return tempURL
    }
}

// MARK: - Example Usage in ContentView

struct EnhancedContentView: View {
    @State private var auralKit = AuralKit()
    @State private var showingTests = false
    @State private var isTranscribing = false
    
    var body: some View {
        VStack {
            // Regular UI
            Text("Current transcription: \(auralKit.currentText)")
                .padding()
            
            HStack {
                // Configuration that won't change during transcription
                Button("Spanish + High Quality") {
                    _ = auralKit.language(.spanish).quality(.high)
                }
                .disabled(isTranscribing)
                
                Button(isTranscribing ? "Stop" : "Start") {
                    Task {
                        try await auralKit.toggle()
                        isTranscribing = await auralKit.isTranscribing
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            
            Button("Show Configuration Tests") {
                showingTests = true
            }
            .padding()
        }
        .sheet(isPresented: $showingTests) {
            ConfigurationTestView()
        }
        .task {
            isTranscribing = await auralKit.isTranscribing
        }
    }
}
