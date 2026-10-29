import XCTest
@testable import NashiCore
final class HTMLResourceBoundaryTests:XCTestCase {
    func testRemoteOutsideAndUnquotedResourcesAreExcluded() throws {
        let fm=FileManager.default;let root=fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at:root,withIntermediateDirectories:true);defer{try? fm.removeItem(at:root)}
        let input=root.appendingPathComponent("test.html")
        try "<link href='file:///outside.css'><style>@import 'https://example.com/x.css';x{background:url(file:///private/data.png)}</style><img src=file:///private/data.png><img src='https://example.com/a.png'><img src=../outside.png>".write(to:input,atomically:true,encoding:.utf8)
        try DocumentEngine.embedHTMLImages(input,token:.init())
        let output=try String(contentsOf:input,encoding:.utf8)
        XCTAssertFalse(output.contains("file:"));XCTAssertFalse(output.contains("https:"));XCTAssertFalse(output.contains("../"));XCTAssertFalse(output.contains("<link"))
    }
}
