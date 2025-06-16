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
  private static let logger = Logger(subsystem: "com.auralkit", category: "AuralKit")

  /// The underlying engine that provides speech recognition functionality
  private let engine: AuralKitEngineProtocol

  /// Current configuration settings for speech recognition
  private var configuration: AuralConfiguration = AuralConfiguration()

  /// Background task for live transcription processing
  private var transcriptionTask: Task<Void, Error>?

  /// Handler for live transcription results
  private var liveTranscriptionHandler: (@MainActor @Sendable (AuralResult) -> Void)?

  // MARK: - Public Observable Properties

  /// Whether speech recognition is currently active
  public private(set) var isTranscribing = false

  /// The current transcribed text (updated in real-time during live transcription)
  public private(set) var currentText = ""

  /// Download progress for speech models (0.0 to 1.0)
  public private(set) var downloadProgress: Double = 0.0

  /// The most recent error that occurred during transcription
  public private(set) var error: AuralError?

  // MARK: - Initialization

  /// Creates a new AuralKit instance with default configuration.
  ///
  /// The default configuration uses English language, medium quality,
  /// and does not include partial results or timestamps.
  public init() {
    self.engine = AuralKitEngine()
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
    engine: AuralKitEngineProtocol, configuration: AuralConfiguration = AuralConfiguration()
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
  /// - Parameter language: The target language for transcription
  /// - Returns: The same AuralKit instance for method chaining
  public func language(_ language: AuralLanguage) -> AuralKit {
    configuration = AuralConfiguration(
      language: language,
      quality: configuration.quality,
      includePartialResults: configuration.includePartialResults,
      includeTimestamps: configuration.includeTimestamps
    )
    return self
  }

  /// Sets the processing quality level for speech recognition.
  ///
  /// Higher quality levels provide better accuracy but may use more
  /// computational resources and have higher latency.
  ///
  /// - Parameter quality: The processing quality level
  /// - Returns: The same AuralKit instance for method chaining
  public func quality(_ quality: AuralQuality) -> AuralKit {
    configuration = AuralConfiguration(
      language: configuration.language,
      quality: quality,
      includePartialResults: configuration.includePartialResults,
      includeTimestamps: configuration.includeTimestamps
    )
    return self
  }

  /// Enables or disables partial results for responsive UI updates.
  ///
  /// When enabled, the system delivers quick, less accurate results
  /// followed by improved results as more audio context becomes available.
  ///
  /// - Parameter enabled: Whether to include partial results
  /// - Returns: The same AuralKit instance for method chaining
  public func includePartialResults(_ enabled: Bool) -> AuralKit {
    configuration = AuralConfiguration(
      language: configuration.language,
      quality: configuration.quality,
      includePartialResults: enabled,
      includeTimestamps: configuration.includeTimestamps
    )
    return self
  }

  /// Enables or disables timestamp information in results.
  ///
  /// When enabled, transcription results include timing information
  /// that can be used for subtitle generation or time-synchronized
  /// text display.
  ///
  /// - Parameter enabled: Whether to include timestamp information
  /// - Returns: The same AuralKit instance for method chaining
  public func includeTimestamps(_ enabled: Bool) -> AuralKit {
    configuration = AuralConfiguration(
      language: configuration.language,
      quality: configuration.quality,
      includePartialResults: configuration.includePartialResults,
      includeTimestamps: enabled
    )
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
    guard !isTranscribing else {
      throw AuralError.recognitionFailed
    }

    error = nil
    isTranscribing = true

    defer {
      isTranscribing = false
    }

    do {
      try await prepareForTranscription()
      try await engine.speechAnalyzer.configure(with: configuration)
      try await engine.speechAnalyzer.startAnalysis()

      // Start audio recording with direct integration to speech analyzer
      if let audioEngine = engine.audioEngine as? AuralAudioEngine {
        let processor = audioEngine.getProcessor()
        try await processor.startRecording(with: engine.speechAnalyzer as! AuralSpeechAnalyzer)
      }

      var finalText = ""

      for await result in engine.speechAnalyzer.results {
        if !result.isPartial {
          finalText = result.text  // Use latest result, not concatenate
          currentText = finalText
        }
      }

      return finalText

    } catch let auralError as AuralError {
      error = auralError
      throw auralError
    } catch {
      let auralError = AuralError.recognitionFailed
      self.error = auralError
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
    guard !isTranscribing else {
      throw AuralError.recognitionFailed
    }

    error = nil
    isTranscribing = true
    liveTranscriptionHandler = onResult

    do {
      try await prepareForTranscription()
      try await engine.speechAnalyzer.configure(with: configuration)
      try await engine.speechAnalyzer.startAnalysis()

      // Start audio recording with direct integration to speech analyzer
      if let audioEngine = engine.audioEngine as? AuralAudioEngine {
        let processor = audioEngine.getProcessor()
        try await processor.startRecording(with: engine.speechAnalyzer as! AuralSpeechAnalyzer)
      }

      transcriptionTask = Task { @MainActor in
        for await result in engine.speechAnalyzer.results {
          if configuration.includePartialResults || !result.isPartial {
            onResult(result)
            currentText = result.text
          }
        }
      }

    } catch let auralError as AuralError {
      error = auralError
      isTranscribing = false
      throw auralError
    } catch {
      let auralError = AuralError.recognitionFailed
      self.error = auralError
      isTranscribing = false
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
    guard isTranscribing else { return }

    transcriptionTask?.cancel()
    transcriptionTask = nil

    try await engine.audioEngine.stopRecording()
    try await engine.speechAnalyzer.stopAnalysis()

    isTranscribing = false
    liveTranscriptionHandler = nil
  }

  /// Toggles transcription on or off.
  ///
  /// This convenience method starts transcription if not active,
  /// or stops it if currently running. It's particularly useful
  /// for simple UI controls.
  ///
  /// - Throws: AuralError if the operation fails
  public func toggle() async throws {
    if isTranscribing {
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
  @available(iOS 26.0, macOS 26.0, *)
  @available(tvOS, unavailable)
  @available(watchOS, unavailable)
  public func transcribeFile(at fileURL: URL) async throws -> String {
    guard !isTranscribing else {
      throw AuralError.recognitionFailed
    }

    error = nil
    isTranscribing = true

    defer {
      isTranscribing = false
    }

    do {
      // Prepare for transcription
      try await prepareForTranscription()

      // Open the audio file
      let audioFile = try AVAudioFile(forReading: fileURL)

      // Create transcriber with the specified language
      let speechTranscriber = SpeechTranscriber(
        locale: configuration.language.locale,
        transcriptionOptions: [],
        reportingOptions: configuration.includePartialResults ? [.volatileResults] : [],
        attributeOptions: configuration.includeTimestamps ? [.audioTimeRange] : []
      )

      // Create analyzer with the audio file directly
      let speechAnalyzer = try await SpeechAnalyzer(
        inputAudioFile: audioFile,
        modules: [speechTranscriber],
        finishAfterFile: true  // Automatically finish when file is processed
      )

      var finalText = ""

      // Process results as they come in
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
  @available(iOS 26.0, macOS 26.0, *)
  @available(tvOS, unavailable)
  @available(watchOS, unavailable)
  public func transcribeFile(
    at fileURL: URL, onResult: @escaping @MainActor @Sendable (AuralResult) -> Void
  ) async throws {
    guard !isTranscribing else {
      throw AuralError.recognitionFailed
    }

    error = nil
    isTranscribing = true
    liveTranscriptionHandler = onResult

    defer {
      isTranscribing = false
      liveTranscriptionHandler = nil
    }

    do {
      // Prepare for transcription
      try await prepareForTranscription()

      // Open the audio file
      let audioFile = try AVAudioFile(forReading: fileURL)

      // Create transcriber with the specified language
      let speechTranscriber = SpeechTranscriber(
        locale: configuration.language.locale,
        transcriptionOptions: [],
        reportingOptions: configuration.includePartialResults ? [.volatileResults] : [],
        attributeOptions: configuration.includeTimestamps ? [.audioTimeRange] : []
      )

      // Create analyzer with the audio file directly
      let speechAnalyzer = try await SpeechAnalyzer(
        inputAudioFile: audioFile,
        modules: [speechTranscriber],
        finishAfterFile: true  // Automatically finish when file is processed
      )

      // Process results as they come in
      for try await result in speechTranscriber.results {
        let auralResult = AuralResult(
          text: result.text.description,
          confidence: 1.0,  // SpeechTranscriber doesn't provide confidence in the new API
          isPartial: !result.isFinal,
          timestamp: extractTimestamp(from: result)
        )

        if configuration.includePartialResults || !auralResult.isPartial {
          await onResult(auralResult)
          currentText = auralResult.text
        }
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
  @available(iOS 26.0, macOS 26.0, *)
  @available(tvOS, unavailable)
  @available(watchOS, unavailable)
  public func transcribeAudioFile(_ audioFile: AVAudioFile) async throws -> String {
    guard !isTranscribing else {
      throw AuralError.recognitionFailed
    }

    error = nil
    isTranscribing = true

    defer {
      isTranscribing = false
    }

    do {
      // Prepare for transcription
      try await prepareForTranscription()

      // Create transcriber with the specified language
      let speechTranscriber = SpeechTranscriber(
        locale: configuration.language.locale,
        transcriptionOptions: [],
        reportingOptions: configuration.includePartialResults ? [.volatileResults] : [],
        attributeOptions: configuration.includeTimestamps ? [.audioTimeRange] : []
      )

      // Create analyzer with the audio file directly
      let speechAnalyzer = try await SpeechAnalyzer(
        inputAudioFile: audioFile,
        modules: [speechTranscriber],
        finishAfterFile: true  // Automatically finish when file is processed
      )

      var finalText = ""

      // Process results as they come in
      for try await result in speechTranscriber.results {
        if result.isFinal {
          finalText += result.text.description + " "
          currentText = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
      }

      return finalText.trimmingCharacters(in: .whitespacesAndNewlines)

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

  /// Extracts timestamp information from a SpeechTranscriber result.
  ///
  /// - Parameter result: The SpeechTranscriber result to extract timing from
  /// - Returns: The timestamp in seconds, or 0 if not available
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
}
