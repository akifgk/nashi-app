import XCTest
import PDFKit
@testable import NashiCore

final class PDFPageEditorStateTests:XCTestCase {
    private func document(pages:Int)->PDFDocument {
        let document=PDFDocument()
        for index in 0..<pages { document.insert(PDFPage(),at:index) }
        return document
    }
    func testResetAfterDuplicatingClearsOutOfRangeSelection() {
        let original=document(pages:2)
        var editor=PDFPageEditorState();editor.reset(document:original)
        editor.select(1);editor.duplicateSelected();editor.select(2);editor.duplicateSelected();editor.select(3)
        XCTAssertEqual(editor.pages.count,4)
        editor.reset(document:original)
        XCTAssertNil(editor.selectedPage)
        editor.rotateSelected();editor.duplicateSelected();editor.deleteSelected();editor.moveSelected(by:-1)
        XCTAssertEqual(editor.pages.count,2)
        XCTAssertEqual(editor.sourceIndexes,[0,1])
        XCTAssertEqual(editor.pages.map(\.rotation),[0,0])
    }
    func testReorderingKeepsSourceAndRotationAttachedToEachPage() {
        var editor=PDFPageEditorState();editor.reset(document:document(pages:3))
        editor.select(1);editor.rotateSelected();editor.duplicateSelected();editor.select(2);editor.moveSelected(by:1)
        XCTAssertEqual(editor.sourceIndexes,[0,1,2,1])
        XCTAssertEqual(editor.rotations,[0:0,1:90,2:0,3:90])
        editor.deleteSelected()
        XCTAssertEqual(editor.sourceIndexes,[0,1,2])
        XCTAssertNil(editor.selectedPage)
    }
    func testInvalidSelectionAndDocumentReplacementCannotMutateOtherPages() {
        var editor=PDFPageEditorState();editor.reset(document:document(pages:1))
        editor.select(Int.max);editor.rotateSelected();editor.duplicateSelected();editor.deleteSelected();editor.moveSelected(by:1)
        XCTAssertNil(editor.selectedPage)
        editor.select(0);editor.deleteSelected();editor.moveSelected(by:-1);editor.moveSelected(by:1)
        XCTAssertEqual(editor.pages.count,1)
        editor.reset()
        XCTAssertTrue(editor.pages.isEmpty)
        XCTAssertTrue(editor.sourceIndexes.isEmpty)
        XCTAssertFalse(editor.hasSelection)
    }
}
