import CanopyCore
import SwiftUI

struct WorkspaceIndexFooterView: View {
    @Bindable var coordinator: WorkspaceIndexCoordinator
    let documents: [Document]
    let onRetry: (Data) -> Void
    let onLocateSource: (UUID) -> Void
    @State private var isPresented = false

    private var visibleStatuses: [PDFTextIndexStatus] {
        coordinator.activeStatuses
    }

    private var shouldShow: Bool {
        !visibleStatuses.isEmpty || coordinator.setupErrorMessage != nil
    }

    var body: some View {
        if shouldShow {
            Button {
                isPresented.toggle()
            } label: {
                HStack(spacing: 8) {
                    if coordinator.isWorking {
                        ProgressView(value: coordinator.aggregateFractionCompleted)
                            .progressViewStyle(.circular)
                            .controlSize(.small)
                    } else {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                    Text(footerLabel)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .background(.bar)
            .overlay(alignment: .top) { Divider() }
            .accessibilityLabel("PDF text indexing activity")
            .accessibilityValue(footerLabel)
            .popover(isPresented: $isPresented, arrowEdge: .trailing) {
                WorkspaceIndexActivityPopover(
                    coordinator: coordinator,
                    documents: documents,
                    onRetry: onRetry,
                    onLocateSource: onLocateSource
                )
            }
        }
    }

    private var footerLabel: String {
        if coordinator.isWorking {
            let count = visibleStatuses.count {
                $0.lifecycle == .pending || $0.lifecycle == .indexing
            }
            return "Indexing \(count) document\(count == 1 ? "" : "s")"
        }
        let count = visibleStatuses.count + (coordinator.setupErrorMessage == nil ? 0 : 1)
        return "Indexing needs attention (\(count))"
    }
}

private struct WorkspaceIndexActivityPopover: View {
    @Bindable var coordinator: WorkspaceIndexCoordinator
    let documents: [Document]
    let onRetry: (Data) -> Void
    let onLocateSource: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("PDF Text Index")
                    .font(.headline)
                Text("Searchable text is stored locally and built in the background.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if let setupErrorMessage = coordinator.setupErrorMessage {
                        activityError(setupErrorMessage)
                    }
                    ForEach(coordinator.activeStatuses, id: \.key) { status in
                        activityRow(status)
                        Divider()
                    }
                }
            }
            .frame(maxHeight: 360)
        }
        .frame(width: 340)
        .background(.regularMaterial)
    }

    private func activityRow(_ status: PDFTextIndexStatus) -> some View {
        let document = documents.first { $0.fingerprint == status.key.fingerprint }
        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: symbol(for: status.lifecycle))
                    .foregroundStyle(color(for: status.lifecycle))
                    .accessibilityHidden(true)
                Text(document?.title ?? "Document")
                    .font(.callout.weight(.medium))
                    .lineLimit(2)
                Spacer(minLength: 8)
                Text(status.lifecycle.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if status.lifecycle == .pending || status.lifecycle == .indexing {
                ProgressView(value: status.fractionCompleted)
                    .accessibilityLabel("Indexing progress")
                    .accessibilityValue(
                        "\(status.indexedPageCount) of \(status.totalPageCount) pages"
                    )
            }

            if let failureDescription = status.failureDescription {
                Text(failureDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if status.lifecycle == .failed {
                Button("Retry") { onRetry(status.key.fingerprint) }
                    .buttonStyle(.link)
            } else if status.lifecycle == .needsSource, let document {
                Button("Locate Source…") { onLocateSource(document.id) }
                    .buttonStyle(.link)
            }
        }
        .padding(12)
    }

    private func activityError(_ message: String) -> some View {
        Label {
            Text(message)
                .font(.caption)
        } icon: {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }
        .padding(12)
    }

    private func symbol(for lifecycle: PDFTextIndexLifecycle) -> String {
        switch lifecycle {
        case .pending: "clock"
        case .indexing: "arrow.trianglehead.2.clockwise.rotate.90"
        case .ready: "checkmark.circle"
        case .needsSource: "externaldrive.badge.exclamationmark"
        case .failed: "exclamationmark.triangle"
        }
    }

    private func color(for lifecycle: PDFTextIndexLifecycle) -> Color {
        switch lifecycle {
        case .pending, .indexing, .ready: .secondary
        case .needsSource: .orange
        case .failed: .red
        }
    }
}

private extension PDFTextIndexLifecycle {
    var displayName: String {
        switch self {
        case .pending: "Pending"
        case .indexing: "Indexing"
        case .ready: "Ready"
        case .needsSource: "Needs Source"
        case .failed: "Failed"
        }
    }
}
