import XCTest
import CoreGraphics
@testable import NashiCore

final class ImageMediaBatchAuditTests: XCTestCase {
    private func fixtureDirectory() throws -> URL { try OutputFiles.temporaryDirectory() }

    private func image(_ directory: URL, name: String = "Photo.png") throws -> URL {
        let context = try XCTUnwrap(CGContext(data: nil, width: 80, height: 40,
                                            bitsPerComponent: 8, bytesPerRow: 80 * 4,
                                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0.3, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 80, height: 40))
        let file = directory.appendingPathComponent(name)
        try ImageEngine.write(XCTUnwrap(context.makeImage()), to: file)
        return file
    }

    private func video(_ directory: URL) throws -> URL {
        let file = directory.appendingPathComponent("Clip.mp4")
        try ProcessRunner.run(Dependencies.executable("ffmpeg"), [
            "-hide_banner", "-nostdin", "-v", "error", "-n", "-f", "lavfi", "-i",
            "testsrc2=size=80x48:rate=8:duration=0.5", "-an", "-c:v", "libx264",
            "-preset", "ultrafast", "-pix_fmt", "yuv420p", file.path
        ])
        return file
    }

    private func corrupted(_ directory: URL, name: String = "Broken.mp4") throws -> URL {
        let file = directory.appendingPathComponent(name)
        try Data("Not decodable media".utf8).write(to: file)
        return file
    }

    private func exportDirectory(_ directory: URL, occupiedName: String) throws -> (URL, URL, Data) {
        let folder = directory.appendingPathComponent("Chosen exports", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let previous = folder.appendingPathComponent(occupiedName)
        let bytes = Data("A previous export that must survive this failed job.\0".utf8)
        try bytes.write(to: previous)
        return (folder, previous, bytes)
    }

    private func assertOnlyPreviousExportRemains(_ folder: URL, _ previous: URL, _ bytes: Data,
                                               file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(try Data(contentsOf: previous), bytes, file: file, line: line)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .map { $0.resolvingSymlinksInPath() },
                       [previous.resolvingSymlinksInPath()], "Failed or cancelled jobs must remove only their own outputs.", file: file, line: line)
    }

    func testFailedMediaConversionBatchRollsBackAndKeepsPreviousExport() throws {
        let directory = try fixtureDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let source = try video(directory), broken = try corrupted(directory)
        let original = try Data(contentsOf: source)
        let (folder, previous, bytes) = try exportDirectory(directory, occupiedName: "Clip.mov")
        var options = OperationOptions(); options.outputDirectory = folder
        XCTAssertThrowsError(try ConversionEngine.run(.init(inputs: [source, broken], operation: .convert("mov"), options: options)))
        try assertOnlyPreviousExportRemains(folder, previous, bytes)
        XCTAssertEqual(try Data(contentsOf: source), original)
    }

    func testFailedImageToolBatchRollsBackAndKeepsPreviousExport() throws {
        let directory = try fixtureDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let source = try image(directory), broken = try corrupted(directory)
        let original = try Data(contentsOf: source)
        let (folder, previous, bytes) = try exportDirectory(directory, occupiedName: "Photo - Cropped.png")
        var options = OperationOptions(); options.outputDirectory = folder
        options.crop = EditRect(x: 0, y: 0, width: 30, height: 20)
        XCTAssertThrowsError(try ConversionEngine.run(.init(inputs: [source, broken], operation: .tool(.cropImage), options: options)))
        try assertOnlyPreviousExportRemains(folder, previous, bytes)
        XCTAssertEqual(try Data(contentsOf: source), original)
    }

    func testFailedCompressionBatchRollsBackAndKeepsPreviousExport() throws {
        let directory = try fixtureDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let source = try video(directory), broken = try corrupted(directory)
        let original = try Data(contentsOf: source)
        let (folder, previous, bytes) = try exportDirectory(directory, occupiedName: "Clip Compressed.mp4")
        var options = OperationOptions(); options.outputDirectory = folder
        XCTAssertThrowsError(try ConversionEngine.run(.init(inputs: [source, broken], operation: .tool(.compress), options: options)))
        try assertOnlyPreviousExportRemains(folder, previous, bytes)
        XCTAssertEqual(try Data(contentsOf: source), original)
    }

    func testCancellationBetweenSuccessfulBatchItemsRollsBackAndKeepsPreviousExport() throws {
        let directory = try fixtureDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let first = try image(directory, name: "First.png"), second = try image(directory, name: "Second.png")
        let firstOriginal = try Data(contentsOf: first), secondOriginal = try Data(contentsOf: second)
        let (folder, previous, bytes) = try exportDirectory(directory, occupiedName: "First.jpg")
        let token = CancellationToken()
        var options = OperationOptions(); options.outputDirectory = folder; options.preserveMetadata = false
        XCTAssertThrowsError(try ConversionEngine.run(.init(inputs: [first, second], operation: .convert("jpg"), options: options),
                                                    token: token, progress: { amount, _ in
            // The second-item callback occurs after the first conversion succeeds.
            if amount > 0 && amount < 1 { token.cancel() }
        })) { error in
            guard case NashiError.cancelled = error else { return XCTFail("Expected cancellation, received \(error)") }
        }
        try assertOnlyPreviousExportRemains(folder, previous, bytes)
        XCTAssertEqual(try Data(contentsOf: first), firstOriginal)
        XCTAssertEqual(try Data(contentsOf: second), secondOriginal)
    }
}
