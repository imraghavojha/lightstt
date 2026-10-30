import SwiftUI
import AppKit
import AVFoundation
import ApplicationServices
import ServiceManagement
import LightTTSCore

struct InlineStatus: View {
    let message: String
    let dismiss: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle")
            Text(message).frame(maxWidth: .infinity, alignment: .leading)
            Button(action: dismiss) { Image(systemName: "xmark") }.buttonStyle(.plain).help(
                "Dismiss")
        }.font(.caption).foregroundStyle(.red).padding(12)
            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}
