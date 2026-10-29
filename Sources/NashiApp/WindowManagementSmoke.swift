import AppKit
import ApplicationServices
import NashiCore
import Darwin

/// Explicit, opt-in native input verification. Only a separately launched Nashi fixture is moved.
/// The normal app never enters this path or synthesizes input.
@MainActor final class WindowManagementSmokeDelegate:NSObject,NSApplicationDelegate {
    private let managerPID:pid_t
    private let output:URL
    private var fixture:NSRunningApplication?
    private var fixtureWindow:AXUIElement?
    private var log:[[String:Any]]=[]
    private let source=CGEventSource(stateID:.hidSystemState)
    private var point=CGPoint.zero
    private var mouseDown=false
    private var heldKey:CGKeyCode?
    private var interrupted=false
    private var signals:[DispatchSourceSignal]=[]
    private var originalPointer:CGPoint?
    private var minimumWidth:CGFloat {
        guard let index=CommandLine.arguments.firstIndex(of:"--minimum-window-width"),index+1<CommandLine.arguments.count,
              let value=Double(CommandLine.arguments[index+1]),value.isFinite else{return 160}
        return min(1200,max(160,value))
    }
    private struct Failure:Error,CustomStringConvertible { let description:String }

    init(managerPID:pid_t,output:URL) { self.managerPID=managerPID;self.output=output }
    func applicationDidFinishLaunching(_ notification:Notification) {
        for value in [SIGTERM,SIGINT] {
            signal(value,SIG_IGN)
            let handler=DispatchSource.makeSignalSource(signal:value,queue:.main)
            handler.setEventHandler { [weak self] in self?.interrupted=true };handler.resume();signals.append(handler)
        }
        Task {
            var result:Int32=0
            do { try await run();try save(passed:true,error:nil) }
            catch { result=1;try? save(passed:false,error:String(describing:error)) }
            cleanup();exit(result)
        }
    }
    private func require(_ value:Bool,_ reason:String)throws { if !value { throw Failure(description:reason) } }
    private func pause(_ milliseconds:UInt64)async throws { try await Task.sleep(nanoseconds:milliseconds*1_000_000);try require(!interrupted,"Native test was interrupted; input was released.") }
    private func run()async throws {
        try require(AXIsProcessTrusted()&&CGPreflightPostEventAccess(),"Nashi needs its own \(WindowManagementController.permissionName) permission; no input was posted.")
        try require(NSEvent.pressedMouseButtons==0&&CGEventSource.flagsState(.combinedSessionState).intersection([.maskCommand,.maskShift,.maskControl,.maskAlternate]).isEmpty,"Release the mouse and modifiers before testing.")
        originalPointer=CGEvent(source:nil)?.location
        let own=Bundle.main.executableURL?.standardizedFileURL
        guard let manager=NSRunningApplication(processIdentifier:managerPID) else { throw Failure(description:"The selected Nashi manager is not running.") }
        try require(managerPID != ProcessInfo.processInfo.processIdentifier&&manager.executableURL?.standardizedFileURL==own,"The manager must be the same installed Nashi executable.")
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        let configuration=NSWorkspace.OpenConfiguration();configuration.arguments=["--window-management-fixture","--minimum-window-width",String(Double(minimumWidth))];configuration.createsNewApplicationInstance=true;configuration.activates=false
        fixture=try await NSWorkspace.shared.openApplication(at:Bundle.main.bundleURL,configuration:configuration)
        guard let fixture else { throw Failure(description:"Fixture did not launch.") }
        try require(fixture.executableURL?.standardizedFileURL==own,"Fixture executable differs from installed Nashi.")
        let app=AXUIElementCreateApplication(fixture.processIdentifier);AXUIElementSetMessagingTimeout(app,0.2)
        for _ in 0..<40 {
            let windows=WindowManagementController.attribute(app,kAXWindowsAttribute) as? [AXUIElement] ?? []
            fixtureWindow=windows.first { WindowManagementController.attribute($0,kAXTitleAttribute) as? String == "Nashi Window Layout Fixture" }
            if fixtureWindow != nil { break };try await pause(100)
        }
        guard let window=fixtureWindow,let screen=NSScreen.screens.first else { throw Failure(description:"The exact disposable fixture window is unavailable.") }
        AXUIElementSetMessagingTimeout(window,0.2)
        for (index,placement) in WindowPlacement.allCases.enumerated() {
            try await gesture(window:window,placement:placement,index:index,screen:screen,cancel:false)
        }
        try await gesture(window:window,placement:.rightHalf,index:4,screen:screen,cancel:false,resize:true)
        try await gesture(window:window,placement:.leftHalf,index:3,screen:screen,cancel:true)
    }
    private func gesture(window:AXUIElement,placement:WindowPlacement,index:Int,screen:NSScreen,cancel:Bool,resize:Bool=false)async throws {
        guard let fixture,!fixture.isTerminated else { throw Failure(description:"Fixture exited.") }
        let work=screen.visibleFrame
        let initial=CGRect(x:work.minX+70,y:work.midY-210,width:min(max(620,minimumWidth),work.width-140),height:420)
        try require(WindowManagementController.setFrame(initial,of:window),"Fixture could not be prepared.")
        fixture.activate(options:[.activateIgnoringOtherApps]);try await pause(200)
        guard let frame=WindowManagementController.frame(of:window) else { throw Failure(description:"Fixture bounds are unavailable.") }
        let start=resize ? CGPoint(x:frame.maxX-3,y:frame.maxY-3):CGPoint(x:frame.midX,y:frame.minY+14)
        var hit:AXUIElement?
        let system=AXUIElementCreateSystemWide();AXUIElementSetMessagingTimeout(system,0.2)
        try require(AXUIElementCopyElementAtPosition(system,Float(start.x),Float(start.y),&hit) == .success,"Fixture drag origin cannot be hit-tested.")
        var hitPID:pid_t=0;if let hit { _=AXUIElementGetPid(hit,&hitPID) }
        try require(hitPID==fixture.processIdentifier,"Fixture is covered by another app; no input was posted.")
        let command=index%2 != 0,key:CGKeyCode=command ? 55:56,flags:CGEventFlags=command ? .maskCommand:.maskShift
        defer { releaseInput() }
        mouse(.mouseMoved,start);mouse(.leftMouseDown,start);mouseDown=true;try await pause(100)
        for step in 1...6 { mouse(.leftMouseDragged,CGPoint(x:start.x+CGFloat(step)*5,y:start.y+CGFloat(step)*3));try await pause(35) }
        keyboard(key,down:true,flags:flags);heldKey=key
        mouse(.leftMouseDragged,CGPoint(x:start.x+40,y:start.y+28),flags:flags)
        var wheel:CGRect?
        for _ in 0..<40 { wheel=windowBounds(pid:managerPID,title:"Nashi Window Management");if wheel != nil { break };try await pause(50) }
        guard let wheel else { throw Failure(description:"The live window wheel did not appear.") }
        let geometry=WheelGeometry(bounds:.zero,count:WindowPlacement.allCases.count)
        let angle=(-Double(geometry.startAngle)+Double(index)*360/Double(geometry.count))*Double.pi/180
        let selected=CGPoint(x:wheel.midX+wheel.width*0.32*cos(angle),y:wheel.midY+wheel.height*0.32*sin(angle))
        for step in 1...8 {
            let fraction=CGFloat(step)/8,from=point
            mouse(.leftMouseDragged,CGPoint(x:from.x+(selected.x-from.x)*fraction,y:from.y+(selected.y-from.y)*fraction),flags:flags);try await pause(30)
        }
        mouse(.leftMouseDragged,selected,flags:flags);try await pause(180)
        if log.isEmpty {
            try captureWheel(pid:managerPID)
            // Explicit live visual QA only; normal test runs and the app never pause here.
            if CommandLine.arguments.contains("--hold-for-capture") { try await pause(6000) }
        }
        if cancel { keyboard(53,down:true,flags:flags);try await pause(80);keyboard(53,down:false,flags:flags);try await pause(100) }
        // Releasing the modifier must keep the choice available until mouse-up.
        keyboard(key,down:false);heldKey=nil;try await pause(100)
        if !cancel { try require(windowBounds(pid:managerPID,title:"Nashi Window Management") != nil,"Releasing the modifier dismissed the wheel.") }
        mouse(.leftMouseUp,selected);mouseDown=false
        let expected=cancel ? initial:placement.frame(in:work,scale:screen.backingScaleFactor,minimumSize:CGSize(width:minimumWidth,height:120))
        let axOrigin=WindowManagementController.accessibilityPoint(CGPoint(x:expected.minX,y:expected.maxY))
        var actual:CGRect?
        for _ in 0..<40 {
            actual=WindowManagementController.frame(of:window)
            if let actual,abs(actual.width-expected.width)<3,abs(actual.height-expected.height)<3,
               cancel || (abs(actual.minX-axOrigin.x)<3&&abs(actual.minY-axOrigin.y)<3) { break }
            try await pause(50)
        }
        guard let actual else { throw Failure(description:"Fixture disappeared after drag.") }
        try require(abs(actual.width-expected.width)<3&&abs(actual.height-expected.height)<3 &&
                    (cancel || abs(actual.minX-axOrigin.x)<3&&abs(actual.minY-axOrigin.y)<3),"\(cancel ? "Escape":placement.rawValue) did not apply the expected live window bounds: \(actual)")
        try require(windowBounds(pid:managerPID,title:"Nashi Window Management")==nil,"Window wheel remained open after mouse-up.")
        log.append(["placement":cancel ? "escape":placement.rawValue,"modifier":command ? "command":"shift","gesture":resize ? "resizeBorder":"titleBar","actual":[actual.minX,actual.minY,actual.width,actual.height],"passed":true])
        try await pause(120)
    }
    private func mouse(_ type:CGEventType,_ location:CGPoint,flags:CGEventFlags=[]) {
        point=location;let event=CGEvent(mouseEventSource:source,mouseType:type,mouseCursorPosition:location,mouseButton:.left);event?.flags=flags;event?.post(tap:.cghidEventTap)
    }
    private func keyboard(_ key:CGKeyCode,down:Bool,flags:CGEventFlags=[]) {
        let event=CGEvent(keyboardEventSource:source,virtualKey:key,keyDown:down);event?.flags=flags;event?.post(tap:.cghidEventTap)
    }
    private func releaseInput() { if mouseDown { mouse(.leftMouseUp,point);mouseDown=false };if let key=heldKey { keyboard(key,down:false);heldKey=nil } }
    private func windowInfo(pid:pid_t,title:String)->[String:Any]? {
        (CGWindowListCopyWindowInfo([.optionOnScreenOnly],kCGNullWindowID) as? [[String:Any]] ?? []).first {
            ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value==pid&&$0[kCGWindowName as String] as? String==title
        }
    }
    private func windowBounds(pid:pid_t,title:String)->CGRect? {
        // Accessibility is already required for this test. Do not require Screen Recording
        // merely to find a separately running Nashi panel; its CG title may be redacted.
        let app=AXUIElementCreateApplication(pid);AXUIElementSetMessagingTimeout(app,0.1)
        let matches=(WindowManagementController.attribute(app,kAXWindowsAttribute) as? [AXUIElement] ?? []).filter {
            WindowManagementController.attribute($0,kAXTitleAttribute) as? String==title
        }
        if matches.count==1,let frame=WindowManagementController.frame(of:matches[0]) { return frame }
        guard let info=windowInfo(pid:pid,title:title),let bounds=info[kCGWindowBounds as String] as? [String:Any] else { return nil }
        return CGRect(dictionaryRepresentation:bounds as CFDictionary)
    }
    private func captureWheel(pid:pid_t)throws {
        guard let number=windowInfo(pid:pid,title:"Nashi Window Management")?[kCGWindowNumber as String] as? NSNumber,
              let image=CGWindowListCreateImage(.null,.optionIncludingWindow,number.uint32Value,[.boundsIgnoreFraming,.bestResolution]) else { return }
        let bitmap=NSBitmapImageRep(cgImage:image)
        if let png=bitmap.representation(using:.png,properties:[:]) { try png.write(to:output.appendingPathComponent("mac-window-management.png")) }
    }
    private func cleanup() { releaseInput();fixture?.terminate();fixture=nil;if let originalPointer { mouse(.mouseMoved,originalPointer) };signals.forEach{$0.cancel()} }
    private func save(passed:Bool,error:String?)throws {
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        let report:[String:Any]=["passed":passed,"error":error as Any? ?? NSNull(),"checks":log,"scope":"Installed Nashi, disposable native fixture, all \(WindowPlacement.allCases.count) physical Shift/Command layout drags, modifier release and Escape. No other windows are moved."]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:output.appendingPathComponent("mac-window-management.json"))
    }
}
