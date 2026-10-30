import SwiftUI
import AppKit
import AVFoundation
import ApplicationServices
import ServiceManagement
import LightTTSCore

// A child panel covers the entire parent frame, including the title bar.
struct ConfirmationFrameOverlay: NSViewRepresentable {
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
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            install()
        }
        func update(
            model: Model?, name: String, cancel: @escaping () -> Void,
            delete: @escaping (Model) -> Void
        ) {
            guard let model else {
                card = nil
                removeOverlay()
                return
            }
            card = ConfirmationCard(
                model: model, name: name, cancel: cancel, delete: { delete(model) })
            install()
        }
        private func install() {
            guard let card, let window else { return }
            if let panel {
                (panel.contentView as? NSHostingView<ConfirmationCard>)?.rootView = card
                return
            }
            let panel = ScrimPanel(
                contentRect: window.frame, styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.contentView = NSHostingView(rootView: card)
            panel.setFrame(window.frame, display: true)
            window.addChildWindow(panel, ordered: .above)
            self.panel = panel
            for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
                observers.append(
                    NotificationCenter.default.addObserver(
                        forName: name, object: window, queue: .main
                    ) { [weak panel, weak window] _ in
                        if let window { panel?.setFrame(window.frame, display: true) }
                    })
            }
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
                [weak self, weak window] event in
                if event.keyCode == 53, event.window === window {
                    self?.card?.cancel()
                    return nil
                }
                return event
            }
        }
        func removeOverlay() {
            for observer in observers { NotificationCenter.default.removeObserver(observer) }
            observers.removeAll()
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
                self.keyMonitor = nil
            }
            if let panel {
                panel.parent?.removeChildWindow(panel)
                panel.orderOut(nil)
                self.panel = nil
            }
        }
        deinit { removeOverlay() }
    }
    final class ScrimPanel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }
}
