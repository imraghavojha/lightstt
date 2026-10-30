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
                                } else if value == "Classic" {
                                    VStack(spacing: 2) {
                                        HStack(spacing: 1) {
                                            ForEach(
                                                Array(
                                                    [
                                                        2, 4, 7, 5, 9, 7, 4, 6, 3, 5, 8, 5, 4, 7,
                                                        11, 8, 6, 5, 3, 6, 4, 5, 4, 3, 2,
                                                    ].enumerated()), id: \.offset
                                            ) { _, height in
                                                Capsule().fill(.white).frame(
                                                    width: 1, height: CGFloat(height))
                                            }
                                        }.frame(height: 16)
                                        RoundedRectangle(cornerRadius: 3).fill(Color(white: 0.25))
                                            .frame(width: 56, height: 6)
                                    }.frame(width: 62, height: 30).background(
                                        .black, in: RoundedRectangle(cornerRadius: 6))
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
                        Text(value).font(.system(size: 11, weight: .medium)).lineLimit(1).fixedSize(
                            horizontal: true, vertical: false
                        ).foregroundStyle(selection.wrappedValue == value ? .primary : .secondary)
                    }
                }.buttonStyle(.plain)
            }
        }
    }
}
