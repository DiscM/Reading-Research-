import CanopyCore

enum AnnotationInspectorSortOrder: String, CaseIterable, Identifiable {
    case recentActivity
    case pageOrder

    var id: Self { self }

    var title: String {
        switch self {
        case .recentActivity: "Recent Activity"
        case .pageOrder: "Page Order"
        }
    }
}

enum AnnotationInspectorContents {
    static func visibleAnnotations(
        from annotations: [Annotation],
        selectedColors: Set<HighlightColor>,
        sortOrder: AnnotationInspectorSortOrder
    ) -> [Annotation] {
        let filtered = selectedColors.isEmpty
            ? annotations
            : annotations.filter { selectedColors.contains($0.color) }
        return switch sortOrder {
        case .recentActivity:
            Annotation.sortedByRecentActivity(filtered)
        case .pageOrder:
            Annotation.sortedInPageOrder(filtered)
        }
    }
}
