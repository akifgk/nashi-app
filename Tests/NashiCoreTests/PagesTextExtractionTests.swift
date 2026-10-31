import XCTest
import Foundation
@testable import NashiCore

/// DOCX -> Pages must carry every visible piece of Word text into the model.
final class PagesTextExtractionTests: XCTestCase {
    private var root: URL!
    private let namespaces = "xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\""

    override func setUpWithError() throws { root = try OutputFiles.temporaryDirectory() }
    override func tearDownWithError() throws { if let root { try? FileManager.default.removeItem(at: root) } }

    // F1540
    func testBlockLevelContentControlParagraphsAreKept() throws {
        let sdt = "<w:sdt><w:sdtPr><w:alias w:val=\"Cover\"/></w:sdtPr><w:sdtContent>\(paragraph("Cover title"))</w:sdtContent></w:sdt>"
        let cell = "<w:tbl><w:tr><w:tc><w:sdt><w:sdtContent>\(paragraph("Cell choice"))</w:sdtContent></w:sdt></w:tc></w:tr></w:tbl>"
        let model = try convert(body: sdt + paragraph("Body") + cell)
        XCTAssertEqual(paragraphTexts(model), ["Cover title", "Body"])
        XCTAssertEqual(cellTexts(model), ["Cell choice"])
    }

    // F1541
    func testRunsInsideInlineWrappersAreKept() throws {
        for wrapper in ["fldSimple", "customXml", "moveTo", "dir", "bdo"] {
            let body = "<w:p>\(run("Page "))<w:\(wrapper) w:val=\"rtl\">\(run("7"))</w:\(wrapper)></w:p>"
            XCTAssertEqual(paragraphTexts(try convert(body: body)), ["Page 7"], wrapper)
        }
    }

    private func run(_ text: String) -> String { "<w:r><w:t xml:space=\"preserve\">\(text)</w:t></w:r>" }
    private func paragraph(_ text: String) -> String { "<w:p>\(run(text))</w:p>" }

    private func paragraphTexts(_ model: [String: Any]) -> [String] {
        (model["blocks"] as? [[String: Any]] ?? []).filter { $0["type"] as? String != "table" }.map { ($0["runs"] as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }.joined() }
    }

    private func cellTexts(_ model: [String: Any]) -> [String] {
        (model["blocks"] as? [[String: Any]] ?? []).filter { $0["type"] as? String == "table" }.flatMap { ($0["rows"] as? [[[String: Any]]] ?? []).flatMap { $0.map { $0["text"] as? String ?? "" } } }
    }

    private func convert(body: String, sections: String = "", parts: [String: (String, String)] = [:]) throws -> [String: Any] {
        let package = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let word = package.appendingPathComponent("word", isDirectory: true)
        try FileManager.default.createDirectory(at: word.appendingPathComponent("_rels", isDirectory: true), withIntermediateDirectories: true)
        try "<w:document \(namespaces)><w:body>\(body)<w:sectPr>\(sections)</w:sectPr></w:body></w:document>".write(to: word.appendingPathComponent("document.xml"), atomically: true, encoding: .utf8)
        var relations = ""
        for (id, part) in parts {
            try "<w:\(part.0) \(namespaces)>\(part.1)</w:\(part.0)>".write(to: word.appendingPathComponent("\(id).xml"), atomically: true, encoding: .utf8)
            relations += "<Relationship Id=\"\(id)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/\(part.0 == "hdr" ? "header" : "footer")\" Target=\"\(id).xml\"/>"
        }
        try "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">\(relations)</Relationships>".write(to: word.appendingPathComponent("_rels/document.xml.rels"), atomically: true, encoding: .utf8)
        let input = package.appendingPathExtension("docx")
        try ArchiveCodec.create(from: package, at: input, format: "zip", token: .init())
        let output = package.appendingPathExtension("pages")
        try PagesCodec.create(fromDOCX: input, at: output, token: .init())
        return try PagesCodec.model(output, token: .init())
    }
}
