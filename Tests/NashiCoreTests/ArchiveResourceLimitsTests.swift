import XCTest
@testable import NashiCore
final class ArchiveResourceLimitsTests:XCTestCase {
    func testEntryAndExpandedByteLimits() throws {
        let manager=FileManager.default
        let root=manager.temporaryDirectory.appendingPathComponent(UUID().uuidString,isDirectory:true)
        try manager.createDirectory(at:root,withIntermediateDirectories:false)
        defer{try? manager.removeItem(at:root)}
        let source=root.appendingPathComponent("source",isDirectory:true)
        try manager.createDirectory(at:source,withIntermediateDirectories:false)
        try Data(repeating:65,count:100).write(to:source.appendingPathComponent("data.txt"))
        try Data([1]).write(to:source.appendingPathComponent("another.txt"))
        let archive=root.appendingPathComponent("test.zip")
        try ArchiveCodec.create(from:source,at:archive,format:"zip",token:.init())
        XCTAssertThrowsError(try ArchiveCodec.extract(archive,into:root.appendingPathComponent("bytes"),token:.init(),limits:.init(maximumEntries:10,maximumBytes:50)))
        XCTAssertThrowsError(try ArchiveCodec.extract(archive,into:root.appendingPathComponent("entries"),token:.init(),limits:.init(maximumEntries:1,maximumBytes:1000)))
        try ArchiveCodec.extract(archive,into:root.appendingPathComponent("valid"),token:.init())
        XCTAssertEqual(try Data(contentsOf:root.appendingPathComponent("valid/data.txt")).count,100)
    }
}
