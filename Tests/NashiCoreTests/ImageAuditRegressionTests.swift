import XCTest
import CoreGraphics
@testable import NashiCore

final class ImageAuditRegressionTests: XCTestCase {
    /// Four distinct quadrants catch a reversed rotation that size checks cannot.
    private func quadrants() throws -> CGImage {
        let width = 80, height = 40
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let rgb: [UInt8] = y < height / 2
                    ? (x < width / 2 ? [255, 0, 0] : [0, 255, 0])
                    : (x < width / 2 ? [0, 0, 255] : [255, 255, 0])
                let offset = (y * width + x) * 4
                pixels.replaceSubrange(offset..<(offset + 3), with: rgb)
            }
        }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
        return try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8,
                                     bitsPerPixel: 32, bytesPerRow: width * 4,
                                     space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                     bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                     provider: provider, decode: nil, shouldInterpolate: false,
                                     intent: .defaultIntent))
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) throws -> [UInt8] {
        let sample = try XCTUnwrap(image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)))
        var rgba = [UInt8](repeating: 0, count: 4)
        try rgba.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: 1, height: 1,
                                                bitsPerComponent: 8, bytesPerRow: 4,
                                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(sample, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return Array(rgba.prefix(3))
    }

    func testEditorQuarterTurnsRotateInTheLabelledDirection() throws {
        let input = try quadrants()
        XCTAssertEqual(try pixel(input, x: 5, y: 5), [255, 0, 0])
        for (angle, topLeft, topRight, bottomLeft, bottomRight) in [
            (90, [0, 0, 255], [255, 0, 0], [255, 255, 0], [0, 255, 0]),
            (-90, [0, 255, 0], [255, 255, 0], [255, 0, 0], [0, 0, 255]),
            (270, [0, 255, 0], [255, 255, 0], [255, 0, 0], [0, 0, 255])
        ] {
            var options = OperationOptions(); options.rotation = angle
            let output = try ImageEngine.editedImage(input, options: options)
            XCTAssertEqual(output.width, 40)
            XCTAssertEqual(output.height, 80)
            XCTAssertEqual(try pixel(output, x: 5, y: 5), topLeft.map(UInt8.init), "\(angle)°")
            XCTAssertEqual(try pixel(output, x: 35, y: 5), topRight.map(UInt8.init), "\(angle)°")
            XCTAssertEqual(try pixel(output, x: 5, y: 75), bottomLeft.map(UInt8.init), "\(angle)°")
            XCTAssertEqual(try pixel(output, x: 35, y: 75), bottomRight.map(UInt8.init), "\(angle)°")
        }
    }

    func testArbitraryPositiveAngleUsesTheSameClockwiseConvention() throws {
        var options = OperationOptions(); options.rotation = 45
        let output = try ImageEngine.editedImage(quadrants(), options: options)
        let center = (Double(output.width) / 2, Double(output.height) / 2)
        let c = sqrt(0.5)
        // Centers of the four source quadrants after a clockwise screen rotation.
        for (x, y, expected) in [(20.0, 10.0, [255, 0, 0]), (60, 10, [0, 255, 0]),
                                 (20, 30, [0, 0, 255]), (60, 30, [255, 255, 0])] {
            let dx = x - 40, dy = y - 20
            let actual = try pixel(output, x: Int(center.0 + c * dx - c * dy),
                                   y: Int(center.1 + c * dx + c * dy))
            XCTAssertEqual(actual, expected.map(UInt8.init))
        }
    }
}
