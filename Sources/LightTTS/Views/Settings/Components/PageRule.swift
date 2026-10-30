import SwiftUI
import AppKit
import AVFoundation
import ApplicationServices
import ServiceManagement
import LightTTSCore

struct PageRule: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Rectangle().fill(
            scheme == .dark
                ? Color(red: 80 / 255, green: 81 / 255, blue: 86 / 255) : Color(white: 226 / 255)
        ).frame(height: 0.5)
    }
}
