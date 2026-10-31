import AppKit
import QuartzCore

enum RecordingHUDStyle: Equatable {
    case mini
    case island(IslandMetrics)
}

/// The recording window content. It is drawn with plain Core Animation layers, so size
/// changes and the level meter are interpolated by the render server at the display's
/// refresh rate. The main thread only sets target values when something changes.
@MainActor final class RecordingHUDView: NSView {
    var onCancel: (() -> Void)?
    private(set) var style: RecordingHUDStyle = .mini
    private var state = "idle"
    private var message = ""
    private var copied = false

    private let canvas = NSView()
    private let shape = CALayer()
    private let barGroup = CALayer()
    private var bars: [CALayer] = []
    private let icon = CALayer()
    private let badge = CALayer()
    private let dot = CALayer()
    private let spinner = CAShapeLayer()
    private let label = NSTextField(wrappingLabelWithString: "")
    private let closeButton = NSButton()
    private var shapeFrame = NSRect.zero
    private var level: CGFloat = 0
    private var lastLevelTime: CFTimeInterval = 0

    private static let miniFill = NSColor(
        srgbRed: 11 / 255, green: 11 / 255, blue: 12 / 255, alpha: 1)
    private static let miniEdge = NSColor(
        srgbRed: 64 / 255, green: 64 / 255, blue: 64 / 255, alpha: 1)
    private static let miniBars: [CGFloat] = [6, 10, 14, 14, 10, 6]
    private static let islandBars: [CGFloat] = [5, 9, 13, 13, 9, 5]

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = .clear
        canvas.wantsLayer = true
        canvas.frame = bounds
        canvas.autoresizingMask = [.width, .height]
        addSubview(canvas)
        guard let root = canvas.layer else { return }
        root.isOpaque = false
        for sublayer in [shape, barGroup, icon, badge, dot, spinner] { root.addSublayer(sublayer) }
        for _ in 0..<6 {
            let bar = CALayer()
            bar.backgroundColor = .white
            barGroup.addSublayer(bar)
            bars.append(bar)
        }
        dot.backgroundColor = NSColor(srgbRed: 1, green: 0.27, blue: 0.23, alpha: 1).cgColor
        dot.bounds = CGRect(x: 0, y: 0, width: 8, height: 8)
        dot.cornerRadius = 4
        spinner.path = CGPath(
            ellipseIn: CGRect(x: 0, y: 0, width: 13, height: 13), transform: nil)
        spinner.bounds = CGRect(x: 0, y: 0, width: 13, height: 13)
        spinner.fillColor = nil
        spinner.strokeColor = NSColor.white.cgColor
        spinner.lineWidth = 1.6
        spinner.lineCap = .round
        spinner.strokeEnd = 0.7
        icon.contentsGravity = .center
        badge.contentsGravity = .center
        badge.contents = Self.symbol("doc.on.clipboard", size: 11, weight: .medium, alpha: 0.8)?
            .layerContents(forContentsScale: 2)
        badge.bounds = CGRect(x: 0, y: 0, width: 16, height: 16)
        label.isEditable = false
        label.isSelectable = false
        label.drawsBackground = false
        label.isBordered = false
        label.textColor = .white
        label.maximumNumberOfLines = 3
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)
        closeButton.isBordered = false
        closeButton.imagePosition = .imageOnly
        closeButton.image = Self.symbol("xmark", size: 10, weight: .semibold, alpha: 0.8)
        closeButton.target = self
        closeButton.action = #selector(cancelPressed)
        addSubview(closeButton)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        apply(state: "idle", message: "", copied: false, appearing: true)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        guard state == "error", shapeFrame.contains(convert(event.locationInWindow, from: nil))
        else { return }
        onCancel?()
    }
    @objc private func cancelPressed() { onCancel?() }

    func setStyle(_ newStyle: RecordingHUDStyle) {
        guard newStyle != style else { return }
        style = newStyle
        apply(state: state, message: message, copied: copied, appearing: true)
    }

    /// Moves to the given state. `appearing` starts from the collapsed shape, so a window
    /// that is just being shown grows into place instead of popping in.
    func apply(
        state newState: String, message newMessage: String, copied newCopied: Bool, appearing: Bool
    ) {
        let changed = newState != state || newMessage != message || newCopied != copied
        guard changed || appearing else { return }
        state = newState
        message = newMessage
        copied = newCopied
        if newState != "recording" && newState != "starting" { level = 0 }
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        for sublayer in [shape, barGroup, icon, badge, dot, spinner] + bars {
            sublayer.contentsScale = scale
        }
        if appearing {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layoutCollapsed()
            CATransaction.commit()
        }
        switch style {
        case .mini: layoutMini(animated: true)
        case .island(let metrics): layoutIsland(metrics, animated: true)
        }
        setAccessibilityLabel(newState == "error" ? newMessage : newState.capitalized)
    }

    /// Updates the level meter. Each step is interpolated over the time since the previous
    /// sample, so the bars move continuously instead of jumping at the capture rate.
    func setLevel(_ value: Float) {
        guard state == "recording" else { return }
        let target = CGFloat(min(1, max(0, value)))
        // Rise quickly, fall gently.
        level = target > level ? target : level * 0.6 + target * 0.4
        let now = CACurrentMediaTime()
        let interval = lastLevelTime == 0 ? 0.08 : min(0.15, max(0.04, now - lastLevelTime))
        lastLevelTime = now
        CATransaction.begin()
        CATransaction.setAnimationDuration(interval)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .linear))
        layoutBars()
        if case .island = style { dot.opacity = Float(0.55 + 0.45 * min(1, level * 3)) }
        CATransaction.commit()
    }

    // MARK: Layout

    private var isIsland: Bool {
        if case .island = style { return true }
        return false
    }

    private func layoutCollapsed() {
        switch style {
        case .mini:
            let center = miniCenter
            setShape(CGRect(x: center.x - 22, y: center.y - 16, width: 44, height: 32), radius: 16)
            shape.opacity = 0
            shape.transform = CATransform3DMakeScale(0.85, 0.85, 1)
        case .island(let metrics):
            shape.opacity = 1
            shape.transform = CATransform3DIdentity
            let top = bounds.maxY
            setShape(
                CGRect(
                    x: bounds.midX - metrics.notchWidth / 2, y: top - metrics.notchHeight,
                    width: metrics.notchWidth, height: metrics.notchHeight), radius: 11)
        }
        for item in [barGroup, icon, badge, dot, spinner] { item.opacity = 0 }
        label.alphaValue = 0
        closeButton.alphaValue = 0
    }

    private var miniCenter: CGPoint { CGPoint(x: bounds.midX, y: bounds.midY + 9.5) }

    private func layoutMini(animated: Bool) {
        let center = miniCenter
        var width: CGFloat = 60
        var height: CGFloat = 32
        var labelText = ""
        var labelFont = NSFont.systemFont(ofSize: 11)
        var labelColor = NSColor.white
        var iconName: String?
        var showClose = false
        switch state {
        case "idle":
            width = 45
            height = 8
        case "processing":
            width = 76
            iconName = "waveform"
            showClose = true
        case "loading":
            labelText = "Loading model…"
            labelFont = .systemFont(ofSize: 11, weight: .semibold)
            width = textWidth(labelText, labelFont) + 50
            showClose = true
        case "done":
            iconName = "checkmark"
            if copied {
                labelText = "Copied to clipboard"
                labelColor = NSColor.white.withAlphaComponent(0.7)
                width = textWidth(labelText, labelFont) + 48
            }
        case "error":
            iconName = "exclamationmark.circle"
            labelText = message
            width = min(360, max(100, textWidth(message, labelFont) + 66))
            showClose = true
        default: break
        }
        // Error text wraps between the icon and the dismiss button.
        let textArea = width - 14 - 13 - 8 - 22 - 14
        if state == "error" {
            let textHeight = textSize(message, labelFont, width: textArea).height
            height = max(32, textHeight + 20)
        }
        let frame = CGRect(
            x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
        animateShape(to: frame, radius: min(height / 2, 18), spring: (420, 30))
        let fade = state != "idle"
        transition {
            self.shape.opacity = fade ? 1 : 0
            self.shape.transform = CATransform3DIdentity
            self.shape.backgroundColor = Self.miniFill.cgColor
            self.shape.borderColor = Self.miniEdge.cgColor
            self.shape.borderWidth = 1
            self.shape.shadowColor = .black
            self.shape.shadowOpacity = 0.12
            self.shape.shadowRadius = 6
            self.shape.shadowOffset = CGSize(width: 0, height: -4)
        }
        // Content.
        let showBars = state == "recording" || state == "starting"
        barGroup.position = CGPoint(x: center.x - 1, y: center.y)
        let iconImage = iconName.flatMap {
            Self.symbol($0, size: $0 == "exclamationmark.circle" ? 13 : 12, weight: .semibold)
        }
        var iconCenter = center
        var labelFrame = NSRect.zero
        var closeCenter = CGPoint.zero
        let iconWidth: CGFloat = iconImage == nil ? 0 : 14
        switch state {
        case "processing":
            iconCenter = CGPoint(x: center.x - 12, y: center.y)
            closeCenter = CGPoint(x: center.x + 8, y: center.y)
        case "loading":
            let w = textWidth(labelText, labelFont)
            let start = center.x - (w + 24) / 2
            labelFrame = NSRect(x: start - 2, y: center.y - 8, width: w + 6, height: 16)
            closeCenter = CGPoint(x: start + w + 2 + 11, y: center.y)
        case "done" where copied:
            let w = textWidth(labelText, labelFont)
            let start = center.x - (iconWidth + 4 + w) / 2
            iconCenter = CGPoint(x: start + iconWidth / 2, y: center.y)
            labelFrame = NSRect(
                x: start + iconWidth + 2, y: center.y - 8, width: w + 6, height: 16)
        case "error":
            iconCenter = CGPoint(x: frame.minX + 14 + 6.5, y: center.y)
            let size = textSize(message, labelFont, width: textArea)
            labelFrame = NSRect(
                x: frame.minX + 14 + 13 + 8, y: center.y - size.height / 2, width: textArea,
                height: size.height)
            closeCenter = CGPoint(x: frame.maxX - 14 - 11 + 4, y: center.y)
        default: break
        }
        transition {
            self.barGroup.opacity = showBars ? (self.state == "recording" ? 1 : 0.4) : 0
            self.layoutBars()
            self.dot.opacity = 0
            self.badge.opacity = 0
            self.spinner.opacity = 0
            self.setIcon(iconImage, center: iconCenter)
        }
        stopSpinner()
        setLabel(labelText, font: labelFont, color: labelColor, frame: labelFrame)
        setClose(showClose, center: closeCenter, help: state == "error" ? "Dismiss" : "Cancel")
    }

    private func layoutIsland(_ metrics: IslandMetrics, animated: Bool) {
        let top = bounds.maxY
        let expanded = state != "idle"
        let isError = state == "error"
        let notchHeight = metrics.notchHeight
        let width = expanded ? metrics.expandedWidth : metrics.notchWidth
        let height = notchHeight + (isError ? 40 : 0)
        let frame = CGRect(
            x: bounds.midX - width / 2, y: top - height, width: width, height: height)
        animateShape(to: frame, radius: isError ? 16 : 11, spring: (300, 24))
        transition {
            self.shape.opacity = 1
            self.shape.transform = CATransform3DIdentity
            self.shape.backgroundColor = .black
            self.shape.borderWidth = 0
            self.shape.shadowOpacity = 0
        }
        let leading = CGPoint(
            x: bounds.midX - metrics.notchWidth / 2 - IslandMetrics.wing / 2,
            y: top - notchHeight / 2)
        let trailing = CGPoint(
            x: bounds.midX + metrics.notchWidth / 2 + IslandMetrics.wing / 2,
            y: top - notchHeight / 2)
        var iconImage: NSImage?
        var showDot = false
        var showSpinner = false
        var showBars = false
        var showClose = false
        var showBadge = false
        switch state {
        case "recording", "starting":
            showDot = true
            showBars = true
        case "loading", "processing":
            showSpinner = true
            showClose = true
        case "done":
            iconImage = Self.symbol("checkmark", size: 12, weight: .bold, color: .systemGreen)
            showBadge = copied
        case "error":
            iconImage = Self.symbol(
                "exclamationmark.circle", size: 13, weight: .semibold, color: .systemOrange)
            showClose = true
        default: break
        }
        // Content fades in once the wings are mostly out, so it never pokes past the edge.
        let delay: CFTimeInterval = expanded ? 0.1 : 0
        transition(delay: delay) {
            self.dot.position = leading
            self.dot.opacity = showDot ? (self.state == "recording" ? 1 : 0.4) : 0
            self.dot.backgroundColor =
                self.state == "recording"
                ? NSColor(srgbRed: 1, green: 0.27, blue: 0.23, alpha: 1).cgColor
                : NSColor.white.cgColor
            self.spinner.position = leading
            self.spinner.opacity = showSpinner ? 1 : 0
            self.barGroup.position = trailing
            self.barGroup.opacity = showBars ? (self.state == "recording" ? 1 : 0.4) : 0
            self.layoutBars()
            self.badge.position = trailing
            self.badge.opacity = showBadge ? 1 : 0
            self.setIcon(iconImage, center: leading)
        }
        if showSpinner { startSpinner() } else { stopSpinner() }
        let font = NSFont.systemFont(ofSize: 11)
        if isError {
            let left = frame.minX + 14
            let textWidth = frame.width - 28 - 30
            let size = textSize(message, font, width: textWidth)
            setLabel(
                message, font: font, color: .white,
                frame: NSRect(
                    x: left, y: top - notchHeight - 20 - size.height / 2 + 2, width: textWidth,
                    height: size.height))
            setClose(
                true, center: CGPoint(x: frame.maxX - 14 - 11 + 4, y: top - notchHeight - 18),
                help: "Dismiss")
        } else {
            setLabel("", font: font, color: .white, frame: .zero)
            setClose(showClose, center: trailing, help: "Cancel transcription")
        }
    }

    private func layoutBars() {
        let heights = isIsland ? Self.islandBars : Self.miniBars
        let width: CGFloat = isIsland ? 2.5 : 2
        let spacing: CGFloat = 2
        let total = CGFloat(bars.count) * width + CGFloat(bars.count - 1) * spacing
        barGroup.bounds = CGRect(x: 0, y: 0, width: total, height: 20)
        let minimum: CGFloat = isIsland ? 3 : 2
        for (index, bar) in bars.enumerated() {
            let height = max(minimum, minimum + level * heights[index])
            bar.bounds = CGRect(x: 0, y: 0, width: width, height: height)
            bar.cornerRadius = width / 2
            bar.position = CGPoint(x: CGFloat(index) * (width + spacing) + width / 2, y: 10)
        }
    }

    // MARK: Helpers

    private func setShape(_ frame: CGRect, radius: CGFloat) {
        shapeFrame = frame
        shape.bounds = CGRect(origin: .zero, size: frame.size)
        shape.position = CGPoint(x: frame.midX, y: frame.midY)
        shape.cornerRadius = radius
        shape.maskedCorners =
            isIsland
            ? [.layerMinXMinYCorner, .layerMaxXMinYCorner]
            : [
                .layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner,
                .layerMaxXMaxYCorner,
            ]
        shape.shadowPath = CGPath(
            roundedRect: CGRect(origin: .zero, size: frame.size), cornerWidth: radius,
            cornerHeight: radius, transform: nil)
    }

    /// Springs the shape to a new frame. Bounds, position, radius and shadow move together.
    private func animateShape(
        to frame: CGRect, radius: CGFloat, spring: (stiffness: CGFloat, damping: CGFloat)
    ) {
        let from = shape.presentation() ?? shape
        let old = (
            bounds: from.bounds, position: from.position, radius: from.cornerRadius,
            shadow: from.shadowPath
        )
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        setShape(frame, radius: radius)
        CATransaction.commit()
        let values: [(String, Any?, Any?)] = [
            ("bounds", NSValue(rect: old.bounds), NSValue(rect: shape.bounds)),
            ("position", NSValue(point: old.position), NSValue(point: shape.position)),
            ("cornerRadius", old.radius, radius),
            ("shadowPath", old.shadow, shape.shadowPath),
        ]
        for (key, fromValue, toValue) in values {
            let animation = CASpringAnimation(keyPath: key)
            animation.fromValue = fromValue
            animation.toValue = toValue
            animation.stiffness = spring.stiffness
            animation.damping = spring.damping
            animation.mass = 1
            animation.duration = animation.settlingDuration
            shape.add(animation, forKey: key)
        }
    }

    private func transition(delay: CFTimeInterval = 0, _ changes: @escaping () -> Void) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.16)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        if delay > 0 {
            // Opacity-only fades start after the delay; positions update immediately.
            let layers = [barGroup, icon, badge, dot, spinner]
            let before = layers.map(\.opacity)
            changes()
            for (layer, start) in zip(layers, before) where layer.opacity != start {
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = start
                fade.toValue = layer.opacity
                fade.beginTime = CACurrentMediaTime() + delay
                fade.duration = 0.16
                fade.fillMode = .backwards
                layer.add(fade, forKey: "opacity")
            }
        } else {
            changes()
        }
        CATransaction.commit()
    }

    private func setIcon(_ image: NSImage?, center: CGPoint) {
        icon.opacity = image == nil ? 0 : 1
        guard let image else { return }
        icon.contents = image.layerContents(forContentsScale: icon.contentsScale)
        icon.bounds = CGRect(origin: .zero, size: image.size)
        icon.position = center
    }

    private func setLabel(_ text: String, font: NSFont, color: NSColor, frame: NSRect) {
        label.stringValue = text
        // Errors wrap to three lines; short status labels stay on one line.
        let wraps = state == "error"
        label.lineBreakMode = wraps ? .byWordWrapping : .byClipping
        label.cell?.truncatesLastVisibleLine = true
        label.maximumNumberOfLines = wraps ? 3 : 1
        label.font = font
        label.textColor = color
        label.toolTip = state == "error" ? text : nil
        if !text.isEmpty { label.frame = frame }
        label.alphaValue = text.isEmpty ? 0 : 1
    }

    private func setClose(_ visible: Bool, center: CGPoint, help: String) {
        closeButton.isHidden = !visible
        closeButton.alphaValue = visible ? 1 : 0
        closeButton.toolTip = help
        closeButton.setAccessibilityLabel(help)
        if visible {
            closeButton.frame = NSRect(x: center.x - 11, y: center.y - 12, width: 22, height: 24)
        }
    }

    private func startSpinner() {
        guard spinner.animation(forKey: "spin") == nil else { return }
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = -2 * Double.pi
        spin.duration = 0.8
        spin.repeatCount = .infinity
        spinner.add(spin, forKey: "spin")
    }

    private func stopSpinner() { spinner.removeAnimation(forKey: "spin") }

    private func textWidth(_ text: String, _ font: NSFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    private func textSize(_ text: String, _ font: NSFont, width: CGFloat) -> CGSize {
        let rect = (text as NSString).boundingRect(
            with: NSSize(width: width - 4, height: 200), options: [.usesLineFragmentOrigin],
            attributes: [.font: font])
        return CGSize(
            width: ceil(rect.width),
            height: min(ceil(rect.height), ceil(font.boundingRectForFont.height * 3)))
    }

    private static var symbols: [String: NSImage] = [:]
    static func symbol(
        _ name: String, size: CGFloat, weight: NSFont.Weight, color: NSColor = .white,
        alpha: CGFloat = 1
    ) -> NSImage? {
        let key = "\(name)-\(size)-\(weight.rawValue)-\(color)-\(alpha)"
        if let cached = symbols[key] { return cached }
        let configuration = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
            .applying(.init(paletteColors: [color.withAlphaComponent(alpha)]))
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        symbols[key] = image
        return image
    }
}
