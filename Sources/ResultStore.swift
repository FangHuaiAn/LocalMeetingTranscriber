import Foundation

/// 1D 結果落地：每次測試輸出到 ~/Documents/LocalMeetingTranscriber/Output/<engine>/<audio>/。
/// （App 從 DerivedData 執行，故落地到使用者 Documents，而非專案相對路徑。）
enum ResultStore {
    static func outputBase() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs
            .appendingPathComponent("LocalMeetingTranscriber")
            .appendingPathComponent("Output")
    }

    /// 寫出 TXT / MD / JSON / SRT + Test Run 紀錄，回傳輸出資料夾 URL。
    @discardableResult
    static func save(_ r: TranscriptionResult, audioFileName: String) throws -> URL {
        let audioStem = (audioFileName as NSString).deletingPathExtension
        let dir = outputBase()
            .appendingPathComponent(sanitize(r.engine))
            .appendingPathComponent(sanitize(audioStem))
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        try Exporters.txt(r).write(to: dir.appendingPathComponent("transcript.txt"), atomically: true, encoding: .utf8)
        try Exporters.markdown(r, audioFileName: audioFileName).write(to: dir.appendingPathComponent("transcript.md"), atomically: true, encoding: .utf8)
        try Exporters.json(r, audioFileName: audioFileName).write(to: dir.appendingPathComponent("transcript.json"), atomically: true, encoding: .utf8)

        // SRT 僅在有時間戳時輸出；否則記錄限制。
        if r.segments.contains(where: { $0.end > 0 }) {
            try Exporters.srt(r).write(to: dir.appendingPathComponent("transcript.srt"), atomically: true, encoding: .utf8)
        }

        try testRunMarkdown(r, audioFileName: audioFileName).write(to: dir.appendingPathComponent("test_run.md"), atomically: true, encoding: .utf8)
        return dir
    }

    /// README §10 Test Run 模板，可量測欄位自動帶入，人工欄位留空。
    private static func testRunMarkdown(_ r: TranscriptionResult, audioFileName: String) -> String {
        let m = r.metrics
        return """
        # Test Run

        ## Metadata

        - Date: \(ISO8601DateFormatter().string(from: Date()))
        - Device: \(m.device)
        - OS Version: \(m.osVersion)
        - Engine: \(r.engine)
        - Model: \(r.model)
        - Audio File: \(audioFileName)
        - Audio Duration: \(TimeFormat.hms(m.audioDurationSeconds))
        - Language Hint: \(r.detectedLanguage ?? "auto")

        ## Runtime

        - Transcription Time: \(String(format: "%.2f", m.transcriptionTimeSeconds))s
        - Real-time Factor: \(String(format: "%.3f", m.realTimeFactor))
        - Peak Memory: \(m.peakMemoryMB.map { String(format: "%.1f MB", $0) } ?? "n/a")
        - Battery Delta: n/a
        - Thermal State: \(m.thermalState ?? "n/a")
        - Crash / Error:

        ## Output Quality

        - Overall Readability:
        - Chinese Accuracy:
        - English Accuracy:
        - Mixed Language Accuracy:
        - Proper Noun Accuracy:
        - Timestamp Quality:
        - Segment Quality:

        ## Failure Notes

        - Missing Segments:
        - Hallucination:
        - Repetition:
        - Bad Punctuation:
        - Speaker Confusion:
        - Noise Sensitivity:

        ## Human Correction

        - Correction Time:
        - Correction Ratio:
        - Main Correction Types:

        ## Decision Notes

        - Strengths:
        - Weaknesses:
        - Should Continue Testing:
        - Should Be Main Route Candidate:
        """
    }

    private static func sanitize(_ s: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.whitespaces)
        return s.components(separatedBy: invalid).filter { !$0.isEmpty }.joined(separator: "_")
    }
}
