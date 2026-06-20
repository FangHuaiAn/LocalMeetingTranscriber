# Local Meeting Transcriber 技術路線測試

## 1. 專案目的

本專案的目的不是立即設計完整的會議知識庫系統，而是先建立一個可重複測試的技術驗證環境，用來比較不同本地端語音轉文字技術路線在 macOS 與 iOS 上的可行性。

第一階段只回答一個核心問題：

> 哪一條本地端 transcription 技術路線，最適合作為未來 macOS / iOS 會議轉錄 app 的主引擎？

本階段不追求完整產品功能，不處理雲端同步、知識庫、摘要、行動事項、權限管理或跨裝置資料同步。這些功能必須等技術路線選定後，再進入完整系統規劃。

---

## 2. 測試原則

本專案採用「一個共同測試殼 + 三個 transcription engine adapter」的方式進行驗證。

不建立三套不同 app，也不建立三套不同 UI。三條路線必須共用相同的輸入、輸出、音訊前處理、測試資料與評分標準。只有 transcription engine 可以替換。

核心原則如下：

1. 三條路線使用同一組測試音檔。
2. 三條路線輸出相同格式的結果。
3. 三條路線使用同一張評分表。
4. 第一輪只測 transcription，不測完整會議知識庫。
5. 第一輪不把 speaker diarization 當作必要功能。
6. 測試重點是「使用者校訂成本」，不是單純模型名聲或 API 新穎性。

---

## 3. 第一階段範圍

### 3.1 本階段要做

第一階段只驗證以下能力：

- 匯入音檔。
- 錄音檔轉成模型可接受的音訊格式。
- 本地端 transcription。
- 產生段落時間戳。
- 輸出 TXT、Markdown、JSON。
- 若技術路線可合理支援，輸出 SRT。
- 記錄推論時間、耗電、發熱、記憶體壓力與失敗案例。

### 3.2 本階段不做

第一階段不做以下功能：

- 完整會議知識庫。
- 自動摘要。
- 行動事項提取。
- 雲端同步。
- 多使用者權限。
- 會議搜尋系統。
- 完整 speaker diarization。
- 即時字幕產品化。
- App Store 發布。
- 長期資料庫 schema 設計。

---

## 4. 三條 MVP 技術路線

## 4.1 MVP A：Apple SpeechAnalyzer / SpeechTranscriber

### 目的

驗證 Apple 原生 speech-to-text 路線是否足以作為產品主引擎。

### 核心問題

> Apple 原生 speech-to-text 是否已足夠處理 macOS / iOS 上的本地端會議轉錄？

### 優先驗證項目

| 項目 | 觀察重點 |
|---|---|
| 中文辨識 | 國語會議、台灣口音、一般會議語境 |
| 英文辨識 | 英文簡報、技術討論、專有名詞 |
| 中英混合 | 中文句子中夾英文術語、英文縮寫、產品名稱 |
| 長音訊 | 30 / 60 / 90 分鐘音檔是否穩定 |
| 遠距收音 | iPhone 放桌上、Mac 內建麥克風收音 |
| 時間戳 | 是否能支援音訊回放對齊 |
| 即時性 | 是否具備 live transcription 潛力 |
| 模型管理 | 使用者是否需要手動下載或管理語言模型 |
| 系統限制 | iOS / macOS 版本限制是否可接受 |

### 成功標準

若 Apple 原生路線在中文、英文、長音訊與時間戳品質上達到可接受水準，且整合成本明顯低於其他方案，則應列為第一順位主路線。

### 失敗條件

若出現以下情況，則不應將它作為唯一主路線：

- 語言支援不足。
- 專有名詞錯誤率高。
- 長音訊穩定性不足。
- 時間戳控制不足。
- 無法滿足本地端隱私需求。
- OS 版本限制過高，導致目標使用者無法使用。

---

## 4.2 MVP B：WhisperKit / Core ML

### 目的

驗證 Swift-native Whisper 類模型路線是否更適合本地端會議轉錄。

### 核心問題

> WhisperKit 是否能在 Apple 裝置上提供比 Apple 原生方案更好的轉錄品質與控制權？

