import Foundation

enum TimeFormat {
    /// 00:00:12
    static func hms(_ t: TimeInterval) -> String {
        let total = Int(t.rounded(.down))
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    /// 00:00:12,500 (SRT)
    static func srt(_ t: TimeInterval) -> String {
        let total = Int(t.rounded(.down))
        let ms = Int(((t - Double(total)) * 1000).rounded())
        return String(format: "%02d:%02d:%02d,%03d", total / 3600, (total % 3600) / 60, total % 60, ms)
    }
}

/// 1C 輸出層：TXT / Markdown / JSON / SRT，四條 engine 共用同一格式。
enum Exporters {
    static func txt(_ r: TranscriptionResult) -> String {
        r.segments.isEmpty ? r.transcript : r.segments.map(\.text).joined(separator: "\n")
    }

    static func markdown(_ r: TranscriptionResult, audioFileName: String) -> String {
        var lines: [String] = []
        lines.append("# Meeting Transcript")
        lines.append("")
        lines.append("## Metadata")
        lines.append("")
        lines.append("- Engine: \(r.engine)")
        lines.append("- Model: \(r.model)")
        lines.append("- Audio File: \(audioFileName)")
        lines.append("- Duration: \(TimeFormat.hms(r.metrics.audioDurationSeconds))")
        lines.append("- Transcription Time: \(String(format: "%.2f", r.metrics.transcriptionTimeSeconds))s")
        lines.append("- Language Hint: \(r.detectedLanguage ?? "auto")")
        lines.append("")
        lines.append("## Transcript")
        lines.append("")
        for s in r.segments {
            lines.append("[\(TimeFormat.hms(s.start)) - \(TimeFormat.hms(s.end))] \(s.text)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func srt(_ r: TranscriptionResult) -> String {
        var blocks: [String] = []
        for (i, s) in r.segments.enumerated() {
            blocks.append("\(i + 1)")
            blocks.append("\(TimeFormat.srt(s.start)) --> \(TimeFormat.srt(s.end))")
            blocks.append(s.text)
            blocks.append("")
        }
        return blocks.joined(separator: "\n")
    }

    static func json(_ r: TranscriptionResult, audioFileName: String) throws -> String {
        let export = JSONExport(
            engine: r.engine,
            model: r.model,
            audio_file: audioFileName,
            audio_duration_seconds: r.metrics.audioDurationSeconds,
            transcription_time_seconds: r.metrics.transcriptionTimeSeconds,
            segments: r.segments.map {
                JSONExport.Seg(start: $0.start, end: $0.end, text: $0.text, confidence: $0.confidence)
            },
            metrics: JSONExport.Metrics(
                device: r.metrics.device,
                os_version: r.metrics.osVersion,
                memory_peak_mb: r.metrics.peakMemoryMB,
                thermal_state: r.metrics.thermalState,
                battery_delta_percent: nil
            )
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        let data = try encoder.encode(export)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

/// 對應 README §6.3 JSON schema。
private struct JSONExport: Codable {
    let engine: String
    let model: String
    let audio_file: String
    let audio_duration_seconds: Double
    let transcription_time_seconds: Double
    let segments: [Seg]
    let metrics: Metrics

    struct Seg: Codable {
        let start: Double
        let end: Double
        let text: String
        let confidence: Double?
    }

    struct Metrics: Codable {
        let device: String
        let os_version: String
        let memory_peak_mb: Double?
        let thermal_state: String?
        let battery_delta_percent: Double?
    }
}
