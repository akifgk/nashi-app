import XCTest
import ImageIO
@testable import NashiCore

final class YouTubeThumbnailTests:XCTestCase {
    private let source=URL(string:"https://i.ytimg.com/vi/mXS5W7_kdzk/hqdefault.jpg")!

    private func jpeg(_ width:Int,_ height:Int) throws -> Data {
        let context=try XCTUnwrap(CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:0,
                                          space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red:0.2,green:0.5,blue:0.8,alpha:1));context.fill(CGRect(x:0,y:0,width:width,height:height))
        let data=NSMutableData(),image=try XCTUnwrap(context.makeImage())
        let destination=try XCTUnwrap(CGImageDestinationCreateWithData(data,"public.jpeg" as CFString,1,nil))
        CGImageDestinationAddImage(destination,image,nil);XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    func testFeedPreviewUpgradesToRealMaxResolutionCover() async throws {
        let small=try jpeg(480,360),large=try jpeg(1280,720)
        let result=try await YouTubeThumbnail.resolve(source,token:.init()) { url in
            url.lastPathComponent=="maxresdefault.jpg" ? large:small
        }
        XCTAssertEqual(result?.url.lastPathComponent,"maxresdefault.jpg")
        XCTAssertEqual(result?.width,1280);XCTAssertEqual(result?.height,720)
    }

    func testSuccessfulPlaceholderResponseFallsBackToActualStandardImage() async throws {
        let small=try jpeg(480,360),placeholder=try jpeg(120,90),standard=try jpeg(640,480)
        let result=try await YouTubeThumbnail.resolve(source,token:.init()) { url in
            switch url.lastPathComponent {case "maxresdefault.jpg":return placeholder;case "sddefault.jpg":return standard;default:return small}
        }
        XCTAssertEqual(result?.url.lastPathComponent,"sddefault.jpg");XCTAssertEqual(result?.width,640)
    }

    func testAlreadyLargerSourceIsNeverDowngraded() async throws {
        let original=URL(string:"https://i.ytimg.com/vi_webp/mXS5W7_kdzk/hq720.webp?sqp=preview")!
        let large=try jpeg(1600,900),canonical=try jpeg(1280,720)
        let result=try await YouTubeThumbnail.resolve(original,token:.init()) { $0==original ? large:canonical }
        XCTAssertEqual(result?.url,original);XCTAssertEqual(result?.width,1600)
    }

    func testUnavailableAndNonImageVariantsKeepTheValidOriginal() async throws {
        let small=try jpeg(480,360)
        let result=try await YouTubeThumbnail.resolve(source,token:.init()) { url in
            if url==self.source { return small }
            if url.lastPathComponent=="maxresdefault.jpg" { throw URLError(.fileDoesNotExist) }
            return Data("not an image".utf8)
        }
        XCTAssertEqual(result?.url,source)
    }

    func testOtherImagesAndLookalikeHostsAreNotRewritten() async throws {
        for text in ["https://example.org/vi/mXS5W7_kdzk/a.jpg","https://i.ytimg.com.evil.example/vi/mXS5W7_kdzk/a.jpg","https://i.ytimg.com/vi/short/a.jpg","https://i.ytimg.com:8080/vi/mXS5W7_kdzk/a.jpg"] {
            let result=try await YouTubeThumbnail.resolve(URL(string:text)!,token:.init()) { _ in
                XCTFail("Unrelated URLs must not trigger thumbnail requests");return nil
            }
            XCTAssertNil(result)
        }
    }

    func testCancellationCannotReturnAPreviouslyFoundImage() async throws {
        let token=CancellationToken(),data=try jpeg(480,360)
        do {
            _=try await YouTubeThumbnail.resolve(source,token:token) { _ in token.cancel();return data }
            XCTFail("A cancelled inspection must not publish its result")
        } catch { XCTAssertTrue(token.isCancelled) }
    }

    func testOptInRealPreviewLinkDownloadsTheFullSizeImage() async throws {
        guard let text=ProcessInfo.processInfo.environment["NASHI_TEST_YOUTUBE_THUMBNAIL"] else { throw XCTSkip("Live public CDN check is opt-in") }
        let info=try await WebDownloadEngine.inspect(try WebDownloadEngine.link(text))
        XCTAssertEqual(info.kind,.image);XCTAssertEqual(info.imageWidth,1280);XCTAssertEqual(info.imageHeight,720)
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("Nashi-Thumbnail-Test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:folder)}
        let files=try await WebDownloadEngine.download(info,mode:.original,maximumHeight:nil,destination:folder,progress:{_,_ in})
        let file=try XCTUnwrap(files.first),image=try XCTUnwrap(CGImageSourceCreateWithURL(file as CFURL,nil))
        let properties=try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(image,0,nil) as? [CFString:Any])
        XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int,1280)
        XCTAssertEqual(properties[kCGImagePropertyPixelHeight] as? Int,720)
    }
}
