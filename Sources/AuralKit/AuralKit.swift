@preconcurrency import AVFoundation
import Foundation
import Speech
import CoreMedia

// MARK: - Configuration

/// Configuration options for AuralKit
internal struct AuralConfiguration {
    let locale: Locale
    let includePartialResults: Bool
    let includeTimestamps: Bool

    init(
        locale: Locale = Locale.current,
        includePartialResults: Bool = true,
        includeTimestamps: Bool = false
    ) {
        self.locale = locale
        self.includePartialResults = includePartialResults
        self.includeTimestamps = includeTimestamps
    }
}

// MARK: - Errors

/// Errors that can occur during speech recognition
public enum AuralError: LocalizedError {
    case permissionDenied
    case unsupportedLanguage
    case audioEngineFailure
    case recognitionNotAvailable
    case modelNotAvailable
    case networkUnavailable
    case alreadyTranscribing
    case unknown(Error)

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone or speech recognition permission denied"
        case .unsupportedLanguage:
            return "The selected language is not supported on this device"
        case .audioEngineFailure:
            return "Failed to start audio engine"
        case .recognitionNotAvailable:
            return "Speech recognition is not available"
        case .modelNotAvailable:
            return "Speech recognition model is not available"
        case .networkUnavailable:
            return "Network connection required for speech recognition"
        case .alreadyTranscribing:
            return "Transcription is already in progress"
        case .unknown(let error):
            return error.localizedDescription
        }
    }
}

// MARK: - Language

/// Supported languages for speech recognition
public enum AuralLanguage: String, CaseIterable, Sendable {
    // Major Languages
    case english = "en-US"
    case englishUK = "en-GB"
    case englishAustralia = "en-AU"
    case englishCanada = "en-CA"
    case englishIndia = "en-IN"

    case spanish = "es-ES"
    case spanishMexico = "es-MX"
    case spanishUS = "es-US"

    case french = "fr-FR"
    case frenchCanada = "fr-CA"

    case german = "de-DE"
    case italian = "it-IT"
    case portuguese = "pt-BR"
    case portuguesePT = "pt-PT"

    case chinese = "zh-CN"
    case chineseTraditional = "zh-TW"
    case chineseHongKong = "zh-HK"

    case japanese = "ja-JP"
    case korean = "ko-KR"

    // More Languages
    case arabic = "ar-SA"
    case dutch = "nl-NL"
    case hindi = "hi-IN"
    case russian = "ru-RU"
    case swedish = "sv-SE"
    case turkish = "tr-TR"
    case polish = "pl-PL"
    case indonesian = "id-ID"
    case norwegian = "no-NO"
    case danish = "da-DK"
    case finnish = "fi-FI"
    case hebrew = "he-IL"
    case thai = "th-TH"
    case greek = "el-GR"
    case czech = "cs-CZ"
    case romanian = "ro-RO"
    case hungarian = "hu-HU"
    case catalan = "ca-ES"
    case croatian = "hr-HR"
    case malay = "ms-MY"
    case slovak = "sk-SK"
    case ukrainian = "uk-UA"
    case vietnamese = "vi-VN"

    /// The locale for this language
    public var locale: Locale {
        Locale(identifier: rawValue)
    }

    /// User-friendly name for the language
    public var displayName: String {
        locale.localizedString(forIdentifier: rawValue) ?? rawValue
    }

    /// Check if this language is supported on the current device
    public var isSupported: Bool {
        SFSpeechRecognizer.supportedLocales().contains(locale)
    }

    /// Get all languages that are actually supported on this device
    public static var supportedLanguages: [AuralLanguage] {
        allCases.filter { $0.isSupported }
    }
}

// MARK: - Result

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

// MARK: - Legacy Speech Recognizer

/// Simple wrapper for legacy SFSpeechRecognizer
internal class LegacySpeechRecognizer: @unchecked Sendable {
    private let recognizer: SFSpeechRecognizer
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    init(locale: Locale) throws {
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw AuralError.unsupportedLanguage
        }
        guard recognizer.isAvailable else {
            throw AuralError.modelNotAvailable
        }
        self.recognizer = recognizer
    }

    func startRecognition(
        includePartialResults: Bool,
        onResult: @escaping @Sendable (_ text: String, _ isPartial: Bool) -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) -> SFSpeechAudioBufferRecognitionRequest {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = includePartialResults

        recognitionRequest = request

        recognitionTask = recognizer.recognitionTask(with: request) { result, error in
            if let error = error {
                onError(error)
                return
            }

            if let result = result {
                onResult(
                    result.bestTranscription.formattedString,
                    !result.isFinal
                )
            }
        }

        return request
    }

    func stopRecognition() {
        recognitionTask?.cancel()
        recognitionRequest?.endAudio()
        recognitionTask = nil
        recognitionRequest = nil
    }
}

