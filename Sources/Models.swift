import Foundation

/// 三條 engine 共用的輸入請求。
struct TranscriptionRequest {
    let audioURL: URL          // 已正規化的音檔
    let languageHint: String?  // "zh" / "en" / nil = auto
    let modelOption: String?   // engine-specific model id
    let wantTimestamps: Bool
}

/// 單一時間戳段落。
struct Segment: Identifiable {
    let id = UUID()
    let start: TimeInterval
    let end: TimeInterval
    let text: String
    let confidence: Double?    // nil if unavailable
}

/// 執行期量測指標。
struct RuntimeMetrics {
    let audioDurationSeconds: Double
    let transcriptionTimeSeconds: Double
    let peakMemoryMB: Double?
    let thermalState: String?
    let device: String
    let osVersion: String

    var realTimeFactor: Double {
        guard audioDurationSeconds > 0 else { return 0 }
        return transcriptionTimeSeconds / audioDurationSeconds
    }
}

/// 一次轉錄的完整結果，所有 engine 輸出相同結構。
struct TranscriptionResult {
    let transcript: String
    let segments: [Segment]
    let detectedLanguage: String?
    let engine: String
    let model: String
    let metrics: RuntimeMetrics
}
