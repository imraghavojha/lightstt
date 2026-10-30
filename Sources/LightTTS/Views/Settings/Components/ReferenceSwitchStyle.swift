import SwiftUI
import AppKit
import AVFoundation
import ApplicationServices
import ServiceManagement
import LightTTSCore

struct ReferenceSwitchStyle: ToggleStyle {
    let label: String
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            Capsule().fill(
                configuration.isOn
                    ? Color(red: 246 / 255, green: 79 / 255, blue: 158 / 255)
                    : Color.primary.opacity(0.16)
            )
            .overlay(
                Circle().fill(Color.white).frame(width: 16, height: 16).shadow(
                    color: .black.opacity(0.18), radius: 1, y: 1
                ).offset(x: configuration.isOn ? 7 : -7)
            )
            .frame(width: 34, height: 20).opacity(enabled ? 1 : 0.5)
        }.buttonStyle(.plain).accessibilityLabel(label).accessibilityValue(
            configuration.isOn ? "On" : "Off")
    }
}
