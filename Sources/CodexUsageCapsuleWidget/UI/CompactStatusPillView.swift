import AppKit

/// Decoration only: the native status button keeps sizing, hover and menu handling.
@MainActor
final class CompactStatusPillView: NSView {
    static let font = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold)
    static let height: CGFloat = 18
    static let horizontalPadding: CGFloat = 6

    var title = "" {
        didSet { needsDisplay = true }
    }

    var emphasizedLabels: [String] = [] {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        autoresizingMask = [.width, .height]
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { nil }

    // Leave the complete hit area, including the tooltip, with NSStatusBarButton.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Self.font,
            .foregroundColor: NSColor.labelColor
        ]
        let text = NSMutableAttributedString(string: title, attributes: attributes)
        // Keep the existing pill geometry even when lighter labels narrow slightly.
        let size = text.size()
        let source = title as NSString
        let labelFont = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .medium)
        for label in emphasizedLabels where !label.isEmpty {
            let range = source.range(of: label)
            if range.location != NSNotFound {
                text.addAttribute(.font, value: labelFont, range: range)
            }
        }
        let separatorRange = source.range(of: "·")
        if separatorRange.location != NSNotFound {
            text.addAttribute(
                .foregroundColor,
                value: NSColor.labelColor.withAlphaComponent(0.45),
                range: separatorRange
            )
        }
        let pill = NSRect(
            x: bounds.midX - (size.width + Self.horizontalPadding * 2) / 2,
            y: bounds.midY - Self.height / 2,
            width: size.width + Self.horizontalPadding * 2,
            height: Self.height
        )
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        NSColor.white.withAlphaComponent(dark ? 0.12 : 0.20).setFill()
        NSBezierPath(roundedRect: pill, xRadius: 9, yRadius: 9).fill()

        let border = NSBezierPath(
            roundedRect: pill.insetBy(dx: 0.25, dy: 0.25),
            xRadius: 8.75,
            yRadius: 8.75
        )
        border.lineWidth = 0.5
        NSColor.labelColor.withAlphaComponent(0.045).setStroke()
        border.stroke()
        let textSize = text.size()
        text.draw(at: NSPoint(x: bounds.midX - textSize.width / 2, y: bounds.midY - textSize.height / 2))
    }
}
