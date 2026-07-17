import Foundation
import SwiftData

public enum HighlightColor: String, CaseIterable, Codable, Sendable {
    case yellow
    case green
    case blue
    case pink
    case purple
}

public enum AnnotationKind: String, CaseIterable, Codable, Sendable {
    case textHighlight
    case area
}

@Model
public final class Annotation {
    @Attribute(.unique) public var id: UUID
    public private(set) var kindRawValue: String
    public private(set) var pageIndex: Int
    public private(set) var quadrilaterals: Data?
    public private(set) var selectedText: String?
    public private(set) var areaRect: Data?
    public private(set) var colorRawValue: String
    public var note: String
    public var createdAt: Date
    public var updatedAt: Date
    public var paper: Paper?

    public internal(set) var color: HighlightColor {
        get { HighlightColor(rawValue: colorRawValue) ?? .yellow }
        set { colorRawValue = newValue.rawValue }
    }

    public var kind: AnnotationKind {
        get { AnnotationKind(rawValue: kindRawValue) ?? .textHighlight }
    }

    public var textAnchor: TextAnnotationAnchor? {
        guard kind == .textHighlight,
              let quadrilaterals,
              let selectedText,
              let decoded = try? AnnotationQuadrilateralCoding.decode(quadrilaterals) else {
            return nil
        }
        return TextAnnotationAnchor(
            pageIndex: pageIndex,
            quadrilaterals: decoded,
            selectedText: selectedText
        )
    }

    public var areaAnchor: AreaAnnotationAnchor? {
        guard kind == .area,
              let areaRect,
              let decoded = try? AnnotationRectCoding.decode(areaRect) else {
            return nil
        }
        return AreaAnnotationAnchor(pageIndex: pageIndex, rect: decoded)
    }

    public static func sortedInPageOrder(_ annotations: [Annotation]) -> [Annotation] {
        annotations.sorted { lhs, rhs in
            if lhs.pageIndex != rhs.pageIndex { return lhs.pageIndex < rhs.pageIndex }
            let lhsTop = lhs.textAnchor?.quadrilaterals.first?.top ?? lhs.areaAnchor?.rect.top ?? 0
            let rhsTop = rhs.textAnchor?.quadrilaterals.first?.top ?? rhs.areaAnchor?.rect.top ?? 0
            if lhsTop != rhsTop { return lhsTop > rhsTop }
            return lhs.createdAt < rhs.createdAt
        }
    }

    public static func sortedByRecentActivity(_ annotations: [Annotation]) -> [Annotation] {
        annotations.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    internal func replaceTextAnchor(_ anchor: TextAnnotationAnchor) throws {
        pageIndex = anchor.pageIndex
        quadrilaterals = try AnnotationQuadrilateralCoding.encode(anchor.quadrilaterals)
        selectedText = anchor.selectedText
    }

    internal func replaceAreaAnchor(_ anchor: AreaAnnotationAnchor) throws {
        pageIndex = anchor.pageIndex
        areaRect = try AnnotationRectCoding.encode(anchor.rect)
    }

    private init(
        id: UUID = UUID(),
        kind: AnnotationKind,
        pageIndex: Int,
        quadrilaterals: Data? = nil,
        selectedText: String? = nil,
        areaRect: Data? = nil,
        color: HighlightColor,
        note: String = "",
        createdAt: Date = .now,
        paper: Paper? = nil
    ) {
        self.id = id
        self.kindRawValue = kind.rawValue
        self.pageIndex = pageIndex
        self.quadrilaterals = quadrilaterals
        self.selectedText = selectedText
        self.areaRect = areaRect
        self.colorRawValue = color.rawValue
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.paper = paper
    }

    convenience init(
        id: UUID = UUID(),
        textAnchor: TextAnnotationAnchor,
        color: HighlightColor,
        note: String = "",
        createdAt: Date = .now,
        paper: Paper? = nil
    ) throws {
        try self.init(
            id: id,
            kind: .textHighlight,
            pageIndex: textAnchor.pageIndex,
            quadrilaterals: AnnotationQuadrilateralCoding.encode(textAnchor.quadrilaterals),
            selectedText: textAnchor.selectedText,
            color: color,
            note: note,
            createdAt: createdAt,
            paper: paper
        )
    }

    convenience init(
        id: UUID = UUID(),
        areaAnchor: AreaAnnotationAnchor,
        color: HighlightColor,
        note: String = "",
        createdAt: Date = .now,
        paper: Paper? = nil
    ) throws {
        try self.init(
            id: id,
            kind: .area,
            pageIndex: areaAnchor.pageIndex,
            areaRect: AnnotationRectCoding.encode(areaAnchor.rect),
            color: color,
            note: note,
            createdAt: createdAt,
            paper: paper
        )
    }
}
