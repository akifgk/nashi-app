import AppKit
import SwiftUI
import ApplicationServices
import NashiUpdates

/// Explicit opt-in QA. Uses a private pasteboard and isolated defaults, never the user's Library.
@MainActor final class DesktopParitySmoke:NSObject,NSApplicationDelegate {
    let output:URL;private var window:NSWindow?;private var state:AppState?;private var monitor:Any?
    private let board=NSPasteboard.withUniqueName();private var checks:[String]=[]
    init(output:URL){self.output=output}
    func applicationDidFinishLaunching(_ notification:Notification) {
        Task {do {try await run();finish(nil)}catch{finish(error)}}
    }
    private func check(_ value:Bool,_ label:String)throws {guard value else {throw NSError(domain:"Nashi Desktop QA",code:1,userInfo:[NSLocalizedDescriptionKey:label])};checks.append(label)}
    private func pause()async {try? await Task.sleep(nanoseconds:220_000_000)}
    private func key(_ code:UInt16,flags:CGEventFlags=[],in target:NSWindow)async throws {
        target.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true);await pause()
        try check(NSApp.keyWindow===target,"Keyboard target belongs to the Nashi fixture")
        for down in [true,false] {let event=CGEvent(keyboardEventSource:nil,virtualKey:code,keyDown:down);event?.flags=flags;event?.post(tap:.cghidEventTap)}
        await pause()
    }
    private func capture(_ target:NSWindow,_ name:String)throws {
        guard let view=target.contentView,let rep=view.bitmapImageRepForCachingDisplay(in:view.bounds) else{return}
        view.cacheDisplay(in:view.bounds,to:rep);if let data=rep.representation(using:.png,properties:[:]) {try data.write(to:output.appendingPathComponent(name))}
    }
    private func run()async throws {
        guard CGPreflightPostEventAccess() else {throw NSError(domain:"Nashi Desktop QA",code:2,userInfo:[NSLocalizedDescriptionKey:"Nashi needs its existing event access to run native keyboard tests."])}
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        let suite="Nashi.DesktopQA."+UUID().uuidString;let defaults=UserDefaults(suiteName:suite)!;defer{defaults.removePersistentDomain(forName:suite)}
        let state=AppState(defaults:defaults);self.state=state
        let w=NSWindow(contentRect:NSRect(x:100,y:100,width:820,height:780),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false);w.title="Nashi Desktop QA";w.isReleasedWhenClosed=false;window=w
        w.contentView=NSHostingView(rootView:HomeView(state:state,updater:AppUpdater()).nashiLanguage());monitor=NSEvent.addLocalMonitorForEvents(matching:.keyDown){[weak self] event in guard let self,event.window===w,w.isKeyWindow else{return event};return state.handleHomeKey(event,window:w,pasteboard:self.board) ? nil:event}
        w.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true);await pause()
        let unicode="Nashi clipboard · Türkçe ıİşğü 🍐\r\nSecond line"
        board.setString(unicode,forType:.string);try await key(9,flags:.maskCommand,in:w)
        try check(state.inputs.count==1 && (try? String(contentsOf:state.inputs[0],encoding:.utf8))==unicode,"Native Command+V keeps Unicode and line breaks")
        let text=state.inputs[0];try check(AppState(defaults:defaults).history.count==1,"Pasted text survives Library reload")
        let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:320,pixelsHigh:180,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:1280,bitsPerPixel:32)!
        for i in stride(from:0,to:320*180*4,by:4){rep.bitmapData![i]=240;rep.bitmapData![i+1]=190;rep.bitmapData![i+2]=30;rep.bitmapData![i+3]=255}
        board.clearContents();board.setData(rep.tiffRepresentation,forType:.tiff);try await key(9,flags:.maskCommand,in:w)
        let image=state.inputs[0];let pasted=NSBitmapImageRep(data:try Data(contentsOf:image))!
        try check(pasted.pixelsWide==320 && pasted.pixelsHigh==180,"Image paste preserves source pixel dimensions")
        try check(state.history.count==2 && FileManager.default.fileExists(atPath:text.path),"Image paste keeps previous text imports")
        let folder=output.appendingPathComponent("Folder fixture",isDirectory:true);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        board.clearContents();board.writeObjects([folder as NSURL,image as NSURL]);try await key(9,flags:.maskCommand,in:w)
        try check(state.inputs==[folder,image],"File and folder paste keeps selection order")
        var copiedLink:URL?;state.onWebDownload={url,_ in copiedLink=url};board.clearContents();board.setString("https://example.com/media",forType:.string);try await key(9,flags:.maskCommand,in:w)
        try check(copiedLink?.absoluteString=="https://example.com/media" && state.history.count==3,"Link paste opens the download flow without a text file")
        try await key(18,flags:.maskCommand,in:w);try check(!state.libraryVisible,"Command+1 opens Home")
        try capture(w,"mac-home.png")
        try await key(19,flags:.maskCommand,in:w);try check(state.libraryVisible,"Command+2 opens Library")
        try await key(3,flags:.maskCommand,in:w);try check((w.firstResponder as? NSTextView)?.isEditable==true,"Command+F focuses Library search")
        let paste=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:.command,timestamp:0,windowNumber:w.windowNumber,context:nil,characters:"v",charactersIgnoringModifiers:"v",isARepeat:false,keyCode:9)!
        try check(!state.handleHomeKey(paste,window:w,pasteboard:board),"Text field paste remains native and does not import")
        state.libraryQuery="Pasted image";await pause();try await key(125,in:w)
        try check(state.selectedHistoryID==state.filteredHistory.first?.id && state.filteredHistory.count==1,"Down selects a matching Library result")
        try capture(w,"mac-library.png")
        try await key(49,in:w);guard let preview=NSApp.windows.first(where:{$0.isVisible && $0.title.hasSuffix("· Preview · Nashi")}) else {throw NSError(domain:"Nashi Desktop QA",code:3,userInfo:[NSLocalizedDescriptionKey:"Space did not open the Library preview"])}
        try capture(preview,"mac-library-preview.png");try await key(53,in:preview);try check(!preview.isVisible,"Escape closes Library preview")
        try await key(36,in:w);try check(state.inputs==[image] && !state.libraryVisible,"Return reuses the selected Library result")
        try check(AppState(defaults:defaults).history.count==3,"Library search, preview and reuse preserve history")
        var wheelRequests=0;state.onOpenWheel={wheelRequests+=1};w.makeFirstResponder(nil);try await key(36,flags:.maskCommand,in:w);try await key(36,in:w);try check(wheelRequests==2,"Command+Return and Return open selected-file tools")
        state.libraryVisible=true;board.clearContents();try await key(9,flags:.maskCommand,in:w);try check(state.error != nil && state.history.count==3,"Empty clipboard reports an error without changing Library");state.error=nil
        let shelf=FloatShelfController(urls:[image,text]);shelf.showWindow(nil);await pause();try await key(49,in:shelf.window!);guard let shelfPreview=NSApp.windows.first(where:{$0.isVisible && $0.title.hasSuffix("· Preview · Nashi")}) else{throw NSError(domain:"Nashi Desktop QA",code:5)}
        try await key(124,in:shelfPreview);try check(shelfPreview.title.hasPrefix(text.lastPathComponent),"Float Space opens the shared batch preview and Right navigates");try await key(53,in:shelfPreview);shelf.close()

        state.filePreview.show([image,text]);await pause();guard let batch=NSApp.windows.first(where:{$0.isVisible && $0.title.hasSuffix("· Preview · Nashi")}) else{throw NSError(domain:"Nashi Desktop QA",code:4)}
        try await key(124,in:batch);try check(batch.title.hasPrefix(text.lastPathComponent),"Preview Right navigates a batch")
        try await key(53,in:batch);try check(FileManager.default.fileExists(atPath:image.path),"Preview leaves imported originals intact")
        // The only imported files from this isolated run live outside its bundle; remove its fixtures.
        for record in state.history {for path in record.outputs where path != folder.path && path != image.path {if path.contains("/Nashi/Imports/Clipboard "){try? FileManager.default.removeItem(atPath:path)}}};try? FileManager.default.removeItem(at:image)
    }
    private func finish(_ error:Error?) {
        if let monitor {NSEvent.removeMonitor(monitor)};board.releaseGlobally();state?.filePreview.close();window?.close()
        let report:[String:Any]=["passed":checks.count,"checks":checks,"error":error?.localizedDescription as Any? ?? NSNull(),"scope":"Real macOS keyboard events through the production Home router; isolated Library and private clipboard."]
        if let data=try? JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]) {try? data.write(to:output.appendingPathComponent("mac-desktop-parity.json"))}
        exit(error == nil ? 0:1)
    }
}
