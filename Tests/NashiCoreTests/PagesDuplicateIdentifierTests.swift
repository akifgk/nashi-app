import XCTest
import Foundation
@testable import NashiCore

final class PagesDuplicateIdentifierTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = try OutputFiles.temporaryDirectory()
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    func testDuplicateStyleIdentifiersReturnErrorWithoutPublishing() throws {
        try assertRejected(
            fixture("Duplicate styles", styleIDs: ["Normal", "Normal"]),
            reason: "duplicate style identifiers"
        )
    }

    func testDuplicateRelationshipIdentifiersReturnErrorWithoutPublishing() throws {
        try assertRejected(
            fixture("Duplicate relationships", relationshipIDs: ["rId1", "rId1"]),
            reason: "duplicate relationship identifiers"
        )
    }

    func testDuplicateIdenticalRelationshipsAreAlsoRejected() throws {
        try assertRejected(
            fixture("Identical relationships", relationshipIDs: ["rId1", "rId1"], identicalTargets: true),
            reason: "duplicate relationship identifiers"
        )
    }

    func testUniqueIdentifiersStillProduceReadablePages() throws {
        let input = try fixture("Unique identifiers", styleIDs: ["Normal", "Heading1"], relationshipIDs: ["rId1", "rId2"])
        let original = try Data(contentsOf: input)
        var options = OperationOptions()
        options.outputDirectory = root.appendingPathComponent("Valid exports", isDirectory: true)
        let output = try XCTUnwrap(ConversionEngine.run(.init(inputs: [input], operation: .convert("pages"), options: options)).first)
        let model = try PagesCodec.model(output, token: .init())
        let blocks = try XCTUnwrap(model["blocks"] as? [[String: Any]])
        let runs = blocks.flatMap { $0["runs"] as? [[String: Any]] ?? [] }
        XCTAssertEqual(runs.compactMap { $0["text"] as? String }.joined(), "Unique identifiers keep this text Şişli")
        XCTAssertEqual(try Data(contentsOf: input), original)
    }

    func testInvalidAndOversizedTableSpansReturnErrorsWithoutPublishing() throws {
        for rawSpan in ["-9223372036854775808", "0", "-1", "1025", "9223372036854775807", "99999999999999999999", "not-a-number"] {
            let cell = "<w:tc><w:tcPr><w:gridSpan w:val=\"\(rawSpan)\"/></w:tcPr><w:p><w:r><w:t>Bad span</w:t></w:r></w:p></w:tc>"
            let input = try fixture("Bad span \(rawSpan)", body: "<w:tbl><w:tr>\(cell)\(cell)</w:tr></w:tbl>")
            try assertRejected(input, reason: "table cell span")
        }
    }

    func testTotalTableColumnsAreBoundedBeforeExpandingCells() throws {
        let cell = "<w:tc><w:tcPr><w:gridSpan w:val=\"600\"/></w:tcPr><w:p><w:r><w:t>Too wide</w:t></w:r></w:p></w:tc>"
        try assertRejected(fixture("Oversized row", body: "<w:tbl><w:tr>\(cell)\(cell)</w:tr></w:tbl>"), reason: "1024 columns")
    }

    func testValidMergedCellsRetainTextAndSpan() throws {
        let first = "<w:tc><w:tcPr><w:gridSpan w:val=\"2\"/></w:tcPr><w:p><w:r><w:t>Merged cell</w:t></w:r></w:p></w:tc>"
        let second = "<w:tc><w:p><w:r><w:t>Third column</w:t></w:r></w:p></w:tc>"
        let grid = "<w:tblGrid><w:gridCol w:w=\"2000\"/><w:gridCol w:w=\"2000\"/><w:gridCol w:w=\"2000\"/></w:tblGrid>"
        let input = try fixture("Valid merged table", body: "<w:tbl>\(grid)<w:tr>\(first)\(second)</w:tr></w:tbl>")
        let output = try XCTUnwrap(ConversionEngine.run(.init(inputs: [input], operation: .convert("pages"))).first)
        let model = try PagesCodec.model(output, token: .init())
        let blocks = try XCTUnwrap(model["blocks"] as? [[String: Any]])
        let table = try XCTUnwrap(blocks.first { $0["type"] as? String == "table" })
        let rows = try XCTUnwrap(table["rows"] as? [[[String: Any]]])
        XCTAssertEqual(rows.first?.count, 3)
        XCTAssertEqual(rows.first?.first?["text"] as? String, "Merged cell")
        XCTAssertEqual(rows.first?.last?["text"] as? String, "Third column")
        let merges = try XCTUnwrap(table["merges"] as? [[String: Any]])
        XCTAssertTrue(merges.contains { ($0["row"] as? Int) == 0 && ($0["column"] as? Int) == 0 && ($0["columnCount"] as? Int) == 2 })
    }

    private func assertRejected(_ input: URL, reason: String) throws {
        let original = try Data(contentsOf: input)
        let directory = root.appendingPathComponent(input.deletingPathExtension().lastPathComponent + " exports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let previous = directory.appendingPathComponent("Previous.pages")
        let previousBytes = Data("An existing export must remain unchanged".utf8)
        try previousBytes.write(to: previous)
        var options = OperationOptions()
        options.outputDirectory = directory
        XCTAssertThrowsError(try ConversionEngine.run(.init(inputs: [input], operation: .convert("pages"), options: options))) { error in
            XCTAssertTrue(error is NashiError)
            XCTAssertTrue(error.localizedDescription.contains(reason), error.localizedDescription)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).map(\.lastPathComponent), ["Previous.pages"])
        XCTAssertEqual(try Data(contentsOf: previous), previousBytes)
        XCTAssertEqual(try Data(contentsOf: input), original)
    }

    private func fixture(_ name: String, styleIDs: [String] = ["Normal"], relationshipIDs: [String] = ["rId1"], identicalTargets: Bool = false, body: String? = nil) throws -> URL {
        let package = root.appendingPathComponent(name + " package", isDirectory: true)
        let word = package.appendingPathComponent("word", isDirectory: true)
        let relationships = word.appendingPathComponent("_rels", isDirectory: true)
        try FileManager.default.createDirectory(at: relationships, withIntermediateDirectories: true)
        let content = body ?? "<w:p><w:pPr><w:pStyle w:val=\"Normal\"/></w:pPr><w:r><w:t>Unique identifiers keep this text Şişli</w:t></w:r></w:p>"
        let document = "<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:body>\(content)</w:body></w:document>"
        try document.write(to: word.appendingPathComponent("document.xml"), atomically: true, encoding: .utf8)
        let styles = styleIDs.map { "<w:style w:styleId=\"\($0)\"><w:name w:val=\"\($0)\"/></w:style>" }.joined()
        try "<w:styles xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\">\(styles)</w:styles>".write(to: word.appendingPathComponent("styles.xml"), atomically: true, encoding: .utf8)
        let relations = relationshipIDs.enumerated().map { index, id in
            "<Relationship Id=\"\(id)\" Target=\"media/image-\(identicalTargets ? 0 : index).png\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\"/>"
        }.joined()
        try "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">\(relations)</Relationships>".write(to: relationships.appendingPathComponent("document.xml.rels"), atomically: true, encoding: .utf8)
        let input = root.appendingPathComponent(name).appendingPathExtension("docx")
        try ArchiveCodec.create(from: package, at: input, format: "zip", token: .init())
        return input
    }
}
