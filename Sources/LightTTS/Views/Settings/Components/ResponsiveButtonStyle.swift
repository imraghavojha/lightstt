import SwiftUI

/// A plain button whose whole frame is clickable, with immediate press feedback.
struct ResponsiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}

extension ButtonStyle where Self == ResponsiveButtonStyle {
    static var responsive: ResponsiveButtonStyle { ResponsiveButtonStyle() }
}
