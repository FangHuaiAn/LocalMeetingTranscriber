import AVFoundation

/// 正規化後的音訊：16kHz、mono、Float32。
/// 同時提供磁碟上的 WAV（給接受 URL 的 engine，如 Apple）與
/// 記憶體中的 float 樣本（給 WhisperKit / whisper.cpp）。
struct NormalizedAudio {
    let url: URL
    let samples: [Float]
    let duration: TimeInterval
    let sampleRate: Double
}

enum AudioPipelineError: LocalizedError {
    case converterInit
    case conversion(String)

    var errorDescription: String? {
        switch self {
        case .converterInit: return "無法建立音訊轉換器"
        case .conversion(let m): return "音訊轉換失敗：\(m)"
        }
    }
}

/// 1B 音訊前處理層：Format Normalizer / Sample Rate / Channel Converter。
/// Optional noise preprocessing 預留掛點（本階段不實作演算法）。
enum AudioPipeline {
    static let targetSampleRate: Double = 16000

    /// 預留的降噪掛點。Phase 1 直接回傳原樣本。
    static func optionalNoisePreprocess(_ samples: [Float]) -> [Float] {
        return samples
    }

    static func normalize(_ sourceURL: URL) throws -> NormalizedAudio {
        let samples = try self.samples(from: sourceURL)
        let duration = Double(samples.count) / targetSampleRate
        let url = try writeWAV(samples, sourceName: sourceURL.deletingPathExtension().lastPathComponent)
        return NormalizedAudio(url: url, samples: samples, duration: duration, sampleRate: targetSampleRate)
    }

    /// 把任意音檔讀成 16kHz、mono、Float32 樣本（不落地）。whisper.cpp 直接吃這個。
    static func samples(from sourceURL: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: sourceURL)
        let inFormat = file.processingFormat

        guard let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                            sampleRate: targetSampleRate,
                                            channels: 1,
                                            interleaved: false) else {
            throw AudioPipelineError.converterInit
        }

        guard let converter = AVAudioConverter(from: inFormat, to: outFormat) else {
            throw AudioPipelineError.converterInit
        }

        let inCapacity = AVAudioFrameCount(16384)
        guard let inBuffer = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: inCapacity) else {
            throw AudioPipelineError.converterInit
        }

        let ratio = outFormat.sampleRate / inFormat.sampleRate
        let outCapacity = AVAudioFrameCount(Double(inCapacity) * ratio) + 1024
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: outCapacity) else {
            throw AudioPipelineError.converterInit
        }

        var samples = [Float]()
        var fileFinished = false

        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if fileFinished {
                outStatus.pointee = .endOfStream
                return nil
            }
            do {
                try file.read(into: inBuffer)
            } catch {
                outStatus.pointee = .endOfStream
                fileFinished = true
                return nil
            }
            if inBuffer.frameLength == 0 {
                fileFinished = true
                outStatus.pointee = .endOfStream
                return nil
            }
            outStatus.pointee = .haveData
            return inBuffer
        }

        loop: while true {
            outBuffer.frameLength = 0
            var error: NSError?
            let status = converter.convert(to: outBuffer, error: &error, withInputFrom: inputBlock)
            if let error {
                throw AudioPipelineError.conversion(error.localizedDescription)
            }
            if outBuffer.frameLength > 0, let ch = outBuffer.floatChannelData {
                samples.append(contentsOf: UnsafeBufferPointer(start: ch[0], count: Int(outBuffer.frameLength)))
            }
            switch status {
            case .haveData, .inputRanDry:
                if fileFinished && outBuffer.frameLength == 0 { break loop }
            case .endOfStream, .error:
                break loop
            @unknown default:
                break loop
            }
        }

        return optionalNoisePreprocess(samples)
    }

    /// 寫出 16-bit PCM WAV（廣相容），供需要 URL 的 engine 與時間軸校對使用。
    private static func writeWAV(_ samples: [Float], sourceName: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("\(sourceName)-16k-mono.wav")

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: targetSampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]

        let outFile = try AVAudioFile(forWriting: url, settings: settings)

        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: targetSampleRate, channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(max(samples.count, 1))) else {
            throw AudioPipelineError.converterInit
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        if let ch = buffer.floatChannelData, !samples.isEmpty {
            samples.withUnsafeBufferPointer { src in
                ch[0].update(from: src.baseAddress!, count: samples.count)
            }
        }
        try outFile.write(from: buffer)
        return url
    }
}
