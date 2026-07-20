import SwiftUI

enum WorkspaceInspectorTab: String, CaseIterable, Identifiable, Sendable {
    case overview
    case annotations

    static let launchDefault: Self = .annotations

    var id: Self { self }

    var displayName: String {
        switch self {
        case .overview: "Overview"
        case .annotations: "Annotations"
        }
    }
}

struct WorkspaceInspectorContainer<OverviewContent: View, AnnotationsContent: View>: View {
    @Binding var selection: WorkspaceInspectorTab
    private let overview: OverviewContent
    private let annotations: AnnotationsContent

    init(
        selection: Binding<WorkspaceInspectorTab>,
        @ViewBuilder overview: () -> OverviewContent,
        @ViewBuilder annotations: () -> AnnotationsContent
    ) {
        _selection = selection
        self.overview = overview()
        self.annotations = annotations()
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Inspector", selection: $selection) {
                ForEach(WorkspaceInspectorTab.allCases) { tab in
                    Text(tab.displayName).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .accessibilityLabel("Inspector Section")

            Divider()

            Group {
                switch selection {
                case .overview:
                    overview
                case .annotations:
                    annotations
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 250, idealWidth: 300)
    }
}
