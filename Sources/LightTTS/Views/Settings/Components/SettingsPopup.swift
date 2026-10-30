import SwiftUI
import AppKit
import AVFoundation
import ApplicationServices
import ServiceManagement
import LightTTSCore

struct SettingsPopup: NSViewRepresentable {
    @Binding var selection: Int
    let options: [(Int, String)]
    let width: CGFloat
    init(selection: Binding<Int>, options: [(Int, String)], width: CGFloat) {
        self._selection = selection
        self.options = options
        self.width = width
    }
    init(selection: Binding<Int>, options: [String], width: CGFloat) {
        self.init(
            selection: selection,
            options: Array(options.enumerated()).map { ($0.offset, $0.element) }, width: width)
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.isBordered = false
        (button.cell as? NSPopUpButtonCell)?.arrowPosition = .noArrow
        button.target = context.coordinator
        button.action = #selector(Coordinator.changed(_:))
        return button
    }
    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.parent = self
        if button.itemTitles != options.map(\.1) {
            button.removeAllItems()
            button.addItems(withTitles: options.map(\.1))
        }
        if let index = options.firstIndex(where: { $0.0 == selection }) {
            button.selectItem(at: index)
        }
    }
    final class Coordinator: NSObject {
        var parent: SettingsPopup
        init(_ parent: SettingsPopup) { self.parent = parent }
        @objc func changed(_ sender: NSPopUpButton) {
            guard parent.options.indices.contains(sender.indexOfSelectedItem) else { return }
            parent.selection = parent.options[sender.indexOfSelectedItem].0
            if let index = parent.options.firstIndex(where: { $0.0 == parent.selection }) {
                sender.selectItem(at: index)
            }
        }
    }
}

struct NeutralSettingsPopup: View {
    @Binding var selection: Int
    let options: [(Int, String)]
    let width: CGFloat
    var body: some View {
        SettingsPopup(selection: $selection, options: options, width: width)
            .padding(.leading, 7).padding(.trailing, 22)
            .frame(width: width, height: 28)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
            .overlay(
                RoundedRectangle(cornerRadius: 9).stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
            )
            .overlay(alignment: .trailing) {
                Image(systemName: "chevron.up.chevron.down").font(
                    .system(size: 10, weight: .semibold)
                ).padding(.trailing, 8).allowsHitTesting(false)
            }
    }
}
