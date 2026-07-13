import Foundation

public struct PaperViewport: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct PaperReaderState: Equatable, Sendable {
    public var pageIndex: Int
    public var viewport: PaperViewport?
    public var zoomScale: Double
    public var isInspectorPresented: Bool

    public init(
        pageIndex: Int,
        viewport: PaperViewport? = nil,
        zoomScale: Double,
        isInspectorPresented: Bool
    ) {
        self.pageIndex = pageIndex
        self.viewport = viewport
        self.zoomScale = zoomScale
        self.isInspectorPresented = isInspectorPresented
    }
}
