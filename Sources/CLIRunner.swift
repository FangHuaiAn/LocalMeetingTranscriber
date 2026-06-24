import Foundation

/// Headless 測試跑批：正規化 → 轉錄 → 落地，並印出摘要。
/// 用法：LocalMeetingTranscriber --transcribe <audio> [--engine apple|mock] [--lang zh|en]
enum CLIRunner {
    static func run(path: String, engineName: String?, lang: String?) async {
        let url = URL(fileURLWithPath: path)
        let engines: [TranscriptionEngine] = [AppleSpeechEngine(), WhisperKitEngine(), MockEngine()]
        let key = (engineName ?? "apple").lowercased()
        let engine = engines.first { $0.name.lowercased().contains(key) } ?? engines[0]

        do {
            log("正規化音訊：\(url.lastPathComponent)")
            let norm = try AudioPipeline.normalize(url)
            log("時長 \(String(format: "%.1f", norm.duration))s，engine = \(engine.name)，轉錄中…")

            let request = TranscriptionRequest(
                audioURL: norm.url, languageHint: lang, modelOption: nil, wantTimestamps: true
            )
            let res = try await engine.transcribe(request) { _ in }
            let dir = try ResultStore.save(res, audioFileName: url.lastPathComponent)

            let m = res.metrics
            print("---------------------------------------------")
            print("Engine:     \(res.engine)")
            print("Language:   \(res.detectedLanguage ?? "auto")")
            print("Duration:   \(String(format: "%.2f", m.audioDurationSeconds))s")
            print("Time:       \(String(format: "%.2f", m.transcriptionTimeSeconds))s")
            print("RTF:        \(String(format: "%.3f", m.realTimeFactor))")
            print("Peak Mem:   \(m.peakMemoryMB.map { String(format: "%.0f MB", $0) } ?? "n/a")")
            print("Segments:   \(res.segments.count)")
            print("Output:     \(dir.path)")
            print("--- transcript (前 600 字) ---")
            print(String(res.transcript.prefix(600)))
            print("---------------------------------------------")
        } catch {
            print("ERROR: \(error.localizedDescription)")
        }
    }

    private static func log(_ s: String) {
        FileHandle.standardError.write(("• " + s + "\n").data(using: .utf8)!)
    }
}
