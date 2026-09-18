import XCTest
import AVFoundation
import ImageIO
@testable import clipcap

final class RecordingImportTests: XCTestCase {
    func testMP4AndGIFConversionPreservesSourceAndProducesPlayableMedia() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.mov")
        try await Self.makeVideo(source)
        let original = try Data(contentsOf: source)
        for compress in [false, true] {
            let result = try await RecordingImport.convert(source, format: "mp4", compress: compress, outputDirectory: root)
            let asset = AVURLAsset(url: result)
            let playable = try await asset.load(.isPlayable)
            let duration = try await asset.load(.duration)
            XCTAssertTrue(playable)
            XCTAssertGreaterThan(duration.seconds, 0.8)
            XCTAssertEqual(try Data(contentsOf: source), original)
            XCTAssertNotNil(HistoryImagePreview.load(url: result, pixelSize: 100).cgImage)
        }
        let gif = try await RecordingImport.convert(source, format: "gif", compress: false, outputDirectory: root)
        let imageSource = try XCTUnwrap(CGImageSourceCreateWithURL(gif as CFURL, nil))
        XCTAssertGreaterThan(CGImageSourceGetCount(imageSource), 1)
        XCTAssertEqual(CGImageSourceGetStatus(imageSource), .statusComplete)
        XCTAssertEqual(try Data(contentsOf: source), original)
    }

    func testInvalidVideoLeavesNoPartialOutputAndPreservesSource() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("invalid.mov")
        let contents = Data("incomplete recording".utf8)
        try contents.write(to: source)
        do {
            _ = try await RecordingImport.convert(source, format: "mp4", compress: true, outputDirectory: root)
            XCTFail("Invalid movie should not convert")
        } catch {}
        XCTAssertEqual(try Data(contentsOf: source), contents)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["invalid.mov"])
    }

    func testMonitorDeliversNewVideoOnceAndIgnoresInvalidMovie() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = root.appendingPathComponent("existing.mov")
        try await Self.makeVideo(fixture)
        let ready = expectation(description: "new movie imported")
        ready.assertForOverFulfill = true
        let monitor = SystemScreenshotDirectoryMonitor(directoryURL: root, reconciliationInterval: 0.1) { url in
            XCTAssertEqual(url.lastPathComponent, "new.mov")
            ready.fulfill()
        }
        monitor.start()
        defer { monitor.stop() }
        try await Task.sleep(nanoseconds: 200_000_000)
        try FileManager.default.copyItem(at: fixture, to: root.appendingPathComponent("new.mov"))
        try Data("partial".utf8).write(to: root.appendingPathComponent("invalid.mov"))
        await fulfillment(of: [ready], timeout: 8)
        try await Task.sleep(nanoseconds: 2_500_000_000)
    }

    private static func makeVideo(_ url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 64, AVVideoHeightKey: 64
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 64
        ])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<24 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
            var buffer: CVPixelBuffer?
            XCTAssertEqual(CVPixelBufferPoolCreatePixelBuffer(nil, try XCTUnwrap(adaptor.pixelBufferPool), &buffer), kCVReturnSuccess)
            let pixels = try XCTUnwrap(buffer)
            CVPixelBufferLockBaseAddress(pixels, [])
            memset(CVPixelBufferGetBaseAddress(pixels), Int32(frame * 10), CVPixelBufferGetDataSize(pixels))
            CVPixelBufferUnlockBaseAddress(pixels, [])
            XCTAssertTrue(adaptor.append(pixels, withPresentationTime: CMTime(value: Int64(frame), timescale: 24)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)
    }
}
