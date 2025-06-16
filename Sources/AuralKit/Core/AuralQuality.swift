import Foundation

/// Represents the quality level for speech recognition processing.
///
/// Different quality levels provide a trade-off between accuracy and performance.
/// Higher quality levels may use more computational resources and provide better
/// accuracy, while lower quality levels prioritize speed and efficiency.
///
/// ## Quality Characteristics
/// - `low`: Fastest processing, suitable for real-time applications with basic accuracy needs
/// - `medium`: Balanced performance and accuracy, recommended for most use cases
/// - `high`: Best accuracy, may have higher latency and resource usage
///
/// ## Example
/// ```swift
/// let auralKit = AuralKit()
///     .quality(.high)
///     .language(.english)
/// ```
public enum AuralQuality: Sendable, Hashable {
    /// Low quality processing for maximum speed
    case low
    
    /// Medium quality processing with balanced performance
    case medium
    
    /// High quality processing for maximum accuracy
    case high
}