import XCTest
import CoreGraphics
@testable import NashiCore

final class ImageRedactionBoundsRegressionTests: XCTestCase {
    private func image(_ width: Int, _ height: Int) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height,
                                             bitsPerComponent: 8, bytesPerRow: width * 4,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.8, blue: 0.3, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }

    func testEveryStyleRejectsInvalidAreasInsteadOfSilentlyClippingOrSkipping() throws {
        let source = try image(160, 100)
        let invalid: [EditRect] = [
            .init(x: 200, y: 0, width: 10, height: 10),
            .init(x: 140, y: 60, width: 40, height: 30),
            .init(x: -1, y: 0, width: 20, height: 20),
            .init(x: 0, y: -1, width: 20, height: 20),
            .init(x: 0, y: 0, width: 0, height: 20),
            .init(x: 0, y: 0, width: 20, height: -1),
            .init(x: 0, y: 0, width: .greatestFiniteMagnitude, height: 20),
            .init(x: .infinity, y: 0, width: 20, height: 20),
            .init(x: 0, y: 0, width: 20, height: .nan)
        ]
        for style in ImageRedactionStyle.allCases {
            for rect in invalid {
                var options = OperationOptions()
                var settings = ImageRedactionOptions(); settings.style = style
                options.imageRedaction = settings
                // A valid first region must not hide an invalid later one.
                options.redactions = [.init(x: 10, y: 10, width: 20, height: 20), rect]
                XCTAssertThrowsError(try ImageEngine.preview(source, tool: .redactImage, options: options),
                                     "\(style.rawValue) must reject \(rect)") { error in
                    guard case NashiError.invalidInput = error else { return XCTFail("Unexpected error: \(error)") }
                }
            }
        }
    }

    func testMixedSizeRedactionBatchRollsBackAndIdentifiesTheSmallerImage() throws {
        let directory = try OutputFiles.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("First 160x100.png")
        let second = directory.appendingPathComponent("Second 40x25.png")
        try ImageEngine.write(image(160, 100), to: first)
        try ImageEngine.write(image(40, 25), to: second)
        let firstBytes = try Data(contentsOf: first), secondBytes = try Data(contentsOf: second)
        let exports = directory.appendingPathComponent("Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: exports, withIntermediateDirectories: true)
        let previous = exports.appendingPathComponent("Previous export.png")
        let sentinel = Data("Previous output must survive.".utf8)
        try sentinel.write(to: previous)

        for style in ImageRedactionStyle.allCases {
            var options = OperationOptions(); options.outputDirectory = exports
            var settings = ImageRedactionOptions(); settings.style = style
            options.imageRedaction = settings
            options.redactions = [.init(x: 100, y: 60, width: 40, height: 30)]
            XCTAssertThrowsError(try ConversionEngine.run(.init(inputs: [first, second], operation: .tool(.redactImage), options: options))) { error in
                XCTAssertTrue(error.localizedDescription.contains(second.lastPathComponent))
                XCTAssertTrue(error.localizedDescription.contains("40 × 25"))
            }
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: exports.path), [previous.lastPathComponent])
            XCTAssertEqual(try Data(contentsOf: previous), sentinel)
            XCTAssertEqual(try Data(contentsOf: first), firstBytes)
            XCTAssertEqual(try Data(contentsOf: second), secondBytes)
        }
    }

    func testFractionalRegionsAtTheBoundaryRemainValidForAllStyles() throws {
        let source = try image(160, 100)
        for style in ImageRedactionStyle.allCases {
            var options = OperationOptions()
            var settings = ImageRedactionOptions(); settings.style = style
            options.imageRedaction = settings
            options.redactions = [.init(x: 159.5, y: 99.5, width: 0.5, height: 0.5)]
            let result = try ImageEngine.preview(source, tool: .redactImage, options: options)
            XCTAssertEqual(result.width, 160); XCTAssertEqual(result.height, 100)
        }
    }

    func testNoManualRegionsAndNoDetectedFacesDoNotClaimSuccess() throws {
        let source = try image(160, 100)
        var options = OperationOptions()
        XCTAssertThrowsError(try ImageEngine.preview(source, tool: .redactImage, options: options))
        var settings = ImageRedactionOptions(); settings.detectFaces = true
        options.imageRedaction = settings
        // A uniform synthetic image has no faces. A detector finding nothing
        // must retain the existing explicit "select an area" error semantics.
        XCTAssertThrowsError(try ImageEngine.preview(source, tool: .redactImage, options: options)) { error in
            XCTAssertTrue(error.localizedDescription.contains("Select an area to redact"))
        }
    }
}
