import Foundation
import CoreGraphics
@main struct LayoutTests {
    static func main() {
        let displays: [CGRect] = [
            CGRect(x: 0, y: 38, width: 1512, height: 920),
            CGRect(x: 1512, y: 0, width: 1920, height: 1055),
            CGRect(x: 0, y: 982, width: 1920, height: 1055),
            CGRect(x: -1920, y: -1080, width: 1920, height: 1020),
            CGRect(x: 0, y: 0, width: 800, height: 480)
        ]
        for display in displays {
            for x in [display.minX - 100, display.minX, display.midX, display.maxX, display.maxX + 100] {
                let panel = PanelLayout.frame(in: display, centeredAt: x)
                assert(display.contains(panel), "Panel escaped display: \(display) → \(panel)")
                assert(panel.width <= 410 && panel.height <= 620)
                assert(panel.minY >= display.minY + 8 && panel.maxY <= display.maxY - 8)
            }
        }
        print("PASS: popup containment on built-in, external, stacked, negative-origin, and short displays")
    }
}
