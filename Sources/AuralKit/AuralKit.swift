@preconcurrency import AVFoundation
import Foundation
import Speech

// MARK: - Buffer Converter (from Apple's sample)

class BufferConverter: @unchecked Sendable {
    enum Error: Swift.Error {
        case failedToCreateConverter
        case failedToCreateConversionBuffer
        case conversionFailed(NSError?)
    }
    
    private var converter: AVAudioConverter?
    func convertBuffer(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let inputFormat = buffer.format
        guard inputFormat != format else {
            return buffer
        }
        
        if converter == nil || converter?.outputFormat != format {
            converter = AVAudioConverter(from: inputFormat, to: format)
            converter?.primeMethod = .none // Sacrifice quality of first samples in order to avoid any timestamp drift from source
        }
        
        guard let converter else {
            throw Error.failedToCreateConverter
        }
        
        let sampleRateRatio = converter.outputFormat.sampleRate / converter.inputFormat.sampleRate
        let scaledInputFrameLength = Double(buffer.frameLength) * sampleRateRatio
        let frameCapacity = AVAudioFrameCount(scaledInputFrameLength.rounded(.up))
        guard let conversionBuffer = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: frameCapacity) else {
            throw Error.failedToCreateConversionBuffer
        }
        
        var nsError: NSError?
        
        final class BufferState: @unchecked Sendable {
            var processed = false
        }
        let bufferState = BufferState()
        
        let status = converter.convert(to: conversionBuffer, error: &nsError) { packetCount, inputStatusPointer in
            defer { bufferState.processed = true } // This closure can be called multiple times, but it only offers a single buffer.
            inputStatusPointer.pointee = bufferState.processed ? .noDataNow : .haveData
            return bufferState.processed ? nil : buffer
        }
        
        guard status != .error else {
            throw Error.conversionFailed(nsError)
        }
        
        return conversionBuffer
    }
}

// MARK: - AuralKit

@available(iOS 26.0, macOS 26.0, *)
public final class AuralKit: @unchecked Sendable {
    
    // MARK: - Properties
    
    private let audioEngine = AVAudioEngine()
    private var outputContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    
    private var inputSequence: AsyncStream<AnalyzerInput>?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var recognizerTask: Task<(), Error>?
    
    private var analyzerFormat: AVAudioFormat?
    private let converter = BufferConverter()
    
    private let locale: Locale
    
    // MARK: - Init
    
    public init(locale: Locale = .current) {
        self.locale = locale
    }
    
    // MARK: - Public API
    
    /// Start transcribing
    public func startTranscribing() -> AsyncThrowingStream<AttributedString, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    // Request permissions
                    guard await isAuthorized() else {
                        throw NSError(domain: "AuralKit", code: -10, userInfo: [NSLocalizedDescriptionKey: "Microphone permission denied"])
                    }
                    
                    #if os(iOS)
                    try setUpAudioSession()
                    #endif
                    
                    try await setUpTranscriber()
                    
                    // Set up recognition task
                    recognizerTask = Task {
                        guard let transcriber = self.transcriber else { return }
                        do {
                            for try await result in transcriber.results {
                                continuation.yield(result.text)
                            }
                        } catch {
                            continuation.finish(throwing: error)
                        }
                    }
                    
                    // Start audio stream
                    for await buffer in try await audioStream() {
                        try await self.streamAudioToTranscriber(buffer)
                    }
                    
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    /// Stop transcribing
    public func stopTranscribing() async {
        audioEngine.stop()
        inputBuilder?.finish()
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        recognizerTask?.cancel()
        recognizerTask = nil
    }
    
    // MARK: - Private Methods (following Apple's pattern)
    
    private func isAuthorized() async -> Bool {
        // Check microphone permission
        #if os(iOS)
        if AVCaptureDevice.authorizationStatus(for: .audio) != .authorized {
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            if !granted {
                return false
            }
        }
        #endif
        
        // Check speech recognition permission
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        default:
            return false
        }
    }
    
    #if os(iOS)
    private func setUpAudioSession() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .spokenAudio, options: [.duckOthers])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
    }
    #endif
    
    private func setUpTranscriber() async throws {
        transcriber = SpeechTranscriber(locale: locale,
                                        transcriptionOptions: [],
                                        reportingOptions: [.volatileResults],
                                        attributeOptions: [.audioTimeRange])

        guard let transcriber else {
            throw NSError(domain: "AuralKit", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to setup recognition stream"])
        }

        analyzer = SpeechAnalyzer(modules: [transcriber])
        
        do {
            try await ensureModel(transcriber: transcriber, locale: locale)
        } catch {
            throw error
        }
        
        self.analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        (inputSequence, inputBuilder) = AsyncStream<AnalyzerInput>.makeStream()
        
        guard let inputSequence else { return }
        
        try await analyzer?.start(inputSequence: inputSequence)
    }
    
    private func audioStream() async throws -> AsyncStream<AVAudioPCMBuffer> {
        audioEngine.inputNode.removeTap(onBus: 0)
        
        audioEngine.inputNode.installTap(onBus: 0,
                                         bufferSize: 4096,
                                         format: audioEngine.inputNode.outputFormat(forBus: 0)) { [weak self] (buffer, time) in
            guard let self else { return }
            self.outputContinuation?.yield(buffer)
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        
        return AsyncStream(AVAudioPCMBuffer.self, bufferingPolicy: .unbounded) { continuation in
            outputContinuation = continuation
        }
    }
    
    private func streamAudioToTranscriber(_ buffer: AVAudioPCMBuffer) async throws {
        guard let inputBuilder, let analyzerFormat else {
            throw NSError(domain: "AuralKit", code: -3, userInfo: [NSLocalizedDescriptionKey: "Invalid audio data type"])
        }
        
        let converted = try self.converter.convertBuffer(buffer, to: analyzerFormat)
        let input = AnalyzerInput(buffer: converted)
        
        inputBuilder.yield(input)
    }
    
    // MARK: - Model Management (from Apple's sample)
    
    private func ensureModel(transcriber: SpeechTranscriber, locale: Locale) async throws {
        guard await supported(locale: locale) else {
            throw NSError(domain: "AuralKit", code: -2, userInfo: [NSLocalizedDescriptionKey: "This locale is not yet supported by SpeechAnalyzer"])
        }
        
        if await installed(locale: locale) {
            return
        } else {
            try await downloadIfNeeded(for: transcriber)
        }
    }
    
    private func supported(locale: Locale) async -> Bool {
        let supported = await SpeechTranscriber.supportedLocales
        return supported.map { $0.identifier(.bcp47) }.contains(locale.identifier(.bcp47))
    }

    private func installed(locale: Locale) async -> Bool {
        let installed = await Set(SpeechTranscriber.installedLocales)
        return installed.map { $0.identifier(.bcp47) }.contains(locale.identifier(.bcp47))
    }

    private func downloadIfNeeded(for module: SpeechTranscriber) async throws {
        if let downloader = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            try await downloader.downloadAndInstall()
        }
    }
}