// MARK: - Buffer Converter

/// Converts audio buffers between formats
internal class BufferConverter: @unchecked Sendable {
    private var converter: AVAudioConverter?

    func convertBuffer(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        if buffer.format == format {
            return buffer
        }

        if converter == nil || converter?.inputFormat != buffer.format || converter?.outputFormat != format {
            converter = AVAudioConverter(from: buffer.format, to: format)
        }

        guard let converter = converter else {
            throw AuralError.audioEngineFailure
        }

        let outputFrameCapacity = AVAudioFrameCount(
            Double(buffer.frameLength) * format.sampleRate / buffer.format.sampleRate
        )

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: outputFrameCapacity
        ) else {
            throw AuralError.audioEngineFailure
        }

        var error: NSError?
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        if let error = error {
            throw error
        }

        return outputBuffer
    }
}

// MARK: - AuralKit

/// Simple wrapper for speech-to-text transcription using Apple's APIs
public final class AuralKit: @unchecked Sendable {

    // MARK: - Properties

    private var configuration = AuralConfiguration()
    private let audioEngine = AVAudioEngine()
    private var isTranscribing = false

    // For iOS 26+
    private var speechTranscriber: Any? // SpeechTranscriber
    private var speechAnalyzer: Any? // SpeechAnalyzer

    // For legacy
    private var legacyRecognizer: LegacySpeechRecognizer?
    
    // MARK: - Initializer
    
    public init() {}

    // MARK: - Configuration

    public func locale(_ locale: Locale) -> Self {
        configuration = AuralConfiguration(
            locale: locale,
            includePartialResults: configuration.includePartialResults,
            includeTimestamps: configuration.includeTimestamps
        )
        return self
    }

    public func language(_ language: AuralLanguage) -> Self {
        configuration = AuralConfiguration(
            locale: language.locale,
            includePartialResults: configuration.includePartialResults,
            includeTimestamps: configuration.includeTimestamps
        )
        return self
    }

    public func includePartialResults(_ include: Bool = true) -> Self {
        configuration = AuralConfiguration(
            locale: configuration.locale,
            includePartialResults: include,
            includeTimestamps: configuration.includeTimestamps
        )
        return self
    }

    public func includeTimestamps(_ include: Bool = true) -> Self {
        configuration = AuralConfiguration(
            locale: configuration.locale,
            includePartialResults: configuration.includePartialResults,
            includeTimestamps: include
        )
        return self
    }

    // MARK: - Public API

    /// Start transcribing audio from the microphone
    public func transcribe() -> AsyncThrowingStream<AuralResult, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await requestPermissions()

