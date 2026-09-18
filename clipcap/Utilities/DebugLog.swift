import AppKit

/// Opt-in, bounded diagnostics. Never include search text or clipboard contents.
enum DebugLog {
    private static let lock = NSLock()
    private static let preferenceKey = "debugLogEnabled"
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/clipcap/debug.log")

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: preferenceKey) }
        set {
            if !newValue { record("logging.disabled") }
            UserDefaults.standard.set(newValue, forKey: preferenceKey)
            if newValue { sessionStarted() }
        }
    }

    static func sessionStarted() {
        record("logging.session", detail: "version=\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "unknown") system=\(DiagnosticLog.systemSnapshot())")
    }

    static func record(_ event: String, detail: @autoclosure () -> String = "",
                       file: StaticString = #fileID, line: UInt = #line) {
        guard isEnabled else { return }
        lock.lock()
        defer { lock.unlock() }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let fields = detail().replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\r", with: "\\r")
            let data = Data("\(ISO8601DateFormatter().string(from: Date())) uptime=\(ProcessInfo.processInfo.systemUptime) event=\(event) \(fields) source=\(file):\(line)\n".utf8)
            if !FileManager.default.fileExists(atPath: url.path) {
                try Data().write(to: url)
            }
            let size = (try url.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
            if size > 2_000_000 {
                let previous = try Data(contentsOf: url)
                let tail = previous.suffix(1_000_000)
                let boundary = tail.firstIndex(of: 10)
                let retained = boundary.map { Data(tail.suffix(from: tail.index(after: $0))) } ?? Data()
                try (Data("--- earlier debug lines truncated ---\n".utf8) + retained).write(to: url, options: .atomic)
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            NSLog("[clipcap] Debug log write failed: %@", error.localizedDescription)
        }
    }

    static func contents() throws -> String {
        lock.lock()
        defer { lock.unlock() }
        guard FileManager.default.fileExists(atPath: url.path) else { return "" }
        return try String(contentsOf: url, encoding: .utf8)
    }

    static func clear() throws {
        lock.lock()
        defer { lock.unlock() }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: url, options: .atomic)
    }

    static func focusState(_ window: NSWindow?) -> String {
        let responder = window?.firstResponder
        let editor = responder as? NSTextView
        return "active=\(NSApp.isActive) key=\(window?.isKeyWindow ?? false) visible=\(window?.isVisible ?? false) responder=\(responder.map { String(describing: type(of: $0)) } ?? "nil") fieldEditor=\(editor?.isFieldEditor ?? false) marked=\(editor?.hasMarkedText() ?? false)"
    }
}