### 優先驗證項目

| 項目 | 觀察重點 |
|---|---|
| 轉錄品質 | 中文、英文、中英混合是否優於 Apple 原生 |
| 模型大小 | tiny / base / small / large 類模型的品質與成本差異 |
| iPhone 效能 | 耗電、發熱、記憶體、推論速度 |
| macOS 效能 | Apple Silicon 上長音訊處理能力 |
| 專有名詞 | 是否能透過 prompt / context 改善辨識 |
| 時間戳 | 是否容易取得 segment-level 或 word-level timestamp |
| 模型管理 | 模型下載、模型更新、App 體積是否可接受 |
| 延展性 | 未來是否容易接 speaker diarization 或摘要流程 |

### 成功標準

若 WhisperKit 在中文、英文、中英混合、專有名詞與長音訊品質上明顯優於 Apple 原生方案，且 iOS 裝置上的速度、耗電、發熱與 App 體積可接受，則應列為主路線候選。

### 失敗條件

若出現以下情況，則不適合作為第一版主路線：

- iOS 記憶體壓力過高。
- 發熱或耗電不可接受。
- 推論速度過慢。
- 模型檔案過大，導致部署成本過高。
- 模型管理流程過於複雜。
- 實際品質沒有顯著優於 Apple 原生方案。

---

## 4.3 MVP C：whisper.cpp

### 目的

驗證高控制權 C/C++ 引擎路線是否值得額外工程成本。

### 核心問題

> whisper.cpp 的控制權、模型選擇、量化與效能調校，是否值得 Swift bridge 與 C/C++ 整合成本？

### 優先驗證項目

| 項目 | 觀察重點 |
|---|---|
| Swift 整合成本 | Objective-C++ bridge 或 C API wrapper 是否可維護 |
| 模型控制 | 不同模型與量化版本的品質差距 |
| 效能 | CPU / Metal / Core ML 路線差異 |
| 長音訊穩定性 | 是否出現 hallucination、重複、漏段、崩潰 |
| 輸出控制 | segment、timestamp、language detection 是否可控 |
| 部署成本 | 模型檔、binary、App Store 風險 |
| 可移植性 | 未來是否能延伸到 Windows / Linux |
| 維護成本 | C/C++ dependency 是否會提高長期維護負擔 |

### 成功標準

若 whisper.cpp 在效能、模型大小、輸出控制與長音訊穩定性上明顯勝出，且 Swift bridge 成本可控，則值得成為長期核心路線。

### 失敗條件

若出現以下情況，則不適合作為第一階段主路線：

- Swift / C++ 整合成本過高。
- crash 或記憶體問題難以排除。
- 結果沒有明顯優於 WhisperKit。
- App 打包與模型部署流程過於複雜。
- 長期維護需要投入過多底層工程資源。

---

## 5. 共用測試殼設計

三條路線必須共用同一個測試殼。

概念架構如下：

```text
MeetingTranscriberTestbed

Input Layer
  - Audio File Importer
  - Recording Importer

Audio Processing Layer
  - Format Normalizer
  - Sample Rate Converter
  - Channel Converter
  - Optional Noise Preprocessing

Engine Adapter Layer
  - AppleSpeechEngine
  - WhisperKitEngine
  - WhisperCppEngine

Output Layer
  - TXT Exporter
  - Markdown Exporter
  - JSON Exporter
  - SRT Exporter

Evaluation Layer
  - Runtime Logger
  - Memory Logger
  - Output Comparator
  - Human Correction Notes
```

Engine adapter 應盡量使用相同的輸入與輸出介面。

建議輸入：

```text
Audio file path
Language hint
Model option
Timestamp option
```

建議輸出：

```text
Transcript
Segments
Start time
End time
Confidence, if available
Detected language, if available
Engine metadata
Runtime metrics
```

---

## 6. 共用輸出格式

每條路線都至少輸出以下格式。

### 6.1 TXT

用途：快速閱讀與人工校訂。

### 6.2 Markdown

用途：作為未來會議紀錄與知識庫輸入格式。

