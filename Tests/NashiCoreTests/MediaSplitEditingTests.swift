import XCTest
@testable import NashiCore

final class MediaSplitEditingTests: XCTestCase {
    private struct Fixtures {
        let directory: URL
        let video: URL
        let silent: URL
        init() throws {
            directory = try OutputFiles.temporaryDirectory()
            video = directory.appendingPathComponent("Segments 'quoted' $dollar.mp4")
            silent = directory.appendingPathComponent("Silent.mov")
            let tone = "aevalsrc=exprs='0.2*sin(2*PI*if(lt(t,1),330,if(lt(t,2),660,990))*t)':s=48000:d=3"
            try ProcessRunner.run(Dependencies.executable("ffmpeg"), ["-v", "error", "-f", "lavfi", "-i", "color=c=red:size=96x64:rate=20:duration=1", "-f", "lavfi", "-i", "color=c=lime:size=96x64:rate=20:duration=1", "-f", "lavfi", "-i", "color=c=blue:size=96x64:rate=20:duration=1", "-f", "lavfi", "-i", tone, "-filter_complex", "[0:v][1:v][2:v]concat=n=3:v=1:a=0[v]", "-map", "[v]", "-map", "3:a", "-c:v", "libx264", "-preset", "ultrafast", "-crf", "12", "-c:a", "aac", video.path])
            try ProcessRunner.run(Dependencies.executable("ffmpeg"), ["-v", "error", "-i", video.path, "-map", "0:v:0", "-c:v", "copy", "-an", silent.path])
        }
        func remove() { try? FileManager.default.removeItem(at: directory) }
    }

