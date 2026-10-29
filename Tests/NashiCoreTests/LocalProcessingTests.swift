import XCTest
@testable import NashiCore

final class LocalProcessingTests:XCTestCase {
    func testMediaInputRejectsRemoteNestedResourcesBeforeFetching() throws {
        let folder=try OutputFiles.temporaryDirectory();defer { try? FileManager.default.removeItem(at:folder) }
        let file=folder.appendingPathComponent("external.m3u8")
        try Data("#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:2\n#EXT-X-MEDIA-SEQUENCE:0\n#EXTINF:1.0,\nhttp://127.0.0.1:9/not-fetched.aac\n#EXT-X-ENDLIST\n".utf8).write(to:file)
        for program in ["ffmpeg","ffprobe"] {
            let args=program=="ffmpeg" ? ["-v","error","-i",file.path,"-f","null","-"]:["-v","error","-show_format",file.path]
            XCTAssertThrowsError(try ProcessRunner.run(Dependencies.executable(program),args)) { error in
                XCTAssertTrue(error.localizedDescription.contains("not on whitelist"),error.localizedDescription)
            }
        }
    }
    func testXMPRejectsDocumentTypesAndExternalEntities() throws {
        let input=Data("<!DOCTYPE x:xmpmeta [<!ENTITY private SYSTEM 'file:///not-read'>]><x:xmpmeta xmlns:x='adobe:ns:meta/'/>".utf8)
        XCTAssertThrowsError(try XMPPacketEditor.fields(input))
        XCTAssertThrowsError(try XMPPacketEditor.edit(input,updates:["{XMP-dc}.Title":"Value"],removals:[]))
    }
}
