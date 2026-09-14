import Foundation

do {
    try await Command(arguments: Array(CommandLine.arguments.dropFirst())).run()
} catch let error as CLIError {
    stderr("hearsay: \(error.message)")
    exit(error.exitCode)
} catch {
    stderr("hearsay: \(error.localizedDescription)")
    exit(1)
}

private struct Command {
    var arguments: [String]

    func run() async throws {
        guard let name = arguments.first else {
            printHelp()
            return
        }

        let rest = Array(arguments.dropFirst())
        switch name {
        case "api":
            try printAPIInfo()
        case "health":
            try await health()
        case "open":
            try runProcess("/usr/bin/open", ["-a", "Hearsay"])
        case "quit", "close":
            _ = try? runProcess("/usr/bin/osascript", ["-e", "tell application id \"com.andrewsharp.hearsay\" to quit"])
            _ = try? runProcess("/usr/bin/osascript", ["-e", "tell application id \"com.swair.hearsay\" to quit"])
        case "dictate":
            try await dictate(rest)
        case "stop":
            try await control(rest, action: "stop")
        case "cancel":
            try await control(rest, action: "cancel")
        case "history":
            try history(rest)
        case "logs":
            try logs(rest)
        case "mic", "microphone":
            try await mic(rest)
        case "hotkey", "hotkeys", "shortcut", "shortcuts":
            try await hotkey(rest)
        case "help", "--help", "-h":
            printHelp()
        default:
            throw CLIError("unknown command '\(name)'", exitCode: 64)
        }
    }

    private func logs(_ args: [String]) throws {
        var parser = ArgumentParser(args)
        let printPath = parser.flag("--path")
        let openLog = parser.flag("--open")
        let copyLog = parser.flag("--copy")
        let clearLog = parser.flag("--clear")
        try parser.rejectUnused()

        let reader = DiagnosticLogReader()

        if clearLog {
            try reader.clear()
            print("Diagnostic log cleared")
            return
        }

        if printPath {
            print(reader.logURL.path)
            return
        }

        let snapshot = try reader.snapshotText()

        if copyLog {
            try runProcess("/usr/bin/pbcopy", [], standardInput: Data(snapshot.utf8))
            stderr("Copied metadata-only diagnostic logs to clipboard")
        }

        if openLog {
            let snapshotURL = try reader.writeSnapshotFile(text: snapshot)
            try runProcess("/usr/bin/open", [snapshotURL.path])
        }

        if !copyLog && !openLog {
            print(snapshot, terminator: snapshot.hasSuffix("\n") ? "" : "\n")
        }
    }

    private func printAPIInfo() throws {
        let info = try LocalAPIInfo.load()
        print("http://\(info.host):\(info.port)")
    }

    private func health() async throws {
        let data = try await APIClient().request(method: "GET", path: "/v1/health")
        printPrettyJSON(data)
    }

    private func dictate(_ args: [String]) async throws {
        var parser = ArgumentParser(args)
        let caller = try parser.stringValue(after: "--caller") ?? "hearsay-cli"
        let requestId = try parser.stringValue(after: "--request-id") ?? UUID().uuidString
        let jsonOutput = parser.flag("--json")
        let stopOnEnter = parser.flag("--stop-on-enter")
        try parser.rejectUnused()

        guard UUID(uuidString: requestId) != nil else {
            throw CLIError("--request-id must be a UUID", exitCode: 64)
        }

        let body = StartDictationRequest(
            caller: caller,
            mode: "returnToCaller",
            requestId: requestId,
            metadata: ["source": "hearsay-cli"]
        )

        stderr("requestId: \(requestId)")

        let client = APIClient(timeout: 60 * 60)
        let resultTask = Task {
            try await client.request(
                method: "POST",
                path: "/v1/dictations",
                body: try JSONEncoder().encode(body)
            )
        }

        if stopOnEnter {
            stderr("Recording. Press Enter to stop.")
            _ = readLine()
            do {
                _ = try await client.request(method: "POST", path: "/v1/dictations/\(requestId)/stop")
            } catch let error as CLIError {
                stderr("stop request did not change state: \(error.message)")
            }
        }

        let resultData = try await resultTask.value
        if jsonOutput {
            printPrettyJSON(resultData)
            return
        }

        let result = try JSONDecoder().decode(DictationResult.self, from: resultData)
        switch result.status {
        case "completed":
            print(result.text ?? "")
        case "cancelled":
            throw CLIError("dictation cancelled", exitCode: 130)
        default:
            throw CLIError(result.error ?? "dictation failed", exitCode: 1)
        }
    }

