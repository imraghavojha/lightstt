import SwiftUI
import AppKit
import AVFoundation
import ApplicationServices
import ServiceManagement
import LightTTSCore

extension SoundPageView {
    var soundEffectsCard: some View {
        SettingsCard {
            SettingsRow(title: "Sound effects", height: 54) {
                HStack(spacing: 0) {
                    ForEach(["Simple", "Classic", "Off"], id: \.self) { value in
                        Button {
                            sound = value
                        } label: {
                            Text(value).font(
                                .system(size: 12, weight: sound == value ? .semibold : .regular)
                            ).frame(
                                width: value == "Classic" ? 62 : value == "Simple" ? 62 : 40,
                                height: 24
                            ).foregroundStyle(
                                sound == value
                                    ? (scheme == .dark ? Color.white : Color.black)
                                    : Color.secondary
                            ).background(
                                sound == value
                                    ? (scheme == .dark
                                        ? Color(red: 91 / 255, green: 93 / 255, blue: 99 / 255)
                                        : Color.white) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 7)
                            ).overlay(
                                RoundedRectangle(cornerRadius: 7).stroke(
                                    sound == value ? Color.primary.opacity(0.12) : .clear,
                                    lineWidth: 0.5)
                            ).shadow(
                                color: sound == value ? .black.opacity(0.12) : .clear, radius: 1,
                                y: 0.5)
                        }.buttonStyle(.responsive)
                    }
                }.padding(2).background(
                    Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 9)
                ).overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.primary.opacity(0.1)))
            }
            PageRule()
            SettingsRow(title: "Volume", height: 46) {
                Button {
                    playSound(start: true)
                } label: {
                    Image(systemName: "speaker.fill")
                }.buttonStyle(.responsive)
                SoundVolumeSlider(value: $volume, dark: scheme == .dark)
                Button {
                    playSound(start: false)
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                }.buttonStyle(.responsive)
            }
        }
    }
}
