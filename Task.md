# Task — Local Meeting Transcriber 技術路線測試（第一階段）

本檔依 `README.md` 擬定第一階段實作計畫。第一階段目標：建立「一個共用測試殼 + 三個 transcription engine adapter」，產出足以支持技術選型的證據集。

## 決策前提

| 項目 | 決策 | 影響 |
|---|---|---|
| 平台 | **先做 macOS（Apple Silicon）** | 整合最簡；iOS 效能/耗電指標延後到路線初步收斂後再驗 |
| Engine 範圍 | **三條全做**（Apple / WhisperKit / whisper.cpp） | 完整對比，whisper.cpp C++ bridge 為最大工程量 |
| 測試語料 | **尚未準備** | 計畫需包含 A1–A12 音檔的錄製/收集工作 |

第一階段**不做**：完整知識庫、摘要、行動事項、雲端同步、權限、會議搜尋、完整 speaker diarization、即時字幕產品化、App Store 發布、長期 DB schema。

第一階段只驗證資料流：`音訊 → 文字 → 時間戳 → 匯出`。

---

## 架構總覽

```text
MeetingTranscriberTestbed (SwiftUI macOS app)

Core (SPM library，平台無關，方便日後 iOS 共用)
  - Models: TranscriptionRequest / Result / Segment / Metrics
  - TranscriptionEngine protocol
  - AudioPipeline (normalize → 16kHz mono PCM)
  - Exporters: TXT / Markdown / JSON / SRT
  - Evaluation: RuntimeLogger / MemoryLogger / Comparator

Engines
  - AppleSpeechEngine   (SpeechAnalyzer / SpeechTranscriber)
  - WhisperKitEngine    (SPM: argmaxinc/WhisperKit)
  - WhisperCppEngine    (whisper.cpp + Obj-C++ bridge)

UI (SwiftUI，最小可用)
  - 匯入音檔、選 engine/model、跑轉錄、看結果、匯出、看 metrics
```

設計原則：UI 與 Core 解耦，三條 engine 共用相同 input/output 介面，只有 `TranscriptionEngine` 實作可替換。

---

## 共用介面契約（先鎖定，三條 engine 共用）

```swift
struct TranscriptionRequest {
    let audioURL: URL          // 已正規化的音檔
    let languageHint: String?  // e.g. "zh", "en", nil = auto
    let modelOption: String?   // engine-specific model id
    let wantTimestamps: Bool
}

struct Segment {
    let start: TimeInterval
    let end: TimeInterval
    let text: String
    let confidence: Double?    // nil if unavailable
}

struct TranscriptionResult {
    let transcript: String
    let segments: [Segment]
    let detectedLanguage: String?
    let engine: String
    let model: String
    let metrics: RuntimeMetrics
}

struct RuntimeMetrics {
    let audioDurationSeconds: Double
    let transcriptionTimeSeconds: Double
    var realTimeFactor: Double { transcriptionTimeSeconds / audioDurationSeconds }
    let peakMemoryMB: Double?
    let thermalState: String?
    let device: String
    let osVersion: String
}

protocol TranscriptionEngine {
    var name: String { get }
    func availableModels() -> [String]
    func transcribe(_ request: TranscriptionRequest,
                    progress: ((Double) -> Void)?) async throws -> TranscriptionResult
}
```

驗收：任一 engine 換掉，UI 與 Exporter 程式碼不需更動。

---

## Phase 0 — 專案骨架

- [ ] 0.1 建立 Xcode SwiftUI macOS app（target: Apple Silicon，最低 OS 對應 SpeechAnalyzer 可用版本，於 0.2 確認）
- [ ] 0.2 確認 `SpeechAnalyzer` / `SpeechTranscriber` 在當前 macOS 版本可用，記錄最低系統需求
- [ ] 0.3 拆出 `Core` 為本地 SPM package（平台無關），app 依賴之
- [ ] 0.4 定義上節共用介面契約（Models + `TranscriptionEngine` protocol），先寫成可編譯的 stub
- [ ] 0.5 設定 `.gitignore`（Xcode / SPM / 模型檔 / 音檔產物），建立 `Models/`、`Corpus/`、`Output/` 目錄約定
- [ ] 0.6 麥克風 / 檔案存取等 entitlements 與 Info.plist 權限字串

