import XCTest
import CoreGraphics
@testable import NashiCore

final class AnnotationDrawingTests:XCTestCase {
    private let curve:[ImagePoint]=[.init(x:20,y:20),.init(x:50,y:80),.init(x:100,y:30)]
    private func draft(_ kind:ImageAnnotationKind,points:[ImagePoint]?=nil) throws -> ImageAnnotation {
        var style=ImageAnnotation(kind:kind,rect:.init(x:0,y:0,width:0,height:0))
        style.color="#FF0000";style.strokeWidth=6;style.text="Hello";style.fontSize=18
        return try XCTUnwrap(AnnotationDrawing.draft(style:style,points:points ?? curve))
    }
    func testFreehandAndHighlightKeepTheFullCurveAndItsBounds() throws {
        for kind in [ImageAnnotationKind.freehand,.highlight] {
            let item=try draft(kind)
            XCTAssertEqual(item.kind,kind);XCTAssertEqual(item.points.count,3)
            XCTAssertEqual(item.rect.x,20);XCTAssertEqual(item.rect.y,20)
            XCTAssertEqual(item.rect.width,80);XCTAssertEqual(item.rect.height,60)
        }
    }
    func testClosedFreehandLoopIsNotDiscardedWhenItsEndpointsMatch() throws {
        let points=curve+[curve[0]]
        let item=try draft(.freehand,points:points)
        XCTAssertEqual(item.points.count,4);XCTAssertEqual(item.rect.width,80);XCTAssertEqual(item.rect.height,60)
    }
    func testLinesAndArrowsUseOnlyTheTwoEndpoints() throws {
        for kind in [ImageAnnotationKind.line,.arrow] {
            let item=try draft(kind)
            XCTAssertEqual(item.points.count,2)
            XCTAssertEqual(item.points[0].x,20);XCTAssertEqual(item.points[1].x,100)
            XCTAssertEqual(item.points[1].y,30);XCTAssertEqual(item.rect.height,10)
        }
    }
    func testAreaToolsNeverStoreAFreehandTrail() throws {
        for kind in ImageAnnotationKind.allCases where ![.freehand,.highlight,.line,.arrow].contains(kind) {
            let item=try draft(kind)
            XCTAssertTrue(item.points.isEmpty,kind.rawValue)
            XCTAssertEqual(item.rect.width,80);XCTAssertEqual(item.rect.height,10)
        }
    }
    func testReverseDragNormalizesShapeBoundsButKeepsLineDirection() throws {
        let reverse=[ImagePoint(x:100,y:80),.init(x:20,y:30)]
        let rect=try draft(.rectangle,points:reverse),arrow=try draft(.arrow,points:reverse)
        XCTAssertEqual(rect.rect.x,20);XCTAssertEqual(rect.rect.y,30)
        XCTAssertEqual(rect.rect.width,80);XCTAssertEqual(rect.rect.height,50)
        XCTAssertEqual(arrow.points[0].x,100);XCTAssertEqual(arrow.points[1].x,20)
    }
    func testHorizontalAndVerticalStrokesAreValidButDegenerateShapesAreNot() throws {
        let horizontal=[ImagePoint(x:20,y:30),.init(x:100,y:30)]
        let vertical=[ImagePoint(x:20,y:30),.init(x:20,y:100)]
        for kind in [ImageAnnotationKind.freehand,.highlight,.line,.arrow] {
            _=try draft(kind,points:horizontal);_=try draft(kind,points:vertical)
        }
        let style=ImageAnnotation(kind:.rectangle,rect:.init(x:0,y:0,width:1,height:1))
        XCTAssertNil(AnnotationDrawing.draft(style:style,points:horizontal))
        XCTAssertNil(AnnotationDrawing.draft(style:style,points:vertical))
        XCTAssertNil(AnnotationDrawing.draft(style:style,points:[]))
        XCTAssertNil(AnnotationDrawing.draft(style:style,points:[.init(x:0,y:0),.init(x:.nan,y:50)]))
    }
    func testActiveStyleIsPreserved() throws {
        var style=try draft(.freehand)
        style.opacity=0.7;style.fontFamily="serif";style.number=7;style.fillColor="#0000FF"
        let item=try XCTUnwrap(AnnotationDrawing.draft(style:style,points:curve))
        XCTAssertEqual(item.color,"#FF0000");XCTAssertEqual(item.strokeWidth,6)
        XCTAssertEqual(item.opacity,0.7);XCTAssertEqual(item.fontFamily,"serif")
        XCTAssertEqual(item.number,7);XCTAssertEqual(item.fillColor,"#0000FF")
    }
    func testFreehandAndRectanglePaintOnlyTheirOwnGeometry() throws {
        let image=try white()
        var options=OperationOptions();options.imageAnnotations=[try draft(.freehand)]
        let freehand=try ImageEngine.annotatedImage(image,options:options)
        XCTAssertEqual(try pixel(freehand,x:50,y:80),[255,0,0])
        XCTAssertEqual(try pixel(freehand,x:100,y:20),[255,255,255],"No bounding rectangle may be painted")
        options.imageAnnotations=[try draft(.rectangle)]
        let rectangle=try ImageEngine.annotatedImage(image,options:options)
        XCTAssertEqual(try pixel(rectangle,x:20,y:25),[255,0,0])
        XCTAssertEqual(try pixel(rectangle,x:50,y:80),[255,255,255],"No marker trail may be painted")
    }
    func testStraightLineDoesNotFollowTheMouseDetour() throws {
        var options=OperationOptions();options.imageAnnotations=[try draft(.line)]
        let image=try ImageEngine.annotatedImage(white(),options:options)
        XCTAssertEqual(try pixel(image,x:60,y:25),[255,0,0])
        XCTAssertEqual(try pixel(image,x:50,y:80),[255,255,255])
    }
    private func white() throws -> CGImage {
        let ctx=try XCTUnwrap(CGContext(data:nil,width:160,height:120,bitsPerComponent:8,bytesPerRow:640,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(gray:1,alpha:1));ctx.fill(CGRect(x:0,y:0,width:160,height:120))
        return try XCTUnwrap(ctx.makeImage())
    }
    private func pixel(_ image:CGImage,x:Int,y:Int) throws -> [UInt8] {
        let crop=try XCTUnwrap(image.cropping(to:CGRect(x:x,y:y,width:1,height:1)))
        let ctx=try XCTUnwrap(CGContext(data:nil,width:1,height:1,bitsPerComponent:8,bytesPerRow:4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(crop,in:CGRect(x:0,y:0,width:1,height:1))
        return Array(UnsafeBufferPointer(start:try XCTUnwrap(ctx.data).assumingMemoryBound(to:UInt8.self),count:3))
    }
}
