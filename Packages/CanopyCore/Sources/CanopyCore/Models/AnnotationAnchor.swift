import Foundation

public struct AnnotationPoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct AnnotationQuadrilateral: Codable, Equatable, Sendable {
    public var upperLeft: AnnotationPoint
    public var upperRight: AnnotationPoint
    public var lowerLeft: AnnotationPoint
    public var lowerRight: AnnotationPoint

    public init(
        upperLeft: AnnotationPoint,
        upperRight: AnnotationPoint,
        lowerLeft: AnnotationPoint,
        lowerRight: AnnotationPoint
    ) {
        self.upperLeft = upperLeft
        self.upperRight = upperRight
        self.lowerLeft = lowerLeft
        self.lowerRight = lowerRight
    }

    public var top: Double {
        max(upperLeft.y, upperRight.y, lowerLeft.y, lowerRight.y)
    }
}

public struct AnnotationAnchor: Codable, Equatable, Sendable {
    public var pageIndex: Int
    public var quadrilaterals: [AnnotationQuadrilateral]
    public var selectedText: String
    public var contextBefore: String
    public var contextAfter: String

    public init(
        pageIndex: Int,
        quadrilaterals: [AnnotationQuadrilateral],
        selectedText: String,
        contextBefore: String = "",
        contextAfter: String = ""
    ) {
        self.pageIndex = pageIndex
        self.quadrilaterals = quadrilaterals
        self.selectedText = selectedText
        self.contextBefore = contextBefore
        self.contextAfter = contextAfter
    }
}

public enum AnnotationAnchorCoding {
    public static func encode(_ quadrilaterals: [AnnotationQuadrilateral]) throws -> Data {
        try JSONEncoder().encode(quadrilaterals)
    }

    public static func decode(_ data: Data) throws -> [AnnotationQuadrilateral] {
        try JSONDecoder().decode([AnnotationQuadrilateral].self, from: data)
    }
}
