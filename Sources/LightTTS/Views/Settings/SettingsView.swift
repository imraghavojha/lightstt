import SwiftUI
import AppKit
import LightTTSCore
import ApplicationServices

private final class SettingsDialogState: ObservableObject { @Published var deleting: Model? }

struct SettingsView: View {
    @ObservedObject var controller: AppController
    var detach: () -> Void
    var attached: Bool
    @StateObject private var dialog = SettingsDialogState()
    @AppStorage("selectedModel") private var selectedModel = "whisper-tiny.en"
    @AppStorage("pushToTalk") private var pushToTalk = false
    @AppStorage("rightOption") private var rightOption = false
    @AppStorage("keepModelLoaded") private var keepModelLoaded = true
    @AppStorage("customModelURL") private var customModelURL = ""
    @AppStorage("customModelSHA256") private var customModelSHA256 = ""
    @AppStorage("hotkeyCode") private var hotkeyCode = 49
    private func alertName(_ model: Model) -> String {
        switch model.id {
        case "whisper-large-v3": return "Whisper Large"
        case "whisper-large-v3-turbo": return "Whisper Large v3 Turbo"
        case "whisper-medium": return "Whisper Medium"
        case "whisper-small", "whisper-small.en": return "Whisper Small"
        case "whisper-tiny", "whisper-tiny.en": return "Whisper Tiny"
        default: return model.name
        }
    }
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading) {
                ForEach(["Sound", "Models", "Library", "Configuration"], id: \.self) { tab in Button(tab) { controller.settingsSelection = tab }.buttonStyle(.plain).padding(8).frame(maxWidth: .infinity, alignment: .leading).background(controller.settingsSelection == tab ? Color.accentColor.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 6)) }
                Spacer(); Button(attached ? "Detach into window" : "Back to menu") { detach() }; Button("Quit LightTTS") { NSApp.terminate(nil) }
            }.padding().frame(width: 150).background(.quaternary.opacity(0.4))
            VStack(alignment: .leading) {
                if controller.settingsSelection != "Models" { Text(controller.settingsSelection).font(.title2.bold()) }
                switch controller.settingsSelection {
                case "Sound": Text("Microphone: system default"); Text("Audio is processed locally at 16 kHz mono.").foregroundStyle(.secondary)
                case "Models":
                    ModelsPageView(controller: controller, deleting: $dialog.deleting)
                case "Library": ScrollView { LazyVStack(alignment: .leading) { ForEach(controller.history) { item in VStack(alignment: .leading) { Text(item.text); Text(item.date, style: .date).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading); Divider() } } }
                default:
                    Toggle("Push to talk", isOn: $pushToTalk)
                    Toggle("Use Right Option only", isOn: $rightOption)
                    Toggle("Keep model loaded between recordings", isOn: $keepModelLoaded)
                    Text("Loaded models are released after five minutes of inactivity.").font(.caption).foregroundStyle(.secondary)
                    HStack { Text("Option + key code:"); TextField("49 (Space)", value: $hotkeyCode, format: .number).frame(width: 80).disabled(rightOption) }
                    Button("Request permissions / Retry shortcut") { controller.requestPermissions() }
                    Text("Enable Accessibility and Input Monitoring in System Settings, then retry the shortcut. Accessibility allows text insertion.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(controller.settingsSelection == "Models" ? 0 : 16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }.frame(width: 650, height: 440)
        .background(ConfirmationFrameOverlay(model: dialog.deleting, name: dialog.deleting.map(alertName) ?? "", cancel: {
            dialog.deleting = nil
        }, delete: { model in
            do { try controller.deleteModel(model) } catch { controller.message = error.localizedDescription }
            dialog.deleting = nil
        }))
        .onChange(of: selectedModel) { _ in controller.reloadSelectedModel() }
    }
}

// A child panel covers the entire parent frame, including the title bar.
private struct ConfirmationFrameOverlay: NSViewRepresentable {
    let model: Model?
    let name: String
    let cancel: () -> Void
    let delete: (Model) -> Void

    func makeNSView(context: Context) -> Anchor { Anchor() }
    func updateNSView(_ view: Anchor, context: Context) {
        view.update(model: model, name: name, cancel: cancel, delete: delete)
    }
    static func dismantleNSView(_ view: Anchor, coordinator: ()) { view.removeOverlay() }

    final class Anchor: NSView {
        private var panel: ScrimPanel?
        private var card: ConfirmationCard?
        private var observers: [NSObjectProtocol] = []
        private var keyMonitor: Any?
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); install() }
        func update(model: Model?, name: String, cancel: @escaping () -> Void, delete: @escaping (Model) -> Void) {
            guard let model else { card = nil; removeOverlay(); return }
            card = ConfirmationCard(model: model, name: name, cancel: cancel, delete: { delete(model) })
            install()
        }
        private func install() {
            guard let card, let window else { return }
            if let panel { (panel.contentView as? NSHostingView<ConfirmationCard>)?.rootView = card; return }
            let panel = ScrimPanel(contentRect: window.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.contentView = NSHostingView(rootView: card)
            panel.setFrame(window.frame, display: true)
            window.addChildWindow(panel, ordered: .above)
            self.panel = panel
            for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak panel, weak window] _ in
                    if let window { panel?.setFrame(window.frame, display: true) }
                })
            }
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak window] event in
                if event.keyCode == 53, event.window === window { self?.card?.cancel(); return nil }
                return event
            }
        }
        func removeOverlay() {
            for observer in observers { NotificationCenter.default.removeObserver(observer) }
            observers.removeAll()
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
            if let panel { panel.parent?.removeChildWindow(panel); panel.orderOut(nil); self.panel = nil }
        }
        deinit { removeOverlay() }
    }
    final class ScrimPanel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }
}

private struct ConfirmationCard: View {
    let model: Model
    let name: String
    let cancel: () -> Void
    let delete: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        ZStack {
            Color.black.opacity(0.50)
            VStack(alignment: .leading, spacing: 11) {
                Text("Delete \(name)").font(.system(size: 13, weight: .bold))
                Text(model.engine == "apple" ? "LightTTS will forget this selection; macOS manages the speech assets." : model.engine == "cloud" ? "The model and its API key will be removed." : "Are you sure you want to delete this model?").font(.system(size: 13)).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button("Cancel", action: cancel).keyboardShortcut(.cancelAction).buttonStyle(AlertButton(destructive: false))
                    Button("Delete", role: .destructive, action: delete).buttonStyle(AlertButton(destructive: true))
                }
            }.padding(20).frame(width: 260).background(colorScheme == .dark ? Color(red: 18/255, green: 19/255, blue: 23/255) : Color(red: 179/255, green: 180/255, blue: 184/255), in: RoundedRectangle(cornerRadius: 34)).shadow(radius: 18).offset(y: -14)
        }.ignoresSafeArea()
    }
}

private struct AlertButton: ButtonStyle {
    let destructive: Bool
    @Environment(\.colorScheme) private var colorScheme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .semibold)).foregroundStyle(destructive ? Color.red : Color.primary).frame(maxWidth: .infinity).frame(height: 28).background(destructive ? (colorScheme == .dark ? Color(red: 37/255, green: 21/255, blue: 22/255) : Color.red.opacity(configuration.isPressed ? 0.3 : 0.14)) : Color.primary.opacity(configuration.isPressed ? 0.2 : 0.12), in: Capsule())
    }
}
