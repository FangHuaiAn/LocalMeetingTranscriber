import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor
final class TestbedViewModel: ObservableObject {
    @Published var audioURL: URL?
    @Published var languageHint: String = "auto"   // auto / zh / en
    @Published var wantTimestamps = true
    @Published var selectedEngineName: String
    @Published var isRunning = false
    @Published var progress: Double = 0
    @Published var statusMessage = "請匯入音檔。"
    @Published var result: TranscriptionResult?
    @Published var exportDir: URL?

    /// Phase 4 會把 whisper.cpp 加入此清單。
    let engines: [TranscriptionEngine] = [AppleSpeechEngine(), WhisperKitEngine(), MockEngine()]
    let pendingEngines = ["whisper.cpp（Phase 4）"]

    init() {
        selectedEngineName = engines[0].name
    }

    func pickAudio() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audio]
        if panel.runModal() == .OK, let url = panel.url {
            audioURL = url
            result = nil
            exportDir = nil
            statusMessage = "已選擇：\(url.lastPathComponent)"
        }
    }

    func run() {
        guard let audioURL else { return }
        guard let engine = engines.first(where: { $0.name == selectedEngineName }) else { return }
        let lang = languageHint == "auto" ? nil : languageHint
        isRunning = true
        progress = 0
        result = nil
        exportDir = nil
        statusMessage = "正規化音訊（16kHz mono）…"

        Task {
            do {
                let normalized = try AudioPipeline.normalize(audioURL)
                statusMessage = "轉錄中…（\(engine.name)）"
                let request = TranscriptionRequest(
                    audioURL: normalized.url,
                    languageHint: lang,
                    modelOption: nil,
                    wantTimestamps: wantTimestamps
                )
                let res = try await engine.transcribe(request) { p in
                    Task { @MainActor in self.progress = p }
                }
                result = res
                statusMessage = "完成。RTF \(String(format: "%.3f", res.metrics.realTimeFactor))"
            } catch {
                statusMessage = "錯誤：\(error.localizedDescription)"
            }
            isRunning = false
        }
    }

    func export() {
        guard let result, let audioURL else { return }
        do {
            let dir = try ResultStore.save(result, audioFileName: audioURL.lastPathComponent)
            exportDir = dir
            statusMessage = "已匯出：\(dir.path)"
        } catch {
            statusMessage = "匯出失敗：\(error.localizedDescription)"
        }
    }
}

struct ContentView: View {
    @StateObject private var vm = TestbedViewModel()

    var body: some View {
        HSplitView {
            controls
                .frame(minWidth: 300, idealWidth: 340, maxWidth: 420)
            resultPane
                .frame(minWidth: 380)
        }
        .frame(minWidth: 820, minHeight: 560)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Local Meeting Transcriber — Testbed")
                .font(.headline)

            GroupBox("音檔") {
                VStack(alignment: .leading, spacing: 8) {
                    Button("匯入音檔…") { vm.pickAudio() }
                    Text(vm.audioURL?.lastPathComponent ?? "尚未選擇")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(4)
            }

            GroupBox("設定") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Engine", selection: $vm.selectedEngineName) {
                        ForEach(vm.engines, id: \.name) { Text($0.name).tag($0.name) }
                    }
                    Picker("語言提示", selection: $vm.languageHint) {
                        Text("auto").tag("auto")
                        Text("中文 (zh)").tag("zh")
                        Text("English (en)").tag("en")
                    }
                    Toggle("輸出時間戳", isOn: $vm.wantTimestamps)
                    Text("待實作：" + vm.pendingEngines.joined(separator: "、"))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(4)
            }

            HStack {
                Button(vm.isRunning ? "執行中…" : "開始轉錄") { vm.run() }
                    .disabled(vm.audioURL == nil || vm.isRunning)
                    .keyboardShortcut(.return)
                Button("匯出結果") { vm.export() }
                    .disabled(vm.result == nil || vm.isRunning)
            }

            if vm.isRunning {
                ProgressView(value: vm.progress)
            }
            Text(vm.statusMessage)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let dir = vm.exportDir {
                Button("在 Finder 顯示") { NSWorkspace.shared.activateFileViewerSelecting([dir]) }
                    .font(.caption)
            }

            Spacer()
        }
        .padding(16)
    }

    private var resultPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let r = vm.result {
                metricsBar(r)
                Divider()
                List(r.segments) { seg in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("[\(TimeFormat.hms(seg.start)) - \(TimeFormat.hms(seg.end))]")
                            .font(.caption.monospaced()).foregroundStyle(.secondary)
                        Text(seg.text)
                    }
                    .padding(.vertical, 2)
                }
            } else {
                ContentUnavailableView("尚無結果", systemImage: "waveform",
                                       description: Text("匯入音檔並按「開始轉錄」。"))
            }
        }
    }

    private func metricsBar(_ r: TranscriptionResult) -> some View {
        let m = r.metrics
        return Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
            GridRow {
                Text("Engine").foregroundStyle(.secondary); Text(r.engine)
                Text("時長").foregroundStyle(.secondary); Text(TimeFormat.hms(m.audioDurationSeconds))
            }
            GridRow {
                Text("轉錄耗時").foregroundStyle(.secondary); Text(String(format: "%.2fs", m.transcriptionTimeSeconds))
                Text("RTF").foregroundStyle(.secondary); Text(String(format: "%.3f", m.realTimeFactor))
            }
            GridRow {
                Text("Peak Mem").foregroundStyle(.secondary)
                Text(m.peakMemoryMB.map { String(format: "%.0f MB", $0) } ?? "n/a")
                Text("Thermal").foregroundStyle(.secondary); Text(m.thermalState ?? "n/a")
            }
        }
        .font(.caption)
        .padding(12)
    }
}

#Preview {
    ContentView()
}
