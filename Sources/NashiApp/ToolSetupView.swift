import AppKit
import SwiftUI
import NashiCore

@MainActor struct ToolSetupView: View {
    @StateObject private var model: ToolSetupModel
    let onDone: () -> Void
    init(model: ToolSetupModel, onDone: @escaping () -> Void = {}) {
        _model = StateObject(wrappedValue: model); self.onDone = onDone
    }
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    NashiPageHeading(eyebrow: "FIRST-TIME SETUP", title: "A few tools. More possibilities.", subtitle: "One download per tool group. No account or GitHub token.")
                    group("Media tools", symbol: "film", ready: model.status.mediaReady,
                          detail: "FFmpeg, ffprobe, yt-dlp and Deno enable media conversion, previews and web downloads. Approximately 180 MB. FFmpeg and yt-dlp use GPL licenses; Deno uses MIT.",
                          button: "Download media tools", id: "SetupMedia", action: { model.install(.media) })
                    group("Office tools", symbol: "doc.text", ready: model.status.officeReady,
                          detail: "LibreOffice 26.8.1 enables Office document conversions. A 285 MB download; about 1 GB installed. MPL 2.0 and its included third-party licenses.",
                          button: "Download office tools", id: "SetupOffice", action: { model.install(.office) })
                    Link("Upstream versions, licenses and source links", destination: URL(string: "https://github.com/orkunisitmak/nashi-app/blob/main/docs/dependencies.md")!).font(.callout)
                }.padding(28)
            }
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                LText(model.message).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("SetupStatus")
                if model.working {
                    if let value = model.fraction { ProgressView(value: value) }
                    else { ProgressView().controlSize(.small) }
                }
                HStack {
                    if model.working {
                        Button("Cancel setup", action: model.cancel).accessibilityIdentifier("SetupCancel").keyboardShortcut(.cancelAction)
                    }
                    Spacer()
                    Button(model.status.ready ? "Continue to Nashi" : "Download missing tools") {
                        if model.status.ready { onDone() } else { model.install() }
                    }.buttonStyle(NashiButtonStyle(.primary)).disabled(model.working)
                        .accessibilityIdentifier("SetupContinue").keyboardShortcut(.defaultAction)
                }
            }.padding(24)
        }.frame(minWidth: 590, minHeight: 560).background(NashiPalette.canvas).tint(.nashi).buttonStyle(NashiButtonStyle())
            .onAppear { model.refresh() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refresh() }
    }
    private func group(_ title: String, symbol: String, ready: Bool, detail: String, button: String, id: String, action: @escaping () -> Void) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label(LocalizedStringKey(title), systemImage: symbol).font(.headline)
                LText(detail).font(.callout).foregroundStyle(.secondary)
                if ready {
                    Label("Already available on your computer", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(NashiPalette.forest).accessibilityIdentifier(id + "Ready")
                } else {
                    Button(action: action) { LText(button) }.disabled(model.working).accessibilityIdentifier(id)
                }
            }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
extension Notification.Name {
    static let showToolSetup = Notification.Name("NashiShowToolSetup")
    static let toolSetupChanged = Notification.Name("NashiToolSetupChanged")
}
