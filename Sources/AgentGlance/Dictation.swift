import AgentGlanceCore
@preconcurrency import AVFoundation
import Speech

enum DictationError: LocalizedError {
    case microphoneDenied, unsupportedLanguage, noAudioFormat

    var errorDescription: String? {
        switch self {
        case .microphoneDenied: "Microphone access is off. Turn it on in System Settings → Privacy & Security."
        case .unsupportedLanguage: "On-device dictation doesn't support your language yet."
        case .noAudioFormat: "Couldn't start the microphone."
        }
    }
}

/// On-device dictation with Apple's DictationTranscriber. The microphone runs only between
/// `start` and `finish`/`cancel`; nothing is sent anywhere until the caller delivers the text.
@MainActor
final class Dictation {
    private(set) var target: SessionKey?
    /// Called with the live transcript (finalized text plus the current guess).
    var onTranscript: (String) -> Void = { _ in }

    private var mic: MicCapture?
    private var analyzer: SpeechAnalyzer?
    private var input: AsyncStream<AnalyzerInput>.Continuation?
    private var results: Task<Void, Never>?
    private var finalized = ""
    private var volatile = ""

    var text: String { (finalized + volatile).trimmingCharacters(in: .whitespacesAndNewlines) }

    func start(for key: SessionKey) async throws {
        cancel()
        target = key
        finalized = ""
        volatile = ""
        guard await AVCaptureDevice.requestAccess(for: .audio) else { throw DictationError.microphoneDenied }
        guard let locale = await DictationTranscriber.supportedLocale(equivalentTo: .current) else {
            throw DictationError.unsupportedLanguage
        }
        let transcriber = DictationTranscriber(locale: locale, preset: .progressiveShortDictation)
        if let install = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            onTranscript("Downloading the speech model (first use only)…")
            try await install.downloadAndInstall()
        }
        guard target == key else { return }  // cancelled while preparing

        let mic = try MicCapture()
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber],
                                                                         considering: mic.inputFormat) else {
            throw DictationError.noAudioFormat
        }
        guard target == key else { return }  // stopped while preparing: never open the mic
        let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let results = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    self?.receive(String(result.text.characters), isFinal: result.isFinal)
                }
            } catch {}
        }
        try await analyzer.start(inputSequence: stream)
        guard target == key else {  // stopped while the analyzer was starting
            continuation.finish()
            results.cancel()
            await analyzer.cancelAndFinishNow()
            return
        }
        try mic.start(converting: format) { buffer in continuation.yield(AnalyzerInput(buffer: buffer)) }
        self.mic = mic
        self.analyzer = analyzer
        self.input = continuation
        self.results = results
        onTranscript("")
    }

    /// Stops listening and returns everything that was said.
    func finish() async -> String {
        mic?.stop()
        input?.finish()
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        await results?.value
        let said = text
        reset()
        return said
    }

    /// Stops listening and throws the text away.
    func cancel() {
        mic?.stop()
        input?.finish()
        if let analyzer { Task { await analyzer.cancelAndFinishNow() } }
        results?.cancel()
        reset()
    }

    private func reset() {
        mic = nil
        analyzer = nil
        input = nil
        results = nil
        target = nil
        finalized = ""
        volatile = ""
    }

    private func receive(_ text: String, isFinal: Bool) {
        if isFinal {
            finalized += text
            volatile = ""
        } else {
            volatile = text
        }
        onTranscript(self.text)
    }
}

/// Microphone capture. Deliberately not main-actor isolated: the tap runs on the audio thread.
final class MicCapture: @unchecked Sendable {
    private let engine = AVAudioEngine()
    let inputFormat: AVAudioFormat

    init() throws {
        inputFormat = engine.inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else { throw DictationError.noAudioFormat }
    }

    func start(converting target: AVAudioFormat, onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws {
        guard let converter = AVAudioConverter(from: inputFormat, to: target) else { throw DictationError.noAudioFormat }
        let ratio = target.sampleRate / inputFormat.sampleRate
        engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
            guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
            nonisolated(unsafe) var consumed = false
            var error: NSError?
            converter.convert(to: out, error: &error) { _, status in
                if consumed {
                    status.pointee = .noDataNow
                    return nil
                }
                consumed = true
                status.pointee = .haveData
                return buffer
            }
            if error == nil, out.frameLength > 0 { onBuffer(out) }
        }
        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }
}
