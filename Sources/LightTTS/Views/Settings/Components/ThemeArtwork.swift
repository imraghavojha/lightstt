import SwiftUI
import AppKit
import AVFoundation
import ApplicationServices
import ServiceManagement
import LightTTSCore

struct ThemeArtwork: View {
    let mode: Int
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                if mode == 0 {
                    HStack(spacing: 0) {
                        desktop(dark: true).frame(width: proxy.size.width / 2)
                        desktop(dark: false).frame(width: proxy.size.width / 2)
                    }
                } else {
                    desktop(dark: mode == 2)
                }
            }.frame(width: proxy.size.width, height: proxy.size.height).clipped()
        }
    }
    private func desktop(dark: Bool) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                LinearGradient(
                    colors: dark
                        ? [
                            Color(red: 0.23, green: 0.16, blue: 0.50),
                            Color(red: 0.01, green: 0.05, blue: 0.28),
                            Color(red: 0.01, green: 0.20, blue: 0.60),
                        ]
                        : [
                            Color(red: 0.82, green: 0.82, blue: 0.77),
                            Color(red: 0.35, green: 0.70, blue: 0.90),
                            Color(red: 0.01, green: 0.17, blue: 0.59),
                        ], startPoint: .topLeading, endPoint: .bottomTrailing)
                Path { path in
                    path.move(to: CGPoint(x: -5, y: 30))
                    path.addCurve(
                        to: CGPoint(x: 51, y: -8), control1: CGPoint(x: 12, y: 24),
                        control2: CGPoint(x: 19, y: 4))
                    path.addLine(to: CGPoint(x: 73, y: -8))
                    path.addCurve(
                        to: CGPoint(x: -5, y: 42), control1: CGPoint(x: 36, y: 7),
                        control2: CGPoint(x: 25, y: 34))
                    path.closeSubpath()
                }.fill(
                    LinearGradient(
                        colors: dark
                            ? [
                                Color(red: 0.43, green: 0.32, blue: 0.68),
                                Color(red: 0.05, green: 0.22, blue: 0.58),
                            ]
                            : [
                                Color(red: 0.92, green: 0.88, blue: 0.76),
                                Color(red: 0.37, green: 0.69, blue: 0.91),
                            ], startPoint: .topLeading, endPoint: .bottomTrailing))
                RoundedRectangle(cornerRadius: 4).fill(
                    LinearGradient(
                        colors: dark
                            ? [
                                Color(red: 0.04, green: 0.13, blue: 0.37),
                                Color(red: 0.01, green: 0.07, blue: 0.25),
                            ]
                            : [
                                Color(red: 0.55, green: 0.76, blue: 0.96),
                                Color(red: 0.37, green: 0.64, blue: 0.89),
                            ], startPoint: .top, endPoint: .bottom)
                ).frame(width: 39, height: 14).overlay(
                    RoundedRectangle(cornerRadius: 4).stroke(
                        Color.white.opacity(0.3), lineWidth: 0.5)
                ).shadow(color: .black.opacity(0.3), radius: 2, y: 1).offset(
                    x: max(0, geometry.size.width - 41), y: 6)
                RoundedRectangle(cornerRadius: 8).fill(
                    LinearGradient(
                        colors: dark
                            ? [
                                Color(red: 0.09, green: 0.10, blue: 0.16),
                                Color(red: 0.01, green: 0.02, blue: 0.06),
                            ] : [Color.white, Color(red: 0.82, green: 0.87, blue: 0.94)],
                        startPoint: .top, endPoint: .bottom)
                ).frame(width: 52, height: 25).overlay(
                    RoundedRectangle(cornerRadius: 8).stroke(
                        Color.white.opacity(dark ? 0.18 : 0.7), lineWidth: 0.5)
                ).shadow(color: .black.opacity(0.35), radius: 2, y: -1).overlay(
                    alignment: .topLeading
                ) {
                    HStack(spacing: 4) {
                        Circle().fill(Color.green)
                        Circle().fill(Color.yellow)
                        Circle().fill(Color.red)
                    }.frame(height: 6).padding(.leading, 10).padding(.top, 9)
                }.offset(x: 0, y: 25)
                Circle().fill(Color.white.opacity(0.8)).frame(width: 4, height: 4).offset(
                    x: max(0, geometry.size.width - 7), y: 3)
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }
    }
}
