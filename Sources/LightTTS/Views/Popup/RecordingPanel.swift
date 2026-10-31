import AppKit

/// The floating recording window. In the Mini style it can be dragged from anywhere on
/// the capsule; a click that does not move still reaches the buttons inside it.
final class RecordingPanel: NSPanel {
    var allowsDragging = true
    var onMoved: ((NSPoint) -> Void)?
    private var press: NSPoint?
    private var dragStart: (mouse: NSPoint, origin: NSPoint)?

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            press = allowsDragging ? NSEvent.mouseLocation : nil
            dragStart = nil
        case .leftMouseDragged:
            guard let press else { break }
            let mouse = NSEvent.mouseLocation
            if dragStart == nil {
                guard hypot(mouse.x - press.x, mouse.y - press.y) >= 3 else { break }
                dragStart = (press, frame.origin)
            }
            if let start = dragStart {
                setFrameOrigin(
                    NSPoint(
                        x: start.origin.x + mouse.x - start.mouse.x,
                        y: start.origin.y + mouse.y - start.mouse.y))
            }
            return
        case .leftMouseUp:
            defer {
                press = nil
                dragStart = nil
            }
            guard dragStart != nil else { break }
            onMoved?(NSPoint(x: frame.midX, y: frame.midY))
            // Release the press far outside the panel, so a drag never clicks a button.
            if let release = NSEvent.mouseEvent(
                with: .leftMouseUp, location: NSPoint(x: -10_000, y: -10_000),
                modifierFlags: [], timestamp: event.timestamp, windowNumber: windowNumber,
                context: nil, eventNumber: event.eventNumber, clickCount: 1, pressure: 0)
            {
                super.sendEvent(release)
            }
            return
        default:
            break
        }
        super.sendEvent(event)
    }
}

/// Where the Mini recording window appears: the user's last drop point, or bottom center.
enum RecordingPanelPlacement {
    static let key = "recordingPanelPosition"

    static func savedCenter() -> NSPoint? {
        guard let value = UserDefaults.standard.string(forKey: key) else { return nil }
        let parts = value.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 2 else { return nil }
        let point = NSPoint(x: parts[0], y: parts[1])
        return NSScreen.screens.contains { $0.frame.contains(point) } ? point : nil
    }

    static func save(center: NSPoint) {
        UserDefaults.standard.set("\(Int(center.x)),\(Int(center.y))", forKey: key)
    }

    static func origin(for size: NSSize) -> NSPoint? {
        if let center = savedCenter() {
            return NSPoint(x: center.x - size.width / 2, y: center.y - size.height / 2)
        }
        guard let frame = NSScreen.main?.visibleFrame else { return nil }
        return NSPoint(x: frame.midX - size.width / 2, y: frame.minY + 70)
    }
}

/// Notch geometry for the Dynamic Island style. Screens without a notch get a pill that
/// hangs from the menu bar at the same place.
struct IslandMetrics: Equatable {
    static let wing: CGFloat = 72
    static let margin: CGFloat = 60
    static let dropHeight: CGFloat = 64
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let screenFrame: NSRect

    static func current() -> IslandMetrics? {
        let screens = NSScreen.screens
        let notched = screens.first { $0.safeAreaInsets.top > 0 }
        guard let screen = notched ?? NSScreen.main ?? screens.first else { return nil }
        if screen.safeAreaInsets.top > 0, let left = screen.auxiliaryTopLeftArea,
            let right = screen.auxiliaryTopRightArea
        {
            return IslandMetrics(
                notchWidth: max(0, screen.frame.width - left.width - right.width),
                notchHeight: screen.safeAreaInsets.top, screenFrame: screen.frame)
        }
        let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
        return IslandMetrics(
            notchWidth: 0, notchHeight: menuBar > 0 ? menuBar : 24, screenFrame: screen.frame)
    }

    var expandedWidth: CGFloat { notchWidth + 2 * Self.wing }
    var panelSize: NSSize {
        NSSize(width: expandedWidth + 2 * Self.margin, height: notchHeight + Self.dropHeight)
    }
    var panelFrame: NSRect {
        NSRect(
            x: screenFrame.midX - panelSize.width / 2, y: screenFrame.maxY - panelSize.height,
            width: panelSize.width, height: panelSize.height)
    }
}
