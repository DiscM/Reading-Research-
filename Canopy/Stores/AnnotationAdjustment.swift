import CanopyCore
import Foundation

enum AnnotationAnchorValue: Equatable, Sendable {
    case text(TextAnnotationAnchor)
    case area(AreaAnnotationAnchor)

    init?(annotation: Annotation) {
        switch annotation.kind {
        case .textHighlight:
            guard let anchor = annotation.textAnchor else { return nil }
            self = .text(anchor)
        case .area:
            guard let anchor = annotation.areaAnchor else { return nil }
            self = .area(anchor)
        }
    }
}

struct AnnotationAdjustmentRequest: Equatable {
    let annotationID: UUID
    let requestID: UUID

    init(annotationID: UUID, requestID: UUID = UUID()) {
        self.annotationID = annotationID
        self.requestID = requestID
    }
}

struct AnnotationAdjustmentCommand: Equatable {
    enum Action {
        case commit
        case cancel
    }

    let id = UUID()
    let action: Action
}

extension LibraryRepository {
    func updateAnnotationAnchor(annotationID: UUID, anchor: AnnotationAnchorValue) throws {
        switch anchor {
        case let .text(textAnchor):
            try updateTextAnnotationAnchor(annotationID: annotationID, anchor: textAnchor)
        case let .area(areaAnchor):
            try updateAreaAnnotationAnchor(annotationID: annotationID, anchor: areaAnchor)
        }
    }
}
