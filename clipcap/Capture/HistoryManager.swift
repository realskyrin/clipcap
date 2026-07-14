import AppKit

enum HistoryEntryKind {
    case image
    case color(hex: String)
    case text(String)
}

struct HistoryEntry {
    let fileURL: URL
    let createdAt: Date
    let kind: HistoryEntryKind
}

final class HistoryManager {
    static let shared = HistoryManager()

    private let queue = DispatchQueue(label: "clipcap.history", qos: .utility)
    private let directoryURL: URL

    private init() {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        directoryURL = base.appendingPathComponent("clipcap/History", isDirectory: true)
        try? fm.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(limitChanged),
            name: .historyCacheLimitDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(cacheEnabledChanged),
            name: .historyCacheEnabledDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clipboardTextCacheEnabledChanged),
            name: .clipboardTextCacheEnabledDidChange,
            object: nil
        )

        if !Defaults.historyCacheEnabled {
            removeStoredHistoryEntries(withExtensions: ["png", "gif", "color"])
        }
        if !Defaults.clipboardTextCacheEnabled {
            removeStoredHistoryEntries(withExtensions: ["txt"])
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func limitChanged() {
        queue.async { [weak self] in
            self?.pruneToLimit()
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .historyDidUpdate, object: nil)
            }
        }
    }

    @objc private func cacheEnabledChanged() {
        queue.async { [weak self] in
            guard let self else { return }
            if !Defaults.historyCacheEnabled {
                self.removeStoredHistoryEntries(withExtensions: ["png", "gif", "color"])
            }
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .historyDidUpdate, object: nil)
            }
        }
    }

    @objc private func clipboardTextCacheEnabledChanged() {
        queue.async { [weak self] in
            guard let self else { return }
            if !Defaults.clipboardTextCacheEnabled {
                self.removeStoredHistoryEntries(withExtensions: ["txt"])
            }
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .historyDidUpdate, object: nil)
            }
        }
    }

    func add(image: NSImage) {
        guard Defaults.historyCacheEnabled else { return }
        guard let data = image.pngDataPreservingBacking() else { return }
        queue.async { [weak self] in
            guard let self = self else { return }
            guard Defaults.historyCacheEnabled else { return }
            let name = Self.filenameFormatter.string(from: Date()) + ".png"
            let url = self.directoryURL.appendingPathComponent(name)
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                return
            }
            self.pruneToLimit()
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .historyDidUpdate, object: nil)
            }
        }
    }

    func addColor(hex: String) {
        guard Defaults.historyCacheEnabled else { return }
        let normalized = hex.uppercased()
        queue.async { [weak self] in
            guard let self = self else { return }
            guard Defaults.historyCacheEnabled else { return }
            let name = Self.filenameFormatter.string(from: Date()) + ".color"
            let url = self.directoryURL.appendingPathComponent(name)
            do {
                try normalized.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                return
            }
            self.pruneToLimit()
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .historyDidUpdate, object: nil)
            }
        }
    }

    func addText(_ text: String) {
        guard Defaults.clipboardTextCacheEnabled, !text.isEmpty else { return }
        queue.async { [weak self] in
            guard let self else { return }
            guard Defaults.clipboardTextCacheEnabled else { return }
            let name = Self.filenameFormatter.string(from: Date()) + ".txt"
            let url = self.directoryURL.appendingPathComponent(name)
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                return
            }
            self.pruneToLimit()
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .historyDidUpdate, object: nil)
            }
        }
    }

    func addFile(_ sourceURL: URL) {
        guard Defaults.historyCacheEnabled else { return }
        let ext = sourceURL.pathExtension.lowercased()
        guard ext == "gif" else { return }
        queue.async { [weak self] in
            guard let self else { return }
            guard Defaults.historyCacheEnabled else { return }
            let name = Self.filenameFormatter.string(from: Date()) + "." + ext
            let url = self.directoryURL.appendingPathComponent(name)
            let fm = FileManager.default
            do {
                try? fm.removeItem(at: url)
                do {
                    try fm.linkItem(at: sourceURL, to: url)
                } catch {
                    try fm.copyItem(at: sourceURL, to: url)
                }
            } catch {
                return
            }
            self.pruneToLimit()
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .historyDidUpdate, object: nil)
            }
        }
    }

    func entries() -> [HistoryEntry] {
        guard Defaults.isHistoryCacheAvailable else { return [] }
        return loadEntries()
    }

    func imageEntries() -> [HistoryEntry] {
        entries().filter {
            guard case .image = $0.kind else {
                return false
            }
            return true
        }
    }

    func cacheDirectoryURL() -> URL {
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }

    private func loadEntries() -> [HistoryEntry] {
        let cachedEntries = loadCachedEntries()
        let items = deduplicatedEntries(cachedEntries)
        return items.sorted { $0.createdAt > $1.createdAt }
    }

    private func loadCachedEntries() -> [HistoryEntry] {
        var allowedExtensions = Set<String>()
        if Defaults.historyCacheEnabled {
            allowedExtensions.formUnion(["png", "gif", "color"])
        }
        if Defaults.clipboardTextCacheEnabled {
            allowedExtensions.insert("txt")
        }
        return entries(in: directoryURL, allowedExtensions: allowedExtensions)
    }

    private func entries(in directory: URL, allowedExtensions: Set<String>) -> [HistoryEntry] {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return urls.compactMap { url in
            let ext = url.pathExtension.lowercased()
            guard allowedExtensions.contains(ext) else { return nil }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values?.isRegularFile != false else { return nil }
            let date = values?.contentModificationDate ?? .distantPast
            switch ext {
            case "png", "gif":
                return HistoryEntry(fileURL: url, createdAt: date, kind: .image)
            case "color":
                guard let hex = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                return HistoryEntry(fileURL: url, createdAt: date, kind: .color(hex: trimmed))
            case "txt":
                guard let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty else { return nil }
                return HistoryEntry(fileURL: url, createdAt: date, kind: .text(text))
            default:
                return nil
            }
        }
    }

    private func deduplicatedEntries(_ entries: [HistoryEntry]) -> [HistoryEntry] {
        var seen = Set<String>()
        return entries.compactMap { entry in
            let identity = Self.fileIdentity(for: entry.fileURL)
            guard seen.insert(identity).inserted else { return nil }
            return entry
        }
    }

    func image(for entry: HistoryEntry) -> NSImage? {
        guard Defaults.historyCacheEnabled else { return nil }
        guard case .image = entry.kind else { return nil }
        return NSImage(contentsOf: entry.fileURL)
    }

    func clearAll(completion: (() -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.removeAllEntries()
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .historyDidUpdate, object: nil)
                completion?()
            }
        }
    }

    func remove(_ entries: [HistoryEntry], completion: ((Int) -> Void)? = nil) {
        var seen = Set<String>()
        let urls = entries.compactMap { entry -> URL? in
            let url = entry.fileURL.standardizedFileURL
            guard seen.insert(url.path).inserted else { return nil }
            return url
        }

        queue.async {
            let fm = FileManager.default
            var removedCount = 0
            for url in urls {
                do {
                    try fm.removeItem(at: url)
                    removedCount += 1
                } catch {
                    continue
                }
            }
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .historyDidUpdate, object: nil)
                completion?(removedCount)
            }
        }
    }

    private func pruneToLimit() {
        guard Defaults.isHistoryCacheAvailable else {
            removeAllEntries()
            return
        }
        let limit = Defaults.historyCacheLimit
        let all = loadCachedEntries().sorted { $0.createdAt > $1.createdAt }
        guard all.count > limit else { return }
        let fm = FileManager.default
        for extra in all.dropFirst(limit) {
            try? fm.removeItem(at: extra.fileURL)
        }
    }

    private func removeAllEntries() {
        let fm = FileManager.default
        for url in storedHistoryFileURLs() {
            try? fm.removeItem(at: url)
        }
    }

    private func removeStoredHistoryEntries(withExtensions extensions: Set<String>) {
        let fm = FileManager.default
        for url in storedHistoryFileURLs() where extensions.contains(url.pathExtension.lowercased()) {
            try? fm.removeItem(at: url)
        }
    }

    private func storedHistoryFileURLs() -> [URL] {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return urls.filter { url in
            switch url.pathExtension.lowercased() {
            case "png", "gif", "color", "txt":
                return true
            default:
                return false
            }
        }
    }

    private static func fileIdentity(for url: URL) -> String {
        let normalized = url.standardizedFileURL
        if let values = try? normalized.resourceValues(forKeys: [.fileResourceIdentifierKey, .volumeIdentifierKey]),
           let fileIdentifier = values.fileResourceIdentifier {
            let volumeIdentifier = values.volumeIdentifier.map { String(describing: $0) } ?? ""
            return "file:\(volumeIdentifier):\(String(describing: fileIdentifier))"
        }
        return "path:\(normalized.path)"
    }

    private static let filenameFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss-SSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}
