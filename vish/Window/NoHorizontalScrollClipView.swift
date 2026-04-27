import AppKit

@MainActor
final class NoHorizontalScrollClipView: NSClipView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        drawsBackground = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unsupported; vish UI is programmatic")
    }

    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        rect.origin.x = 0
        return rect
    }
}
