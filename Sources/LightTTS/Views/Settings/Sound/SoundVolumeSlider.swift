import SwiftUI
import AppKit
import AVFoundation
import ApplicationServices
import ServiceManagement
import LightTTSCore

struct SoundVolumeSlider: View {
    @Binding var value: Double
    let dark: Bool
    var body: some View {
        GeometryReader { geometry in
            let trackWidth = max(1, geometry.size.width - 20)
            ZStack(alignment: .leading) {
                Capsule().fill(dark ? Color(white: 0.40) : Color(white: 0.86)).frame(
                    width: trackWidth, height: 6
                ).offset(x: 10)
                Capsule().fill(Color(red: 246 / 255, green: 79 / 255, blue: 158 / 255)).frame(
                    width: max(0, trackWidth * value), height: 6
                ).offset(x: 10)
                HStack {
                    ForEach(0..<9) { index in
                        Circle().fill(Color.primary.opacity(0.16)).frame(width: 2, height: 2)
                        if index < 8 { Spacer() }
                    }
                }.padding(.horizontal, 10).offset(y: 7)
                Capsule().fill(dark ? Color(white: 0.88) : Color.white).frame(width: 20, height: 16)
                    .shadow(color: .black.opacity(0.12), radius: 1, y: 1).offset(
                        x: trackWidth * value)
            }.frame(maxHeight: .infinity).contentShape(Rectangle()).gesture(
                DragGesture(minimumDistance: 0).onChanged { point in
                    value = min(1, max(0, (point.location.x - 10) / trackWidth))
                })
        }.frame(width: 211, height: 28).accessibilityElement().accessibilityLabel("Volume")
            .accessibilityValue("\(Int(value * 100)) percent").accessibilityAdjustableAction {
                direction in
                if direction == .increment {
                    value = min(1, value + 0.05)
                } else if direction == .decrement {
                    value = max(0, value - 0.05)
                }
            }
    }
}
