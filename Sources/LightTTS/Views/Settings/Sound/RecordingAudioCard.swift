import SwiftUI
import AppKit
import AVFoundation
import ApplicationServices
import ServiceManagement
import LightTTSCore

extension SoundPageView {
    var recordingAudioCard: some View {
        SettingsCard {
            SettingsRow(title: "Sound while recording", contentOffset: 5) {
                Menu {
                    ForEach(["Keep Playing", "Pause", "Mute", "Lower"], id: \.self) { value in
                        Button(value) {
                            recordingSound = value
                            if value == "Pause" { AutomationPlayers.requestRunning() }
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(
                            systemName: recordingSound == "Pause"
                                ? "pause.circle"
                                : recordingSound == "Mute" ? "speaker.slash" : "speaker.wave.2")
                        Text(recordingSound)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 10))
                    }.padding(.horizontal, 9)
                }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 145, height: 30)
                    .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.primary.opacity(0.1)))
                    .overlay(alignment: .trailing) {
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 10))
                            .foregroundStyle(.secondary).padding(.trailing, 9).allowsHitTesting(
                                false)
                    }
                    .help(
                        "Pause controls Music and Spotify (macOS asks once per app). Mute and Lower reduce output volume while recording."
                    )
            }
            PageRule()
            HStack {
                Text("Automatically increase microphone volume")
                Image(systemName: "questionmark.circle").help(
                    "Increase input volume while recording")
                Spacer()
                Toggle("", isOn: $increaseMic).labelsHidden().toggleStyle(
                    ReferenceSwitchStyle(label: "Automatically increase microphone volume"))
            }.offset(y: -2).frame(minHeight: 44)
        }
    }
}
