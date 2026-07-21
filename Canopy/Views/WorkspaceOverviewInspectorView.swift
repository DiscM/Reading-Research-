import CanopyCore
import SwiftUI

struct WorkspaceOverviewInspectorView: View {
    let model: WorkspaceDocumentOverviewModel
    let onDocumentNoteChange: (UUID, String) -> Bool
    let onKindChange: (UUID, DocumentKind) -> Void
    let onDocumentDateChange: (UUID, DocumentDate?) -> Void
    let onSetCollectionMembership: (UUID, UUID, Bool) -> Void
    let onNewCollection: () -> Void
    let onSourceStatusAction: (UUID) -> Void
    let onIndexStatusAction: (UUID) -> Void

    @State private var isMembershipEditorPresented = false
    @State private var membershipSearchText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.title)
                        .font(.headline)
                        .textSelection(.enabled)
                    Label(model.kind.displayName, systemImage: model.kind.systemImage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                inspectorSection("Document") {
                    Picker("Document Kind", selection: kindBinding) {
                        ForEach(DocumentKind.allCases) { kind in
                            Label(kind.displayName, systemImage: kind.systemImage)
                                .tag(kind)
                        }
                    }

                    WorkspaceDocumentDateEditor(
                        label: model.kind.dateLabel,
                        date: dateBinding
                    )
                    .id(model.id)

                    LabeledContent(model.kind.creatorLabel) {
                        Text(model.creatorSummary.isEmpty ? "None" : model.creatorSummary)
                            .foregroundStyle(model.creatorSummary.isEmpty ? .secondary : .primary)
                            .multilineTextAlignment(.trailing)
                            .textSelection(.enabled)
                    }
                }

                inspectorSection("Collections") {
                    collectionMemberships
                }

                inspectorSection("Document Note") {
                    WorkspaceDocumentNoteEditor(note: model.documentNote) { note in
                        onDocumentNoteChange(model.id, note)
                    }
                    .id(model.id)
                }

                inspectorSection("Source PDF") {
                    statusRow(model.sourceStatus, action: onSourceStatusAction)
                }

                if let indexStatus = model.indexStatus {
                    inspectorSection("Search Index") {
                        statusRow(indexStatus, action: onIndexStatusAction)
                    }
                }
            }
            .padding(14)
        }
        .frame(minWidth: 250, idealWidth: 300)
    }

    private var kindBinding: Binding<DocumentKind> {
        Binding(
            get: { model.kind },
            set: { onKindChange(model.id, $0) }
        )
    }

    private var dateBinding: Binding<DocumentDate?> {
        Binding(
            get: { model.documentDate },
            set: { onDocumentDateChange(model.id, $0) }
        )
    }

    @ViewBuilder
    private func inspectorSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var collectionMemberships: some View {
        VStack(alignment: .leading, spacing: 8) {
            let activeMemberships = model.collectionMemberships.filter { $0.state != .unchecked }
            if activeMemberships.isEmpty {
                Text("Unfiled")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(activeMemberships) { membership in
                    HStack(spacing: 8) {
                        Image(systemName: membership.state == .mixed ? "minus.square.fill" : "folder.fill")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text(membership.name)
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        Button {
                            onSetCollectionMembership(model.id, membership.id, false)
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.plain)
                        .help("Remove from \(membership.name)")
                        .accessibilityLabel("Remove from \(membership.name)")
                    }
                    .accessibilityElement(children: .contain)
                }
            }

            Button {
                isMembershipEditorPresented = true
            } label: {
                Label("Edit Memberships", systemImage: "plus")
            }
            .popover(isPresented: $isMembershipEditorPresented, arrowEdge: .leading) {
                membershipEditor
            }
        }
    }

    private var membershipEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Collection Memberships")
                .font(.headline)

            TextField("Find a Collection", text: $membershipSearchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(filteredMemberships) { membership in
                        Button {
                            onSetCollectionMembership(
                                model.id,
                                membership.id,
                                membership.state != .checked
                            )
                        } label: {
                            HStack {
                                Image(systemName: membership.state.systemImage)
                                    .frame(width: 18)
                                Text(membership.name)
                                    .lineLimit(1)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 5)
                        .accessibilityValue(membershipAccessibilityValue(membership.state))
                    }
                }
            }
            .frame(maxHeight: 240)

            Divider()

            Button(action: onNewCollection) {
                Label("New Collection", systemImage: "plus")
            }
        }
        .padding(14)
        .frame(width: 290)
    }

    private var filteredMemberships: [WorkspaceCollectionMembershipOption] {
        let query = membershipSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return model.collectionMemberships }
        return model.collectionMemberships.filter {
            $0.name.localizedStandardContains(query)
        }
    }

    private func membershipAccessibilityValue(_ state: WorkspaceCollectionMembershipState) -> String {
        switch state {
        case .checked: "Member"
        case .unchecked: "Not a member"
        case .mixed: "Mixed membership"
        }
    }

    private func statusRow(
        _ status: WorkspaceOverviewStatus,
        action: @escaping (UUID) -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: status.systemImage)
                .foregroundStyle(statusColor(status.severity))
                .frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(status.title)
                if let detail = status.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 6)
            if let actionTitle = status.actionTitle {
                Button(actionTitle) {
                    action(model.id)
                }
                .controlSize(.small)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func statusColor(_ severity: WorkspaceStatusSeverity) -> Color {
        switch severity {
        case .neutral: .secondary
        case .warning: .orange
        case .critical: .red
        }
    }
}