    private func control(_ args: [String], action: String) async throws {
        guard args.count == 1, let requestId = args.first else {
            throw CLIError("usage: hearsay \(action) REQUEST_ID", exitCode: 64)
        }
        guard UUID(uuidString: requestId) != nil else {
            throw CLIError("REQUEST_ID must be a UUID", exitCode: 64)
        }

        let data = try await APIClient().request(method: "POST", path: "/v1/dictations/\(requestId)/\(action)")
        printPrettyJSON(data)
    }

    private func history(_ args: [String]) throws {
        var parser = ArgumentParser(args)
        let limit = try parser.intValue(after: "--limit") ?? 10
        let jsonOutput = parser.flag("--json")
        try parser.rejectUnused()

        let items = try HistoryReader().recent(limit: limit)
        if jsonOutput {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            print(String(data: try encoder.encode(items), encoding: .utf8) ?? "[]")
            return
        }

        if items.isEmpty {
            print("No transcriptions yet")
            return
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        for item in items {
            let text = item.text.replacingOccurrences(of: "\n", with: " ")
            let preview = text.count > 90 ? String(text.prefix(87)) + "..." : text
            print("\(formatter.string(from: item.timestamp))  \(preview)")
        }
    }

    private func printHelp() {
        print("""
        Usage:
          hearsay open
          hearsay quit
          hearsay api
          hearsay health
          hearsay dictate [--caller NAME] [--request-id UUID] [--json] [--stop-on-enter]
          hearsay stop REQUEST_ID
          hearsay cancel REQUEST_ID
          hearsay history [--limit N] [--json]
          hearsay logs [--open] [--copy] [--path] [--clear]
          hearsay mic <list|get|set>
          hearsay hotkey <get|set|clear|reset>
        """)
    }

    private func mic(_ arguments: [String]) async throws {
        guard let action = arguments.first else {
            printMicHelp()
            return
        }

        let rest = Array(arguments.dropFirst())
        switch action {
        case "list", "ls":
            try await micList(rest)
        case "get", "current", "status":
            try await micGet(rest)
        case "set", "select":
            try await micSet(rest)
        case "help", "--help", "-h":
            printMicHelp()
        default:
            throw CLIError("unknown mic command '\(action)'\n\nRun 'hearsay mic help' for usage.", exitCode: 64)
        }
    }

    private func micList(_ arguments: [String]) async throws {
        var parser = ArgumentParser(arguments)
        let jsonOutput = parser.flag("--json")
        try parser.rejectUnused()

        let client = APIClient()
        let data = try await client.request(method: "GET", path: "/v1/microphones")

        if jsonOutput {
            printPrettyJSON(data)
            return
        }

        struct DeviceInfo: Decodable {
            let uid: String
            let name: String
            let isBuiltIn: Bool
            let isActive: Bool?
            let isSelected: Bool?
        }
        struct MicListResponse: Decodable {
            let devices: [DeviceInfo]
            let activeDevice: DeviceInfo?
            let selectedUID: String?
        }

        let resp = try JSONDecoder().decode(MicListResponse.self, from: data)
        guard !resp.devices.isEmpty else {
            print("No microphones found.")
            return
        }

        for dev in resp.devices {
            var badges: [String] = []
            if dev.isActive == true {
                badges.append("active")
            }
            if dev.isSelected == true {
                badges.append("selected")
            } else if dev.isActive == true && resp.selectedUID == nil {
                badges.append("system default")
            }
            if dev.isBuiltIn {
                badges.append("built-in")
            }
            let badgeStr = badges.isEmpty ? "" : " (\(badges.joined(separator: ", ")))"
            let prefix = (dev.isActive == true) ? "* " : "  "
            print("\(prefix)\(dev.name)\(badgeStr)")
            print("    UID: \(dev.uid)")
        }
    }

    private func micGet(_ arguments: [String]) async throws {
        var parser = ArgumentParser(arguments)
        let jsonOutput = parser.flag("--json")
        try parser.rejectUnused()

        let client = APIClient()
        let data = try await client.request(method: "GET", path: "/v1/microphones/current")

        if jsonOutput {
            printPrettyJSON(data)
            return
        }

        struct DeviceInfo: Decodable {
            let uid: String
            let name: String
            let isBuiltIn: Bool
        }
        struct MicCurrentResponse: Decodable {
            let activeDevice: DeviceInfo?
            let selectedUID: String?
        }

        let resp = try JSONDecoder().decode(MicCurrentResponse.self, from: data)
        if let active = resp.activeDevice {
            let builtInStr = active.isBuiltIn ? " (Built-in)" : ""
            print("Active: \(active.name)\(builtInStr)")
            print("UID: \(active.uid)")
            if let selectedUID = resp.selectedUID {
                print("Selection: Explicit (\(selectedUID))")
            } else {
                print("Selection: System Default (auto)")
            }
        } else {
            print("No active microphone.")
        }
    }

    private func micSet(_ arguments: [String]) async throws {
        var parser = ArgumentParser(arguments)
        let jsonOutput = parser.flag("--json")
        guard let target = parser.positionalArgument() else {
            throw CLIError("Usage: hearsay mic set <name-or-uid|default> [--json]", exitCode: 64)
        }
        try parser.rejectUnused()

        let client = APIClient()
        let payload = ["uid": target]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let data = try await client.request(method: "POST", path: "/v1/microphones/select", body: body)

        if jsonOutput {
            printPrettyJSON(data)
            return
        }

        struct DeviceInfo: Decodable {
            let uid: String
            let name: String
            let isBuiltIn: Bool
        }
        struct MicSetResponse: Decodable {
            let ok: Bool
            let activeDevice: DeviceInfo?
            let selectedUID: String?
        }

        let resp = try JSONDecoder().decode(MicSetResponse.self, from: data)
        if let active = resp.activeDevice {
            if resp.selectedUID == nil {
                print("Microphone set to System Default (auto).")
                print("Active: \(active.name) [\(active.uid)]")
            } else {
                print("Microphone selected: \(active.name)")
                print("UID: \(active.uid)")
            }
        } else {
            print("Microphone updated, but no active microphone detected.")
        }
    }

    private func printMicHelp() {
        print("""
        Usage:
          hearsay mic list [--json]
          hearsay mic get [--json]
          hearsay mic set <name-or-uid|default> [--json]

        Commands:
          list, ls          List available audio input devices
          get, current      Show active microphone details
          set, select       Select microphone by name/UID or reset with 'default'
        """)
    }

    private func hotkey(_ arguments: [String]) async throws {
        guard let action = arguments.first else {
            try await hotkeyGet([])
            return
        }

        let rest = Array(arguments.dropFirst())
        switch action {
        case "get", "status", "show":
            try await hotkeyGet(rest)
        case "set":
            try await hotkeySet(rest)
        case "clear":
            try await hotkeyClear(rest)
        case "reset":
            try await hotkeyReset(rest)
        case "help", "--help", "-h":
            printHotkeyHelp()
        default:
            throw CLIError("unknown hotkey command '\(action)'\n\nRun 'hearsay hotkey help' for usage.", exitCode: 64)
        }
    }

    private func hotkeyGet(_ arguments: [String]) async throws {
        var parser = ArgumentParser(arguments)
        let jsonOutput = parser.flag("--json")
        try parser.rejectUnused()

        let client = APIClient()
        let data = try await client.request(method: "GET", path: "/v1/hotkeys")

        if jsonOutput {
            printPrettyJSON(data)
            return
        }

        struct KeyInfo: Decodable {
            let keyCode: Int
            let name: String
        }
        struct ComboInfo: Decodable {
            let keyCode: Int
            let modifiers: Int
            let enabled: Bool
            let display: String
        }
        struct HotkeysResponse: Decodable {
            let activationMode: String
            let holdKey: KeyInfo
            let toggleCombo: ComboInfo
            let screenshotCombo: ComboInfo
            let fullScreenshotCombo: ComboInfo
        }

        let resp = try JSONDecoder().decode(HotkeysResponse.self, from: data)
        let modeDesc = resp.activationMode == "doubleTap" ? "Double-tap (tap twice to start, once to stop)" : "Hold (hold key while speaking)"
        print("Activation Mode: \(resp.activationMode) [\(modeDesc)]")
        print("Trigger Key:     \(resp.holdKey.name) (key code \(resp.holdKey.keyCode))")
        print("Toggle Combo:    \(resp.toggleCombo.display)")
        print("Screenshot:      \(resp.screenshotCombo.display)")
        print("Full Screenshot: \(resp.fullScreenshotCombo.display)")
    }

    private func hotkeySet(_ arguments: [String]) async throws {
        var parser = ArgumentParser(arguments)
        let jsonOutput = parser.flag("--json")
        guard let target = parser.positionalArgument() else {
            throw CLIError("Usage: hearsay hotkey set <mode|hold|toggle> <value> [--json]", exitCode: 64)
        }
        guard let value = parser.positionalArgument() else {
            throw CLIError("Usage: hearsay hotkey set \(target) <value> [--json]", exitCode: 64)
        }
        try parser.rejectUnused()

        var payload: [String: Any] = [:]
        switch target.lowercased() {
        case "mode":
            let lower = value.lowercased()
            if lower == "hold" || lower == "0" {
                payload["mode"] = "hold"
            } else if lower == "doubletap" || lower == "double-tap" || lower == "1" {
                payload["mode"] = "doubleTap"
            } else {
                throw CLIError("mode must be 'hold' or 'double-tap'", exitCode: 64)
            }
        case "hold", "trigger", "key":
            let keyCode = try parseKeyOrKeyCode(value)
            payload["holdKeyCode"] = keyCode
        case "toggle", "combo":
            let parsed = try parseShortcutCombo(value)
            payload["toggleKeyCode"] = parsed.keyCode
            payload["toggleModifiers"] = parsed.modifiers
        default:
            throw CLIError("Unknown target '\(target)'. Allowed: mode, hold, toggle", exitCode: 64)
        }

        let client = APIClient()
        let body = try JSONSerialization.data(withJSONObject: payload)
        let data = try await client.request(method: "POST", path: "/v1/hotkeys/update", body: body)

        if jsonOutput {
            printPrettyJSON(data)
            return
        }

        print("Hotkey settings updated successfully.")
        try await hotkeyGet([])
    }

    private func hotkeyClear(_ arguments: [String]) async throws {
        var parser = ArgumentParser(arguments)
        let jsonOutput = parser.flag("--json")
        guard let target = parser.positionalArgument() else {
            throw CLIError("Usage: hearsay hotkey clear toggle [--json]", exitCode: 64)
        }
        try parser.rejectUnused()

        guard target.lowercased() == "toggle" || target.lowercased() == "combo" else {
            throw CLIError("Only 'toggle' combo can be cleared.", exitCode: 64)
        }

        let payload: [String: Any] = [
            "toggleKeyCode": 0,
            "toggleModifiers": 0
        ]

        let client = APIClient()
        let body = try JSONSerialization.data(withJSONObject: payload)
        let data = try await client.request(method: "POST", path: "/v1/hotkeys/update", body: body)

        if jsonOutput {
            printPrettyJSON(data)
            return
        }

        print("Toggle combination disabled.")
        try await hotkeyGet([])
    }

    private func hotkeyReset(_ arguments: [String]) async throws {
        var parser = ArgumentParser(arguments)
        let jsonOutput = parser.flag("--json")
        try parser.rejectUnused()

        let payload: [String: Any] = ["reset": true]
        let client = APIClient()
        let body = try JSONSerialization.data(withJSONObject: payload)
        let data = try await client.request(method: "POST", path: "/v1/hotkeys/update", body: body)

        if jsonOutput {
            printPrettyJSON(data)
            return
        }

        print("Restored default hotkey settings.")
        try await hotkeyGet([])
    }

    private func printHotkeyHelp() {
        print("""
        Usage:
          hearsay hotkey [get] [--json]
          hearsay hotkey set mode <hold|double-tap>
          hearsay hotkey set hold <key>
          hearsay hotkey set toggle <combo|none>
          hearsay hotkey clear toggle
          hearsay hotkey reset

        Commands:
          get               Show current hotkeys and activation mode
          set mode          Set activation style: 'hold' or 'double-tap'
          set hold          Set trigger key (e.g. RightOption, LeftOption, Fn, F5)
          set toggle        Set toggle combo (e.g. Option+Space, Cmd+Shift+D)
          clear toggle      Disable the toggle combination
          reset             Restore default settings (Hold RightOption, Option+Space)
        """)
    }
}

private struct APIClient {
    var timeout: TimeInterval = 30

