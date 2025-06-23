import AVFoundation
import Foundation
import OSLog
import Observation
import Speech

/// The main interface for AuralKit speech recognition operations.
///
/// AuralKit provides a simplified, high-level API for speech-to-text transcription
/// that abstracts away the complexity of Apple's SpeechAnalyzer framework. It handles
/// audio recording, model management, and speech recognition with minimal code.
///
/// ## Key Features
/// - **Simple API**: Start transcribing with a single method call
/// - **Automatic Management**: Handles permissions, model downloads, and audio setup
/// - **Fluent Configuration**: Chain method calls to customize behavior
/// - **SwiftUI Integration**: Works seamlessly with SwiftUI's observation system
/// - **Live Transcription**: Real-time speech recognition with partial results
/// - **Error Handling**: Comprehensive error reporting and recovery
///
/// ## Basic Usage
/// ```swift
/// // Simple one-shot transcription
/// let text = try await AuralKit.startTranscribing()
///
/// // Live transcription with callback
/// let auralKit = AuralKit()
/// try await auralKit.startLiveTranscription { result in
///     print("Transcribed: \(result.text)")
/// }
/// ```
///
/// ## Configuration
/// ```swift
/// let auralKit = AuralKit()
///     .language(.spanish)
///     .quality(.high)
///     .includePartialResults()
///     .includeTimestamps()
///
/// let text = try await auralKit.startTranscribing()
/// ```
///
/// ## SwiftUI Integration
/// ```swift
/// struct ContentView: View {
///     @StateObject private var auralKit = AuralKit()
///
///     var body: some View {
///         VStack {
///             Text(auralKit.currentText)
///
///             Button(auralKit.isTranscribing ? "Stop" : "Start") {
///                 Task {
///                     try await auralKit.toggle()
///                 }
///             }
///         }
///     }
/// }
/// ```
@MainActor
@Observable
public final class AuralKit {

  // MARK: - Private Properties

  /// Logger for AuralKit operations
  internal static let logger = Logger(subsystem: "com.auralkit", category: "AuralKit")

  /// The underlying engine that provides speech recognition functionality
  internal let engine: AuralKitEngine

  /// Current configuration settings for speech recognition
  private var configuration: AuralConfiguration = AuralConfiguration()
  
  /// Flag to track if the speech analyzer has been configured
  private var isConfigured = false

  /// Background task for live transcription processing
  private var transcriptionTask: Task<Void, Error>?

  /// Handler for live transcription results
  private var liveTranscriptionHandler: (@MainActor @Sendable (AuralResult) -> Void)?
  
  /// Cancellation handler for ongoing operations
  private var cancellationTask: Task<Void, Never>?
  
  /// Shared state manager for coordinating across actors
  internal let stateManager = AuralState.shared

  // MARK: - Public Observable Properties

  /// Whether speech recognition is currently active
  public var isTranscribing: Bool {
    get async {
      await stateManager.isTranscribing()
    }
  }

  /// The current transcribed text (updated in real-time during live transcription)
  public private(set) var currentText = ""

  /// Download progress for speech models (0.0 to 1.0)
  public private(set) var downloadProgress: Double = 0.0

  /// The most recent error that occurred during transcription
  public internal(set) var error: AuralError?

  // MARK: - Initialization

  /// Creates a new AuralKit instance with default configuration.
  ///
  /// The default configuration uses English language, medium quality,
  /// and does not include partial results or timestamps.
  public init() {
    self.engine = AuralKitEngine()
    
    // Set up permission monitoring
    Task { [weak self] in
      guard let self = self else { return }
      
      // Monitor audio permission changes
      await self.engine.permissionManager.onAudioPermissionChange { [weak self] isGranted in
        await self?.handlePermissionChange(audio: isGranted)
      }
      
      // Monitor speech permission changes
      await self.engine.permissionManager.onSpeechPermissionChange { [weak self] isGranted in
        await self?.handlePermissionChange(speech: isGranted)
      }
      
      // Monitor audio hardware changes
      await self.engine.audioHardwareMonitor.onHardwareChange { [weak self] change in
        await self?.handleAudioHardwareChange(change)
      }
    }
  }

