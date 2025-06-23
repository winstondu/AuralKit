import Foundation

/// Protocol defining the complete engine interface for AuralKit operations.
///
/// AuralKitEngineProtocol serves as a dependency injection container that
/// provides all the components needed for speech recognition operations.
/// This design allows for easy testing by injecting mock implementations
/// and supports different engine implementations for different platforms.
///
/// ## Dependency Injection
/// The engine protocol follows the dependency injection pattern, allowing
/// the main AuralKit class to work with different implementations:
/// - Production engines for real speech recognition
/// - Mock engines for unit testing
/// - Platform-specific engines for iOS, macOS, etc.
///
/// ## Component Architecture
/// The engine aggregates four main components:
/// - **Speech Analyzer**: Handles speech-to-text processing
/// - **Audio Engine**: Manages audio recording and input
/// - **Model Manager**: Handles speech model download and management
/// - **Buffer Processor**: Converts audio formats as needed
///
/// ## Example
/// ```swift
/// // Production usage
/// let engine: AuralKitEngineProtocol = ProductionAuralKitEngine()
/// let auralKit = AuralKit(engine: engine)
/// 
/// // Testing usage
/// let mockEngine: AuralKitEngineProtocol = MockAuralKitEngine()
/// let auralKit = AuralKit(engine: mockEngine)
/// ```
internal protocol AuralKitEngineProtocol: Sendable {
    /// The speech analysis component for speech-to-text processing.
    ///
    /// This component handles the core speech recognition functionality,
    /// taking audio input and producing text transcriptions with metadata.
    var speechAnalyzer: any SpeechAnalyzerProtocol { get }
    
    /// The audio engine component for recording and audio management.
    ///
    /// This component handles microphone access, audio recording,
    /// and provides audio format information for other components.
    var audioEngine: any AudioEngineProtocol { get }
    
    /// The model manager component for speech model management.
    ///
    /// This component handles downloading, installing, and managing
    /// speech recognition models for different languages.
    var modelManager: any ModelManagerProtocol { get }
    
    /// The buffer processor component for audio format conversion.
    ///
    /// This component handles audio format conversion between the
    /// recording system and the speech recognition system.
    var bufferProcessor: any AudioBufferProcessorProtocol { get }
    
    /// Clean up all resources managed by this engine.
    ///
    /// This method ensures all temporary files, active resources,
    /// and allocated memory are properly cleaned up. It should be
    /// called when the engine is no longer needed or on error paths.
    func cleanup() async
}