    func request(method: String, path: String, body: Data? = nil) async throws -> Data {
        let info = try LocalAPIInfo.load()
        guard let url = URL(string: "http://\(info.host):\(info.port)\(path)") else {
            throw CLIError("invalid local API URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.httpBody = body
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: configuration)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cannotConnectToHost || error.code == .notConnectedToInternet || error.code == .networkConnectionLost {
            throw CLIError("Hearsay local API is not reachable. Run 'hearsay open' and try again.")
        }

        guard let http = response as? HTTPURLResponse else {
            throw CLIError("local API did not return an HTTP response")
        }

        guard (200..<300).contains(http.statusCode) else {
            if let apiError = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
                throw CLIError(apiError.message, exitCode: http.statusCode == 409 ? 75 : 1)
            }
            throw CLIError("local API returned HTTP \(http.statusCode)")
        }

        return data
    }
}

private struct LocalAPIInfo: Decodable {
    let host: String
    let port: Int
    let version: Int

    static func load() throws -> LocalAPIInfo {
        let url = appSupportDirectory().appendingPathComponent("local-api.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CLIError("Hearsay is not running. Run 'hearsay open' first.")
        }
        return try JSONDecoder().decode(LocalAPIInfo.self, from: Data(contentsOf: url))
    }
}

private struct StartDictationRequest: Encodable {
    let caller: String
    let mode: String
    let requestId: String
    let metadata: [String: String]
}

private struct DictationResult: Decodable {
    let requestId: String
    let status: String
    let text: String?
    let error: String?
    let durationSeconds: Double?
}

private struct APIErrorResponse: Decodable {
    let error: String
    let message: String
}

private struct HistoryReader {
    func recent(limit: Int) throws -> [HistoryItem] {
        guard limit > 0 else { return [] }
        let indexURL = historyDirectory().appendingPathComponent("index.json")
        guard FileManager.default.fileExists(atPath: indexURL.path) else {
            return []
        }

        let index = try JSONDecoder().decode(HistoryIndex.self, from: Data(contentsOf: indexURL))
        var items: [HistoryItem] = []
        for chunk in index.chunks {
            let chunkURL = historyDirectory().appendingPathComponent(String(format: "chunk_%04d.json", chunk.id))
            guard FileManager.default.fileExists(atPath: chunkURL.path) else {
                continue
            }
            let chunkItems = try JSONDecoder().decode([HistoryItem].self, from: Data(contentsOf: chunkURL))
            items.append(contentsOf: chunkItems.prefix(max(0, limit - items.count)))
            if items.count >= limit {
                break
            }
        }
        return items
    }
}

private struct HistoryIndex: Decodable {
    struct Chunk: Decodable {
        let id: Int
        let count: Int
    }