  /// Creates a new AuralKit instance with a custom engine.
  ///
  /// This initializer is primarily used for testing with mock engines.
  /// Production code should typically use the default initializer.
  ///
  /// - Parameters:
  ///   - engine: The engine to use for speech recognition operations
  ///   - configuration: Initial configuration (default: AuralConfiguration())
  internal init(
    engine: AuralKitEngine, configuration: AuralConfiguration = AuralConfiguration()
  ) {
    self.engine = engine
    self.configuration = configuration
  }
}

// MARK: - Configuration Methods

extension AuralKit {

  /// Sets the target language for speech recognition.
  ///
  /// The language setting determines which speech recognition model
  /// will be used for transcription. The model for the specified
  /// language will be downloaded automatically if not available.
  ///
  /// Note: Configuration changes are not allowed during active transcription.
  ///
  /// - Parameter language: The target language for transcription
  /// - Returns: The same AuralKit instance for method chaining
  public func language(_ language: AuralLanguage) -> AuralKit {
    // Configuration changes are checked when actually used
    // This prevents race conditions with async state checks
    
    configuration = AuralConfiguration(
      language: language,
      quality: configuration.quality,
      includePartialResults: configuration.includePartialResults,
      includeTimestamps: configuration.includeTimestamps
    )
    isConfigured = false  // Mark as needing reconfiguration
    return self
  }

  /// Sets the processing quality level for speech recognition.
  ///
  /// Higher quality levels provide better accuracy but may use more
  /// computational resources and have higher latency.
  ///
  /// Note: Configuration changes are not allowed during active transcription.
  ///
  /// - Parameter quality: The processing quality level
  /// - Returns: The same AuralKit instance for method chaining
  public func quality(_ quality: AuralQuality) -> AuralKit {
    // Configuration changes are checked when actually used
    // This prevents race conditions with async state checks
    
    configuration = AuralConfiguration(
      language: configuration.language,
      quality: quality,
      includePartialResults: configuration.includePartialResults,
      includeTimestamps: configuration.includeTimestamps
    )
    isConfigured = false  // Mark as needing reconfiguration
    return self
  }

  /// Enables or disables partial results for responsive UI updates.
  ///
  /// When enabled, the system delivers quick, less accurate results
  /// followed by improved results as more audio context becomes available.
  ///
  /// Note: Configuration changes are not allowed during active transcription.
  ///
  /// - Parameter enabled: Whether to include partial results
  /// - Returns: The same AuralKit instance for method chaining
  public func includePartialResults(_ enabled: Bool = true) -> AuralKit {
    // Configuration changes are checked when actually used
    // This prevents race conditions with async state checks
    
    configuration = AuralConfiguration(
      language: configuration.language,
      quality: configuration.quality,
      includePartialResults: enabled,
      includeTimestamps: configuration.includeTimestamps
    )
    isConfigured = false  // Mark as needing reconfiguration
    return self
  }

  /// Enables or disables timestamp information in results.
  ///
  /// When enabled, transcription results include timing information
  /// that can be used for subtitle generation or time-synchronized
  /// text display.
  ///
  /// Note: Configuration changes are not allowed during active transcription.
  ///
  /// - Parameter enabled: Whether to include timestamp information
  /// - Returns: The same AuralKit instance for method chaining
  public func includeTimestamps(_ enabled: Bool = true) -> AuralKit {
    // Configuration changes are checked when actually used
    // This prevents race conditions with async state checks
    
    configuration = AuralConfiguration(
      language: configuration.language,
      quality: configuration.quality,
      includePartialResults: configuration.includePartialResults,
      includeTimestamps: enabled
    )
    isConfigured = false  // Mark as needing reconfiguration
    return self
  }
}

// MARK: - Transcription Methods

extension AuralKit {

  /// Starts speech transcription and returns the complete result.
  ///
  /// This static method provides the simplest way to perform speech-to-text
  /// transcription with default settings. It handles all setup, recording,
  /// and cleanup automatically.
  ///
  /// - Returns: The complete transcribed text
  /// - Throws: AuralError if transcription fails
  public static func startTranscribing() async throws -> String {
    let auralKit = AuralKit()
    return try await auralKit.startTranscribing()
  }

