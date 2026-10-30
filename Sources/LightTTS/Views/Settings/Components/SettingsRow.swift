import SwiftUI
import AppKit
import AVFoundation
import ApplicationServices
import ServiceManagement
import LightTTSCore

struct SettingsRow<Content: View>: View {
    let title: String
    var help: String? = nil
    var height: CGFloat = 48
    var contentOffset: CGFloat = 0
    @ViewBuilder var content: Content
    var body: some View {
        HStack(spacing: 8) {
            Text(title).lineLimit(1).fixedSize(horizontal: true, vertical: false)
            if let help { Image(systemName: "info.circle").help(help) }
            Spacer()
            content
        }.offset(y: contentOffset).frame(minHeight: height)
    }
}
