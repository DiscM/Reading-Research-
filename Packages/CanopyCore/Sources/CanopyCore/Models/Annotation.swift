import Foundation
import SwiftData

public enum HighlightColor: String, CaseIterable, Codable, Sendable {
    case yellow
    case green
    case blue
    case pink
    case purple
}

@Model
public final class Annotation {
    @Attribute(.unique) public var id: UUID
    public var pageIndex: Int
    public var quadrilaterals: Data
    public var selectedText: String
    public var contextBefore: String
    public var contextAfter: String
    public var colorRawValue: String
    public var note: String
    public var createdAt: Date
    public var updatedAt: Date
    public var paper: Paper?

    public var color: HighlightColor {
        get { HighlightColor(rawValue: colorRawValue) ?? .yellow }
        set { colorRawValue = newValue.rawValue }
    }

    public init(
        id: UUID = UUID(),
        pageIndex: Int,
        quadrilaterals: Data,
        selectedText: String,
        contextBefore: String = "",
        contextAfter: String = "",
        color: HighlightColor,
        note: String = "",
        createdAt: Date = .now,
        paper: Paper? = nil
    ) {
        self.id = id
        self.pageIndex = pageIndex
        self.quadrilaterals = quadrilaterals
        self.selectedText = selectedText
        self.contextBefore = contextBefore
        self.contextAfter = contextAfter
        self.colorRawValue = color.rawValue
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.paper = paper
    }
}