**驗收**：空殼 app 可編譯、可開啟、Core package 可被測試 target 匯入。

---

## Phase 1 — 共用測試殼（先以 Apple engine 打通端到端）

### 1A 輸入層
- [ ] 1.1 Audio File Importer：支援常見格式（m4a / wav / mp3 / caf），取得時長與基本 metadata

### 1B 音訊前處理層
- [ ] 1.2 `AudioPipeline`：用 AVAudioConverter 正規化為 16kHz、mono、PCM（Whisper 系標準輸入）
- [ ] 1.3 Sample rate / channel 轉換與邊界處理（已是 16k mono 時略過）
- [ ] 1.4 預留 optional noise preprocessing 介面（本階段不實作演算法，留掛點）

### 1C 輸出層
- [ ] 1.5 TXT Exporter
- [ ] 1.6 Markdown Exporter（依 README §6.2 metadata + `[hh:mm:ss - hh:mm:ss] 文字` 格式）
- [ ] 1.7 JSON Exporter（依 README §6.3 schema，含 metrics 區塊）
- [ ] 1.8 SRT Exporter（無可靠時間戳的 engine 可跳過並記錄為限制）

### 1D 評估層
- [ ] 1.9 RuntimeLogger：量測 transcription time、Real-time Factor
- [ ] 1.10 MemoryLogger：peak memory（`task_info` / `os_proc_available_memory`），thermalState（`ProcessInfo.thermalState`）
- [ ] 1.11 結果落地：每次測試輸出到 `Output/<engine>/<audio>/`（TXT/MD/JSON/SRT + Test Run 紀錄）

### 1E 最小 UI
- [ ] 1.12 匯入音檔 → 選 engine/model/語言提示 → 跑轉錄（含進度）→ 顯示 transcript + segments + metrics → 一鍵匯出
- [ ] 1.13 不追求美觀，只要能完整跑完一輪測試

**驗收**：用一個樣本音檔，透過 Apple engine 完整跑出 TXT/MD/JSON（必要時 SRT）+ metrics。

---

## Phase 2 — Engine A：Apple SpeechAnalyzer / SpeechTranscriber

- [ ] 2.1 `AppleSpeechEngine` 實作 `TranscriptionEngine`
- [ ] 2.2 接 `SpeechAnalyzer` + `SpeechTranscriber`，取得 segment + 時間戳 + （若有）confidence
- [ ] 2.3 語言提示處理（zh / en / auto），記錄是否需手動下載語言模型（README §4.1 模型管理）
- [ ] 2.4 長音訊串流處理（30/60/90 分鐘穩定性，不可一次塞爆記憶體）
- [ ] 2.5 detectedLanguage 與 engine metadata 回填

**驗收**：對 A1–A6 可穩定輸出含時間戳的結果，並記錄 OS / 模型限制。

---

## Phase 3 — Engine B：WhisperKit / Core ML

- [ ] 3.1 加入 SPM 依賴 `argmaxinc/WhisperKit`
- [ ] 3.2 `WhisperKitEngine` 實作 `TranscriptionEngine`
- [ ] 3.3 模型管理：tiny / base / small / large 下載與選擇（記錄 App 體積與下載流程成本）
- [ ] 3.4 取得 segment-level（必要時 word-level）timestamp
- [ ] 3.5 專有名詞 prompt / context 機制（README §4.2），可選帶入詞表
- [ ] 3.6 macOS（Apple Silicon）長音訊效能與記憶體量測

**驗收**：同一組 A1–A6 跑出可比較結果，不同 model size 的品質/成本差異有紀錄。

---

## Phase 4 — Engine C：whisper.cpp

