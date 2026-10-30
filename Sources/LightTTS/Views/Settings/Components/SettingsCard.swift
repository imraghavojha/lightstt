import SwiftUI
import AppKit
import AVFoundation
import ApplicationServices
import ServiceManagement
import LightTTSCore

struct SettingsCard<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }.padding(.horizontal, 16).background(
            scheme == .dark
                ? Color(red: 58 / 255, green: 63 / 255, blue: 68 / 255) : Color(white: 253 / 255),
            in: RoundedRectangle(cornerRadius: 18)
        ).overlay(
            RoundedRectangle(cornerRadius: 18).stroke(
                LinearGradient(
                    colors: scheme == .dark
                        ? [
                            Color(red: 77 / 255, green: 78 / 255, blue: 83 / 255),
                            Color(red: 55 / 255, green: 57 / 255, blue: 62 / 255),
                        ] : [Color.white, Color.black.opacity(0.09)], startPoint: .top,
                    endPoint: .bottom), lineWidth: 0.5))
    }
}
