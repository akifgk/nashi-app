import SwiftUI
import NashiCore

struct EPUBOptionsView:View {
    @ObservedObject var state:AppState
    let inputs:[URL]
    @State private var layout="reflowable"
    var body:some View {
        VStack(alignment:.leading,spacing:22) {
            NashiPageHeading(eyebrow:"PDF → EPUB",title:"A good read, your way.",subtitle:"Choose how your pages make the move.")
            VStack(alignment:.leading,spacing:13) {
                Picker("Layout",selection:$layout) { Text("Flexible, reflowable text").tag("reflowable");Text("Keep the original pages").tag("fixed") }.pickerStyle(.radioGroup)
                Text(layout=="fixed" ? "Keeps the look and dimensions of each page. Best for visual layouts.":"Text adapts to the reader’s screen and font size. Best for reading.").font(.system(size:12)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }.padding(19).nashiCard(radius:18)
            HStack { Label("Your original stays safe",systemImage:"lock").font(.system(size:10)).foregroundStyle(.secondary);Spacer();Button("Make EPUB") { var options=FormatPreferences.shared.options(for:"epub");options.epubLayout=layout;state.execute(.convert("epub"),options:options,inputs:inputs) }.buttonStyle(NashiButtonStyle(.primary)).disabled(state.working) }
            JobProgressView(state:state)
        }.padding(28).frame(minWidth:470,minHeight:310).background(NashiPalette.canvas).tint(.nashi).nashiAnimation(value:layout).onAppear { layout=FormatPreferences.shared.profile(for:"epub").epubLayout }
    }
}
