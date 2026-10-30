import SwiftUI
import AppKit
import AVFoundation
import ApplicationServices

final class PermissionStatus: ObservableObject {
    @Published var accessibility = AXIsProcessTrusted()
    @Published var microphone = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
}

struct PermissionsCard: View {
    @ObservedObject var controller: AppController
    @StateObject private var status = PermissionStatus()
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Permissions").font(.system(size: 13, weight: .medium)).padding(.bottom, 9)
            SettingsCard {
                row("Microphone", granted: status.microphone, pane: "Privacy_Microphone")
                Divider()
                row("Accessibility", granted: status.accessibility, pane: "Privacy_Accessibility")
            }
        }.padding(.bottom, 18)
            .onAppear { refresh() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }
    private func refresh() {
        let access = AXIsProcessTrusted()
        if access != status.accessibility { status.accessibility = access; controller.installHotkey() }
        status.microphone = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    private func row(_ title: String, granted: Bool, pane: String) -> some View {
        HStack { Circle().fill(granted ? Color.green : Color.red).frame(width: 8, height: 8); Text(title); Spacer(); Text(granted ? "Granted" : "Not granted").foregroundStyle(.secondary).font(.system(size: 11)); Button(granted ? "Open Settings" : "Grant") { if pane == "Privacy_Microphone" && AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined { Task { _ = await AVCaptureDevice.requestAccess(for: .audio) } }; if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(url) } }.controlSize(.small) }.frame(height: 44)
    }
}
