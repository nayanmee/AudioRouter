import Foundation
import CoreGraphics

// All coordinates are AppKit points, never backing pixels. Displays can have
// negative origins or sit above/below one another in the desktop arrangement.
enum PanelLayout {
    static func frame(in visibleFrame: CGRect, centeredAt x: CGFloat) -> CGRect {
        let margin: CGFloat = min(8, max(0, min(visibleFrame.width, visibleFrame.height) / 4))
        let usable = visibleFrame.insetBy(dx: margin, dy: margin)
        let width = min(410, usable.width)
        let height = min(620, usable.height)
        let left = min(max(x - width / 2, usable.minX), usable.maxX - width)
        return CGRect(x: left, y: usable.maxY - height, width: width, height: height)
    }
}