建議格式：

```markdown
# Meeting Transcript

## Metadata

- Engine:
- Model:
- Audio File:
- Duration:
- Transcription Time:
- Language Hint:

## Transcript

[00:00:00 - 00:00:12] 文字內容
[00:00:12 - 00:00:25] 文字內容
```

### 6.3 JSON

用途：後續比較、分析、測試自動化。

建議欄位：

```json
{
  "engine": "",
  "model": "",
  "audio_file": "",
  "audio_duration_seconds": 0,
  "transcription_time_seconds": 0,
  "segments": [
    {
      "start": 0.0,
      "end": 0.0,
      "text": "",
      "confidence": null
    }
  ],
  "metrics": {
    "device": "",
    "os_version": "",
    "memory_peak_mb": null,
    "thermal_state": null,
    "battery_delta_percent": null
  }
}
```

### 6.4 SRT

用途：時間軸校對與音訊回放對齊。

若某條技術路線無法可靠輸出時間戳，可以先不輸出 SRT，但必須記錄為限制。

---

## 7. 共用測試語料

三條 MVP 必須使用同一組測試音檔。

| 編號 | 類型 | 測試內容 | 目的 |
|---|---|---|---|
| A1 | 乾淨中文 | 5 分鐘國語錄音 | 測基本中文品質 |
| A2 | 乾淨英文 | 5 分鐘英文錄音 | 測基本英文品質 |
| A3 | 中英混合 | 10 分鐘中英混合討論 | 測 code-switching |
| A4 | 中長會議 | 30 分鐘會議錄音 | 測中長音訊穩定性 |
| A5 | 長會議 | 60 分鐘會議錄音 | 測長時間推論成本 |
| A6 | 超長會議 | 90 分鐘會議錄音 | 測極限情境 |
| A7 | 遠距收音 | iPhone 放會議桌中央 | 測真實收音品質 |
| A8 | 專有名詞 | 人名、機構名、產品名、縮寫 | 測專有名詞錯誤率 |
| A9 | 兩人交談 | 兩位講者輪流發言 | 測段落切分 |
| A10 | 多人會議 | 三人以上討論 | 測多人語境 |
| A11 | 雜音環境 | 冷氣聲、鍵盤聲、背景聲 | 測抗噪能力 |
| A12 | 重疊說話 | 插話、打斷、同時發言 | 測失敗模式 |

測試語料不可只使用乾淨錄音。真正的會議 app 主要失敗點通常來自遠距收音、多人搶話、中英混合、專有名詞與背景噪音。

---

## 8. 評分指標

每條路線使用同一張評分表。

| 指標 | 權重 | 說明 |
|---|---:|---|
| 轉錄準確率 | 25% | 中文、英文、中英混合的整體辨識品質 |
| 長音訊穩定性 | 15% | 30–90 分鐘是否崩潰、重複、漏段 |
| 時間戳品質 | 15% | 是否可支援音訊回放對齊與 SRT 輸出 |
| iOS 效能 | 15% | 耗電、發熱、速度、記憶體 |
| macOS 效能 | 10% | Apple Silicon 上的長音訊處理能力 |
| 整合成本 | 10% | Swift 整合、維護、debug 成本 |
| 模型 / 系統限制 | 5% | OS 版本、模型下載、授權、App 體積 |
| 未來延展性 | 5% | speaker diarization、摘要、知識庫化潛力 |
| **總計** | **100%** |  |

---

## 9. 人工校訂成本指標

第一輪不必追求學術級 WER 評估。更重要的產品指標是：

> 一小時會議轉錄後，使用者需要花多少時間修到可用？

建議記錄：

| 項目 | 說明 |
|---|---|
| Raw transcript 可讀性 | 未校訂前是否能理解大意 |
| 每 10 分鐘錯誤數 | 估算人工修正密度 |
| 專有名詞錯誤 | 人名、公司名、產品名、技術名詞 |
| 標點與斷句 | 是否需要大量重排 |
| 漏段 | 是否漏掉整句或整段 |
| 幻覺 | 是否產生音訊中不存在的內容 |
| 重複 | 是否出現重複句段 |
| 校訂時間 | 修正到可用所需時間 |

