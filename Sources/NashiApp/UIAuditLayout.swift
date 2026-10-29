import SwiftUI
import AppKit

/// Explicit QA only. No geometry readers or preference traffic in normal UI.
private struct UIAuditEnabledKey: EnvironmentKey { static let defaultValue=false }
extension EnvironmentValues {
    var uiAuditEnabled:Bool { get { self[UIAuditEnabledKey.self] } set { self[UIAuditEnabledKey.self]=newValue } }
}
private struct UIAuditFramesKey:PreferenceKey {
    static let defaultValue:[String:CGRect]=[:]
    static func reduce(value:inout [String:CGRect],nextValue:()->[String:CGRect]) { value.merge(nextValue(),uniquingKeysWith:{$1}) }
}
private struct UIAuditStatusKey:PreferenceKey {
    static let defaultValue="ready"
    static func reduce(value:inout String,nextValue:()->String) { value=nextValue() }
}
private struct UIAuditProbe:ViewModifier {
    @Environment(\.uiAuditEnabled) private var enabled
    let id:String
    @ViewBuilder func body(content:Content)->some View {
        if enabled { content.background(GeometryReader { proxy in Color.clear.preference(key:UIAuditFramesKey.self,value:[id:proxy.frame(in:.named("nashi.ui-audit"))]) }) }
        else { content }
    }
}
private struct UIAuditStatus:ViewModifier {
    @Environment(\.uiAuditEnabled) private var enabled
    let value:String
    @ViewBuilder func body(content:Content)->some View {
        if enabled { content.preference(key:UIAuditStatusKey.self,value:value) }else{content}
    }
}
@MainActor final class UIAuditLayout {
    var frames:[String:CGRect]=[:]
    var status="waiting"
    func issues(in bounds:CGRect,editor:Bool)->[String] {
        guard [bounds.minX,bounds.minY,bounds.width,bounds.height].allSatisfy({$0.isFinite}),bounds.width>0,bounds.height>0 else{return ["Invalid visible content bounds"]}
        var issues:[String]=[]
        let tolerance:CGFloat=1
        let outer=bounds.insetBy(dx:-tolerance,dy:-tolerance)
        if editor {
            for name in ["editor.header","editor.body","editor.preview","editor.options","editor.footer","editor.primary","editor.primary.label","editor.reset"] where frames[name]==nil { issues.append("Missing layout probe: "+name) }
        }
        for (name,frame) in frames {
            guard [frame.minX,frame.minY,frame.width,frame.height].allSatisfy({$0.isFinite}),frame.width>0,frame.height>0 else { issues.append("Invalid layout frame: "+name);continue }
            if !outer.contains(frame) { issues.append("Outside visible content: "+name) }
        }
        if let footer=frames["editor.footer"] {
            for name in ["editor.primary","editor.reset"] {if let rect=frames[name],!footer.insetBy(dx:-1,dy:-1).contains(rect){issues.append("Footer control is clipped: "+name)}}
        }
        if let button=frames["editor.primary"],let label=frames["editor.primary.label"] {
            if abs(button.midX-label.midX)>1 || abs(button.midY-label.midY)>1 { issues.append("Primary button label is not centered") }
            if !button.insetBy(dx:-1,dy:-1).contains(label) { issues.append("Primary button label is clipped") }
        }
        if let primary=frames["editor.primary"],let reset=frames["editor.reset"],primary.intersects(reset) { issues.append("Footer controls overlap") }
        if let header=frames["editor.header"],let footer=frames["editor.footer"],header.intersects(footer) { issues.append("Header and footer overlap") }
        if let body=frames["editor.body"] {
            for name in ["editor.preview","editor.options"] {if let rect=frames[name],!body.insetBy(dx:-tolerance,dy:-tolerance).contains(rect){issues.append("Body region is clipped: "+name)}}
            for name in ["editor.header","editor.footer"] {if let rect=frames[name],body.intersects(rect){issues.append("Body overlaps: "+name)}}
        }
        return issues.sorted()
    }
    var jsonFrames:[String:[String:Double]] {
        frames.mapValues { r in ["x":r.minX,"y":r.minY,"width":r.width,"height":r.height].mapValues { $0.isFinite ? Double($0):0 } }
    }
}
extension View {
    func uiAuditProbe(_ id:String)->some View { modifier(UIAuditProbe(id:id)) }
    func uiAuditStatus(_ value:String)->some View { modifier(UIAuditStatus(value:value)) }
    @MainActor func uiAuditRoot(_ recorder:UIAuditLayout)->some View {
        self.environment(\.uiAuditEnabled,true).coordinateSpace(name:"nashi.ui-audit")
            .onPreferenceChange(UIAuditFramesKey.self){recorder.frames=$0}
            .onPreferenceChange(UIAuditStatusKey.self){recorder.status=$0}
    }
}

/// A bounded sample catches clear/flat cacheDisplay captures without walking a
/// full-resolution Retina bitmap. Text rendering quality still needs visual QA.
struct UIAuditRaster {
    let samples:Int
    let visibleSamples:Int
    let colors:Int
    var nonBlank:Bool {visibleSamples>100 && colors>=3}
    static func inspect(_ bitmap:NSBitmapImageRep)->Self {
        let width=bitmap.pixelsWide,height=bitmap.pixelsHigh
        guard width>0,height>0,let image=bitmap.cgImage else{return Self(samples:0,visibleSamples:0,colors:0)}
        let columns=min(64,width),rows=min(64,height)
        var pixels=[UInt8](repeating:0,count:columns*rows*4)
        let rendered=pixels.withUnsafeMutableBytes { bytes->Bool in
            guard let context=CGContext(data:bytes.baseAddress,width:columns,height:rows,bitsPerComponent:8,bytesPerRow:columns*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else{return false}
            context.interpolationQuality = .low
            context.draw(image,in:CGRect(x:0,y:0,width:columns,height:rows))
            return true
        }
        guard rendered else{return Self(samples:0,visibleSamples:0,colors:0)}
        var visible=0,colors=Set<UInt32>()
        for offset in stride(from:0,to:pixels.count,by:4) where pixels[offset+3]>0 {
            visible+=1
            if colors.count<64 {colors.insert(UInt32(pixels[offset]) | UInt32(pixels[offset+1])<<8 | UInt32(pixels[offset+2])<<16 | UInt32(pixels[offset+3])<<24)}
        }
        return Self(samples:columns*rows,visibleSamples:visible,colors:colors.count)
    }
}