    let nextChunkId: Int
    let chunks: [Chunk]
}

private struct HistoryItem: Codable {
    let id: UUID
    let text: String
    let timestamp: Date
    let durationSeconds: Double
    let audioFilePath: String?
}

private struct DiagnosticLogReader {
    let logURL = appSupportDirectory().appendingPathComponent("debug.log")

    private let maxAge: TimeInterval = 24 * 60 * 60
    private let maxBytes = 1_000_000

    func snapshotText() throws -> String {
        let body = try prunedBody()
        let generatedAt = Self.isoFormatter().string(from: Date())
        return """
        # Hearsay diagnostic log
        # Generated: \(generatedAt)
        # Retention: last 24 hours, capped at 1000000 bytes
        # Privacy: metadata only; raw transcripts, audio, clipboard text, screenshots, and prompts are not recorded

        \(body)
        """
    }

    func writeSnapshotFile(text: String) throws -> URL {
        let timestamp = Self.isoFormatter()
            .string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Hearsay-Diagnostics-\(timestamp).log")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func clear() throws {
        if FileManager.default.fileExists(atPath: logURL.path) {
            try FileManager.default.removeItem(at: logURL)
        }
    }

    private func prunedBody() throws -> String {
        guard FileManager.default.fileExists(atPath: logURL.path) else {
            return ""
        }

        let raw = try String(contentsOf: logURL, encoding: .utf8)
        let cutoff = Date().addingTimeInterval(-maxAge)
        let formatter = Self.isoFormatter()

        var lines: [String] = []
        for line in raw.split(separator: "\n", omittingEmptySubsequences: true).map(String.init) {
            guard
                let data = line.data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let timestamp = object["timestamp"] as? String,
                let date = formatter.date(from: timestamp),
                date >= cutoff
            else {
                continue
            }
            lines.append(line)
        }

        while byteCount(for: lines) > maxBytes, !lines.isEmpty {
            lines.removeFirst()
        }

        return lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
    }

