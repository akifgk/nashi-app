import XCTest
import AppKit
import ImageIO
@testable import NashiCore

final class ImageColorOpacityRegressionTests: XCTestCase {
    private func sourceImage() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 20, height: 12,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.systemRed.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 20, height: 12))
        return try XCTUnwrap(context.makeImage())
    }

    private func alpha(_ image: CGImage, x: Int = 1, y: Int = 1) throws -> Int {
        let sample = try XCTUnwrap(image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)))
        var bytes = [UInt8](repeating: 0, count: 4)
        try bytes.withUnsafeMutableBytes { data in
            let context = try XCTUnwrap(CGContext(data: data.baseAddress, width: 1, height: 1,
                bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(sample, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return Int(bytes[3])
    }

    func testCollageBackgroundOpacitySurvivesColorSerializationAndPNGExport() throws {
        let directory = try OutputFiles.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = try sourceImage()
        for (index, opacity) in [CGFloat(0), CGFloat(0.4), CGFloat(1)].enumerated() {
            var settings = CollageOptions()
            settings.width = 80; settings.height = 48; settings.outerPadding = 8; settings.spacing = 4
            settings.backgroundColor = ImageColorCodec.backgroundHex(NSColor(srgbRed: 0.2,
                green: 0.4, blue: 0.6, alpha: opacity))
            let result = try ImageEngine.collageImage([image, image], settings: settings)
            let output = directory.appendingPathComponent("Opacity-\(index).png")
            try ImageEngine.write(result, to: output)
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL, nil))
            let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            XCTAssertLessThanOrEqual(abs(try alpha(decoded) - Int((opacity * 255).rounded())), 1)
            XCTAssertEqual(try alpha(decoded, x: 14, y: 16), 255, "Foreground images stay opaque.")
        }
    }

    func testFrameBackgroundOpacitySurvivesTheSharedBindingFormat() throws {
        var frame = ImageFrameOptions()
        frame.padding = 8; frame.cornerRadius = 0; frame.shadowRadius = 0; frame.shadowOpacity = 0
        frame.backgroundColor = ImageColorCodec.backgroundHex(NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0))
        var options = OperationOptions(); options.imageFrame = frame
        let output = try ImageEngine.preview(sourceImage(), tool: .frameImage, options: options)
        XCTAssertEqual(try alpha(output), 0)
        XCTAssertEqual(try alpha(output, x: 14, y: 12), 255)
    }

    func testFrameExportPreservesRequestedOpacityForPNGAndJPEGInputs() throws {
        let directory = try OutputFiles.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        for ext in ["png", "jpg"] {
            let input = directory.appendingPathComponent("Source.\(ext)")
            try ImageEngine.write(sourceImage(), to: input)
            let original = try Data(contentsOf: input)
            for opacity in [CGFloat(0), CGFloat(0.4), CGFloat(1)] {
                var frame = ImageFrameOptions()
                frame.padding = 8; frame.cornerRadius = 0; frame.shadowRadius = 0; frame.shadowOpacity = 0
                frame.backgroundColor = ImageColorCodec.backgroundHex(NSColor(srgbRed: 1,
                    green: 1, blue: 1, alpha: opacity))
                var options = OperationOptions(); options.imageFrame = frame
                let outputs = try ConversionEngine.run(.init(inputs: [input], operation: .tool(.frameImage), options: options))
                let output = try XCTUnwrap(outputs.first)
                XCTAssertEqual(output.pathExtension, opacity < 1 ? "png" : ext,
                               "Transparency requires an output format that preserves alpha.")
                let source = try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL, nil))
                let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
                XCTAssertEqual(decoded.width, 36); XCTAssertEqual(decoded.height, 28)
                XCTAssertLessThanOrEqual(abs(try alpha(decoded) - Int((opacity * 255).rounded())), 1)
                XCTAssertEqual(try alpha(decoded, x: 14, y: 12), 255)
                XCTAssertEqual(try Data(contentsOf: input), original)
            }
        }
    }
}
