import Foundation
import AVFoundation

/// Protocol defining the interface for speech analysis operations.
///
/// SpeechAnalyzerProtocol abstracts the underlying speech recognition engine,
/// allowing for different implementations including production engines using
/// Apple's SpeechAnalyzer and mock implementations for testing.
///
/// ## Lifecycle
/// 1. Configure the analyzer with desired settings
/// 2. Start analysis to begin processing
/// 3. Consume results from the async stream
/// 4. Stop or finish analysis when complete
///
/// ## Example
/// ```swift
/// let analyzer: SpeechAnalyzerProtocol = ProductionSpeechAnalyzer()
/// 
/// try await analyzer.configure(with: configuration)
/// try await analyzer.startAnalysis()
/// 
/// for await result in analyzer.results {
///     print("Transcribed: \(result.text)")
/// }
/// ```
protocol SpeechAnalyzerProtocol: Sendable {
    /// Async stream of recognition results.
    ///
    /// Results are delivered as they become available, with partial results
    /// (if enabled) followed by final results. The stream continues until
    /// analysis is stopped or finished.
    var results: AsyncStream<AuralResult> { get }
    
    /// Configures the speech analyzer with the specified settings.
    ///
    /// This method must be called before starting analysis to set up
    /// the recognition engine with the appropriate language, quality,
    /// and result delivery preferences.
    ///
    /// - Parameter configuration: The configuration settings to apply
    /// - Throws: AuralError if configuration fails
    func configure(with configuration: AuralConfiguration) async throws
    
    /// Starts the speech analysis process.
    ///
    /// Once started, the analyzer will begin processing audio input and
    /// delivering results through the `results` stream. Audio input should
    /// be provided separately through the audio engine.
    ///
    /// - Throws: AuralError if analysis cannot be started
    func startAnalysis() async throws
    
    /// Stops the speech analysis process.
    ///
    /// This method stops analysis immediately and may not process any
    /// remaining audio. For graceful completion, use `finishAnalysis()` instead.
    ///
    /// - Throws: AuralError if stopping fails
    func stopAnalysis() async throws
    
    /// Finishes the speech analysis process gracefully.
    ///
    /// This method allows the analyzer to complete processing of any
    /// remaining audio before stopping. This is the preferred way to
    /// end analysis for best results.
    ///
    /// - Throws: AuralError if finishing fails
    func finishAnalysis() async throws
}