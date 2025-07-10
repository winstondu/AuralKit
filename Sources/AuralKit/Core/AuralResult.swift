import Foundation
import CoreMedia

/// Result of a speech transcription operation
public struct AuralResult: Sendable {
    /// The transcribed text content
    public let text: AttributedString
    
    /// Whether this result is final (true) or volatile (false)
    public let isFinal: Bool
    
    /// The audio time range this result applies to
    public let range: CMTimeRange
    
    /// Alternative interpretations in descending order of likelihood
    public let alternatives: [AttributedString]
    
    /// Time up to which results have been finalized
    public let resultsFinalizationTime: CMTime
    
    /// Creates a result with all properties
    public init(
        text: AttributedString,
        isFinal: Bool,
        range: CMTimeRange = CMTimeRange(),
        alternatives: [AttributedString] = [],
        resultsFinalizationTime: CMTime = .zero
    ) {
        self.text = text
        self.isFinal = isFinal
        self.range = range
        self.alternatives = alternatives.isEmpty ? [text] : alternatives
        self.resultsFinalizationTime = resultsFinalizationTime
    }
}