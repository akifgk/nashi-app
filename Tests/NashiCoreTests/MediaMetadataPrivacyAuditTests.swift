import XCTest
import CoreGraphics
@testable import NashiCore

final class MediaMetadataPrivacyAuditTests: XCTestCase {
    private func runFFmpeg(_ arguments: [String]) throws {
        try ProcessRunner.run(Dependencies.executable("ffmpeg"),
                              ["-hide_banner", "-nostdin", "-v", "error", "-n"] + arguments)
    }

    private func artwork(_ directory: URL) throws -> URL {
        let context = try XCTUnwrap(CGContext(data: nil, width: 32, height: 32,
                                            bitsPerComponent: 8, bytesPerRow: 32 * 4,
                                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        let output = directory.appendingPathComponent("Private artwork.jpg")
        try ImageEngine.write(XCTUnwrap(context.makeImage()), to: output)
        return output
    }

    /// Hash demuxed encoded packets, so a copied codec payload is compared
    /// independently of tags, stream ordering and container timestamps.
    private func payloadHash(_ input: URL, stream: String) throws -> String {
        try ProcessRunner.run(Dependencies.executable("ffmpeg"), [
            "-hide_banner", "-nostdin", "-v", "error", "-i", input.path,
            "-map", "0:\(stream)", "-c", "copy", "-f", "hash", "-hash", "sha256", "-"
        ]).text
    }

    private func mp3WithArtwork(_ directory: URL) throws -> URL {
        let cover = try artwork(directory), output = directory.appendingPathComponent("Private album.mp3")
        try runFFmpeg(["-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000:duration=1",
                       "-i", cover.path, "-map", "0:a:0", "-map", "1:v:0", "-c:a", "libmp3lame",
                       "-b:a", "192k", "-c:v", "copy", "-id3v2_version", "3", "-metadata",
                       "title=Private title", "-metadata:s:v", "title=Private artwork", output.path])
        return output
    }

    func testRemoveAllDropsMP3ArtworkAndPreservesEncodedAudio() throws {
        let directory = try OutputFiles.temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let source = try mp3WithArtwork(directory), original = try Data(contentsOf: source)
        XCTAssertEqual(try MediaEngine.inspect(source).streams.filter(\.isAttachedPicture).count, 1)
        var options = OperationOptions(); options.metadataRemoveAll = true
        let output = try XCTUnwrap(ConversionEngine.run(.init(inputs: [source], operation: .tool(.removeMetadata), options: options)).first)
        let after = try MediaEngine.inspect(output)
        XCTAssertTrue(after.streams.filter(\.isAttachedPicture).isEmpty)
        XCTAssertTrue(after.streams.allSatisfy { $0.kind == "audio" })
        XCTAssertEqual(try payloadHash(source, stream: "a:0"), try payloadHash(output, stream: "a:0"))
        XCTAssertFalse(try MediaEngine.readMetadata(output).values.contains { $0.contains("Private") })
        XCTAssertEqual(try Data(contentsOf: source), original)
    }

    func testEditingOneTagRetainsArtworkWhenRemoveAllWasNotRequested() throws {
        let directory = try OutputFiles.temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let source = try mp3WithArtwork(directory), original = try Data(contentsOf: source)
        let output = try XCTUnwrap(MediaEngine.editMetadata(source, metadata: ["file:title": "New title"]).first)
        XCTAssertEqual(try MediaEngine.inspect(output).streams.filter(\.isAttachedPicture).count, 1)
        XCTAssertEqual(try payloadHash(source, stream: "a:0"), try payloadHash(output, stream: "a:0"))
        XCTAssertEqual(try payloadHash(source, stream: "v:0"), try payloadHash(output, stream: "v:0"))
        XCTAssertEqual(try MediaEngine.readMetadata(output)["file:title"], "New title")
        XCTAssertEqual(try Data(contentsOf: source), original)
    }

    func testRemoveAllRetainsRealVideoEncodedPayloadAndDisplayOrientation() throws {
        let directory = try OutputFiles.temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let base = directory.appendingPathComponent("Base.mp4"), source = directory.appendingPathComponent("Rotated video.mp4")
        try runFFmpeg(["-f", "lavfi", "-i", "testsrc2=size=80x48:rate=8:duration=1", "-f", "lavfi", "-i",
                       "sine=frequency=440:sample_rate=48000:duration=1", "-map", "0:v:0", "-map", "1:a:0",
                       "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", "-metadata", "title=Private title", base.path])
        try runFFmpeg(["-display_rotation", "90", "-i", base.path, "-map", "0", "-c", "copy", source.path])
        let original = try Data(contentsOf: source), before = try MediaEngine.inspect(source)
        XCTAssertTrue(before.hasVideo); XCTAssertTrue(before.hasAudio)
        XCTAssertFalse(before.streams.contains { $0.isAttachedPicture })
        let output = try XCTUnwrap(MediaEngine.editMetadata(source, metadata: [:], removeAll: true).first)
        let after = try MediaEngine.inspect(output)
        XCTAssertTrue(after.hasVideo); XCTAssertTrue(after.hasAudio)
        XCTAssertEqual(after.video?.rotation, before.video?.rotation)
        XCTAssertEqual(after.video?.width, before.video?.width); XCTAssertEqual(after.video?.height, before.video?.height)
        XCTAssertEqual(try payloadHash(source, stream: "v:0"), try payloadHash(output, stream: "v:0"))
        XCTAssertEqual(try payloadHash(source, stream: "a:0"), try payloadHash(output, stream: "a:0"))
        XCTAssertFalse(try MediaEngine.readMetadata(output).values.contains { $0.contains("Private") })
        XCTAssertEqual(try Data(contentsOf: source), original)
    }
}