private struct WorkspaceDocumentNoteEditor: View {
    let note: String
    let onSave: (String) -> Bool

    @State private var draftNote: String
    @State private var savedNote: String
    @FocusState private var isFocused: Bool

    init(note: String, onSave: @escaping (String) -> Bool) {
        self.note = note
        self.onSave = onSave
        _draftNote = State(initialValue: note)
        _savedNote = State(initialValue: note)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $draftNote)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(5)
                .focused($isFocused)
            if draftNote.isEmpty {
                Text("Summary, takeaways, assignments, or context")
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 12)
                    .allowsHitTesting(false)
            }
        }
        .frame(minHeight: 120)
        .frame(maxWidth: .infinity)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator.opacity(0.5))
        }
        .accessibilityLabel("Document Note")
        .task(id: draftNote) {
            guard draftNote != savedNote else { return }
            try? await Task.sleep(for: .milliseconds(550))
            guard !Task.isCancelled else { return }
            saveNote()
        }
        .onChange(of: isFocused) { _, focused in
            if !focused { saveNote() }
        }
        .onChange(of: note) { _, newNote in
            guard newNote != savedNote else { return }
            if !isFocused || draftNote == savedNote {
                draftNote = newNote
                savedNote = newNote
            }
        }
        .onDisappear(perform: saveNote)
    }

    private func saveNote() {
        guard draftNote != savedNote else { return }
        if onSave(draftNote) {
            savedNote = draftNote
        }
    }
}

private struct WorkspaceDocumentDateEditor: View {
    let label: String
    @Binding var date: DocumentDate?
    @State private var draft: String
    @State private var validationMessage: String?
    @FocusState private var isFocused: Bool

    init(label: String, date: Binding<DocumentDate?>) {
        self.label = label
        _date = date
        _draft = State(initialValue: Self.inputText(for: date.wrappedValue))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            TextField(label, text: $draft, prompt: Text("YYYY, YYYY-MM, or YYYY-MM-DD"))
                .frame(maxWidth: .infinity)
                .focused($isFocused)
                .onSubmit(commitDraft)
                .onChange(of: draft) { _, _ in
                    validationMessage = nil
                }
                .onChange(of: date) { _, newDate in
                    let externalText = Self.inputText(for: newDate)
                    if Self.parsedDate(from: draft) != newDate {
                        draft = externalText
                    }
                }
                .onChange(of: isFocused) { _, focused in
                    if !focused { commitDraft() }
                }

            if let validationMessage {
                Label(validationMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Enter only the precision you know.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .onDisappear(perform: commitDraft)
    }

    private func commitDraft() {
        let normalized = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty {
            date = nil
            validationMessage = nil
            return
        }
        guard let parsedDate = Self.parsedDate(from: normalized) else {
            validationMessage = "Use YYYY, YYYY-MM, or YYYY-MM-DD from 1000 through next year."
            return
        }
        date = parsedDate
        draft = Self.inputText(for: parsedDate)
        validationMessage = nil
    }

    private static func parsedDate(from text: String) -> DocumentDate? {
        let components = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "-", omittingEmptySubsequences: false)
        guard (1 ... 3).contains(components.count),
              let year = Int(components[0]),
              MetadataValidator.validPublicationYear(year) else {
            return nil
        }
        let month = components.count >= 2 ? Int(components[1]) : nil
        let day = components.count == 3 ? Int(components[2]) : nil
        if components.count >= 2, month == nil { return nil }
        if components.count == 3, day == nil { return nil }
        return DocumentDate(year: year, month: month, day: day)
    }

    private static func inputText(for date: DocumentDate?) -> String {
        guard let date else { return "" }
        var result = String(format: "%04d", date.year)
        if let month = date.month {
            result += String(format: "-%02d", month)
        }
        if let day = date.day {
            result += String(format: "-%02d", day)
        }
        return result
    }
}
