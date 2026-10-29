import AppKit
import SwiftUI
import ApplicationServices
import NashiCore
import NashiUpdates

/// Opt-in QA uses an isolated preference suite and only its own Nashi window.
@MainActor final class LocalizationSmoke:NSObject,NSApplicationDelegate {
    private let output:URL
    private var window:NSWindow?
    private var checks:[String]=[]
    init(output:URL) { self.output=output }
    func applicationDidFinishLaunching(_ notification:Notification) {
        Task {
            var failure:String?
            do { try await run() } catch { failure=String(describing:error) }
            let report:[String:Any]=["passed":failure == nil,"checks":checks,"error":failure as Any? ?? NSNull(),"scope":"Isolated Nashi settings, real language picker, open-view refresh, draft preservation and native wheel render."]
            try? FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
            if let data=try? JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]) { try? data.write(to:output.appendingPathComponent("mac-localization.json")) }
            window?.close();exit(failure == nil ? 0:1)
        }
    }
    private func check(_ value:Bool,_ label:String)throws { if !value { throw NSError(domain:"Nashi Language QA",code:1,userInfo:[NSLocalizedDescriptionKey:label]) };checks.append(label) }
    private func pause()async { try? await Task.sleep(nanoseconds:350_000_000) }
    private func attribute(_ element:AXUIElement,_ key:String)->Any? { var value:CFTypeRef?;return AXUIElementCopyAttributeValue(element,key as CFString,&value) == .success ? value:nil }
    private func descendants(_ element:AXUIElement,depth:Int=0)->[AXUIElement] {
        guard depth<28 else { return [] }
        return [element]+((attribute(element,kAXChildrenAttribute) as? [AXUIElement]) ?? []).flatMap{descendants($0,depth:depth+1)}
    }
    private func texts(_ root:AXUIElement)->[String] { descendants(root).flatMap { item in [kAXTitleAttribute,kAXDescriptionAttribute,kAXValueAttribute].compactMap{attribute(item,$0) as? String} } }
    private func key(_ code:CGKeyCode) { for down in [true,false] { CGEvent(keyboardEventSource:nil,virtualKey:code,keyDown:down)?.post(tap:.cghidEventTap) } }
    private func capture(_ view:NSView,_ name:String)throws {
        view.layoutSubtreeIfNeeded();guard let rep=view.bitmapImageRepForCachingDisplay(in:view.bounds) else { return }
        view.cacheDisplay(in:view.bounds,to:rep);if let data=rep.representation(using:.png,properties:[:]) { try data.write(to:output.appendingPathComponent(name)) }
    }
    private func run()async throws {
        try check(AXIsProcessTrusted()&&CGPreflightPostEventAccess(),"Existing Nashi Accessibility permission is available")
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        let suite="Nashi.LanguageQA."+UUID().uuidString,defaults=UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        defaults.set("en",forKey:"appLanguage")
        let view=LanguageFixture(updater:AppUpdater()).nashiLanguage().defaultAppStorage(defaults)
        let w=NSWindow(contentRect:NSRect(x:100,y:80,width:860,height:750),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
        w.title="Nashi Language QA";w.isReleasedWhenClosed=false;w.contentView=NSHostingView(rootView:view);window=w
        w.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true);await pause()
        let app=AXUIElementCreateApplication(getpid());AXUIElementSetMessagingTimeout(app,0.3)
        guard let root=(attribute(app,kAXWindowsAttribute) as? [AXUIElement])?.first(where:{attribute($0,kAXTitleAttribute) as? String=="Nashi Language QA"}) else { throw NSError(domain:"Nashi Language QA",code:2,userInfo:[NSLocalizedDescriptionKey:"Own fixture window is not accessible"]) }
        let elements=descendants(root)
        guard let picker=elements.first(where:{attribute($0,kAXIdentifierAttribute) as? String=="AppLanguage"}),
              let draft=elements.first(where:{attribute($0,kAXIdentifierAttribute) as? String=="LanguageDraft"}) else {
            try texts(root).joined(separator:"\n").write(to:output.appendingPathComponent("accessibility.txt"),atomically:true,encoding:.utf8)
            throw NSError(domain:"Nashi Language QA",code:3,userInfo:[NSLocalizedDescriptionKey:"Language picker or draft field not accessible"])
        }
        let raw="Home Library · Türkçe ıİşğü 🍐 {0}"
        try check(AXUIElementSetAttributeValue(draft,kAXValueAttribute as CFString,raw as CFString) == .success,"Draft edited through Accessibility")
        try check(texts(root).contains("Language"),"English UI is the existing default")
        try check(AXUIElementPerformAction(picker,kAXPressAction as CFString) == .success,"Real language picker opens")
        await pause();key(125);key(36);await pause();await pause()
        try check(defaults.string(forKey:"appLanguage")=="tr","Selecting Türkçe persists its stable language code")
        try check(texts(root).contains("Dil")&&texts(root).contains("Genel"),"Static and dynamic settings labels update live")
        try check(attribute(draft,kAXValueAttribute) as? String==raw,"Changing language preserves an unsaved user draft")
        try capture(w.contentView!,"mac-settings-turkish.png")
        let oldDomain=UserDefaults.standard.volatileDomain(forName:UserDefaults.argumentDomain)
        var argumentDomain=oldDomain;argumentDomain["appLanguage"]="tr";UserDefaults.standard.setVolatileDomain(argumentDomain,forName:UserDefaults.argumentDomain)
        defer { UserDefaults.standard.setVolatileDomain(oldDomain,forName:UserDefaults.argumentDomain) }
        let wheel=WheelView(frame:NSRect(x:0,y:0,width:420,height:420));wheel.items=WindowPlacement.allCases.map{WheelItem(title:$0.title,symbol:"rectangle",windowPlacement:$0)};wheel.centerTitle="Pencere düzeni"
        try capture(wheel,"mac-window-wheel-turkish.png")
        UserDefaults.standard.setVolatileDomain(oldDomain,forName:UserDefaults.argumentDomain)
        try check(AXUIElementPerformAction(picker,kAXPressAction as CFString) == .success,"Language picker remains available after translating")
        await pause();key(126);key(36);await pause();await pause()
        try check(defaults.string(forKey:"appLanguage")=="en"&&texts(root).contains("Language"),"Switching back to English updates the same window")
        try check(attribute(draft,kAXValueAttribute) as? String==raw,"Switching back preserves the draft")
        defaults.removeObject(forKey:"appLanguage")
    }
}
private struct LanguageFixture:View {
    let updater:AppUpdater
    @State private var draft="Original fixture text"
    var body:some View { VStack(spacing:0) { SettingsView(updater:updater);TextField("Draft",text:$draft).accessibilityIdentifier("LanguageDraft").padding(12) } }
}
