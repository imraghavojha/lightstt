import SwiftUI
import AppKit
import AVFoundation
import ApplicationServices
import ServiceManagement
import LightTTSCore

@MainActor final class SettingsDevices: ObservableObject {
    @Published var devices: [InputDevice] = []
    @Published var systemDefault: InputDevice?
    var choices: [InputDevice] {
        InputDevice.choices(available: devices, systemDefault: systemDefault)
    }
    private var observers: [NSObjectProtocol] = []
    init() {
        refresh()
        for name in [
            AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification,
        ] {
            observers.append(
                NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
                    [weak self] _ in Task { @MainActor in self?.refresh() }
                })
        }
    }
    deinit { for observer in observers { NotificationCenter.default.removeObserver(observer) } }
    private func refresh() {
        DispatchQueue.global(qos: .userInitiated).async {
            let devices = InputDevice.available
            let systemDefault = InputDevice.systemDefault
            DispatchQueue.main.async {
                self.devices = devices
                self.systemDefault = systemDefault
            }
        }
    }
}

extension SettingsView {
    var header: some View {
        HStack {
            Text(controller.settingsSelection).font(.system(size: 13, weight: .bold))
            Spacer()
            Menu {
                let selected = selectedInput
                let followsDefault = selected.isEmpty || selected == devices.systemDefault?.id
                ForEach(devices.choices, id: \.id) { device in
                    Button {
                        selectedInput = device.id
                    } label: {
                        if device.id.isEmpty ? followsDefault : device.id == selected {
                            Label(device.name, systemImage: "checkmark")
                        } else {
                            Text(device.name)
                        }
                    }
                }
            } label: {
                Image(systemName: "laptopcomputer").font(.system(size: 14)).foregroundStyle(
                    .secondary)
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 28, height: 28)
                .background(
                    LinearGradient(
                        colors: dark
                            ? [Color(white: 0.29), Color(white: 0.22)]
                            : [Color(white: 0.99), Color(white: 0.92)], startPoint: .top,
                        endPoint: .bottom), in: Circle()
                ).overlay(Circle().stroke(Color.primary.opacity(0.16), lineWidth: 0.5)).offset(x: 6)
                .help("Select microphone")
        }.padding(.horizontal, 16).frame(height: 48).background(
            Color(
                nsColor: dark
                    ? NSColor(srgbRed: 43 / 255, green: 48 / 255, blue: 53 / 255, alpha: 1)
                    : NSColor(srgbRed: 0.95, green: 0.95, blue: 0.95, alpha: 1))
        ).zIndex(1)
    }
}
