import XCTest
import CoreGraphics
@testable import NashiCore

final class ImageCropBoundsRegressionTests: XCTestCase {
    func testValidExactCropPreservesGeometryAndSourcePixels() throws {
        let input = try pattern(width: 800, height: 600)
        for (x, y, width, height) in [(300, 200, 300, 200), (500, 400, 300, 200), (799, 599, 1, 1)] {
            var options = OperationOptions()
            options.crop = EditRect(x: Double(x), y: Double(y), width: Double(width), height: Double(height))
            let output = try ImageEngine.preview(input, tool: .cropImage, options: options)
            XCTAssertEqual(output.width, width); XCTAssertEqual(output.height, height)
            let expected = try pattern(width: width, height: height, originX: x, originY: y)
            XCTAssertEqual(try pixels(output), try pixels(expected))
        }
    }

    func testFractionalAspectPresetUsesTheDisplayedWholePixelGeometry() throws {
        let input = try pattern(width: 400, height: 300)
        var options = OperationOptions()
        options.crop = EditRect(x: 0, y: 37.5, width: 400, height: 225)
        let output = try ImageEngine.preview(input, tool: .cropImage, options: options)
        XCTAssertEqual(output.width, 400); XCTAssertEqual(output.height, 225)
        let expected = try pattern(width: 400, height: 225, originX: 0, originY: 37)
        XCTAssertEqual(try pixels(output), try pixels(expected))
    }

    func testFractionalDragFloorsEachComponentWithoutAddingPixels() throws {
        let input = try pattern(width: 400, height: 300)
        let cases: [(EditRect, Int, Int, Int, Int)] = [
            (.init(x: 10.875, y: 20.25, width: 123.875, height: 89.75), 10, 20, 123, 89),
            (.init(x: 0.9, y: 0.9, width: 1.9, height: 1.9), 0, 0, 1, 1),
            (.init(x: 298.5, y: 198.5, width: 101.5, height: 101.5), 298, 198, 101, 101)
        ]
        for (rect, x, y, width, height) in cases {
            var options = OperationOptions(); options.crop = rect
            let output = try ImageEngine.preview(input, tool: .cropImage, options: options)
            XCTAssertEqual(output.width, width); XCTAssertEqual(output.height, height)
            let expected = try pattern(width: width, height: height, originX: x, originY: y)
            XCTAssertEqual(try pixels(output), try pixels(expected))
        }
    }

    func testFractionalBoundsAreValidatedBeforePixelQuantization() throws {
        let input = try pattern(width: 400, height: 300)
        let invalid: [EditRect] = [
            .init(x: 0.5, y: 0, width: 400, height: 200),
            .init(x: 399.5, y: 0, width: 1, height: 1),
            .init(x: 0, y: 299.5, width: 1, height: 1),
            .init(x: -0.25, y: 0, width: 20, height: 20),
            .init(x: 0, y: 0, width: 0.75, height: 20)
        ]
        for rect in invalid {
            var options = OperationOptions(); options.crop = rect; options.width = 100; options.height = 100
            XCTAssertThrowsError(try ImageEngine.preview(input, tool: .cropImage, options: options)) { error in
                guard case NashiError.invalidInput = error else { return XCTFail("Expected the original invalid rectangle to be rejected, received \(error)") }
            }
        }
    }

    func testValidCropExportKeepsAnExplicitResize() throws {
        let directory = try OutputFiles.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("Explicit resize.png")
        try ImageEngine.write(pattern(width: 800, height: 600, solid: [24, 96, 192, 255]), to: input)
        let original = try Data(contentsOf: input)
        var options = OperationOptions()
        options.crop = EditRect(x: 300, y: 200, width: 300, height: 200)
        options.width = 100; options.height = 50
        let outputs = try ConversionEngine.run(.init(inputs: [input], operation: .tool(.cropImage), options: options))
        let output = try ImageEngine.load(XCTUnwrap(outputs.first))
        XCTAssertEqual(output.width, 100); XCTAssertEqual(output.height, 50)
        XCTAssertEqual(try pixels(output), try pixels(pattern(width: 100, height: 50, solid: [24, 96, 192, 255])))
        XCTAssertEqual(try Data(contentsOf: input), original)
    }

    func testPartiallyOutOfBoundsCropWithResizeIsRejected() throws {
        let input = try pattern(width: 400, height: 300)
        var options = OperationOptions()
        options.crop = EditRect(x: 300, y: 200, width: 300, height: 200)
        // This is the 0.4.3 GUI request: intersecting to100x100 and then stretching
        // to300x200 must never turn an invalid requested rectangle into success.
        options.width = 300; options.height = 200
        XCTAssertThrowsError(try ImageEngine.preview(input, tool: .cropImage, options: options)) { error in
            guard case NashiError.invalidInput = error else { return XCTFail("Expected invalid crop input, received \(error)") }
        }
        options.width = nil; options.height = nil
        XCTAssertThrowsError(try ImageEngine.preview(input, tool: .cropImage, options: options))
    }

