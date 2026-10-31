import SwiftUI
import AppKit
import AVFoundation
import ApplicationServices
import ServiceManagement
import LightTTSCore

extension ConfigurationPageView {
    func choices(_ values: [String], selection: Binding<String>, icons: [String]) -> some View {
        HStack(spacing: values.first == "Auto" ? 15 : 16) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                Button {
                    selection.wrappedValue = value
                } label: {
                    VStack(spacing: values.first == "Auto" ? 8 : 5) {
                        ZStack {
                            if values.first == "Auto" {
                                ThemeArtwork(mode: index)
                            } else {
                                RoundedRectangle(cornerRadius: 8).fill(
                                    scheme == .dark
                                        ? Color.black.opacity(0.36)
                                        : (selection.wrappedValue == value
                                            ? Color.blue.opacity(0.10) : Color.white))
                                if value == "None" {
                                    Image(systemName: "eye.slash").foregroundStyle(.secondary)
                                } else if value == "Island" {
                                    IslandChoiceArtwork(selected: selection.wrappedValue == value)
                                } else {
                                    HStack(spacing: 1) {
                                        ForEach(
                                            Array([2, 4, 7, 4, 9, 5, 7, 4, 6, 3, 2].enumerated()),
                                            id: \.offset
                                        ) { _, height in
                                            Capsule().fill(Color.white).frame(
                                                width: 2, height: CGFloat(height))
                                        }
                                    }.frame(width: 50, height: 20).background(.black, in: Capsule())
                                }
                            }
                        }.frame(width: values.first == "Auto" ? 70 : 95, height: 44).clipShape(
                            RoundedRectangle(cornerRadius: 8)
                        ).overlay(
                            RoundedRectangle(cornerRadius: 8).stroke(
                                Color.primary.opacity(0.2), lineWidth: 0.5)
                        ).overlay(
                            RoundedRectangle(cornerRadius: 10).stroke(
                                selection.wrappedValue == value
                                    ? Color(red: 0 / 255, green: 145 / 255, blue: 255 / 255)
                                    : .clear, lineWidth: 2
                            ).padding(-3))
                        Text(value == "Island" ? "Dynamic Island" : value).font(
                            .system(size: 11, weight: .medium)
                        ).lineLimit(1).fixedSize(
                            horizontal: true, vertical: false
                        ).foregroundStyle(selection.wrappedValue == value ? .primary : .secondary)
                    }
                }.buttonStyle(.responsive)
            }
        }
    }
}

/// A small preview of the notch with a wing on each side.
private struct IslandChoiceArtwork: View {
    let selected: Bool

    var body: some View {
        VStack {
            HStack(spacing: 0) {
                Circle().fill(Color(red: 1, green: 0.27, blue: 0.23)).frame(width: 4, height: 4)
                    .frame(width: 16)
                Color.black.frame(width: 22)
                HStack(spacing: 1) {
                    ForEach(Array([3, 5, 7, 5, 3].enumerated()), id: \.offset) { _, height in
                        Capsule().fill(Color.white).frame(width: 1.5, height: CGFloat(height))
                    }
                }.frame(width: 16)
            }.frame(height: 11).background(
                UnevenRoundedRectangle(bottomLeadingRadius: 5, bottomTrailingRadius: 5)
                    .fill(.black))
            Spacer(minLength: 0)
        }
    }
}
