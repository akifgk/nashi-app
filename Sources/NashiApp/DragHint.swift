import AppKit
import NashiCore

/// Remembers which wheel modifier was pressed last, so holding Control and then Option opens the Option wheel.
@MainActor final class ModifierPressOrder {
    static let shared=ModifierPressOrder()
    private var pressed:[NSEvent.ModifierFlags]=[]
    func reset() { pressed.removeAll() }
    func mode(for flags:NSEvent.ModifierFlags)->WheelMode? {
        let singles:[NSEvent.ModifierFlags]=[.control,.option,.shift,.command]
        let current=singles.filter{flags.contains($0)}
        pressed.removeAll{!current.contains($0)}
        for flag in current where !pressed.contains(flag) { pressed.append(flag) }
        for flag in pressed.reversed() {
            var best:WheelShortcut?;var size=0
            for wheel in WheelShortcut.allCases {
                let chord=ModifierPreferences.chord(for:wheel).flags
                let count=chord.rawValue.nonzeroBitCount
                if chord.contains(flag),flags.contains(chord),count>size { best=wheel;size=count }
            }
            switch best {
            case .conversions?:return .convert
            case .tools?:return .tools
            case .actions?:return .actions
            case nil:continue
            }
        }
        return nil
    }
}

/// Small click-through key legend. Without `current` it lists all three wheels beside the pointer during a drag;
/// with `current` it shows the other two wheels in one row under the open wheel.
@MainActor final class DragHintPanel {
    private let panel:NSPanel
    static var enabled:Bool { UserDefaults.standard.object(forKey:"dragHint") as? Bool ?? true }
    private static func title(_ wheel:WheelShortcut)->String {
        switch wheel { case .conversions:return "Convert";case .tools:return "Tools";case .actions:return "File actions" }
    }
    init(current:WheelShortcut?) {
        let compact=current != nil
        let stack=NSStackView();stack.orientation=compact ? .horizontal:.vertical;stack.alignment=compact ? .centerY:.leading;stack.spacing=compact ? 14:5
        for wheel in WheelShortcut.allCases where wheel != current {
            let key=NSTextField(labelWithString:"\u{00A0}\(ModifierPreferences.chord(for:wheel).symbols)\u{00A0}")
            key.font=.systemFont(ofSize:12,weight:.semibold);key.alignment=.center;key.wantsLayer=true
            key.layer?.cornerRadius=5;key.layer?.backgroundColor=NSColor.controlBackgroundColor.cgColor
            let name=NSTextField(labelWithString:L10n.text(Self.title(wheel)));name.font=.systemFont(ofSize:13)
            let row=NSStackView(views:[key,name]);row.orientation=.horizontal;row.alignment=.centerY;row.spacing=8
            stack.addArrangedSubview(row)
        }
        let effect=NSVisualEffectView();effect.material=.popover;effect.blendingMode=.behindWindow;effect.state=.active
        effect.wantsLayer=true;effect.layer?.cornerRadius=compact ? 14:10;effect.layer?.masksToBounds=true
        stack.translatesAutoresizingMaskIntoConstraints=false;effect.addSubview(stack)
        let fit=stack.fittingSize
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo:effect.leadingAnchor,constant:12),stack.trailingAnchor.constraint(equalTo:effect.trailingAnchor,constant:-12),
            stack.topAnchor.constraint(equalTo:effect.topAnchor,constant:7),stack.bottomAnchor.constraint(equalTo:effect.bottomAnchor,constant:-7)])
        let p=NSPanel(contentRect:NSRect(x:0,y:0,width:fit.width+24,height:fit.height+14),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        p.backgroundColor = .clear;p.isOpaque=false;p.hasShadow=true;p.level = .statusBar;p.hidesOnDeactivate=false
        p.ignoresMouseEvents=true;p.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.transient];p.contentView=effect
        panel=p
    }
    func show() { panel.orderFrontRegardless() }
    func close() { panel.orderOut(nil) }
    /// Follows the pointer, kept inside the visible area of its screen.
    func move(to point:NSPoint) {
        let screen=NSScreen.screens.first(where:{$0.frame.contains(point)}) ?? NSScreen.main
        let visible=screen?.visibleFrame ?? NSRect(x:0,y:0,width:1440,height:900)
        let size=panel.frame.size
        let x=min(max(visible.minX+4,point.x+18),visible.maxX-size.width-4)
        let y=min(max(visible.minY+4,point.y-size.height-14),visible.maxY-size.height-4)
        panel.setFrameOrigin(NSPoint(x:x,y:y))
    }
    /// Centers under the wheel; flips above it when the wheel sits at the bottom of the screen.
    func placeBelow(_ wheel:NSPanel) {
        let frame=wheel.frame
        let visible=(wheel.screen ?? NSScreen.main)?.visibleFrame ?? frame
        let size=panel.frame.size
        var y=frame.minY-size.height-8
        if y<visible.minY+4 { y=frame.maxY+8 }
        let x=min(max(visible.minX+4,frame.midX-size.width/2),visible.maxX-size.width-4)
        panel.setFrameOrigin(NSPoint(x:x,y:y))
    }
}
