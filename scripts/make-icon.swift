import AppKit

@main struct MakeNashiIcon {
    static func main() throws {
        let output=URL(fileURLWithPath:CommandLine.arguments[1]);try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        func bitmap(_ width:Int,_ height:Int,_ draw:(NSRect)->Void)->NSBitmapImageRep {
            let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:width,pixelsHigh:height,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
            NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:rep);draw(NSRect(x:0,y:0,width:width,height:height));NSGraphicsContext.restoreGraphicsState();return rep
        }
        for happy in [false,true] { let mark=bitmap(256,256) { rect in NashiArtwork.draw(in:rect,happy:happy) };try mark.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent(happy ? "NashiMarkHappy.png":"NashiMark.png")) }
        let icon=bitmap(1024,1024) { _ in
            let background=NSBezierPath(roundedRect:NSRect(x:48,y:48,width:928,height:928),xRadius:205,yRadius:205)
            NSGradient(starting:NSColor(srgbRed:0.19,green:0.29,blue:0.21,alpha:1),ending:NSColor(srgbRed:0.07,green:0.15,blue:0.10,alpha:1))!.draw(in:background,angle:-90)
            NashiArtwork.draw(in:NSRect(x:125,y:90,width:774,height:824),happy:true)
        }
        let png=icon.representation(using:.png,properties:[:])!;try png.write(to:output.appendingPathComponent("NashiIcon.png"))
        let iconset=output.appendingPathComponent("NashiIcon.iconset");try FileManager.default.createDirectory(at:iconset,withIntermediateDirectories:true)
        let image=NSImage(data:png)!
        for size in [16,32,128,256,512] { for factor in [1,2] {
            let pixels=size*factor;let rep=bitmap(pixels,pixels) { rect in NSGraphicsContext.current?.imageInterpolation = .high;image.draw(in:rect) }
            try rep.representation(using:.png,properties:[:])!.write(to:iconset.appendingPathComponent("icon_\(size)x\(size)\(factor==2 ? "@2x":"").png"))
        } }
        let banner=bitmap(1280,640) { rect in
            NSColor(srgbRed:0.976,green:0.965,blue:0.930,alpha:1).setFill();rect.fill()
            NashiArtwork.draw(in:NSRect(x:75,y:115,width:390,height:410),happy:true)
            let font=NSFont.systemFont(ofSize:118,weight:.bold);let rounded=NSFont(descriptor:font.fontDescriptor.withDesign(.rounded)!,size:118)!
            ("Nashi" as NSString).draw(at:NSPoint(x:515,y:315),withAttributes:[.font:rounded,.foregroundColor:NSColor(srgbRed:0.17,green:0.27,blue:0.19,alpha:1)])
            ("Your files, a little sweeter." as NSString).draw(at:NSPoint(x:523,y:265),withAttributes:[.font:NSFont.systemFont(ofSize:32,weight:.medium),.foregroundColor:NSColor(srgbRed:0.30,green:0.40,blue:0.29,alpha:1)])
            ("Convert. Edit. Organize. Download." as NSString).draw(at:NSPoint(x:523,y:208),withAttributes:[.font:NSFont.systemFont(ofSize:23),.foregroundColor:NSColor(srgbRed:0.43,green:0.47,blue:0.39,alpha:1)])
        }
        try banner.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent("NashiSocial.png"))
        print(output.path)
    }
}