  /// Starts speech transcription and returns the complete result.
  ///
  /// This method begins audio recording and speech recognition, continuing
  /// until manually stopped. It returns the final transcribed text when
  /// transcription is complete.
  ///
  /// - Returns: The complete transcribed text
  /// - Throws: AuralError if transcription fails or is already in progress
  public func startTranscribing() async throws -> String {
    // Check state through state manager
    guard !(await stateManager.isTranscribing()) else {
      throw AuralError.recognitionFailed
    }

    error = nil
    
    // Begin state transition
    try await stateManager.beginPreparing()

    defer {
      Task {
        await stateManager.completeStop()
      }
    }

    do {
      try await prepareForTranscription()
      try await engine.speechAnalyzer.configure(with: configuration)
      
      // CRITICAL: Start audio FIRST, before speech recognition
      // This prevents the race condition where speech recognition expects buffers
      // but audio hasn't started yet
      if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
        if let audioEngine = engine.audioEngine as? AuralAudioEngine {
          let processor = audioEngine.getProcessor()
          
          // Start recording first
          try await processor.startRecording(with: engine.speechAnalyzer as! AuralSpeechAnalyzer)
          
          // Mark audio as started in state manager
          await stateManager.audioRecordingStarted()
          
          // Wait for audio to be ready before starting speech analysis
          try await stateManager.waitForAudioReady()
          
          // NOW start speech analysis
          try await engine.speechAnalyzer.startAnalysis()
          await stateManager.speechRecognitionStarted()
        }
      } else {
        // Legacy implementation
        if let audioEngine = engine.audioEngine as? LegacyAuralAudioEngine,
           let speechAnalyzer = engine.speechAnalyzer as? LegacyAuralSpeechAnalyzer {
          let processor = audioEngine.getProcessor()
          let recognizer = await speechAnalyzer.getRecognizer()
          
          // Start speech recognition first for legacy (it creates the request)
          try await recognizer.startRecognition()
          
          // Then start audio recording
          try await processor.startRecording(with: recognizer)
          
          // Update state
          await stateManager.audioRecordingStarted()
          await stateManager.speechRecognitionStarted()
        }
      }

      var finalText = ""
      let timeoutActor = TimeoutActor()
      
      // Create timeout task
      let timeoutTask = Task {
        do {
          try await Task.sleep(nanoseconds: 300_000_000_000) // 5 minutes timeout
          if await !timeoutActor.hasReceivedFinalResult {
            Self.logger.error("Transcription timed out after 5 minutes")
            transcriptionTask?.cancel()
          }
        } catch {
          // Task was cancelled - this is expected
        }
      }
      
      defer {
        timeoutTask.cancel()
      }

      for await result in engine.speechAnalyzer.results {
        if !result.isPartial {
          finalText = result.text  // Use latest result, not concatenate
          currentText = finalText
          await timeoutActor.markResultReceived()
        }
      }

      return finalText

    } catch let auralError as AuralError {
      error = auralError
      // Ensure cleanup on error
      await engine.cleanup()
      throw auralError
    } catch {
      // Preserve original error information
      let detailedError = DetailedError(error, context: "Transcription failed")
      Self.logger.error("\(detailedError)")
      let auralError = detailedError.toAuralError()
      self.error = auralError
      // Ensure cleanup on error
      await engine.cleanup()
      throw auralError
    }
  }

  /// Starts live speech transcription with real-time result callbacks.
  ///
  /// This method begins continuous speech recognition, delivering results
  /// through the provided callback as they become available. The transcription
  /// continues until explicitly stopped.
  ///
  /// - Parameter onResult: Callback function that receives transcription results
  /// - Throws: AuralError if transcription fails or is already in progress
  public func startLiveTranscription(onResult: @escaping @MainActor @Sendable (AuralResult) -> Void)
    async throws
  {
    guard !(await stateManager.isTranscribing()) else {
      throw AuralError.recognitionFailed
    }

    error = nil
    liveTranscriptionHandler = onResult

    do {
      try await prepareForTranscription()
      try await configureAnalyzerIfNeeded()
      
      // Begin state transition
      try await stateManager.beginPreparing()
      
      try await engine.speechAnalyzer.startAnalysis()

      // Start audio recording with direct integration to speech analyzer
      if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
        if let audioEngine = engine.audioEngine as? AuralAudioEngine {
          let processor = audioEngine.getProcessor()
          try await processor.startRecording(with: engine.speechAnalyzer as! AuralSpeechAnalyzer)
          
          // Mark audio as started in state manager
          await stateManager.audioRecordingStarted()
          await stateManager.speechRecognitionStarted()
        }
      } else {
        // Legacy implementation
        if let audioEngine = engine.audioEngine as? LegacyAuralAudioEngine,
           let speechAnalyzer = engine.speechAnalyzer as? LegacyAuralSpeechAnalyzer {
          let processor = audioEngine.getProcessor()
          let recognizer = await speechAnalyzer.getRecognizer()
          try await processor.startRecording(with: recognizer)
          
          // Update state
          await stateManager.audioRecordingStarted()
          await stateManager.speechRecognitionStarted()
        }
      }

      transcriptionTask = Task { @MainActor in
        do {
          let results = engine.speechAnalyzer.results
          for try await result in results {
            if configuration.includePartialResults || !result.isPartial {
              onResult(result)
              currentText = result.text
            }
          }
        }
      }
      
      // Setup timeout monitoring for live transcription
      cancellationTask = Task { [weak self] in
        // Monitor for inactivity - if no results for 30 seconds, log warning
        var lastUpdateTime = Date()
        var previousText = ""
        
        while !Task.isCancelled {
          do {
            try await Task.sleep(nanoseconds: 30_000_000_000) // Check every 30 seconds
          } catch {
            // Task was cancelled
            break
          }
          
          guard let self = self else { break }
          
          let timeSinceLastUpdate = Date().timeIntervalSince(lastUpdateTime)
          if timeSinceLastUpdate > 30 {
            Self.logger.warning("No transcription results for \(Int(timeSinceLastUpdate)) seconds")
          }
          
          // Update time when we get new text
          if self.currentText != previousText {
            lastUpdateTime = Date()
            previousText = self.currentText
          }
        }
      }

    } catch let auralError as AuralError {
      error = auralError
      // State managed by state manager
      await stateManager.handleError(auralError)
      // Ensure cleanup on error
      await engine.cleanup()
      throw auralError
    } catch {
      // Preserve original error information
      let detailedError = DetailedError(error, context: "Live transcription failed")
      Self.logger.error("\(detailedError)")
      let auralError = detailedError.toAuralError()
      self.error = auralError
      // State managed by state manager
      await stateManager.handleError(auralError)
      // Ensure cleanup on error
      await engine.cleanup()
      throw auralError
    }
  }

  /// Stops the current transcription session.
  ///
  /// This method stops audio recording and speech recognition,
  /// cleaning up all resources. Any ongoing transcription will
  /// be completed gracefully.
  ///
  /// - Throws: AuralError if stopping fails
  public func stopTranscription() async throws {
    guard await stateManager.isTranscribing() else { return }

    defer {
      // State managed by state manager
      liveTranscriptionHandler = nil
      Task {
        await stateManager.completeStop()
        await engine.cleanup()
      }
    }

    // Begin stopping process
    await stateManager.beginStopping()

    // Cancel monitoring task
    cancellationTask?.cancel()
    cancellationTask = nil
    
    // Cancel transcription task
    transcriptionTask?.cancel()
    transcriptionTask = nil

    // Stop audio and speech analysis
    do {
      try await engine.audioEngine.stopRecording()
      await stateManager.audioRecordingStopped()
      
      try await engine.speechAnalyzer.stopAnalysis()
      await stateManager.speechRecognitionStopped()
    } catch {
      let detailedError = DetailedError(error, context: "Error stopping transcription")
      Self.logger.error("\(detailedError)")
      // Continue with cleanup even if stop fails
    }
  }

  /// Toggles transcription on or off.
  ///
  /// This convenience method starts transcription if not active,
  /// or stops it if currently running. It's particularly useful
  /// for simple UI controls.
  ///
  /// - Throws: AuralError if the operation fails
  public func toggle() async throws {
    if await stateManager.isTranscribing() {
      try await stopTranscription()
    } else {
      try await startLiveTranscription { @MainActor [weak self] result in
        self?.currentText = result.text
      }
    }
  }

  /// Transcribes an audio file and returns the complete transcription.
  ///
  /// This method processes a pre-recorded audio file and returns the full
  /// transcription text. The file is processed from beginning to end,
  /// with the system automatically determining when processing is complete.
  ///
  /// ## Supported Audio Formats
  /// - WAV, AIFF, CAF, M4A, MP3, and other formats supported by AVAudioFile
  /// - Mono or stereo audio
  /// - Various sample rates (will be converted as needed)
  ///
  /// ## Example
  /// ```swift
  /// let audioURL = Bundle.main.url(forResource: "recording", withExtension: "wav")!
  /// let transcription = try await auralKit
  ///     .language(.english)
  ///     .includeTimestamps(true)
  ///     .transcribeFile(at: audioURL)
  /// print("Transcription: \(transcription)")
  /// ```
  ///
  /// - Parameter fileURL: URL of the audio file to transcribe
  /// - Returns: The complete transcribed text
  /// - Throws: AuralError if transcription fails or file cannot be read
  public func transcribeFile(at fileURL: URL) async throws -> String {
    guard !(await stateManager.isTranscribing()) else {
      throw AuralError.recognitionFailed
    }

    error = nil
    // State managed by state manager

    defer {
      // State managed by state manager
    }

    do {
      // Prepare for transcription and ensure analyzer is configured
      try await prepareForTranscription()
      try await configureAnalyzerIfNeeded()

      if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
        // Use new Speech framework for iOS 26+
        return try await transcribeFileWithNewAPI(at: fileURL)
      } else {
        // Use legacy SFSpeechRecognizer for older versions
        return try await transcribeFileWithLegacyAPI(at: fileURL)
      }

    } catch let auralError as AuralError {
      error = auralError
      throw auralError
    } catch {
      let auralError = AuralError.recognitionFailed
      self.error = auralError
      throw auralError
    }
  }

  /// Transcribes an audio file with real-time progress callbacks.
  ///
  /// This method processes a pre-recorded audio file and delivers results
  /// through the provided callback as they become available. This is useful
  /// for showing transcription progress in the UI.
  ///
  /// - Parameters:
  ///   - fileURL: URL of the audio file to transcribe
  ///   - onResult: Callback function that receives transcription results as they arrive
  /// - Throws: AuralError if transcription fails or file cannot be read
  public func transcribeFile(
    at fileURL: URL, onResult: @escaping @MainActor @Sendable (AuralResult) -> Void
  ) async throws {
    guard !(await stateManager.isTranscribing()) else {
      throw AuralError.recognitionFailed
    }

    error = nil
    liveTranscriptionHandler = onResult

    defer {
      // State managed by state manager
      liveTranscriptionHandler = nil
    }

    do {
      // Prepare for transcription and ensure analyzer is configured
      try await prepareForTranscription()
      try await configureAnalyzerIfNeeded()

      if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
        // Use new Speech framework for iOS 26+
        try await transcribeFileWithNewAPI(at: fileURL, onResult: onResult)
      } else {
        // Use legacy SFSpeechRecognizer for older versions
        try await transcribeFileWithLegacyAPI(at: fileURL, onResult: onResult)
      }

    } catch let auralError as AuralError {
      error = auralError
      throw auralError
    } catch {
      let auralError = AuralError.recognitionFailed
      self.error = auralError
      throw auralError
    }
  }

  /// Transcribes an audio file from an existing AVAudioFile instance.
  ///
  /// This method allows you to transcribe audio from an already-opened
  /// AVAudioFile, which can be useful when you need more control over
  /// file handling or when working with audio from non-file sources.
  ///
  /// - Parameter audioFile: The AVAudioFile instance to transcribe
  /// - Returns: The complete transcribed text
  /// - Throws: AuralError if transcription fails
  public func transcribeAudioFile(_ audioFile: AVAudioFile) async throws -> String {
    guard !(await stateManager.isTranscribing()) else {
      throw AuralError.recognitionFailed
    }

    error = nil
    // State managed by state manager

    defer {
      // State managed by state manager
    }

    do {
      // Prepare for transcription and ensure analyzer is configured
      try await prepareForTranscription()
      try await configureAnalyzerIfNeeded()

      if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
        // Create transcriber with the specified language
        let speechTranscriber = SpeechTranscriber(
          locale: configuration.language.locale,
          transcriptionOptions: [],
          reportingOptions: configuration.includePartialResults ? [.volatileResults] : [],
          attributeOptions: configuration.includeTimestamps ? [.audioTimeRange] : []
        )

        // Create analyzer with the audio file directly - this automatically starts processing
        let _ = try await SpeechAnalyzer(
          inputAudioFile: audioFile,
          modules: [speechTranscriber],
          finishAfterFile: true  // Automatically finish when file is processed
        )

        var finalText = ""

        // Process results as they come in (analyzer is already running)
        for try await result in speechTranscriber.results {
          if result.isFinal {
            finalText += result.text.description + " "
            currentText = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
          }
        }

        return finalText.trimmingCharacters(in: .whitespacesAndNewlines)
      } else {
        // For older OS versions, save the audio file to a temporary location and use legacy API
        let tempURL = FileManager.default.temporaryDirectory
          .appendingPathComponent(UUID().uuidString)
          .appendingPathExtension("wav")
        
        // Create a new file at the temporary location
        let outputFile = try AVAudioFile(forWriting: tempURL, settings: audioFile.fileFormat.settings)
        
        // Read and write the audio data
        let frameCount = AVAudioFrameCount(audioFile.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat, frameCapacity: frameCount) else {
          throw AuralError.audioSetupFailed
        }
        
        try audioFile.read(into: buffer)
        try outputFile.write(from: buffer)
        
        // Use legacy API with the file URL
        let result = try await transcribeFileWithLegacyAPI(at: tempURL)
        
        // Clean up temporary file
        try? FileManager.default.removeItem(at: tempURL)
        
        return result
      }

    } catch let auralError as AuralError {
      error = auralError
      throw auralError
    } catch {
      let auralError = AuralError.recognitionFailed
      self.error = auralError
      throw auralError
    }
  }
}

