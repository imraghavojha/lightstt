import SwiftUI
import AppKit
import AVFoundation
import ApplicationServices

final class PermissionStatus: ObservableObject {
    @Published var accessibility = AXIsProcessTrusted()
    @Published var microphone = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    @Published var automation: [(String, String)] = []
}

struct PermissionsCard: View {
    @ObservedObject var controller: AppController
    @StateObject private var status = PermissionStatus()
    @AppStorage("recordingSound") private var recordingSound = "Pause"
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Permissions").font(.system(size: 13, weight: .medium)).padding(.bottom, 9)
            SettingsCard {
                row("Microphone", granted: status.microphone, pane: "Privacy_Microphone")
                Divider()
                row("Accessibility", granted: status.accessibility, pane: "Privacy_Accessibility")
                if recordingSound == "Pause" {
                    Divider()
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Automation (pause music)")
                            Text(status.automation.isEmpty ? "No supported players running" : status.automation.map { "\($0.0): \($0.1)" }.joined(separator: " · "))
                                .foregroundStyle(.secondary).font(.system(size: 11))
                        }
                        Spacer()
                        Button("Grant") { AutomationPlayers.requestRunning() }.controlSize(.small)
                        Button("Open Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") { NSWorkspace.shared.open(url) }
                        }.controlSize(.small)
                    }.frame(minHeight: 44)
                }
            }
        }.padding(.bottom, 18)
            .onAppear { refresh() }
            .onReceive(NotificationCenter.default.publisher(for: .automationPermissionChanged)) { _ in refresh() }
            .onChange(of: recordingSound) { _ in refresh() }
            .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in refresh() }
            .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in refresh() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }
    private func refresh() {
        let access = AXIsProcessTrusted()
        if access != status.accessibility { status.accessibility = access; controller.installHotkey() }
        status.microphone = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let players = [("Spotify", "com.spotify.client"), ("Music", "com.apple.Music")].filter { !NSRunningApplication.runningApplications(withBundleIdentifier: $0.1).isEmpty }
        status.automation = players.map { ($0.0, "Checking…") }
        DispatchQueue.global(qos: .utility).async {
            let results = players.map { name, bundle in
                let target = NSAppleEventDescriptor(bundleIdentifier: bundle)
                let code = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, false)
                return (name, code == noErr ? "Allowed" : code == errAEEventWouldRequireUserConsent ? "Not yet requested" : "Not allowed")
            }
            DispatchQueue.main.async { status.automation = results }
        }
    }

    private func row(_ title: String, granted: Bool, pane: String) -> some View {
        HStack { Circle().fill(granted ? Color.green : Color.red).frame(width: 8, height: 8); Text(title); Spacer(); Text(granted ? "Granted" : "Not granted").foregroundStyle(.secondary).font(.system(size: 11)); Button(granted ? "Open Settings" : "Grant") { if pane == "Privacy_Microphone" && AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined { Task { _ = await AVCaptureDevice.requestAccess(for: .audio) } }; if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(url) } }.controlSize(.small) }.frame(height: 44)
    }
}
