import SwiftUI

struct LocalMeetingTranscriberApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 900, height: 640)
    }
}

/// 進入點：有 `--transcribe <path>` 旗標時走 headless CLI（測試自動化用），
/// 否則啟動 SwiftUI GUI。
@main
struct EntryPoint {
    static func main() async {
        let args = CommandLine.arguments
        if let idx = args.firstIndex(of: "--transcribe"), idx + 1 < args.count {
            setbuf(stdout, nil)   // CLI 模式關閉行緩衝，即時輸出
            let path = args[idx + 1]
            await CLIRunner.run(path: path,
                                engineName: flag("--engine", in: args),
                                lang: flag("--lang", in: args))
            exit(0)
        }
        LocalMeetingTranscriberApp.main()
    }

    private static func flag(_ name: String, in args: [String]) -> String? {
        guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
}