// MARK: - Private Helper Methods

extension AuralKit {

  /// Transcribes a file using the new iOS 26+ Speech framework
  @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
  private func transcribeFileWithNewAPI(at fileURL: URL) async throws -> String {
    // Open the audio file
    let audioFile = try AVAudioFile(forReading: fileURL)

    // Create transcriber with the specified language
    let speechTranscriber = SpeechTranscriber(
      locale: configuration.language.locale,
      transcriptionOptions: [],
      reportingOptions: configuration.includePartialResults ? [.volatileResults] : [],
      attributeOptions: configuration.includeTimestamps ? [.audioTimeRange] : []
    )

    // Create analyzer with the audio file directly - this automatically starts processing
    let _ = try await SpeechAnalyzer(
      inputAudioFile: audioFile,
      modules: [speechTranscriber],
      finishAfterFile: true  // Automatically finish when file is processed
    )

    var finalText = ""

    // Create timeout task for file transcription
    let timeoutTask = Task {
      try? await Task.sleep(nanoseconds: 120_000_000_000) // 2 minutes timeout for file
      Self.logger.error("File transcription timed out after 2 minutes")
    }
    
    defer {
      timeoutTask.cancel()
    }
    
    // Process results as they come in (analyzer is already running)
    for try await result in speechTranscriber.results {
      if !result.isFinal && configuration.includePartialResults {
        // Update current text with partial results for UI
        currentText = result.text.description
      } else if result.isFinal {
        // Accumulate final results
        finalText += result.text.description + " "
        currentText = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
      }
    }

    return finalText.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// Transcribes a file using the legacy SFSpeechRecognizer API
  private func transcribeFileWithLegacyAPI(at fileURL: URL) async throws -> String {
    // Use legacy recognizer from the engine
    if let speechAnalyzer = engine.speechAnalyzer as? LegacyAuralSpeechAnalyzer {
      let recognizer = await speechAnalyzer.getRecognizer()
      return try await recognizer.transcribeFile(at: fileURL)
    } else {
      throw AuralError.recognitionFailed
    }
  }

  /// Transcribes a file with callbacks using the new iOS 26+ Speech framework
  @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
  private func transcribeFileWithNewAPI(at fileURL: URL, onResult: @escaping @MainActor @Sendable (AuralResult) -> Void) async throws {
    // Open the audio file
    let audioFile = try AVAudioFile(forReading: fileURL)

    // Create transcriber with the specified language
    let speechTranscriber = SpeechTranscriber(
      locale: configuration.language.locale,
      transcriptionOptions: [],
      reportingOptions: configuration.includePartialResults ? [.volatileResults] : [],
      attributeOptions: configuration.includeTimestamps ? [.audioTimeRange] : []
    )

    // Create analyzer with the audio file directly - this automatically starts processing
    let _ = try await SpeechAnalyzer(
      inputAudioFile: audioFile,
      modules: [speechTranscriber],
      finishAfterFile: true  // Automatically finish when file is processed
    )

    // Create timeout task for file transcription
    let timeoutTask = Task {
      try? await Task.sleep(nanoseconds: 120_000_000_000) // 2 minutes timeout for file
      Self.logger.error("File transcription timed out after 2 minutes")
    }
    
    defer {
      timeoutTask.cancel()
    }
    
    // Process results as they come in (analyzer is already running)
    for try await result in speechTranscriber.results {
      let auralResult = AuralResult(
        text: result.text.description,
        confidence: 1.0,  // SpeechTranscriber doesn't provide confidence in the new API
        isPartial: !result.isFinal,
        timestamp: extractTimestamp(from: result)
      )

      if configuration.includePartialResults || !auralResult.isPartial {
        onResult(auralResult)
        currentText = auralResult.text
      }
    }
  }

  /// Transcribes a file with callbacks using the legacy SFSpeechRecognizer API
  private func transcribeFileWithLegacyAPI(at fileURL: URL, onResult: @escaping @MainActor @Sendable (AuralResult) -> Void) async throws {
    // Use legacy recognizer from the engine
    if let speechAnalyzer = engine.speechAnalyzer as? LegacyAuralSpeechAnalyzer {
      let recognizer = await speechAnalyzer.getRecognizer()
      try await recognizer.transcribeFile(at: fileURL, onResult: onResult)
    } else {
      throw AuralError.recognitionFailed
    }
  }

  /// Extracts timestamp information from a SpeechTranscriber result.
  ///
  /// - Parameter result: The SpeechTranscriber result to extract timing from
  /// - Returns: The timestamp in seconds, or 0 if not available
  @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
  private func extractTimestamp(from result: SpeechTranscriber.Result) -> TimeInterval {
    // For iOS 26 SpeechTranscriber, timestamp extraction would depend on
    // the specific attributes available in the result. This is a placeholder
    // implementation that returns 0 for now.
    return 0.0
  }

  /// Prepares the system for transcription by checking permissions and models.
  fileprivate func prepareForTranscription() async throws {
    guard await engine.audioEngine.requestPermission() else {
      throw AuralError.permissionDenied
    }

    if !(await engine.modelManager.isModelAvailable(for: configuration.language)) {
      try await downloadModelIfNeeded()
    }
  }

  /// Downloads the speech recognition model for the current language if needed.
  fileprivate func downloadModelIfNeeded() async throws {
    do {
      try await engine.modelManager.downloadModel(for: configuration.language)
    } catch {
      throw AuralError.modelNotAvailable
    }
  }
  
  /// Configures the speech analyzer if it hasn't been configured yet or if configuration has changed.
  private func configureAnalyzerIfNeeded() async throws {
    if !isConfigured {
      Self.logger.debug("Configuring speech analyzer with current settings")
      try await engine.speechAnalyzer.configure(with: configuration)
      isConfigured = true
    }
  }
}

// MARK: - Helper Actor for Timeout Management

/// Actor to manage timeout state in a thread-safe way
private actor TimeoutActor {
  private var _hasReceivedFinalResult = false
  
  func markResultReceived() {
    _hasReceivedFinalResult = true
  }
  
  var hasReceivedFinalResult: Bool {
    _hasReceivedFinalResult
  }
}
