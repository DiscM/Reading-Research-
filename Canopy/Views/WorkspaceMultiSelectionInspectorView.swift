import CanopyCore
import SwiftUI

struct WorkspaceMultiSelectionInspectorView: View {
    let documents: [WorkspaceDocumentListItem]
    let collections: [WorkspaceCollectionListItem]
    let onSetKind: ([UUID], DocumentKind) -> Void
    let onSetCollectionMembership: ([UUID], UUID, Bool) -> Void
    let onNewCollection: ([UUID]) -> Void

    private var documentIDs: [UUID] {
        documents.map(\.id).sorted { $0.uuidString < $1.uuidString }
    }

    var body: some View {
        Form {
            Section("Selection") {
                LabeledContent("Documents", value: "\(documents.count)")
                Picker("Document Kind", selection: Binding<DocumentKind?>(
                    get: { commonKind },
                    set: { kind in
                        if let kind { onSetKind(documentIDs, kind) }
                    }
                )) {
                    Text("Mixed").tag(DocumentKind?.none)
                    ForEach(DocumentKind.allCases) { kind in
                        Label(kind.displayName, systemImage: kind.systemImage)
                            .tag(DocumentKind?.some(kind))
                    }
                }
            }

            Section("Collection Memberships") {
                if collections.isEmpty {
                    Text("No Collections")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(collections) { collection in
                        let state = WorkspaceCollectionMembershipState.resolve(
                            collectionID: collection.id,
                            among: documents
                        )
                        Button {
                            onSetCollectionMembership(
                                documentIDs,
                                collection.id,
                                state != .checked
                            )
                        } label: {
                            HStack {
                                Image(systemName: state.systemImage)
                                    .frame(width: 18)
                                Text(collection.name)
                                Spacer()
                                Text(state.inspectorAccessibilityLabel)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityValue(state.inspectorAccessibilityLabel)
                    }
                }

                Button {
                    onNewCollection(documentIDs)
                } label: {
                    Label("New Collection from Selection", systemImage: "plus")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Overview")
    }

    private var commonKind: DocumentKind? {
        guard let first = documents.first?.kind,
              documents.allSatisfy({ $0.kind == first }) else {
            return nil
        }
        return first
    }
}

private extension WorkspaceCollectionMembershipState {
    var inspectorAccessibilityLabel: String {
        switch self {
        case .checked: "All selected"
        case .unchecked: "None selected"
        case .mixed: "Mixed"
        }
    }
}
