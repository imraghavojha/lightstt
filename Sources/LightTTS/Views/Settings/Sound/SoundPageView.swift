import SwiftUI
import AppKit
import AVFoundation
import ApplicationServices
import ServiceManagement
import LightTTSCore

struct SoundPageView: View {
    @ObservedObject var controller: AppController
    @Environment(\.colorScheme) var scheme
    @AppStorage("soundEffects") var sound = "Classic"
    @AppStorage("soundVolume") var volume = 0.8
    @AppStorage("recordingSound") var recordingSound = "Pause"
    @AppStorage("increaseMicVolume") var increaseMic = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                soundEffectsCard
                Text("Recording").font(.system(size: 13, weight: .semibold)).padding(.top, 18)
                    .padding(.bottom, 8.5)
                recordingAudioCard
                if !controller.message.isEmpty {
                    Text(controller.message).font(.caption).foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 24).padding(.top, 16)
        }.font(.system(size: 13))
    }
    func playSound(start: Bool) { AudioSettings.cue(start: start) }
}
