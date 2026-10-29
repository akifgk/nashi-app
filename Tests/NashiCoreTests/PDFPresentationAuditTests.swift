import XCTest
import AppKit
import PDFKit
@testable import NashiCore

final class PDFPresentationAuditTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws { root = try OutputFiles.temporaryDirectory() }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func testLandscapePortraitAndRotatedPDFsKeepTheirSlideAspectAndImageOrientation() throws {
        for (name, size, rotation, expected) in [
            ("Landscape", CGSize(width: 240, height: 120), 0, CGSize(width: 240, height: 120)),
            ("Portrait", CGSize(width: 120, height: 240), 0, CGSize(width: 120, height: 240)),
            ("Rotated", CGSize(width: 240, height: 120), 90, CGSize(width: 120, height: 240))
        ] {
            let input = try fixture(name: name, sizes: [size], firstRotation: rotation)
            let original = try Data(contentsOf: input)
            let package = try convertedPackage(input, name: name)
            let canvas = try slideSize(package)
            XCTAssertEqual(canvas.width, expected.width, accuracy: 0.02, name)
            XCTAssertEqual(canvas.height, expected.height, accuracy: 0.02, name)
            let frame = try imageFrame(package, slide: 1)
            XCTAssertEqual(frame.origin.x, 0, accuracy: 0.02, name)
            XCTAssertEqual(frame.origin.y, 0, accuracy: 0.02, name)
            XCTAssertEqual(frame.width, expected.width, accuracy: 0.02, name)
            XCTAssertEqual(frame.height, expected.height, accuracy: 0.02, name)
            let image = try embeddedImage(package, slide: 1)
            XCTAssertEqual(Double(image.pixelsWide) / Double(image.pixelsHigh), expected.width / expected.height, accuracy: 0.01, name)
            let red = try XCTUnwrap(image.colorAt(x: rotation == 0 ? image.pixelsWide / 4 : image.pixelsWide / 2,
                                                y: rotation == 0 ? image.pixelsHigh / 2 : image.pixelsHigh / 4)?.usingColorSpace(.deviceRGB))
            let blue = try XCTUnwrap(image.colorAt(x: rotation == 0 ? image.pixelsWide * 3 / 4 : image.pixelsWide / 2,
                                                 y: rotation == 0 ? image.pixelsHigh / 2 : image.pixelsHigh * 3 / 4)?.usingColorSpace(.deviceRGB))
            XCTAssertGreaterThan(red.redComponent, 0.9, name); XCTAssertLessThan(red.blueComponent, 0.1, name)
            XCTAssertGreaterThan(blue.blueComponent, 0.9, name); XCTAssertLessThan(blue.redComponent, 0.1, name)
            XCTAssertEqual(try Data(contentsOf: input), original)
        }
    }

    func testMixedPageSizesFitAndCenterInsideTheFirstPagesSharedCanvas() throws {
        let input = try fixture(name: "Mixed", sizes: [CGSize(width: 240, height: 120), CGSize(width: 360, height: 180)], firstRotation: 90)
        let package = try convertedPackage(input, name: "Mixed")
        let canvas = try slideSize(package)
        XCTAssertEqual(canvas.width, 120, accuracy: 0.02)
        XCTAssertEqual(canvas.height, 240, accuracy: 0.02)
        let frame = try imageFrame(package, slide: 2)
        XCTAssertEqual(frame.origin.x, 0, accuracy: 0.02)
        XCTAssertEqual(frame.origin.y, 90, accuracy: 0.02)
        XCTAssertEqual(frame.width, 120, accuracy: 0.02)
        XCTAssertEqual(frame.height, 60, accuracy: 0.02)
        let image = try embeddedImage(package, slide: 2)
        XCTAssertEqual(Double(image.pixelsWide) / Double(image.pixelsHigh), 2, accuracy: 0.01)
    }

    private func fixture(name: String, sizes: [CGSize], firstRotation: Int) throws -> URL {
        let source = root.appendingPathComponent(name + " source.pdf")
        let consumer = try XCTUnwrap(CGDataConsumer(url: source as CFURL))
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: nil, nil))
        for size in sizes {
            var box = CGRect(origin: .zero, size: size)
            context.beginPDFPage([kCGPDFContextMediaBox: Data(bytes: &box, count: MemoryLayout<CGRect>.size)] as CFDictionary)
            context.setFillColor(NSColor.red.cgColor); context.fill(CGRect(x: 0, y: 0, width: size.width / 2, height: size.height))
            context.setFillColor(NSColor.blue.cgColor); context.fill(CGRect(x: size.width / 2, y: 0, width: size.width / 2, height: size.height))
            context.endPDFPage()
        }
        context.closePDF()
        let pdf = try XCTUnwrap(PDFDocument(url: source))
        pdf.page(at: 0)?.rotation = firstRotation
        let output = root.appendingPathComponent(name + ".pdf")
        XCTAssertTrue(pdf.write(to: output))
        return output
    }

    private func convertedPackage(_ source: URL, name: String) throws -> URL {
        let output = try XCTUnwrap(DocumentEngine.convert(source, to: "pptx", options: .init(), token: .init()).first)
        let package = root.appendingPathComponent(name + " package", isDirectory: true)
        try ArchiveCodec.extract(output, into: package, token: .init())
        return package
    }

    private func number(_ xml: XMLDocument, _ path: String) throws -> Double {
        try XCTUnwrap(Double(try XCTUnwrap(xml.nodes(forXPath: path).first?.stringValue))) / 12_700
    }

    private func slideSize(_ package: URL) throws -> CGSize {
        let xml = try XMLDocument(contentsOf: package.appendingPathComponent("ppt/presentation.xml"), options: .nodeLoadExternalEntitiesNever)
        return CGSize(width: try number(xml, "//*[local-name()='sldSz']/@cx"), height: try number(xml, "//*[local-name()='sldSz']/@cy"))
    }

    private func imageFrame(_ package: URL, slide: Int) throws -> CGRect {
        let xml = try XMLDocument(contentsOf: package.appendingPathComponent("ppt/slides/slide\(slide).xml"), options: .nodeLoadExternalEntitiesNever)
        let base = "//*[local-name()='pic']/*[local-name()='spPr']/*[local-name()='xfrm']"
        return CGRect(x: try number(xml, base + "/*[local-name()='off']/@x"), y: try number(xml, base + "/*[local-name()='off']/@y"),
                      width: try number(xml, base + "/*[local-name()='ext']/@cx"), height: try number(xml, base + "/*[local-name()='ext']/@cy"))
    }

    private func embeddedImage(_ package: URL, slide: Int) throws -> NSBitmapImageRep {
        let folder = package.appendingPathComponent("ppt/slides", isDirectory: true)
        let xml = try XMLDocument(contentsOf: folder.appendingPathComponent("slide\(slide).xml"), options: .nodeLoadExternalEntitiesNever)
        let id = try XCTUnwrap(xml.nodes(forXPath: "//*[local-name()='blip']/@*[local-name()='embed']").first?.stringValue)
        let relationships = try XMLDocument(contentsOf: folder.appendingPathComponent("_rels/slide\(slide).xml.rels"), options: .nodeLoadExternalEntitiesNever)
        let target = try XCTUnwrap(relationships.nodes(forXPath: "//*[local-name()='Relationship' and @Id='\(id)']/@Target").first?.stringValue)
        return try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: folder.appendingPathComponent(target).standardizedFileURL)))
    }
}