                    if #available(iOS 26.0, macOS 26.0, *) {
                        try await startModernTranscription(continuation: continuation)
                    } else {
                        try await startLegacyTranscription(continuation: continuation)
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Convenience property for transcription
    public var transcriptions: AsyncThrowingStream<AuralResult, Error> {
        transcribe()
    }

    /// Static method for quick transcription
    public static func transcribe() -> AsyncThrowingStream<AuralResult, Error> {
        AuralKit().transcribe()
    }

    /// Stop transcription
    public func stop() {
        isTranscribing = false
        audioEngine.stop()
        audioEngine.reset()
        legacyRecognizer?.stopRecognition()

        if #available(iOS 26.0, macOS 26.0, *) {
            // Modern API will stop automatically when audio stops
        }
    }

    // MARK: - Private Methods

    private func requestPermissions() async throws {
        // Check microphone permission
#if os(iOS) || os(visionOS)
        switch AVAudioApplication.shared.recordPermission {
        case .denied:
            throw AuralError.permissionDenied
        case .undetermined:
            let granted = await AVAudioApplication.requestRecordPermission()
            if !granted {
                throw AuralError.permissionDenied
            }
        case .granted:
            break
        @unknown default:
            throw AuralError.permissionDenied
        }
#endif
        // On macOS, microphone permission is requested automatically when accessing audio input

        // Check speech recognition permission
        let authStatus = SFSpeechRecognizer.authorizationStatus()

        switch authStatus {
        case .denied, .restricted:
            throw AuralError.permissionDenied
        case .notDetermined:
            let status = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status)
                }
            }
            if status != .authorized {
                throw AuralError.permissionDenied
            }
        case .authorized:
            break
        @unknown default:
            throw AuralError.permissionDenied
        }
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func startModernTranscription(continuation: AsyncThrowingStream<AuralResult, Error>.Continuation) async throws {
        guard !isTranscribing else {
            throw AuralError.alreadyTranscribing
        }

        isTranscribing = true

        // Create transcriber with options
        let transcriber = SpeechTranscriber(
            locale: configuration.locale,
            transcriptionOptions: [],
            reportingOptions: configuration.includePartialResults ? [.volatileResults] : [],
            attributeOptions: configuration.includeTimestamps ? [.audioTimeRange] : []
        )

        // Create analyzer
        let analyzer = SpeechAnalyzer(modules: [transcriber])

        // Ensure model is available
        try await ensureModel(transcriber: transcriber, locale: configuration.locale)

        // Get best audio format
        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw AuralError.audioEngineFailure
        }

        // Create input stream
        let (inputSequence, inputBuilder) = AsyncStream<AnalyzerInput>.makeStream()

        // Start recognition task
        let recognitionTask = Task {
            do {
                for try await result in transcriber.results {
                    let auralResult = AuralResult(
                        text: result.text,
                        isFinal: result.isFinal,
                        range: result.range,
                        alternatives: result.alternatives,
                        resultsFinalizationTime: .zero
                    )
                    continuation.yield(auralResult)
                }
            } catch {
                continuation.finish(throwing: AuralError.unknown(error))
            }
        }

        // Start analyzer
        try await analyzer.start(inputSequence: inputSequence)

        // Set up audio engine
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // Create buffer converter
        let converter = BufferConverter()

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            guard self?.isTranscribing == true else { return }

            // Use Task.detached to avoid dispatch queue conflicts
            Task.detached {
                do {
                    let converted = try converter.convertBuffer(buffer, to: analyzerFormat)
                    let input = AnalyzerInput(buffer: converted)
                    inputBuilder.yield(input)
                } catch {
                    print("Buffer conversion error: \(error)")
                }
            }
        }

        audioEngine.prepare()
        try audioEngine.start()

        // Store references for cleanup
        self.speechTranscriber = transcriber
        self.speechAnalyzer = analyzer

        // Monitor for stop
        Task { [weak self] in
            while self?.isTranscribing == true {
                try await Task.sleep(nanoseconds: 100_000_000)
            }

            inputBuilder.finish()
            try? await analyzer.finalizeAndFinishThroughEndOfInput()
            recognitionTask.cancel()
            continuation.finish()
        }
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func ensureModel(transcriber: SpeechTranscriber, locale: Locale) async throws {
        // Check if locale is supported
        let supported = await SpeechTranscriber.supportedLocales
        guard supported.map({ $0.identifier(.bcp47) }).contains(locale.identifier(.bcp47)) else {
            throw AuralError.unsupportedLanguage
        }

        // Check if already installed
        let installed = await Set(SpeechTranscriber.installedLocales)
        if installed.map({ $0.identifier(.bcp47) }).contains(locale.identifier(.bcp47)) {
            return
        }

        // Download if needed
        if let downloader = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await downloader.downloadAndInstall()
        }
    }

    private func startLegacyTranscription(continuation: AsyncThrowingStream<AuralResult, Error>.Continuation) async throws {
        guard !isTranscribing else {
            throw AuralError.alreadyTranscribing
        }

        isTranscribing = true

        do {
            legacyRecognizer = try LegacySpeechRecognizer(locale: configuration.locale)

            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)

            let request = legacyRecognizer!.startRecognition(
                includePartialResults: configuration.includePartialResults,
                onResult: { text, isPartial in
                    let result = AuralResult(
                        text: AttributedString(text),
                        isFinal: !isPartial
                    )
                    continuation.yield(result)
                },
                onError: { error in
                    continuation.finish(throwing: AuralError.unknown(error))
                }
            )

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                request.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()

            // Monitor for when to finish
            Task { [weak self] in
                while self?.isTranscribing == true {
                    try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                }
                continuation.finish()
            }

        } catch {
            isTranscribing = false
            throw error
        }
    }
}
