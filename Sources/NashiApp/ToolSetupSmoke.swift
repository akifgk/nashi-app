import AppKit
import SwiftUI
import NashiCore

/// Isolated first-run UI replay: fake publishers, real setup shortcuts and model.
/// It never downloads tools, touches the user's tool directory or requests TCC.
@MainActor final class ToolSetupSmoke:NSObject,NSApplicationDelegate {
    private let output:URL
    private var window:NSWindow?
    private var checks:[String]=[]
    init(output:URL) { self.output=output }
    func applicationDidFinishLaunching(_ notification:Notification) {
        Task {
            var failure:String?
            do {try await run()}catch{failure=String(describing:error)}
            let result:[String:Any]=["passed":failure == nil,"checks":checks,"error":failure as Any? ?? NSNull(),"scope":"Own-window Return/Escape setup UI, clean/partial/existing tools, failure, cancellation and retry. Publisher responses are simulated; no real download claimed."]
            if let data=try? JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]) {try? data.write(to:output.appendingPathComponent("mac-tool-setup.json"))}
            window?.close();exit(failure == nil ? 0:1)
        }
    }
    private func check(_ valid:Bool,_ label:String)throws {
        if !valid {throw NSError(domain:"Nashi Setup QA",code:1,userInfo:[NSLocalizedDescriptionKey:label])};checks.append(label)
    }
    private func pause()async {try? await Task.sleep(nanoseconds:160_000_000)}
    private func press(_ identifier:String)throws {
        guard let window else {throw NSError(domain:"Nashi Setup QA",code:2)}
        let cancel=identifier=="SetupCancel"
        let event=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:window.windowNumber,context:nil,characters:cancel ? "\u{1b}":"\r",charactersIgnoringModifiers:cancel ? "\u{1b}":"\r",isARepeat:false,keyCode:cancel ? 53:36)!
        // Dispatch through this fixture window's native default/cancel shortcut.
        // No global keyboard injection or access to another application is used.
        if !window.performKeyEquivalent(with:event) {window.sendEvent(event)}
        checks.append("Own-window shortcut dispatched: "+identifier)
    }
    private func settle(_ model:ToolSetupModel)async throws {
        let end=Date().addingTimeInterval(5)
        while model.working && Date()<end {await pause()}
        try check(!model.working,"Setup task returns to an idle, retryable state")
        await pause()
    }
    private func capture(_ name:String)throws {
        guard let view=window?.contentView,let rep=view.bitmapImageRepForCachingDisplay(in:view.bounds) else{return}
        view.layoutSubtreeIfNeeded();view.cacheDisplay(in:view.bounds,to:rep)
        if let data=rep.representation(using:.png,properties:[:]) {try data.write(to:output.appendingPathComponent(name))}
    }
    private func run()async throws {
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        let suite="Nashi.SetupQA."+UUID().uuidString,defaults=UserDefaults(suiteName:suite)!
        defer{defaults.removePersistentDomain(forName:suite)}
        defaults.set("en",forKey:"appLanguage")
        var status=ToolSetupStatus(mediaReady:false,officeReady:false),mediaCalls=0,officeCalls=0,finish=0,officeMode=0
        let model=ToolSetupModel(probe:{status},install:{group,token,report in
            if group == .media {mediaCalls+=1;status.mediaReady=true;report(1,"Media tools are ready.")}
            else {
                officeCalls+=1
                if officeMode==0 {throw NSError(domain:"Publisher fixture",code:1,userInfo:[NSLocalizedDescriptionKey:"Offline fixture: retry setup."])}
                if officeMode==1 {while !token.isCancelled {try await Task.sleep(nanoseconds:20_000_000)};try token.check()}
                status.officeReady=true;report(1,"Office tools are ready.")
            }
        })
        let w=NSWindow(contentRect:NSRect(x:100,y:80,width:646,height:690),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
        w.title="Nashi First Run QA";w.isReleasedWhenClosed=false
        w.contentView=NSHostingView(rootView:ToolSetupView(model:model,onDone:{finish+=1}).nashiLanguage().defaultAppStorage(defaults))
        window=w;w.makeKeyAndOrderFront(nil);await pause();await pause()
        try check(!model.status.ready&&model.status.missing == [.media,.office],"Clean first-run profile requires both tool groups")
        try capture("mac-first-run-tools.png")
        try press("SetupContinue");await pause();try await settle(model)
        try check(mediaCalls==1&&officeCalls==1&&model.status.missing == [.office]&&finish==0,"An Office download failure retains installed media and does not finish onboarding")
        try capture("mac-first-run-retry.png")
        officeMode=1;try press("SetupContinue");await pause()
        try check(model.working&&mediaCalls==1,"Retry skips the completed media group")
        try press("SetupCancel");try await settle(model)
        try check(!model.status.ready&&model.message=="Setup cancelled. Existing tools were kept.","Cancellation remains incomplete and keeps existing tools")
        officeMode=2;try press("SetupContinue");await pause();try await settle(model)
        try check(model.status.ready&&mediaCalls==1&&officeCalls==3&&finish==0,"Only successfully verified groups enable Continue")
        defaults.set("tr",forKey:"appLanguage");await pause();try capture("mac-first-run-tools-turkish.png")
        try press("SetupContinue");try check(finish==1&&mediaCalls==1,"Continue finishes setup without downloading existing tools")
        status.officeReady=false;model.refresh()
        try check(!model.status.ready&&model.message != "Ready. You can go back to your files.","Removing an external tool clears stale readiness when setup is reopened")
    }
}