    func testDiscardedSegmentsExportSeparatelyInTheirOriginalOrder() throws {
        let f = try Fixtures(); defer { f.remove() }
        let original = try Data(contentsOf: f.video)
        var options = OperationOptions()
        options.splitPoints = [2, 1]
        options.discardedClips = [1, 1]
        options.outputDirectory = f.directory.appendingPathComponent("Exports", isDirectory: true)
        let clips = try MediaEngine.tool(.splitVideo, inputs: [f.video], options: options, token: .init())
        XCTAssertEqual(clips.count, 2)
        let folder = try XCTUnwrap(clips.first?.deletingLastPathComponent())
        XCTAssertEqual(folder.deletingLastPathComponent(), options.outputDirectory)
        XCTAssertEqual(Set(clips.map { $0.deletingLastPathComponent() }).count, 1)
        XCTAssertTrue(clips[0].lastPathComponent.contains("Part 1"))
        XCTAssertTrue(clips[1].lastPathComponent.contains("Part 3"))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).count, 2)
        for clip in clips { XCTAssertEqual(try MediaEngine.inspect(clip).duration, 1, accuracy: 0.1) }
        try assertColor(clips[0], at: 0.4, channel: 0)
        try assertColor(clips[1], at: 0.4, channel: 2)
        XCTAssertEqual(try frequency(clips[0], at: 0.3), 330, accuracy: 12)
        XCTAssertEqual(try frequency(clips[1], at: 0.3), 990, accuracy: 12)
        XCTAssertEqual(try Data(contentsOf: f.video), original)
    }

    func testExportOneVideoJoinsOnlyRetainedContentAndAudio() throws {
        let f = try Fixtures(); defer { f.remove() }
        let original = try Data(contentsOf: f.video)
        var options = OperationOptions()
        options.splitPoints = [1, 2]; options.discardedClips = [1]; options.joinSplitClips = true
        options.outputDirectory = f.directory.appendingPathComponent("Joined", isDirectory: true)
        let outputs = try MediaEngine.tool(.splitVideo, inputs: [f.video], options: options, token: .init())
        XCTAssertEqual(outputs.count, 1)
        let out = try XCTUnwrap(outputs.first)
        XCTAssertEqual(out.deletingLastPathComponent(), options.outputDirectory)
        XCTAssertNotEqual(out, f.video)
        let info = try MediaEngine.inspect(out)
        XCTAssertTrue(info.hasAudio); XCTAssertEqual(info.duration, 2, accuracy: 0.12)
        XCTAssertEqual(info.video?.width, 96); XCTAssertEqual(info.video?.height, 64)
        try assertColor(out, at: 0.4, channel: 0)
        try assertColor(out, at: 1.4, channel: 2)
        XCTAssertEqual(try frequency(out, at: 0.3), 330, accuracy: 12)
        XCTAssertEqual(try frequency(out, at: 1.3), 990, accuracy: 12)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: options.outputDirectory!.path), [out.lastPathComponent])
        XCTAssertEqual(try Data(contentsOf: f.video), original)
    }

    func testExportOneVideoSupportsSilentInputsAndOneRetainedSegment() throws {
        let f = try Fixtures(); defer { f.remove() }
        var options = OperationOptions()
        options.equalClips = 3; options.discardedClips = [1]; options.joinSplitClips = true
        let joined = try XCTUnwrap(MediaEngine.tool(.splitVideo, inputs: [f.silent], options: options, token: .init()).first)
        XCTAssertEqual(joined.pathExtension, "mov")
        XCTAssertFalse(try MediaEngine.inspect(joined).hasAudio)
        XCTAssertEqual(try MediaEngine.inspect(joined).duration, 2, accuracy: 0.12)
        try assertColor(joined, at: 0.4, channel: 0)
        try assertColor(joined, at: 1.4, channel: 2)
        options.discardedClips = [0, 2]
        let one = try XCTUnwrap(MediaEngine.tool(.splitVideo, inputs: [f.video], options: options, token: .init()).first)
        XCTAssertEqual(try MediaEngine.inspect(one).duration, 1, accuracy: 0.1)
        try assertColor(one, at: 0.4, channel: 1)
        XCTAssertEqual(try frequency(one, at: 0.3), 660, accuracy: 12)
    }

    func testSplitIntervalFilteringAndRestoreProduceTheExpectedSegments() throws {
        let f = try Fixtures(); defer { f.remove() }
        var options = OperationOptions(); options.splitInterval = 1; options.discardedClips = [0, 2]
        let retained = try MediaEngine.tool(.splitVideo, inputs: [f.silent], options: options, token: .init())
        XCTAssertEqual(retained.count, 1)
        try assertColor(retained[0], at: 0.4, channel: 1)
        options.discardedClips = []
        let restored = try MediaEngine.tool(.splitVideo, inputs: [f.silent], options: options, token: .init())
        XCTAssertEqual(restored.count, 3)
        for index in 0..<3 { try assertColor(restored[index], at: 0.4, channel: index) }
    }

    func testInvalidOrEmptySelectionFailsBeforeCreatingAnExportFolder() throws {
        let f = try Fixtures(); defer { f.remove() }
        let original = try Data(contentsOf: f.video)
        for removed in [[-1], [3], [0, 1, 2]] {
            for joined in [false, true] {
                var options = OperationOptions(); options.equalClips = 3; options.discardedClips = removed; options.joinSplitClips = joined
                let destination = f.directory.appendingPathComponent("Invalid \(removed) \(joined)", isDirectory: true)
                options.outputDirectory = destination
                XCTAssertThrowsError(try MediaEngine.tool(.splitVideo, inputs: [f.video], options: options, token: .init()))
                XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
            }
        }
        let token = CancellationToken(); token.cancel()
        var options = OperationOptions(); options.joinSplitClips = true
        XCTAssertThrowsError(try MediaEngine.tool(.splitVideo, inputs: [f.video], options: options, token: token))
        XCTAssertEqual(try Data(contentsOf: f.video), original)
    }

    func testRetainedContentPreviewOwnsItsWorkingFiles() async throws {
        let f = try Fixtures(); defer { f.remove() }
        let siblings = try FileManager.default.contentsOfDirectory(atPath: f.directory.path).sorted()
        var options = OperationOptions(); options.splitPoints = [1, 2]; options.discardedClips = [1]; options.joinSplitClips = true
        let preview = try await MediaPreviewEngine.processedPreview(.splitVideo, input: f.video, options: options)
        let directory = try XCTUnwrap(preview.ownedTemporaryDirectory)
        defer { preview.removeTemporaryFiles() }
        XCTAssertEqual(preview.originalURL, f.video)
        XCTAssertNotEqual(directory, f.directory)
        XCTAssertEqual(try MediaEngine.inspect(preview.playbackURL).duration, 2, accuracy: 0.12)
        try assertColor(preview.playbackURL, at: 0.4, channel: 0)
        try assertColor(preview.playbackURL, at: 1.4, channel: 2)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: f.directory.path).sorted(), siblings)
        preview.removeTemporaryFiles()
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testExportOneVideoWorksAcrossTheRemainingSupportedContainers() throws {
        let f = try Fixtures(); defer { f.remove() }
        var options = OperationOptions(); options.splitPoints = [1, 2]; options.discardedClips = [1]; options.joinSplitClips = true
        for format in ["mkv", "webm", "avi", "wmv"] {
            let input = try XCTUnwrap(MediaEngine.convert(f.video, to: format, options: .init(), token: .init()).first)
            let expectedDuration = try MediaEngine.inspect(input).duration - 1
            let out = try XCTUnwrap(MediaEngine.tool(.splitVideo, inputs: [input], options: options, token: .init()).first)
            let info = try MediaEngine.inspect(out)
            XCTAssertEqual(out.pathExtension, format)
            XCTAssertTrue(info.hasAudio, format)
            XCTAssertEqual(info.duration, expectedDuration, accuracy: 0.08, format)
            try assertColor(out, at: 0.4, channel: 0)
            try assertColor(out, at: 1.4, channel: 2)
            XCTAssertEqual(try frequency(out, at: 1.3), 990, accuracy: 12, format)
        }
    }

    func testFailedBatchRemovesJoinedOutputsAndKeepsTheChosenDirectory() throws {
        let f = try Fixtures(); defer { f.remove() }
        let invalid = f.directory.appendingPathComponent("Not media.txt")
        try "This is a local text fixture.".write(to: invalid, atomically: true, encoding: .utf8)
        let destination = f.directory.appendingPathComponent("Chosen destination", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        var options = OperationOptions(); options.equalClips = 3; options.discardedClips = [1]; options.joinSplitClips = true; options.outputDirectory = destination
        XCTAssertThrowsError(try MediaEngine.tool(.splitVideo, inputs: [f.video, invalid], options: options, token: .init()))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: destination.path).isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: f.video.path))
        XCTAssertEqual(try String(contentsOf: invalid, encoding: .utf8), "This is a local text fixture.")
    }

    private func assertColor(_ url: URL, at time: Double, channel: Int, file: StaticString = #filePath, line: UInt = #line) throws {
        let result = try ProcessRunner.run(Dependencies.executable("ffmpeg"), ["-v", "error", "-ss", String(time), "-i", url.path, "-frames:v", "1", "-vf", "scale=1:1", "-pix_fmt", "rgb24", "-f", "rawvideo", "-"]).output
        XCTAssertEqual(result.count, 3, file: file, line: line)
        guard result.count == 3 else { return }
        XCTAssertGreaterThan(result[channel], 220, file: file, line: line)
        for other in 0..<3 where other != channel { XCTAssertLessThan(result[other], 30, file: file, line: line) }
    }

    private func frequency(_ url: URL, at time: Double) throws -> Double {
        let result = try ProcessRunner.run(Dependencies.executable("ffmpeg"), ["-v", "error", "-ss", String(time), "-i", url.path, "-t", "0.3", "-map", "0:a:0", "-ac", "1", "-ar", "48000", "-f", "f32le", "-"]).output
        let samples = result.withUnsafeBytes { bytes in stride(from: 0, to: bytes.count - 3, by: 4).map { bytes.loadUnaligned(fromByteOffset: $0, as: Float.self) } }
        guard samples.count > 1 else { return 0 }
        let crossings = zip(samples, samples.dropFirst()).filter { ($0.0 >= 0) != ($0.1 >= 0) }.count
        return Double(crossings) / (2 * Double(samples.count) / 48000)
    }
}
