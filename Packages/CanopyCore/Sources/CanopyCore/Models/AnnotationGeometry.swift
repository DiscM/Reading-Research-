import Foundation

public enum AreaAnnotationAdjustmentHandle: CaseIterable, Equatable, Sendable {
    case move
    case bottomLeft
    case bottom
    case bottomRight
    case right
    case topRight
    case top
    case topLeft
    case left

    public var affectsMinimumX: Bool {
        self == .bottomLeft || self == .topLeft || self == .left
    }

    public var affectsMaximumX: Bool {
        self == .bottomRight || self == .topRight || self == .right
    }

    public var affectsMinimumY: Bool {
        self == .bottomLeft || self == .bottom || self == .bottomRight
    }

    public var affectsMaximumY: Bool {
        self == .topLeft || self == .top || self == .topRight
    }
}

public enum AreaAnnotationGeometry {
    public static func adjustedRect(
        _ startRect: AnnotationRect,
        handle: AreaAnnotationAdjustmentHandle,
        pagePoint: AnnotationPoint,
        delta: AnnotationPoint,
        pageBounds: AnnotationRect,
        minimumSize: Double = 8
    ) -> AnnotationRect {
        if handle == .move {
            let x = min(
                max(startRect.x + delta.x, pageBounds.x),
                pageBounds.x + pageBounds.width - startRect.width
            )
            let y = min(
                max(startRect.y + delta.y, pageBounds.y),
                pageBounds.y + pageBounds.height - startRect.height
            )
            return AnnotationRect(x: x, y: y, width: startRect.width, height: startRect.height)
        }

        var minX = startRect.x
        var maxX = startRect.x + startRect.width
        var minY = startRect.y
        var maxY = startRect.y + startRect.height
        if handle.affectsMinimumX { minX = min(pagePoint.x, maxX - minimumSize) }
        if handle.affectsMaximumX { maxX = max(pagePoint.x, minX + minimumSize) }
        if handle.affectsMinimumY { minY = min(pagePoint.y, maxY - minimumSize) }
        if handle.affectsMaximumY { maxY = max(pagePoint.y, minY + minimumSize) }
        minX = max(minX, pageBounds.x)
        maxX = min(maxX, pageBounds.x + pageBounds.width)
        minY = max(minY, pageBounds.y)
        maxY = min(maxY, pageBounds.y + pageBounds.height)
        return AnnotationRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