    private func byteCount(for lines: [String]) -> Int {
        lines.reduce(0) { $0 + $1.utf8.count + 1 }
    }

    private static func isoFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}

private struct ArgumentParser {
    private var args: [String]
    private var used: Set<Int> = []

    init(_ args: [String]) {
        self.args = args
    }

    mutating func flag(_ name: String) -> Bool {
        guard let index = args.firstIndex(of: name) else {
            return false
        }
        used.insert(index)
        return true
    }

    mutating func stringValue(after name: String) throws -> String? {
        guard let index = args.firstIndex(of: name) else {
            return nil
        }
        used.insert(index)
        let valueIndex = index + 1
        guard valueIndex < args.count else {
            throw CLIError("\(name) requires a value", exitCode: 64)
        }
        used.insert(valueIndex)
        return args[valueIndex]
    }

    mutating func intValue(after name: String) throws -> Int? {
        guard let raw = try stringValue(after: name) else {
            return nil
        }
        guard let value = Int(raw) else {
            throw CLIError("\(name) requires an integer", exitCode: 64)
        }
        return value
    }

    mutating func positionalArgument() -> String? {
        for (index, arg) in args.enumerated() where !used.contains(index) && !arg.hasPrefix("-") {
            used.insert(index)
            return arg
        }
        return nil
    }

