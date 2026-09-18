import AppKit
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

/// Processes files produced by the system Screenshot app, never captures the screen.
final class RecordingImport {
    static let shared = RecordingImport()
    static func isVideo(_ url: URL) -> Bool { ["mov", "mp4", "m4v"].contains(url.pathExtension.lowercased()) }
    static var format: String {
        get {
            let value = UserDefaults.standard.string(forKey: "recordingFormat") ?? "manual"
            return ["manual", "mp4", "gif"].contains(value) ? value : "manual"
        }
        set { UserDefaults.standard.set(newValue, forKey: "recordingFormat") }
    }
    static var compress: Bool {
        get { UserDefaults.standard.bool(forKey: "recordingCompression") }
        set { UserDefaults.standard.set(newValue, forKey: "recordingCompression") }
    }
    private var pending: [URL] = []
    private var busy = false
    func enqueue(_ url: URL) {
        if !pending.contains(url) { pending.append(url) }
        processNext()
    }
    private func processNext() {
        guard !busy, !pending.isEmpty else { return }
        busy = true
        let source = pending.removeFirst()
        var format = Self.format
        if format == "manual" {
            let alert = NSAlert()
            alert.messageText = Localizer.string("recordingFormatTitle")
            alert.informativeText = source.lastPathComponent
            alert.addButton(withTitle: "MP4")
            alert.addButton(withTitle: "GIF")
            alert.addButton(withTitle: Localizer.string("recordingKeepOriginal"))
            NSApp.activate(ignoringOtherApps: true)
            let response = alert.runModal()
            if response == .alertFirstButtonReturn { format = "mp4" }
            else if response == .alertSecondButtonReturn { format = "gif" }
            else {
                HistoryManager.shared.addFile(source)
                busy = false
                processNext()
                return
            }
        }
        ToastWindow.show(message: Localizer.string("recordingProcessing"))
        let compression = Self.compress
        Task { @MainActor in
            defer { busy = false; processNext() }
            do {
                let result = try await Self.convert(source, format: format, compress: compression)
                HistoryManager.shared.addFile(result)
                ToastWindow.show(message: Localizer.string("recordingSaved"))
            } catch {
                HistoryManager.shared.addFile(source)
                let alert = NSAlert()
                alert.messageText = Localizer.string("recordingConversionFailed")
                alert.informativeText = error.localizedDescription.trimmingCharacters(in: .punctuationCharacters)
                alert.runModal()
            }
        }
    }

    static func convert(_ source: URL, format: String, compress: Bool, outputDirectory: URL? = nil) async throws -> URL {
        let directory = outputDirectory ?? Defaults.screenshotSaveDirectory.appendingPathComponent("Recordings", isDirectory: true)
        // Converted files must not feed back into the watched directory.
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let output = directory.appendingPathComponent(source.deletingPathExtension().lastPathComponent + "-" + UUID().uuidString.prefix(8) + "." + format)
        do {
            if format == "gif" {
                try await Task.detached(priority: .utility) { try makeGIF(source, output: output) }.value
            } else {
                let asset = AVURLAsset(url: source)
                // Remux without generation loss for Original; HEVC retains source resolution for compression.
                if compress {
                    do { try await export(asset, to: output, preset: AVAssetExportPresetHEVCHighestQuality) }
                    catch {
                        try? FileManager.default.removeItem(at: output)
                        try await export(asset, to: output, preset: AVAssetExportPresetHighestQuality)
                    }
                    let originalSize = (try source.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
                    let encodedSize = (try output.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
                    if encodedSize >= originalSize {
                        try FileManager.default.removeItem(at: output)
                        try await export(asset, to: output, preset: AVAssetExportPresetPassthrough)
                    }
                } else {
                    try await export(asset, to: output, preset: AVAssetExportPresetPassthrough)
                }
            }
            return output
        } catch {
            try? FileManager.default.removeItem(at: output)
            throw error
        }
    }
    private static func export(_ asset: AVAsset, to output: URL, preset: String) async throws {
        guard let session = AVAssetExportSession(asset: asset, presetName: preset), session.supportedFileTypes.contains(.mp4) else {
            throw NSError(domain: "RecordingImport", code: 1, userInfo: [NSLocalizedDescriptionKey: Localizer.string("recordingConversionFailed")])
        }
        session.outputURL = output
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        await session.export()
        guard session.status == .completed else { throw session.error ?? CocoaError(.fileWriteUnknown) }
    }
    private static func makeGIF(_ source: URL, output: URL) throws {
        let asset = AVURLAsset(url: source)
        let duration = asset.duration.seconds
        guard duration.isFinite, duration > 0 else { throw CocoaError(.fileReadCorruptFile) }
        let fps = 12.0
        let count = Int(ceil(duration * fps))
        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.gif.identifier as CFString, count, nil) else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1280, height: 1280)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(seconds: 1 / fps, preferredTimescale: 600)
        for index in 0..<count {
            try autoreleasepool {
                let image = try generator.copyCGImage(at: CMTime(seconds: Double(index) / fps, preferredTimescale: 600), actualTime: nil)
                let delay = min(1 / fps, duration - Double(index) / fps)
                CGImageDestinationAddImage(destination, image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary)
            }
        }
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }
}
