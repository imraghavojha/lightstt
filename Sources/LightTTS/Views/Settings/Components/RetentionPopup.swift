import SwiftUI
import AppKit
import AVFoundation
import ApplicationServices
import ServiceManagement
import LightTTSCore

struct RetentionPopup: View {
    @Binding var selection: Int
    private let options = [
        (0, "Forever"), (1, "1 day"), (7, "1 week"), (14, "2 weeks"), (30, "1 month"),
        (180, "6 months"), (365, "1 year"),
    ]
    var body: some View {
        NeutralSettingsPopup(selection: $selection, options: options, width: 125).frame(
            width: 125, height: 28)
    }
}
