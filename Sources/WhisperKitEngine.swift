import Foundation
import AVFoundation
import WhisperKit

/// Phase 3：WhisperKit / Core ML 路線。
/// in-process Whisper 模型（與 Apple daemon 路線不同，記憶體佔用反映真實模型大小）。
struct WhisperKitEngine: TranscriptionEngine {
    var name: String { "WhisperKit" }

    /// README §4.2：tiny / base / small / large 的品質與成本差異。
    func availableModels() -> [String] { ["tiny", "base", "small", "large-v3"] }

    func transcribe(
        _ request: TranscriptionRequest,
        progress: ((Double) -> Void)?
    ) async throws -> TranscriptionResult {
        let t0 = DispatchTime.now()
        let model = request.modelOption ?? "base"

        // 載入（首次會自動下載 Core ML 模型）。
        let config = WhisperKitConfig(model: model, download: true)
        let pipe = try await WhisperKit(config)
        progress?(0.2)

        let options = DecodingOptions(
            task: .transcribe,
            language: request.languageHint,                       // nil → 自動偵測
            detectLanguage: request.languageHint == nil ? true : nil,
            skipSpecialTokens: true,                              // 去除 <|startoftranscript|> 等特殊 token
            wordTimestamps: false,
            chunkingStrategy: .vad                                 // 長音訊以 VAD 切窗，提升穩定性
        )

        let wkResults = try await pipe.transcribe(audioPath: request.audioURL.path, decodeOptions: options)
        progress?(0.95)

        var segments: [Segment] = []
        for r in wkResults {
            for s in r.segments {
                let text = s.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                segments.append(Segment(
                    start: Double(s.start),
                    end: Double(s.end),
                    text: text,
                    confidence: Double(Foundation.exp(s.avgLogprob))   // logprob → 0–1 proxy
                ))
            }
        }

        let duration = (try? AVAudioFile(forReading: request.audioURL)).map {
            Double($0.length) / $0.fileFormat.sampleRate
        } ?? (segments.last?.end ?? 0)

        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1e9
        let metrics = RuntimeMetrics(
            audioDurationSeconds: duration,
            transcriptionTimeSeconds: elapsed,
            peakMemoryMB: SystemMetrics.currentMemoryMB(),
            thermalState: SystemMetrics.thermalStateString(),
            device: SystemMetrics.deviceModel(),
            osVersion: SystemMetrics.osVersion()
        )
        progress?(1.0)

        return TranscriptionResult(
            transcript: segments.map(\.text).joined(separator: " "),
            segments: segments,
            detectedLanguage: wkResults.first?.language ?? request.languageHint,
            engine: name,
            model: model,
            metrics: metrics
        )
    }
}