- [ ] 4.1 引入 whisper.cpp（git submodule 或 xcframework），決定 Metal / Core ML / CPU 建置路線
- [ ] 4.2 Objective-C++ bridge 或 C API wrapper，封裝為 Swift 可呼叫介面
- [ ] 4.3 `WhisperCppEngine` 實作 `TranscriptionEngine`
- [ ] 4.4 模型/量化版本管理（ggml 模型檔，記錄部署成本）
- [ ] 4.5 輸出控制：segment、timestamp、language detection
- [ ] 4.6 長音訊穩定性觀察：hallucination / 重複 / 漏段 / crash
- [ ] 4.7 記錄 Swift↔C++ 整合與維護成本（README §4.3 失敗條件）

**驗收**：bridge 可維護、A1–A6 可穩定跑完，整合成本有明確紀錄。

---

## Phase 5 — 測試語料準備（A1–A12，尚未準備）

- [ ] 5.1 錄製/收集 12 組音檔（README §7），固定後不再更動：
  - A1 乾淨中文 5min / A2 乾淨英文 5min / A3 中英混合 10min
  - A4 30min / A5 60min / A6 90min 會議
  - A7 遠距收音（iPhone 置會議桌中央）/ A8 專有名詞 / A9 兩人交談 / A10 多人 / A11 雜音 / A12 重疊說話
- [ ] 5.2 為 A8 建立專有名詞「標準答案表」（人名/機構/產品/縮寫）以利錯誤率評估
- [ ] 5.3 語料 metadata 表（時長、語言、情境、收音方式），存於 `Corpus/`
- [ ] 5.4 語料不可只含乾淨錄音，須覆蓋遠距、多人、混語、噪音、搶話等真實失敗點

**驗收**：12 組音檔齊備且固定，三條 engine 共用同一份。

---

## Phase 6 — 評估、紀錄與選型報告

- [ ] 6.1 Test Run 紀錄模板（README §10），每次測試自動帶入可量測欄位，人工欄位留空待填
- [ ] 6.2 Output Comparator：同一音檔三 engine 並排比較（transcript diff + metrics）
- [ ] 6.3 人工校訂成本量測流程（README §9）：每 10 分鐘錯誤數、Correction Ratio = 校訂時間 / 音訊時間
- [ ] 6.4 評分表（README §8 八項加權，總分 100%），三條路線各一份
- [ ] 6.5 技術路線選型報告（README §14 格式）：推薦主路線 / 備援 / 不建議 + 失敗模式 + 下一階段建議

**驗收**：產出 README §13 全部七項交付物。

---

## 第一階段交付物檢核（README §13）

- [ ] 1. 共用 SwiftUI 測試殼
- [ ] 2. 三個 transcription engine adapter
- [ ] 3. 一組固定測試音檔（A1–A12）
- [ ] 4. 每條路線的輸出檔案（TXT/MD/JSON/SRT）
- [ ] 5. 每條路線的測試紀錄
- [ ] 6. 一份比較評分表
- [ ] 7. 一份技術路線選型報告

---

## 建議執行順序與相依

```text
Phase 0 ─▶ Phase 1 (Apple 打通端到端) ─▶ Phase 2 (Apple 完整)
                                         ├▶ Phase 3 (WhisperKit)
                                         └▶ Phase 4 (whisper.cpp)
Phase 5 (語料) 可與 Phase 0–1 並行開始，須在 Phase 2 大量測試前完成
Phase 6 在三條 engine 至少可跑 A1–A6 後啟動
```

關鍵風險：
- whisper.cpp bridge（Phase 4）為最大不確定性，建議排在 Apple/WhisperKit 之後，避免阻塞整體進度。
- 語料錄製（Phase 5）耗時且需實體環境，越早開始越好。
- 先用「介面契約」鎖定 I/O，避免三條 engine 各自長出不相容的輸出。

---

## 待確認 / 假設

- macOS 最低版本依 `SpeechAnalyzer` 可用性決定（Phase 0.2 驗證後回填）。
- iOS 效能/耗電/發熱指標（README §8 的 iOS 15%）本階段先以 macOS 為主，待路線初步收斂後再補 iOS 驗證；屆時 Core package 已平台無關，可直接複用。
- 第一輪不做 speaker diarization；A9/A10/A12 只觀察段落切分與失敗模式，不做 speaker label。
