import AppKit
import SwiftUI
import NashiCore

/// In-process replay of the production timeline and its native accessibility
/// actions. It never reads user files, posts global input or requests TCC.
@MainActor final class MediaRangeAccessibilitySmoke:NSObject,NSApplicationDelegate {
    private let output:URL
    private var window:NSWindow?
    private var checks:[String]=[]
    private let keepOpen:Bool
    init(output:URL,keepOpen:Bool=CommandLine.arguments.contains("--keep-range-open")) { self.output=output;self.keepOpen=keepOpen }
    func applicationDidFinishLaunching(_ notification:Notification) {
        Task {
            var failure:String?
            do {try await run()}catch{failure=String(describing:error)}
            let result:[String:Any]=["passed":failure == nil,"checks":checks,"error":failure as Any? ?? NSNull(),"scope":"Own-window production timeline, semantic start/end slider actions, bounded values and direct native pointer-handler regression. No global input, user files, clipboard, TCC or external assistive-technology client."]
            if let data=try? JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]) {try? data.write(to:output.appendingPathComponent("mac-range-accessibility.json"))}
            if failure == nil && keepOpen {window?.title="Nashi Range Accessibility QA — Passed";return}
            window?.close();exit(failure == nil ? 0:1)
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool {true}
    private func check(_ valid:Bool,_ label:String)throws {
        guard valid else{throw NSError(domain:"Nashi Range Accessibility QA",code:1,userInfo:[NSLocalizedDescriptionKey:label])}
        checks.append(label)
    }
    private func near(_ a:Double,_ b:Double)->Bool {abs(a-b)<0.000_001}
    private func pause()async {try? await Task.sleep(nanoseconds:80_000_000)}
    private func findLane(_ view:NSView)->MediaRangeInteraction.LaneView? {
        if let lane=view as? MediaRangeInteraction.LaneView{return lane}
        return view.subviews.lazy.compactMap{self.findLane($0)}.first
    }
    private func capture()throws {
        guard let view=window?.contentView else{return}
        view.layoutSubtreeIfNeeded()
        guard let rep=view.bitmapImageRepForCachingDisplay(in:view.bounds) else{return}
        view.cacheDisplay(in:view.bounds,to:rep)
        if let data=rep.representation(using:.png,properties:[:]) {try data.write(to:output.appendingPathComponent("mac-range-accessibility.png"))}
    }
    private func pointer(_ lane:MediaRangeInteraction.LaneView,from:Double,to:Double)throws {
        guard let window=lane.window else{throw NSError(domain:"Nashi Range Accessibility QA",code:2)}
        func event(_ type:NSEvent.EventType,_ x:Double)->NSEvent {
            NSEvent.mouseEvent(with:type,location:lane.convert(NSPoint(x:x,y:lane.bounds.midY),to:nil),modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:window.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1)!
        }
        lane.mouseDown(with:event(.leftMouseDown,from))
        lane.mouseDragged(with:event(.leftMouseDragged,to))
        lane.mouseUp(with:event(.leftMouseUp,to))
    }
    private func run()async throws {
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        let fixture=RangeFixture()
        let w=NSWindow(contentRect:NSRect(x:120,y:100,width:448,height:180),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        w.title="Nashi Range Accessibility QA";w.isReleasedWhenClosed=false
        w.contentView=NSHostingView(rootView:RangeFixtureView(fixture:fixture).preferredColorScheme(.dark))
        window=w;w.makeKeyAndOrderFront(nil);await pause();await pause()
        guard let content=w.contentView,let lane=findLane(content) else{throw NSError(domain:"Nashi Range Accessibility QA",code:3,userInfo:[NSLocalizedDescriptionKey:"Production timeline did not mount"])}
        func endpoints()->[RangeEndpointAccessibilityElement] {lane.accessibilityChildren() as? [RangeEndpointAccessibilityElement] ?? []}
        let children=endpoints()
        try check(lane.accessibilityIdentifier()=="media.range.timeline" && lane.accessibilityRole() == .group,"Production timeline exposes a stable semantic group")
        try check(children.count==2,"One selected range exposes independent start and end controls")
        let start=children[0],end=children[1]
        try check(start.accessibilityIdentifier()=="media.range.0.start" && end.accessibilityIdentifier()=="media.range.0.end","Start and end controls have stable accessibility identifiers")
        try check(children.allSatisfy{$0.accessibilityRole() == .slider && $0.isAccessibilityEnabled()},"Both endpoints expose enabled native slider roles")
        try check(start.accessibilityLabel()==L10n.text("Start") && end.accessibilityLabel()==L10n.text("End"),"Endpoint names follow the app language")
        try check(!start.accessibilityFrame().isEmpty && !end.accessibilityFrame().isEmpty,"Both endpoint frames identify the painted handles in screen coordinates")
        try check(near((start.accessibilityMinValue() as? NSNumber)?.doubleValue ?? -1,0) && near((start.accessibilityMaxValue() as? NSNumber)?.doubleValue ?? -1,7.98),"Start exposes the current opposite-edge bound")
        try check(near((end.accessibilityMinValue() as? NSNumber)?.doubleValue ?? -1,2.02) && near((end.accessibilityMaxValue() as? NSNumber)?.doubleValue ?? -1,10),"End exposes the current opposite-edge bound")
        try check(start.accessibilityPerformIncrement(),"Start supports the native increment action")
        await pause()
        try check(near(fixture.ranges[0].start,2.1) && near(fixture.ranges[0].end,8),"Increment moves only Start through the production callback")
        try check(end.accessibilityPerformDecrement(),"End supports the native decrement action")
        await pause()
        try check(near(fixture.ranges[0].start,2.1) && near(fixture.ranges[0].end,7.9),"Decrement moves only End through the production callback")
        try check(endpoints()[0] === start && endpoints()[1] === end,"Value updates preserve endpoint identity and assistive focus")
        start.setAccessibilityValue(NSNumber(value:9));await pause()
        try check(near(fixture.ranges[0].start,7.88) && near(fixture.ranges[0].end,7.9),"Setting Start beyond End clamps to the minimum span without moving End")
        start.setAccessibilityValue(NSNumber(value:-100));await pause()
        try check(near(fixture.ranges[0].start,0),"Start cannot move before the source")
        let beforeBoundary=fixture.changeCount
        try check(!start.accessibilityPerformDecrement() && fixture.changeCount==beforeBoundary,"A boundary action is a no-op without a duplicate callback")
        end.setAccessibilityValue(NSNumber(value:-1));await pause()
        try check(near(fixture.ranges[0].end,0.02) && near(fixture.ranges[0].start,0),"End cannot cross Start or collapse the selected range")
        end.setAccessibilityValue(NSNumber(value:100));await pause()
        try check(near(fixture.ranges[0].end,10),"End cannot move beyond the source duration")
        start.setAccessibilityValue("6,250");await pause()
        try check(near(fixture.ranges[0].start,6.25) && near(fixture.ranges[0].end,10),"A numeric accessibility value uses the same bounded callback")
        let beforeInvalid=fixture.changeCount
        start.setAccessibilityValue(NSNumber(value:Double.nan));end.setAccessibilityValue(NSNumber(value:Double.infinity));start.setAccessibilityValue("invalid")
        try check(fixture.changeCount==beforeInvalid,"Non-finite and invalid accessibility values are ignored")
        fixture.enabled=false;await pause()
        let beforeDisabled=fixture.changeCount
        start.setAccessibilityValue(NSNumber(value:1))
        try check(!start.isAccessibilityEnabled() && !start.accessibilityPerformIncrement() && fixture.changeCount==beforeDisabled,"Disabled timelines block both set and adjustment actions")
        try check(!start.isAccessibilitySelectorAllowed(NSSelectorFromString("setAccessibilityValue:")),"Disabled endpoints advertise a read-only accessibility value")
        fixture.enabled=true;fixture.ranges=[TimeRange(start:1,end:3),TimeRange(start:6,end:9)];await pause()
        let multiple=endpoints()
        try check(multiple.count==4 && multiple[2].accessibilityIdentifier()=="media.range.1.start" && multiple[3].accessibilityIdentifier()=="media.range.1.end","Multiple ranges expose separately identified endpoints")
        try check(multiple[2].accessibilityPerformIncrement(),"A later range can be adjusted independently")
        await pause()
        try check(near(fixture.ranges[1].start,6.1) && fixture.ranges[0]==TimeRange(start:1,end:3),"Adjusting a later range leaves the first range unchanged")
        let removed=multiple[3]
        fixture.ranges=[TimeRange(start:2,end:8)];await pause()
        try check(endpoints().count==2 && !removed.accessibilityPerformIncrement(),"Removed endpoints are detached and stale actions are safe")
        fixture.duration=0;await pause()
        try check(endpoints().isEmpty && !start.accessibilityPerformIncrement(),"An unavailable duration exposes no editable endpoints")
        fixture.duration=0.01;fixture.ranges=[TimeRange(start:0,end:0.01)];await pause()
        let tiny=endpoints()
        try check(tiny.count==2 && !tiny[0].accessibilityPerformIncrement() && !tiny[1].accessibilityPerformDecrement(),"Sub-frame sources keep valid independent bounds")
        fixture.duration=10;fixture.ranges=[TimeRange(start:2,end:8)];await pause()
        let width=Double(lane.bounds.width)
        try pointer(lane,from:width*0.8-6,to:width*0.9-6);await pause()
        try check(near(fixture.ranges[0].start,2) && near(fixture.ranges[0].end,9),"Existing native pointer drag still resizes End without rebasing")
        fixture.ranges=[TimeRange(start:2,end:8)];await pause()
        try pointer(lane,from:width*0.4,to:width*0.5);await pause()
        try check(near(fixture.ranges[0].start,3) && near(fixture.ranges[0].end,9),"Existing native pointer drag still moves the full range")
        fixture.ranges=[TimeRange(start:2,end:8)];await pause();try capture()
    }
}

@MainActor private final class RangeFixture:ObservableObject {
    @Published var duration=10.0
    @Published var ranges=[TimeRange(start:2,end:8)]
    @Published var enabled=true
    private(set) var changeCount=0
    func change(_ index:Int,_ range:TimeRange) {guard ranges.indices.contains(index) else{return};ranges[index]=range;changeCount+=1}
}
private struct RangeFixtureView:View {
    @ObservedObject var fixture:RangeFixture
    var body:some View {
        VStack(alignment:.leading,spacing:20) {
            Text("Trim · semantic Start and End").font(.headline)
            MediaTimeRangeLane(duration:fixture.duration,current:0,ranges:fixture.ranges,label:"Trim",onSeek:{_ in},onChange:fixture.change)
                .disabled(!fixture.enabled)
            Text(String(format:"%.3f – %.3f seconds",fixture.ranges.first?.start ?? 0,fixture.ranges.first?.end ?? 0)).font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(width:448,height:180)
    }
}
