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

public struct AnnotationRect: Codable, Equatable, Sendable {
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

    public var top: Double { y + height }

    public var isValid: Bool {
        x.isFinite
            && y.isFinite
            && width.isFinite
            && height.isFinite
            && width > 0
            && height > 0
    }
}

public struct TextAnnotationAnchor: Codable, Equatable, Sendable {
    public var pageIndex: Int
    public var quadrilaterals: [AnnotationQuadrilateral]
    public var selectedText: String

    public init(
        pageIndex: Int,
        quadrilaterals: [AnnotationQuadrilateral],
        selectedText: String
    ) {
        self.pageIndex = pageIndex
        self.quadrilaterals = quadrilaterals
        self.selectedText = selectedText
    }

    public func isValid(pageCount: Int) -> Bool {
        pageIndex >= 0
            && pageIndex < max(pageCount, 1)
            && !quadrilaterals.isEmpty
            && !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public struct AreaAnnotationAnchor: Codable, Equatable, Sendable {
    public var pageIndex: Int
    public var rect: AnnotationRect

    public init(pageIndex: Int, rect: AnnotationRect) {
        self.pageIndex = pageIndex
        self.rect = rect
    }

    public func isValid(pageCount: Int) -> Bool {
        pageIndex >= 0
            && pageIndex < max(pageCount, 1)
            && rect.isValid
    }
}

public enum AnnotationQuadrilateralCoding {
    public static func encode(_ quadrilaterals: [AnnotationQuadrilateral]) throws -> Data {
        try JSONEncoder().encode(quadrilaterals)
    }

    public static func decode(_ data: Data) throws -> [AnnotationQuadrilateral] {
        try JSONDecoder().decode([AnnotationQuadrilateral].self, from: data)
    }
}

public enum AnnotationRectCoding {
    public static func encode(_ rect: AnnotationRect) throws -> Data {
        try JSONEncoder().encode(rect)
    }

    public static func decode(_ data: Data) throws -> AnnotationRect {
        try JSONDecoder().decode(AnnotationRect.self, from: data)
    }
}
