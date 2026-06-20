import AVFoundation

/// Phase 1 用的 pipeline 驗證 engine。
/// 不做真實辨識，只依音訊長度切出時間戳段落，用來打通
/// 匯入 → 正規化 → engine → 匯出 → metrics 的整條資料流。
/// Phase 2 會以相同的 `TranscriptionEngine` protocol 換入真實 Apple engine。
struct MockEngine: TranscriptionEngine {
    var name: String { "Mock (Pipeline 驗證)" }

    func availableModels() -> [String] { ["mock"] }

    func transcribe(
        _ request: TranscriptionRequest,
        progress: ((Double) -> Void)?
    ) async throws -> TranscriptionResult {
        let t0 = DispatchTime.now()

        let file = try AVAudioFile(forReading: request.audioURL)
        let duration = file.fileFormat.sampleRate > 0
            ? Double(file.length) / file.fileFormat.sampleRate
            : 0

        let chunk = 10.0
        let count = max(1, Int(ceil(duration / chunk)))
        var segments: [Segment] = []
        for k in 0..<count {
            let start = Double(k) * chunk
            let end = min(start + chunk, duration)
            let text = request.wantTimestamps
                ? "（示意段落 \(k + 1)，Phase 2 接上真實 engine 後將為實際逐字稿）"
                : "（示意逐字稿，Phase 2 接上真實 engine）"
            segments.append(Segment(start: start, end: end, text: text, confidence: nil))
            progress?(Double(k + 1) / Double(count))
        }

        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1e9
        let metrics = RuntimeMetrics(
            audioDurationSeconds: duration,
            transcriptionTimeSeconds: elapsed,
            peakMemoryMB: SystemMetrics.currentMemoryMB(),
            thermalState: SystemMetrics.thermalStateString(),
            device: SystemMetrics.deviceModel(),
            osVersion: SystemMetrics.osVersion()
        )

        return TranscriptionResult(
            transcript: segments.map(\.text).joined(separator: "\n"),
            segments: segments,
            detectedLanguage: request.languageHint,
            engine: name,
            model: request.modelOption ?? "mock",
            metrics: metrics
        )
    }
}
