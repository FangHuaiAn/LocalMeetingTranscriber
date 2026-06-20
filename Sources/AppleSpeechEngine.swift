import Speech
import AVFoundation

/// Phase 2：Apple 原生 SpeechAnalyzer / SpeechTranscriber 路線（macOS 26+）。
/// 本地端、on-device，逐段回報含 CMTimeRange 時間戳的結果。
struct AppleSpeechEngine: TranscriptionEngine {
    var name: String { "Apple SpeechAnalyzer" }

    func availableModels() -> [String] { ["on-device"] }

    func transcribe(
        _ request: TranscriptionRequest,
        progress: ((Double) -> Void)?
    ) async throws -> TranscriptionResult {
        guard SpeechTranscriber.isAvailable else {
            throw AppleSpeechError.unavailable
        }

        let t0 = DispatchTime.now()
        let locale = await resolveLocale(request.languageHint)
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        try await ensureModelInstalled(for: transcriber, locale: locale)

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let audioFile = try AVAudioFile(forReading: request.audioURL)
        let totalDuration = audioFile.fileFormat.sampleRate > 0
            ? Double(audioFile.length) / audioFile.fileFormat.sampleRate
            : 0

        // 並行消費結果序列。
        let collector = Task { () throws -> [Segment] in
            var segs: [Segment] = []
            for try await result in transcriber.results {
                let start = result.range.start.seconds
                let end = result.range.end.seconds
                let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    segs.append(Segment(start: start, end: end, text: text, confidence: nil))
                }
                if totalDuration > 0 {
                    progress?(min(max(end / totalDuration, 0), 1))
                }
            }
            return segs
        }

        if let lastSample = try await analyzer.analyzeSequence(from: audioFile) {
            try await analyzer.finalizeAndFinish(through: lastSample)
        } else {
            await analyzer.cancelAndFinishNow()
        }

        let segments = try await collector.value
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1e9

        let metrics = RuntimeMetrics(
            audioDurationSeconds: totalDuration,
            transcriptionTimeSeconds: elapsed,
            peakMemoryMB: SystemMetrics.currentMemoryMB(),
            thermalState: SystemMetrics.thermalStateString(),
            device: SystemMetrics.deviceModel(),
            osVersion: SystemMetrics.osVersion()
        )

        return TranscriptionResult(
            transcript: segments.map(\.text).joined(separator: " "),
            segments: segments,
            detectedLanguage: locale.identifier,
            engine: name,
            model: "on-device",
            metrics: metrics
        )
    }

    /// 依語言提示解析最適 locale，並對映到實際支援的 locale。
    private func resolveLocale(_ hint: String?) async -> Locale {
        let candidates: [Locale]
        switch hint {
        case "zh":
            candidates = [Locale(identifier: "zh-TW"), Locale(identifier: "zh-CN"), Locale(identifier: "zh")]
        case "en":
            candidates = [Locale(identifier: "en-US"), Locale(identifier: "en-GB"), Locale(identifier: "en")]
        default:
            candidates = [Locale.current]
        }
        for c in candidates {
            if let equivalent = await SpeechTranscriber.supportedLocale(equivalentTo: c) {
                return equivalent
            }
        }
        return (await SpeechTranscriber.supportedLocales).first ?? Locale(identifier: "en-US")
    }

    /// 確保該 locale 的本地模型已安裝；未安裝則下載。（README §4.1 模型管理觀察點）
    private func ensureModelInstalled(for transcriber: SpeechTranscriber, locale: Locale) async throws {
        _ = try? await AssetInventory.reserve(locale: locale)
        let status = await AssetInventory.status(forModules: [transcriber])
        guard status != .installed else { return }
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
    }
}

enum AppleSpeechError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "此裝置的 SpeechTranscriber 不可用（需 macOS 26+ 並支援該語言）。"
        }
    }
}
