import AppKit

/// Own-window UI replay with disposable files. No global input or permission prompt.
@MainActor final class FloatShelfSmoke:NSObject,NSApplicationDelegate {
    private let output:URL
    private var shelf:FloatShelfController?
    private var checks:[String]=[]
    private var fixtures:[URL]=[]
    private var dragWindow:NSWindow?
    private var moveObserver:NSObjectProtocol?
    init(output:URL) { self.output=output }
    func applicationDidFinishLaunching(_ notification:Notification) {
        Task {
            var failure:String?
            do { try await run() } catch { failure=String(describing:error) }
            let result:[String:Any]=["passed":failure == nil,"checks":checks,"error":failure as Any? ?? NSNull(),"scope":"Own AppKit window controls, keyboard, layout, collapse/expand, edge attachment and original-file safety. Drag source/drop data is inspected separately from global Finder input."]
            if let data=try? JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]) {try? data.write(to:output.appendingPathComponent("mac-float.json"))}
            if failure == nil,CommandLine.arguments.contains("--keep-float-open") {
                shelf?.append(fixtures);shelf?.window?.center();shelf?.showWindow(nil)
                shelf?.onClose={ NSApp.terminate(nil) }
                showDragFixture();return
            }
            shelf?.close();exit(failure == nil ? 0:1)
        }
    }
    private func showDragFixture() {
        guard let shelf,let window=shelf.window else { return }
        moveObserver=NotificationCenter.default.addObserver(forName:NSWindow.didMoveNotification,object:window,queue:.main) { [weak self,weak window] _ in
            guard let self,let window else { return };try? NSStringFromRect(window.frame).write(to:self.output.appendingPathComponent("float-window-frame.txt"),atomically:true,encoding:.utf8)
        }
        let extra=output.appendingPathComponent("Extra drop.txt");try? "Additional Float fixture".write(to:extra,atomically:true,encoding:.utf8)
        let view=FloatDragFixture(frame:NSRect(x:0,y:0,width:310,height:260),file:extra,output:output,onShow:{ [weak shelf] in shelf?.showWindow(nil) })
        let drop=NSWindow(contentRect:view.frame,styleMask:[.titled,.closable],backing:.buffered,defer:false);drop.title="Nashi Float Drag Test";drop.contentView=view;drop.isReleasedWhenClosed=false;drop.level = .floating;drop.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary]
        drop.setFrameOrigin(NSPoint(x:window.frame.maxX+60,y:window.frame.minY-100));drop.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true);dragWindow=drop
        let metadata:[String:Any]=["shelfWindowID":window.windowNumber,"dropWindowID":drop.windowNumber,"shelfFrame":NSStringFromRect(window.frame),"dropFrame":NSStringFromRect(drop.frame)]
        if let data=try? JSONSerialization.data(withJSONObject:metadata,options:[.prettyPrinted,.sortedKeys]) {try? data.write(to:output.appendingPathComponent("fixture-windows.json"))}
    }
    private func check(_ valid:Bool,_ name:String)throws { if !valid { throw NSError(domain:"Nashi Float QA",code:1,userInfo:[NSLocalizedDescriptionKey:name]) };checks.append(name) }
    private func pause()async {try? await Task.sleep(nanoseconds:350_000_000)}
    private func children(_ view:NSView)->[NSView] { [view]+view.subviews.flatMap(children) }
    private func key(_ code:UInt16,_ characters:String,flags:NSEvent.ModifierFlags=[])async {
        guard let window=shelf?.window else { return }
        let event=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:flags,timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:window.windowNumber,context:nil,characters:characters,charactersIgnoringModifiers:characters,isARepeat:false,keyCode:code)!
        window.sendEvent(event);await pause()
    }
    private func capture(_ name:String)throws {
        guard let view=shelf?.window?.contentView,let rep=view.bitmapImageRepForCachingDisplay(in:view.bounds) else {throw NSError(domain:"Nashi Float QA",code:2)}
        view.cacheDisplay(in:view.bounds,to:rep);try rep.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent(name))
    }
    private func run()async throws {
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        let folder=output.appendingPathComponent("Float fixtures",isDirectory:true);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let text=folder.appendingPathComponent("Notes with a longer name.txt");try "Float original – öğeler".write(to:text,atomically:true,encoding:.utf8)
        var images:[URL]=[]
        for (index,color) in [NSColor.systemGreen,NSColor.systemOrange,NSColor.systemPurple].enumerated() {
            let image=NSImage(size:NSSize(width:160,height:120));image.lockFocus();color.setFill();NSBezierPath(roundedRect:NSRect(x:0,y:0,width:160,height:120),xRadius:18,yRadius:18).fill();("Nashi \(index+1)" as NSString).draw(at:NSPoint(x:22,y:48),withAttributes:[.font:NSFont.systemFont(ofSize:25,weight:.bold),.foregroundColor:NSColor.white]);image.unlockFocus()
            let url=folder.appendingPathComponent("Photo \(index+1).png");try NSBitmapImageRep(data:image.tiffRepresentation!)!.representation(using:.png,properties:[:])!.write(to:url);images.append(url)
        }
        fixtures=[text]+images
        let originals=try ([text]+images).map{try Data(contentsOf:$0)}
        let shelf=FloatShelfController(urls:[text]+images);self.shelf=shelf;shelf.showWindow(nil);await pause()
        let window=shelf.window!,views=children(window.contentView!)
        try check(!shelf.isExpanded && abs(window.frame.width-112)<1,"Float starts as a compact stack without window chrome")
        try capture("mac-float-stack.png")
        let stack=views.first{$0.accessibilityIdentifier()=="float.carry"}!
        try check(stack.accessibilityPerformPress(),"Stack exposes a native accessibility press action");await pause()
        try check(shelf.isExpanded && abs(window.frame.width-156)<1,"Press opens a slim vertical shelf")
        let collection=views.compactMap{$0 as? NSCollectionView}.first!
        collection.layoutSubtreeIfNeeded()
        let frames=(0..<4).compactMap{collection.layoutAttributesForItem(at:IndexPath(item:$0,section:0))?.frame}
        try check(frames.count==4 && Set(frames.map{Int($0.minX)}).count==1,"All files occupy one centered thumbnail column")
        try capture("mac-float-expanded.png")
        shelf.append([images[0]]);try check(shelf.urls.count==4,"Dropping an existing path does not duplicate the stack")
        await key(0,"a",flags:.command);try check(shelf.selectedURLs.count==4,"Command+A selects all files")
        await key(53,"\u{1b}");try check(shelf.isExpanded && shelf.selectedURLs.isEmpty,"First Escape clears selection")
        await key(53,"\u{1b}");try check(!shelf.isExpanded,"Second Escape returns to the stack")
        shelf.attach(to:.top);await pause()
        try check(window.frame.maxY>(window.screen?.visibleFrame.maxY ?? 0),"Top edge attachment leaves a small visible tab")
        shelf.setExpanded(true);await pause()
        try check(abs(window.frame.maxY-(window.screen?.visibleFrame.maxY ?? 0))<1,"Opening a tucked stack brings the full shelf on screen")
        shelf.attach(to:nil);shelf.setViewMode(.list);await pause()
        try check(shelf.viewMode == .list && abs(window.frame.width-284)<1,"List mode stays available from Float options")
        try capture("mac-float-list.png")
        shelf.setViewMode(.icons);await pause()
        let previousArguments=UserDefaults.standard.volatileDomain(forName:UserDefaults.argumentDomain);UserDefaults.standard.setVolatileDomain(["appLanguage":"tr"],forName:UserDefaults.argumentDomain);NotificationCenter.default.post(name:.nashiLanguageChanged,object:nil);await pause()
        try capture("mac-float-turkish.png");UserDefaults.standard.setVolatileDomain(previousArguments,forName:UserDefaults.argumentDomain);NotificationCenter.default.post(name:.nashiLanguageChanged,object:nil)
        await key(0,"a",flags:.command);await key(51,"\u{7f}")
        try check(shelf.urls.isEmpty,"Delete removes only the selected Float references")
        for (index,url) in ([text]+images).enumerated() { try check(try Data(contentsOf:url)==originals[index],"Original \(url.lastPathComponent) remains byte-for-byte intact") }
        shelf.setExpanded(false);await pause();try capture("mac-float-empty.png")
    }
}

