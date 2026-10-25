import Foundation
#if canImport(CoreGraphics)
import CoreGraphics   // CGRect geometry on Apple platforms; Foundation provides it on Linux
#endif

/// Where the candidate window goes: under the caret line, above it when there is no room below, and
/// always inside the screen that holds the caret. Rectangles use Cocoa screen coordinates (origin at
/// the bottom left of the main screen, y up), as NSScreen and IMK caret rectangles do.
public enum CandidatePlacement {
    public struct Screen: Equatable {
        public let frame: CGRect
        /// The frame without the menu bar and Dock.
        public let visible: CGRect
        public init(frame: CGRect, visible: CGRect) { self.frame = frame; self.visible = visible }
    }

    public static func origin(size: CGSize, caret: CGRect, screens: [Screen], gap: CGFloat = 3) -> CGPoint {
        let point = CGPoint(x: caret.midX, y: caret.midY)
        let screen = screens.first { $0.frame.contains(point) }
            ?? screens.first { $0.frame.intersects(caret) }
            ?? screens.first
        let area = screen?.visible ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        var y = caret.minY - size.height - gap
        if y < area.minY { y = caret.maxY + gap }
        y = min(max(y, area.minY), area.maxY - size.height)
        let x = min(max(caret.minX, area.minX), area.maxX - size.width)
        return CGPoint(x: x, y: y)
    }
}