    func rejectUnused() throws {
        for (index, arg) in args.enumerated() where !used.contains(index) {
            throw CLIError("unexpected argument '\(arg)'", exitCode: 64)
        }
    }
}

private struct CLIError: Error {
    let message: String
    let exitCode: Int32

    init(_ message: String, exitCode: Int32 = 1) {
        self.message = message
        self.exitCode = exitCode
    }
}

private func parseKeyOrKeyCode(_ input: String) throws -> Int {
    let lower = input.lowercased()
        .replacingOccurrences(of: "-", with: "")
        .replacingOccurrences(of: "_", with: "")
        .replacingOccurrences(of: " ", with: "")
    if let intVal = Int(input) {
        return intVal
    }
    let map: [String: Int] = [
        "rightoption": 61, "roption": 61, "rightalt": 61, "ralt": 61,
        "leftoption": 58, "loption": 58, "leftalt": 58, "lalt": 58,
        "option": 58, "alt": 58,
        "rightcommand": 54, "rcommand": 54, "rcmd": 54, "rightcmd": 54,
        "leftcommand": 55, "lcommand": 55, "lcmd": 55, "leftcmd": 55,
        "command": 55, "cmd": 55,
        "rightshift": 60, "rshift": 60,
        "leftshift": 56, "lshift": 56,
        "shift": 56,
        "rightcontrol": 62, "rcontrol": 62, "rctrl": 62, "rightctrl": 62,
        "leftcontrol": 59, "lcontrol": 59, "lctrl": 59, "leftctrl": 59,
        "control": 59, "ctrl": 59,
        "capslock": 57, "caps": 57,
        "fn": 63, "function": 63,
        "space": 49, "spacebar": 49,
        "return": 36, "enter": 36,
        "tab": 48,
        "delete": 51, "backspace": 51,
        "escape": 53, "esc": 53,
        "up": 126, "down": 125, "left": 123, "right": 124,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
        "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
        "a": 0, "b": 11, "c": 8, "d": 2, "e": 14, "f": 3, "g": 5, "h": 4,
        "i": 34, "j": 38, "k": 40, "l": 37, "m": 46, "n": 45, "o": 31,
        "p": 35, "q": 12, "r": 15, "s": 1, "t": 17, "u": 32, "v": 9,
        "w": 13, "x": 7, "y": 16, "z": 6,
        "0": 29, "1": 18, "2": 19, "3": 20, "4": 21, "5": 23,
        "6": 22, "7": 26, "8": 28, "9": 25,
        "=": 24, "-": 27, "]": 30, "[": 33, "'": 39, ";": 41,
        "\\": 42, ",": 43, "/": 44, ".": 47, "`": 50
    ]
    guard let code = map[lower] else {
        throw CLIError("Unknown key '\(input)'. Run 'hearsay hotkey help' for examples.", exitCode: 64)
    }
    return code
}

private func parseShortcutCombo(_ input: String) throws -> (keyCode: Int, modifiers: Int) {
    let lower = input.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    if lower == "none" || lower == "clear" || lower == "disabled" || lower == "off" {
        return (0, 0)
    }

    let parts = input.components(separatedBy: CharacterSet(charactersIn: "+- ")).filter { !$0.isEmpty }
    guard !parts.isEmpty else {
        throw CLIError("Invalid key combo '\(input)'.", exitCode: 64)
    }

    var modifiers: UInt = 0
    var baseKey: String? = nil

    for part in parts {
        let p = part.lowercased()
        switch p {
        case "cmd", "command", "⌘":
            modifiers |= 1048576 // NSEvent.ModifierFlags.command
        case "alt", "option", "opt", "⌥":
            modifiers |= 524288 // NSEvent.ModifierFlags.option
        case "ctrl", "control", "⌃":
            modifiers |= 262144 // NSEvent.ModifierFlags.control
        case "shift", "⇧":
            modifiers |= 131072 // NSEvent.ModifierFlags.shift
        default:
            if baseKey != nil {
                throw CLIError("Key combo can only have one non-modifier key (found '\(baseKey!)' and '\(part)')", exitCode: 64)
            }
            baseKey = part
        }
    }

    guard let keyStr = baseKey else {
        throw CLIError("Key combo requires a base key (e.g. Option+Space, Cmd+Shift+D)", exitCode: 64)
    }
    let keyCode = try parseKeyOrKeyCode(keyStr)
    return (keyCode, Int(modifiers))
}

private func appSupportDirectory() -> URL {
    FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Hearsay", isDirectory: true)
}

private func historyDirectory() -> URL {
    appSupportDirectory().appendingPathComponent("History", isDirectory: true)
}

private func printPrettyJSON(_ data: Data) {
    guard
        let object = try? JSONSerialization.jsonObject(with: data),
        let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
        let string = String(data: pretty, encoding: .utf8)
    else {
        print(String(data: data, encoding: .utf8) ?? "")
        return
    }
    print(string)
}

private func stderr(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

private func runProcess(_ executable: String, _ arguments: [String]) throws {
    try runProcess(executable, arguments, standardInput: nil)
}

private func runProcess(_ executable: String, _ arguments: [String], standardInput: Data?) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let inputPipe: Pipe?
    if standardInput != nil {
        inputPipe = Pipe()
        process.standardInput = inputPipe
    } else {
        inputPipe = nil
    }
    try process.run()
    if let standardInput, let inputPipe {
        inputPipe.fileHandleForWriting.write(standardInput)
        try? inputPipe.fileHandleForWriting.close()
    }
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw CLIError("\(URL(fileURLWithPath: executable).lastPathComponent) exited with \(process.terminationStatus)")
    }
}