/// A native file source and copy-only destination, restricted to generated fixtures.
@MainActor private final class FloatDragFixture:NSView,NSDraggingSource {
    private let file:URL,output:URL
    private let label=NSTextField(wrappingLabelWithString:"Drag the document above into Float.\n\nDrop Float files here to check their drag payload.")
    private let onShow:()->Void
    init(frame:NSRect,file:URL,output:URL,onShow:@escaping ()->Void) {
        self.file=file;self.output=output;self.onShow=onShow;super.init(frame:frame);registerForDraggedTypes([.fileURL]);wantsLayer=true;layer?.backgroundColor=NSColor.windowBackgroundColor.cgColor
        label.frame=NSRect(x:24,y:56,width:262,height:80);label.alignment = .center;addSubview(label)
        let show=NSButton(title:"Show Float",target:self,action:#selector(showFloat));show.frame=NSRect(x:80,y:12,width:150,height:28);show.bezelStyle = .rounded;addSubview(show)
    }
    @objc private func showFloat() { onShow() }
    required init?(coder:NSCoder) { fatalError() }
    override func draw(_ dirtyRect:NSRect) { NSWorkspace.shared.icon(forFile:file.path).draw(in:NSRect(x:120,y:166,width:64,height:64)) }
    override func mouseDown(with event:NSEvent) {
        let item=NSDraggingItem(pasteboardWriter:file as NSURL);item.setDraggingFrame(NSRect(x:120,y:166,width:64,height:64),contents:NSWorkspace.shared.icon(forFile:file.path));beginDraggingSession(with:[item],event:event,source:self)
    }
    func draggingSession(_ session:NSDraggingSession,sourceOperationMaskFor context:NSDraggingContext)->NSDragOperation { .copy }
    override func draggingEntered(_ sender:NSDraggingInfo)->NSDragOperation { .copy }
    override func performDragOperation(_ sender:NSDraggingInfo)->Bool {
        let urls=(sender.draggingPasteboard.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) as? [URL]) ?? []
        guard !urls.isEmpty,urls.allSatisfy({$0.path.hasPrefix(output.path+"/")}) else { return false }
        label.stringValue="Received \(urls.count) fixture files. Originals unchanged."
        let data=try? JSONSerialization.data(withJSONObject:["count":urls.count,"paths":urls.map(\.path)],options:[.prettyPrinted,.sortedKeys]);try? data?.write(to:output.appendingPathComponent("native-drag-payload.json"));return true
    }
}
