import Foundation
import CoreGraphics

public enum FollowGeometry {
    public static func target(mouse: CGPoint, size: CGSize, screen: CGRect) -> CGPoint {
        let margin: CGFloat = 6
        var x = mouse.x + 18
        var y = mouse.y - size.height - 14
        if x + size.width > screen.maxX - margin { x = mouse.x - size.width - 18 }
        if y < screen.minY + margin { y = mouse.y + 18 }
        x = min(max(x, screen.minX + margin), max(screen.minX + margin, screen.maxX - size.width - margin))
        y = min(max(y, screen.minY + margin), max(screen.minY + margin, screen.maxY - size.height - margin))
        return CGPoint(x: x, y: y)
    }
    public static func step(from: CGPoint, to: CGPoint, dt: Double, response: Double = 0.13) -> CGPoint {
        let amount = 1 - exp(-max(0, min(dt, 0.1)) / max(response, 0.001))
        return CGPoint(x: from.x + (to.x - from.x) * amount, y: from.y + (to.y - from.y) * amount)
    }
}
