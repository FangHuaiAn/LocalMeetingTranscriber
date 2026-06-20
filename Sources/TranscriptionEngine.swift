import Foundation

/// 所有轉錄路線共用的介面契約。
/// 換掉任一實作，UI 與 Exporter 程式碼都不需更動。
protocol TranscriptionEngine {
    /// 顯示用名稱，例如 "Apple SpeechAnalyzer"。
    var name: String { get }

    /// 該 engine 可選的模型清單（engine-specific id）。
    func availableModels() -> [String]

    /// 執行轉錄。`progress` 回報 0.0–1.0 進度。
    func transcribe(
        _ request: TranscriptionRequest,
        progress: ((Double) -> Void)?
    ) async throws -> TranscriptionResult
}
