import AppKit
import SwiftUI
import AVFoundation
import NashiCore

/// Range clips share source time coordinates with the waveform and frame strip.
struct MediaTimeRangeLane:View {
    let duration:Double
    let current:Double
    var ranges:[TimeRange]
    var label:String
    var source:URL? = nil
    var thumbnails=false
    var onSeek:(Double)->Void
    var onChange:(Int,TimeRange)->Void
    var onAdd:((TimeRange)->Void)? = nil
    @State private var pending:TimeRange?
    var body:some View {
        GeometryReader { geometry in
            let scale=geometry.size.width/max(duration,0.001)
            ZStack(alignment:.topLeading) {
                RoundedRectangle(cornerRadius:6).fill(Color.primary.opacity(0.06))
                if thumbnails,let source { VideoThumbnailStrip(source:source,duration:duration) }
                ForEach(Array(ranges.enumerated()),id:\.offset) { index,range in
                    MediaRangeClip(label:label)
                        .frame(width:max(14,(range.end-range.start)*scale),height:geometry.size.height)
                        .offset(x:range.start*scale)
                }
                if let pending { Rectangle().fill(Color.nashi.opacity(0.3)).frame(width:max(1,(pending.end-pending.start)*scale)).offset(x:pending.start*scale) }
                Rectangle().fill(.white).frame(width:2).offset(x:min(geometry.size.width-2,max(0,current*scale))).allowsHitTesting(false)
            }.allowsHitTesting(false).accessibilityHidden(true)
                .overlay {
                    MediaRangeInteraction(duration:duration,ranges:ranges,label:label,onSeek:onSeek,onChange:onChange,onPending:{pending=$0},onAdd:onAdd)
                }.clipped().cornerRadius(6)
        }.frame(height:thumbnails ? 68:32)
    }
}

private struct MediaRangeClip:View {
    let label:String
    var body:some View {
        ZStack {
            RoundedRectangle(cornerRadius:5).fill(Color.nashi.opacity(0.25)).overlay(RoundedRectangle(cornerRadius:5).stroke(Color.nashi,lineWidth:2))
            LText(label).font(.caption2.bold()).foregroundStyle(.white).lineLimit(1).padding(.horizontal,10)
            HStack(spacing:0) { handle(start:true);Spacer(minLength:0);handle(start:false) }
        }
    }
    func handle(start:Bool)->some View {
        RoundedRectangle(cornerRadius:3).fill(Color.nashi).frame(width:12)
            .overlay(Capsule().fill(.white).frame(width:2,height:15))
            .accessibilityLabel(start ? "Range start":"Range end")
    }
}

struct VideoFrameThumbnail:View {
    let source:URL
    let time:Double
    @State private var thumbnail:NSImage?
    var body:some View {
        ZStack { Color.black;if let thumbnail { Image(nsImage:thumbnail).resizable().scaledToFill() } }
            .clipped().task(id:"\(source.path):\(time)") {
                let url=source,seconds=time
                let cg=await Task.detached(priority:.utility) { ()->CGImage? in
                    let generator=AVAssetImageGenerator(asset:AVURLAsset(url:url));generator.appliesPreferredTrackTransform=true;generator.maximumSize=CGSize(width:220,height:150)
                    return try? generator.copyCGImage(at:CMTime(seconds:max(0,seconds),preferredTimescale:60_000),actualTime:nil)
                }.value
                if !Task.isCancelled,let cg { thumbnail=NSImage(cgImage:cg,size:.zero) }
            }.accessibilityLabel("Frame at \(String(format:"%.2f",time)) seconds")
    }
}

struct VideoThumbnailStrip:View {
    let source:URL
    let duration:Double
    var body:some View {
        GeometryReader { geometry in
            let count=8
            HStack(spacing:0) { ForEach(0..<count,id:\.self) { index in VideoFrameThumbnail(source:source,time:duration*Double(index)/Double(count)).frame(width:geometry.size.width/Double(count),height:geometry.size.height) } }
        }.clipped()
    }
}

struct VideoPointTimeline:View {
    let source:URL
    let duration:Double
    let current:Double
    let points:[Double]
    var onSeek:(Double)->Void
    var onChange:(Int,Double)->Void
    var body:some View {
        GeometryReader { geometry in
            let scale=geometry.size.width/max(duration,0.001)
            ZStack(alignment:.topLeading) {
                VideoThumbnailStrip(source:source,duration:duration)
                Color.clear.contentShape(Rectangle()).gesture(DragGesture(minimumDistance:0).onChanged{onSeek(max(0,min(duration,$0.location.x/scale)))})
                ForEach(Array(points.enumerated()),id:\.offset) { index,time in
                    MediaPointMarker(time:time,duration:duration,scale:scale,onChange:{onChange(index,$0)}).offset(x:time*scale-4)
                }
                Rectangle().fill(.white).frame(width:2).offset(x:current*scale).allowsHitTesting(false)
            }.clipped().cornerRadius(6)
        }.frame(height:68)
    }
}

private struct MediaPointMarker:View {
    let time:Double
    let duration:Double
    let scale:CGFloat
    let onChange:(Double)->Void
    @State private var initial:Double?
    var body:some View {
        Rectangle().fill(Color.nashi).frame(width:8).overlay(Capsule().fill(.white).frame(width:2,height:15))
            .gesture(DragGesture(minimumDistance:0).onChanged { value in
                if initial==nil { initial=time };onChange(max(0.001,min(duration-0.001,(initial ?? time)+value.translation.width/scale)))
            }.onEnded { _ in initial=nil })
            .accessibilityLabel("Split at \(String(format:"%.2f",time)) seconds")
    }
}
