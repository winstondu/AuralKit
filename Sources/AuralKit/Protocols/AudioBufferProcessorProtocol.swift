import Foundation
import AVFoundation

/// Protocol defining the interface for audio buffer processing and format conversion.
///
/// AudioBufferProcessorProtocol abstracts audio buffer processing operations,
/// particularly format conversion between different audio formats. This is
/// essential for ensuring audio compatibility between the recording system
/// and the speech recognition engine.
///
/// ## Audio Format Conversion
/// Different audio sources may provide audio in various formats (sample rates,
/// bit depths, channel configurations). The processor ensures that audio
/// is converted to the format expected by the speech recognition system.
///
/// ## Performance Considerations
/// Audio processing should be efficient as it operates in real-time during
/// recording. The processor should minimize latency and avoid blocking
/// the audio recording pipeline.
///
/// ## Example
/// ```swift
/// let processor: AudioBufferProcessorProtocol = ProductionAudioBufferProcessor()
/// let targetFormat = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
/// 
/// let convertedBuffer = try processor.processBuffer(inputBuffer, to: targetFormat)
/// ```
protocol AudioBufferProcessorProtocol: Sendable {
    /// Processes an audio buffer, converting it to the specified format.
    ///
    /// This method takes an input audio buffer and converts it to match
    /// the target format. The conversion may involve sample rate conversion,
    /// channel mixing, or bit depth conversion as needed.
    ///
    /// - Parameters:
    ///   - buffer: The input audio buffer to process
    ///   - format: The target format to convert to
    /// - Returns: A new audio buffer in the target format
    /// - Throws: AuralError.audioSetupFailed if conversion fails
    func processBuffer(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) throws -> AVAudioPCMBuffer
}