建議以以下方式記錄：

```text
Correction Ratio = 校訂時間 / 原始音訊時間
```

例如：

```text
60 分鐘會議，校訂花 30 分鐘，Correction Ratio = 0.5
60 分鐘會議，校訂花 90 分鐘，Correction Ratio = 1.5
```

Correction Ratio 越低，產品價值越高。

---

## 10. 測試紀錄模板

每一次測試都應建立一份紀錄。

```markdown
# Test Run

## Metadata

- Date:
- Device:
- OS Version:
- Engine:
- Model:
- Audio File:
- Audio Duration:
- Language Hint:

## Runtime

- Transcription Time:
- Real-time Factor:
- Peak Memory:
- Battery Delta:
- Thermal State:
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
```

---

## 11. 決策規則

測試完成後，不問「哪個模型最強」，而問：

> 哪條路線最適合成為第一版產品核心？

建議決策規則如下：

| 測試結果 | 決策 |
|---|---|
| Apple SpeechAnalyzer 品質足夠，且整合成本最低 | 採 MVP A 為主路線 |
| WhisperKit 明顯更準，iOS 效能可接受 | 採 MVP B 為主路線 |
| whisper.cpp 明顯更穩、更可控 | 採 MVP C 為主路線 |
| A 最穩、B 最準、C 最可控 | 第一版用 A，上層保留 engine abstraction |
| 三者都不夠 | 先改善音訊前處理與錄音策略，不急著設計大系統 |

---

## 12. 不應過早投入的方向

以下方向在第一階段應避免投入過多時間：

### 12.1 不要過早做完整 UI

UI 只要足夠完成測試即可。第一階段重點不是產品體驗，而是 engine comparison。

### 12.2 不要過早做 speaker diarization

說話者分離會引入額外問題：

- 多人重疊說話。
- 段落切分。
- speaker label 對齊。
- speaker name 人工修正。
- diarization 與 ASR 錯誤互相污染。

第一輪只測：

```text
音訊 → 文字 → 時間戳 → 匯出
```

第二輪才測：

```text
文字段落 → speaker label → 人工修正成本
```

### 12.3 不要過早做摘要

摘要品質會被 transcription 品質直接影響。若逐字稿本身不可靠，摘要只會放大錯誤。

### 12.4 不要過早做知識庫

知識庫設計依賴穩定的資料結構。第一階段應先確認 transcript 的品質、時間戳結構與 metadata 是否穩定。

---

## 13. 第一階段交付物

第一階段完成時，應產出以下成果：

1. 一個共用 SwiftUI 測試殼。
2. 三個 transcription engine adapter。
3. 一組固定測試音檔。
4. 每條路線的輸出檔案。
5. 每條路線的測試紀錄。
6. 一份比較評分表。
7. 一份技術路線選型報告。

---

## 14. 技術路線選型報告格式

測試完成後，建立一份選型報告。

建議格式：

```markdown
# 技術路線選型報告

## 1. 測試結論

推薦主路線：
備援路線：
不建議路線：

## 2. 總分比較

| 路線 | 總分 | 結論 |
|---|---:|---|
| Apple SpeechAnalyzer |  |  |
| WhisperKit |  |  |
| whisper.cpp |  |  |

## 3. 品質比較

## 4. 效能比較

## 5. 整合成本比較

## 6. 主要失敗模式

## 7. 產品風險

## 8. 下一階段建議
```

---

## 15. 底層判準

本專案的底層判準是：

> 哪條技術路線能以最低維護成本，產生最可信任的會議文字資產？

不是哪個模型最新，也不是哪個 API 最酷。

第一階段的正確終點不是完整 app，而是一個足以支持技術決策的證據集。

只有當技術路線被驗證後，才開始討論完整系統規劃，包括：

- 會議資料模型。
- 本地資料庫。
- 搜尋。
- 摘要。
- 行動事項。
- speaker diarization。
- 跨裝置同步。
- 知識庫化。
- 安全與隱私設計。