    func testInvalidOriginsDimensionsAndExtremeCoordinatesAreRejected() throws {
        let input = try pattern(width: 400, height: 300)
        let cases: [(String, EditRect)] = [
            ("negative x", .init(x: -1, y: 20, width: 30, height: 40)),
            ("negative y", .init(x: 10, y: -1, width: 30, height: 40)),
            ("negative width", .init(x: 50, y: 20, width: -30, height: 40)),
            ("negative height", .init(x: 10, y: 60, width: 30, height: -40)),
            ("zero width", .init(x: 10, y: 20, width: 0, height: 40)),
            ("zero height", .init(x: 10, y: 20, width: 30, height: 0)),
            ("right boundary", .init(x: 400, y: 20, width: 1, height: 40)),
            ("bottom boundary", .init(x: 10, y: 300, width: 30, height: 1)),
            ("partial right", .init(x: 390, y: 20, width: 30, height: 40)),
            ("partial bottom", .init(x: 10, y: 290, width: 30, height: 40)),
            ("extreme origin", .init(x: .greatestFiniteMagnitude, y: 0, width: .greatestFiniteMagnitude, height: 20)),
            ("extreme width", .init(x: 1, y: 0, width: .greatestFiniteMagnitude, height: 20)),
            ("infinite coordinate", .init(x: .infinity, y: 0, width: 20, height: 20)),
            ("not a number", .init(x: 0, y: .nan, width: 20, height: 20))
        ]
        for (name, rect) in cases {
            var options = OperationOptions(); options.crop = rect
            XCTAssertThrowsError(try ImageEngine.preview(input, tool: .cropImage, options: options), name) { error in
                guard case NashiError.invalidInput = error else { return XCTFail("\(name): expected invalid crop input, received \(error)") }
            }
        }
    }

    func testMixedSizeBatchRollsBackAndNamesTheFailingInput() throws {
        for useOutputDirectory in [false, true] {
            let directory = try OutputFiles.temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let inputs = directory.appendingPathComponent("Inputs", isDirectory: true)
            let exports = useOutputDirectory ? directory.appendingPathComponent("Exports", isDirectory: true) : inputs
            try FileManager.default.createDirectory(at: inputs, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: exports, withIntermediateDirectories: true)
            let large = inputs.appendingPathComponent("Large Görsel.png")
            let small = inputs.appendingPathComponent("Second İstanbul.png")
            try ImageEngine.write(pattern(width: 800, height: 600), to: large)
            try ImageEngine.write(pattern(width: 400, height: 300), to: small)
            let largeBefore = try Data(contentsOf: large), smallBefore = try Data(contentsOf: small)
            let priorLarge = exports.appendingPathComponent("Large Görsel - Cropped.png")
            let priorSmall = exports.appendingPathComponent("Second İstanbul - Cropped.png")
            let priorLargeBytes = Data("Previously exported large image".utf8), priorSmallBytes = Data("Previously exported small image".utf8)
            try priorLargeBytes.write(to: priorLarge); try priorSmallBytes.write(to: priorSmall)
            let inputNames = try FileManager.default.contentsOfDirectory(atPath: inputs.path).sorted()
            let exportNames = try FileManager.default.contentsOfDirectory(atPath: exports.path).sorted()
            var options = OperationOptions()
            options.crop = EditRect(x: 300, y: 200, width: 300, height: 200)
            options.width = 300; options.height = 200
            if useOutputDirectory { options.outputDirectory = exports }
            XCTAssertThrowsError(try ConversionEngine.run(.init(inputs: [large, small], operation: .tool(.cropImage), options: options))) { error in
                XCTAssertTrue(error.localizedDescription.contains(small.lastPathComponent), error.localizedDescription)
                XCTAssertTrue(error.localizedDescription.contains("400"), error.localizedDescription)
                XCTAssertTrue(error.localizedDescription.contains("300"), error.localizedDescription)
            }
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: inputs.path).sorted(), inputNames)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: exports.path).sorted(), exportNames)
            XCTAssertEqual(try Data(contentsOf: large), largeBefore)
            XCTAssertEqual(try Data(contentsOf: small), smallBefore)
            XCTAssertEqual(try Data(contentsOf: priorLarge), priorLargeBytes)
            XCTAssertEqual(try Data(contentsOf: priorSmall), priorSmallBytes)
        }
    }

    private func pattern(width: Int, height: Int, originX: Int = 0, originY: Int = 0, solid: [UInt8]? = nil) throws -> CGImage {
        var rgba = [UInt8](); rgba.reserveCapacity(width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let sourceX = originX + x, sourceY = originY + y
                rgba += solid ?? [UInt8(sourceX % 256), UInt8(sourceY % 256), UInt8((sourceX * 7 + sourceY * 11) % 256), 255]
            }
        }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(rgba) as CFData))
        return try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }

    private func pixels(_ image: CGImage) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Data(bytes: try XCTUnwrap(context.data), count: image.width * image.height * 4)
    }
}
