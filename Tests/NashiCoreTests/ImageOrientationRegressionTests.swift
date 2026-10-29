import XCTest
import CoreGraphics
import ImageIO
@testable import NashiCore

final class ImageOrientationRegressionTests: XCTestCase {
    private let author = "Orientation QA İstanbul"
    private let title = "Preserve this title"

    private func quadrants() throws -> CGImage {
        let width = 160, height = 96
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let color: [UInt8] = y < height / 2
                    ? (x < width / 2 ? [255, 0, 0] : [0, 255, 0])
                    : (x < width / 2 ? [0, 0, 255] : [255, 255, 0])
                let offset = (y * width + x) * 4
                bytes.replaceSubrange(offset..<(offset + 3), with: color)
            }
        }
        return try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8,
            bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData)),
            decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }

    @discardableResult private func exif(_ arguments: [String]) throws -> Data {
        let script = try Dependencies.executable("exiftool")
        return try ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/perl"),
                                     [script.path, "-config", ""] + arguments).output
    }

    private func numericOrientations(_ url: URL) throws -> [String: Int] {
        let data = try exif(["-j", "-G1", "-a", "-n", "-Orientation", url.path])
        let row = try XCTUnwrap((JSONSerialization.jsonObject(with: data) as? [[String: Any]])?.first)
        return row.reduce(into: [:]) { result, field in
            if field.key.hasSuffix(":Orientation"), let value = field.value as? NSNumber {
                result[field.key] = value.intValue
            }
        }
    }

    private func source(_ directory: URL, orientation: Int? = nil) throws -> URL {
        let url = directory.appendingPathComponent(orientation == nil ? "No orientation.png" : "Rotated.jpg")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL,
            (orientation == nil ? "public.png" : "public.jpeg") as CFString, 1, nil))
        var properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 1,
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFArtist: author],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "Preserve this comment"]
        ]
        if let orientation { properties[kCGImagePropertyOrientation] = orientation }
        CGImageDestinationAddImage(destination, try quadrants(), properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        var arguments = ["-overwrite_original", "-XMP-dc:Title=\(title)"]
        if let orientation { arguments.append("-XMP-tiff:Orientation#=\(orientation)") }
        try exif(arguments + [url.path])
        return url
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) throws -> [UInt8] {
        let sample = try XCTUnwrap(image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)))
        var bytes = [UInt8](repeating: 0, count: 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: 1, height: 1,
                bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(sample, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return Array(bytes.prefix(3))
    }

    private func assertAppearance(_ actual: CGImage, equals expected: CGImage,
                                  file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(actual.width, expected.width, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, file: file, line: line)
        guard actual.width == expected.width, actual.height == expected.height else { return }
        for (x, y) in [(actual.width / 4, actual.height / 4), (actual.width * 3 / 4, actual.height / 4),
                       (actual.width / 4, actual.height * 3 / 4), (actual.width * 3 / 4, actual.height * 3 / 4)] {
            let got = try pixel(actual, x: x, y: y), wanted = try pixel(expected, x: x, y: y)
            XCTAssertLessThanOrEqual(zip(got, wanted).map { abs(Int($0) - Int($1)) }.max() ?? 0,
                                    24, "Wrong displayed quadrant at \(x),\(y): \(got), expected \(wanted)", file: file, line: line)
        }
    }

    private func assertNormalizedOutput(_ output: URL, expected: CGImage, preservesMetadata: Bool = true,
                                       file: StaticString = #filePath, line: UInt = #line) throws {
        let orientations = try numericOrientations(output)
        if preservesMetadata { XCTAssertFalse(orientations.isEmpty, "Expected explicit numeric orientation", file: file, line: line) }
        XCTAssertTrue(orientations.values.allSatisfy { $0 == 1 }, "\(output.pathExtension): \(orientations)", file: file, line: line)
        let imageSource = try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL, nil))
        let raw = try XCTUnwrap(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))
        // Raw samples and a display-aware reader must agree. Raw-only reads
        // miss a correct raster paired with a wrong EXIF orientation.
        try assertAppearance(raw, equals: expected, file: file, line: line)
        try assertAppearance(ImageEngine.load(output), equals: expected, file: file, line: line)
        let fields = try ImageMetadataEngine.fields(output)
        if preservesMetadata {
            XCTAssertEqual(fields["{TIFF}.Artist"], author, file: file, line: line)
            XCTAssertEqual(fields["{XMP-dc}.Title"], title, file: file, line: line)
        } else {
            XCTAssertNil(fields["{TIFF}.Artist"], file: file, line: line)
            XCTAssertNil(fields["{XMP-dc}.Title"], file: file, line: line)
        }
    }

    func testPNGWithoutOrientationExportsUprightWithPreservedTags() throws {
        let directory = try OutputFiles.temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let input = try source(directory), original = try Data(contentsOf: input), expected = try quadrants()
        XCTAssertTrue(try numericOrientations(input).isEmpty)
        for format in ["jpg", "tiff", "heic", "webp"] {
            var options = OperationOptions(); options.quality = 1
            options.outputDirectory = directory.appendingPathComponent(format, isDirectory: true)
            let output = try XCTUnwrap(ConversionEngine.run(.init(inputs: [input], operation: .convert(format), options: options)).first)
            try assertNormalizedOutput(output, expected: expected)
            XCTAssertEqual(try Data(contentsOf: input), original, format)
        }
    }

    func testRotatedJPEGAndXMPOrientationAreNormalizedAfterPixelRotation() throws {
        let directory = try OutputFiles.temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let input = try source(directory, orientation: 6), original = try Data(contentsOf: input)
        XCTAssertTrue(try numericOrientations(input).values.allSatisfy { $0 == 6 })
        let expected = try ImageEngine.load(input)
        XCTAssertEqual(expected.width, 96); XCTAssertEqual(expected.height, 160)
        let blue = try pixel(expected, x: 24, y: 40)
        XCTAssertLessThanOrEqual(max(blue[0], blue[1]), 24); XCTAssertGreaterThanOrEqual(blue[2], 231)
        for format in ["png", "tiff", "heic", "webp"] {
            var options = OperationOptions(); options.quality = 1
            options.outputDirectory = directory.appendingPathComponent(format, isDirectory: true)
            let output = try XCTUnwrap(ConversionEngine.run(.init(inputs: [input], operation: .convert(format), options: options)).first)
            try assertNormalizedOutput(output, expected: expected)
            XCTAssertEqual(try Data(contentsOf: input), original, format)
        }
    }

    func testStrippingMetadataKeepsTheNormalizedDisplayedImage() throws {
        let directory = try OutputFiles.temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let input = try source(directory, orientation: 6), original = try Data(contentsOf: input)
        let expected = try ImageEngine.load(input)
        for format in ["png", "jpg", "heic", "webp"] {
            var options = OperationOptions(); options.quality = 1; options.preserveMetadata = false
            options.outputDirectory = directory.appendingPathComponent(format, isDirectory: true)
            let output = try XCTUnwrap(ConversionEngine.run(.init(inputs: [input], operation: .convert(format), options: options)).first)
            try assertNormalizedOutput(output, expected: expected, preservesMetadata: false)
            XCTAssertEqual(try Data(contentsOf: input), original, format)
        }
    }

    func testRemoveAllRetainsEveryNumericOrientationWithoutReencoding() throws {
        let directory = try OutputFiles.temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        for orientation in 1...8 {
            let fixture = directory.appendingPathComponent("orientation-\(orientation)", isDirectory: true)
            try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
            let input = try source(fixture, orientation: orientation), original = try Data(contentsOf: input)
            let expected = try ImageEngine.load(input), encoded = try ImageMetadataEngine.encodedImageHash(input)
            var options = OperationOptions(); options.imageMetadata = ImageMetadataOptions(); options.imageMetadata?.removeAll = true
            let output = try XCTUnwrap(ConversionEngine.run(.init(inputs: [input], operation: .tool(.removeMetadata), options: options)).first)
            XCTAssertTrue(try numericOrientations(output).values.allSatisfy { $0 == orientation })
            XCTAssertEqual(try ImageMetadataEngine.encodedImageHash(output), encoded)
            try assertAppearance(ImageEngine.load(output), equals: expected)
            XCTAssertNil(try ImageMetadataEngine.fields(output)["{TIFF}.Artist"])
            XCTAssertEqual(try Data(contentsOf: input), original)
        }
    }
}
