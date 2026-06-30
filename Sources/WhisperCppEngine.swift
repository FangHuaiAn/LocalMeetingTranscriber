import Foundation

/// Phase 4：whisper.cpp 路線（C API 經 bridging header 直呼，Metal 後端）。
/// 最高控制權，但整合成本最高：需自行建 xcframework/靜態庫、bridging header、
/// 手動下載 ggml 模型。對照 WhisperKit 的一行 SPM。
struct WhisperCppEngine: TranscriptionEngine {
    var name: String { "whisper.cpp" }

    /// 對應 HuggingFace ggerganov/whisper.cpp 的 ggml 模型檔。
    func availableModels() -> [String] { ["tiny", "base", "small", "large-v3"] }

    func transcribe(
        _ request: TranscriptionRequest,
        progress: ((Double) -> Void)?
    ) async throws -> TranscriptionResult {
        let t0 = DispatchTime.now()
        let model = request.modelOption ?? "base"
        let modelURL = try await ensureModel(model)
        progress?(0.2)

        // 讀成 16kHz mono float（whisper.cpp 的標準輸入）。
        let samples = try AudioPipeline.samples(from: request.audioURL)
        let duration = Double(samples.count) / AudioPipeline.targetSampleRate

        // 初始化 context（use_gpu = Metal）。
        var cparams = whisper_context_default_params()
        cparams.use_gpu = true
        guard let ctx = whisper_init_from_file_with_params(modelURL.path, cparams) else {
            throw WhisperCppError.initFailed
        }
        defer { whisper_free(ctx) }
        progress?(0.3)

        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.print_progress = false
        params.print_realtime = false
        params.print_special = false
        params.no_timestamps = false
        params.translate = false
        params.n_threads = Int32(max(1, ProcessInfo.processInfo.activeProcessorCount - 2))
        params.detect_language = (request.languageHint == nil)

        let langCode = request.languageHint ?? "auto"
        let status: Int32 = langCode.withCString { cLang in
            params.language = cLang
            return samples.withUnsafeBufferPointer { buf in
                whisper_full(ctx, params, buf.baseAddress, Int32(buf.count))
            }
        }
        guard status == 0 else { throw WhisperCppError.inferenceFailed(status) }
        progress?(0.95)

        var segments: [Segment] = []
        let n = whisper_full_n_segments(ctx)
        for i in 0..<n {
            let cText = whisper_full_get_segment_text(ctx, i)
            let text = (cText.map { String(cString: $0) } ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            // t0/t1 為 10ms 單位（centiseconds）。
            let start = Double(whisper_full_get_segment_t0(ctx, i)) / 100.0
            let end = Double(whisper_full_get_segment_t1(ctx, i)) / 100.0
            segments.append(Segment(start: start, end: end, text: text, confidence: nil))
        }

        let detected = whisper_lang_str(whisper_full_lang_id(ctx)).map { String(cString: $0) }
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
            detectedLanguage: detected ?? request.languageHint,
            engine: name,
            model: model,
            metrics: metrics
        )
    }

    /// 確保 ggml 模型存在；缺則自 HuggingFace 下載到 ~/Documents/.../Models/。
    private func ensureModel(_ model: String) async throws -> URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LocalMeetingTranscriber").appendingPathComponent("Models")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileName = "ggml-\(model).bin"
        let dest = dir.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: dest.path) { return dest }

        guard let remote = URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(fileName)") else {
            throw WhisperCppError.modelDownloadFailed
        }
        FileHandle.standardError.write("• 下載 whisper.cpp 模型 \(fileName)…\n".data(using: .utf8)!)
        let (tmp, response) = try await URLSession.shared.download(from: remote)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw WhisperCppError.modelDownloadFailed
        }
        try FileManager.default.moveItem(at: tmp, to: dest)
        return dest
    }
}

enum WhisperCppError: LocalizedError {
    case initFailed
    case inferenceFailed(Int32)
    case modelDownloadFailed

    var errorDescription: String? {
        switch self {
        case .initFailed: return "whisper.cpp context 初始化失敗（模型檔不正確？）"
        case .inferenceFailed(let code): return "whisper_full 失敗，code \(code)"
        case .modelDownloadFailed: return "ggml 模型下載失敗"
        }
    }
}
