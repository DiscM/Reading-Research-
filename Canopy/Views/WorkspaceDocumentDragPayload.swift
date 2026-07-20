import CoreTransferable
import Foundation
import UniformTypeIdentifiers

struct WorkspaceDocumentDragPayload: Codable, Transferable {
    let documentIDs: [UUID]

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .canopyDocumentSelection)
    }
}

private extension UTType {
    static let canopyDocumentSelection = UTType(
        exportedAs: "com.discm.Canopy.document-selection"
    )
}
