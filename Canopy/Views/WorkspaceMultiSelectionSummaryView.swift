import CanopyCore
import SwiftUI

struct WorkspaceMultiSelectionSummaryView: View {
    let documents: [WorkspaceDocumentListItem]
    let collections: [WorkspaceCollectionListItem]
    let onSetKind: ([UUID], DocumentKind) -> Void
    let onSetCollectionMembership: ([UUID], UUID, Bool) -> Void
    let onCreateCollectionFromSelection: ([UUID]) -> Void
    let onRequestRemoval: ([UUID]) -> Void

    private var summary: WorkspaceMultiSelectionSummary {
        WorkspaceMultiSelectionSummary(documents: documents)
    }

    private var documentIDs: [UUID] {
        documents.map(\.id).sorted { $0.uuidString < $1.uuidString }
    }

    var body: some View {
        VStack(spacing: 22) {
            Spacer()

            Image(systemName: "doc.on.doc")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(spacing: 5) {
                Text("\(summary.documentCount) Documents Selected")
                    .font(.title2.weight(.semibold))
                Text("Bulk changes affect the same Documents everywhere they appear.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 12) {
                statistic(
                    title: "Referenced",
                    value: summary.referencedCount,
                    systemImage: "link"
                )
                statistic(
                    title: "Managed Copies",
                    value: summary.managedCopyCount,
                    systemImage: "internaldrive"
                )
                statistic(
                    title: "Kinds",
                    value: summary.kinds.count,
                    systemImage: "square.grid.2x2"
                )
            }

            HStack(spacing: 10) {
                Menu {
                    ForEach(DocumentKind.allCases) { kind in
                        Button(kind.displayName) {
                            onSetKind(documentIDs, kind)
                        }
                    }
                } label: {
                    Label("Set Document Kind", systemImage: "square.grid.2x2")
                }

                Menu {
                    if collections.isEmpty {
                        Text("No Collections")
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
                                Label(collection.name, systemImage: state.systemImage)
                            }
                            .accessibilityLabel("\(collection.name), \(state.accessibilityLabel)")
                        }
                    }
                } label: {
                    Label("Edit Collections", systemImage: "folder.badge.plus")
                }

                Button {
                    onCreateCollectionFromSelection(documentIDs)
                } label: {
                    Label("New Collection from Selection", systemImage: "plus")
                }
            }

            Button(role: .destructive) {
                onRequestRemoval(documentIDs)
            } label: {
                Label("Remove from Library…", systemImage: "trash")
            }

            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }

    private func statistic(
        title: String,
        value: Int,
        systemImage: String
    ) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(value, format: .number)
                .font(.title3.monospacedDigit())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 110)
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue("\(value)")
    }
}

private extension WorkspaceCollectionMembershipState {
    var accessibilityLabel: String {
        switch self {
        case .checked: "All selected Documents are members"
        case .unchecked: "No selected Documents are members"
        case .mixed: "Some selected Documents are members"
        }
    }
}
