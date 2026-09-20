import Foundation

enum CodexConnectionState: String, Decodable {
    case notConfigured, waiting, connected, error

    var title: String {
        switch self {
        case .notConfigured: return "未连接"
        case .waiting: return "等待验证"
        case .connected: return "连接已验证"
        case .error: return "暂时无法确认连接"
        }
    }

    var guidance: String {
        switch self {
        case .notConfigured: return "连接后，Codex 任务回复结束时会在悬浮球旁提醒你。"
        case .waiting: return "在 ChatGPT 的 Codex 任务中发一条消息，等它回复结束。收到提醒后，这里会自动更新。"
        case .connected: return "最近一次回复通知已收到。无需操作，正常使用即可。"
        case .error: return "先点“重新检查”。不需要重新授权或安装。"
        }
    }

    var actionTitle: String? {
        switch self {
        case .notConfigured: return "开始连接"
        case .waiting: return "打开 ChatGPT"
        case .connected: return nil
        case .error: return "重新检查"
        }
    }
}

struct CodexConnectionInfo: Decodable {
    let status: CodexConnectionState
    let receivedAt: TimeInterval?
    let message: String?
}

/// Configuration changes happen only after explicit consent; never writes hook trust.
enum CodexHookInstaller {
    struct SetupError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    @MainActor static func run(install: Bool, completion: @escaping (Result<CodexConnectionInfo, Error>) -> Void) {
        guard let script = Bundle.main.url(forResource: "narc-codex-hook", withExtension: "py") else {
            completion(.failure(SetupError(message: "连接组件缺失，请重新安装 NARC 后重试。")))
            return
        }
        let candidates = ["/Library/Frameworks/Python.framework/Versions/3.11/bin/python3",
                          "/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"]
        guard let python = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            completion(.failure(SetupError(message: "缺少连接所需的 Python 3.11 或更新版本；原有功能不受影响。")))
            return
        }
        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: python)
            process.arguments = [script.path, install ? "--install-notify" : "--notify-status"]
            // Installer output contains no conversational data. Do not inherit stdin.
            process.standardInput = FileHandle.nullDevice
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            let done = DispatchSemaphore(value: 0)
            process.terminationHandler = { _ in done.signal() }
            let result: Result<CodexConnectionInfo, Error>
            do {
                try process.run()
                if done.wait(timeout: .now() + 10) == .timedOut {
                    process.terminate()
                    result = .failure(SetupError(message: "配置超时。请检查配置状态后重试；尚未确认连接。"))
                } else {
                    let data = output.fileHandleForReading.readDataToEndOfFile()
                    if data.count <= 4096, let info = try? JSONDecoder().decode(CodexConnectionInfo.self, from: data) {
                        result = .success(info)
                    } else {
                        result = .failure(SetupError(message: "连接工具未返回有效结果，尚未确认连接。请重新安装 NARC 后重试。"))
                    }
                }
            } catch { result = .failure(SetupError(message: "无法启动本地配置工具，请重新安装 NARC 后重试。")) }
            DispatchQueue.main.async { completion(result) }
        }
    }
}
