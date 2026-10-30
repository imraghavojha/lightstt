import SwiftUI
import AppKit
import AVFoundation
import ApplicationServices
import ServiceManagement
import LightTTSCore

private enum SettingsTab: String, CaseIterable {
    case library = "Library"
    case configuration = "Configuration"
    case sound = "Sound"
    case models = "Models"
    var label: String {
        switch self {
        case .library: "Library"
        case .models: "Models library"
        default: rawValue
        }
    }
    var icon: String {
        switch self {
        case .sound: "speaker.wave.2.fill"
        case .models: "book.fill"
        case .library: "house.fill"
        case .configuration: "gearshape"
        }
    }
}

extension SettingsView {
    var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(SettingsTab.allCases, id: \.rawValue) { tab in
                Button {
                    UITrace.begin("page-\(tab.rawValue)")
                    controller.selectSettings(tab.rawValue)
                } label: {
                    HStack(spacing: 5) {
                        Group {
                            if tab == .configuration {
                                ConfigurationGlyph()
                            } else {
                                Image(systemName: tab.icon).font(
                                    .system(size: 12, weight: .semibold))
                            }
                        }.foregroundStyle(.white).frame(width: 20, height: 20).background(
                            (tab == .library
                                ? Color(red: 1, green: 0.42, blue: 0.19) : Color(white: 0.32))
                                .gradient, in: RoundedRectangle(cornerRadius: 5)
                        ).overlay(
                            RoundedRectangle(cornerRadius: 5).stroke(
                                Color.white.opacity(0.12), lineWidth: 0.5)
                        ).shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                        Text(tab.label).font(.system(size: 13, weight: .medium))
                        Spacer()
                    }.padding(.horizontal, 8).frame(height: 35).background(
                        controller.settingsSelection == tab.rawValue
                            ? (dark ? Color.white.opacity(0.16) : Color.white.opacity(0.65))
                            : .clear, in: RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain)
                if tab == .library { Color.clear.frame(height: 12) }
            }
            Spacer()
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "waveform").font(.system(size: 12, weight: .semibold))
                    Text("LightTTS").font(.system(size: 11, weight: .semibold))
                    Spacer()
                }
                Text("Your voice, in text.").font(.system(size: 11, weight: .medium))
                Text("Record and transcribe from your menu bar.").font(.system(size: 10))
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(9).frame(maxWidth: .infinity, alignment: .leading).background(
                dark ? Color.white.opacity(0.07) : Color.white.opacity(0.55),
                in: RoundedRectangle(cornerRadius: 9)
            ).overlay(
                RoundedRectangle(cornerRadius: 9).stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
            )
            Text("LightTTS").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity).frame(height: 36).background(
                    Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10)
                ).overlay(
                    RoundedRectangle(cornerRadius: 10).stroke(
                        Color.primary.opacity(0.12), lineWidth: 1)
                ).padding(.top, 24)
        }.padding(.horizontal, 12).padding(.top, 58).padding(.bottom, 12).frame(width: 184).frame(
            maxHeight: .infinity
        ).background(
            Color(
                nsColor: dark
                    ? NSColor(srgbRed: 58 / 255, green: 62 / 255, blue: 69 / 255, alpha: 1)
                    : NSColor(srgbRed: 0.91, green: 0.91, blue: 0.91, alpha: 1)))
    }
}

private struct ConfigurationGlyph: View {
    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            for index in 0..<16 {
                let angle = Double(index) * .pi / 8
                var mark = Path()
                mark.move(to: CGPoint(x: center.x + cos(angle) * 5, y: center.y + sin(angle) * 5))
                mark.addLine(
                    to: CGPoint(x: center.x + cos(angle) * 7, y: center.y + sin(angle) * 7))
                context.stroke(mark, with: .color(.white), lineWidth: 0.8)
            }
            let ring = CGRect(x: center.x - 4.5, y: center.y - 4.5, width: 9, height: 9)
            context.stroke(Path(ellipseIn: ring), with: .color(.white), lineWidth: 1)
        }.frame(width: 16, height: 16)
    }
}
