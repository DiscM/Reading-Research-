import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct EvidenceWorkspaceView: View {
    @Environment(PaperStore.self) private var store
    @State private var selectedTableID: EvidenceTable.ID?
    @State private var isCreatingTable = false
    let onOpenPaper: (Paper.ID, Int?) -> Void

    var body: some View {
        HStack(spacing: 0) {
            evidenceSidebar
            Divider()

            if let tableBinding = selectedTableBinding {
                EvidenceTableDetail(table: tableBinding, onOpenPaper: onOpenPaper)
            } else {
                EvidenceLandingView(
                    tableCount: store.researchState.evidenceTables.count,
                    paperCount: store.papers.count,
                    createAction: { isCreatingTable = true }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $isCreatingTable) {
            EvidenceSourcePicker(
                title: "New Evidence Table",
                actionTitle: "Create Table",
                papers: store.papers,
                showsNameField: true
            ) { name, paperIDs in
                store.createEvidenceTable(name: name, paperIDs: paperIDs)
                selectedTableID = store.researchState.evidenceTables.last?.id
            }
        }
        .onAppear(perform: selectInitialTable)
        .onChange(of: store.researchState.evidenceTables.map(\.id)) { _, ids in
            if let selectedTableID, ids.contains(selectedTableID) { return }
            self.selectedTableID = ids.first
        }
    }

    private var evidenceSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Evidence tables")
                        .font(.headline)
                    Text("\(store.researchState.evidenceTables.count) comparisons")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { isCreatingTable = true } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.bordered)
                .help("Create an evidence table")
                .disabled(store.papers.isEmpty)
            }
            .padding(12)

            if store.researchState.evidenceTables.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tablecells.badge.ellipsis")
                        .font(.title2)
                        .foregroundStyle(SolarpunkTheme.fern)
                    Text("No comparisons yet")
                        .font(.subheadline.weight(.semibold))
                    Text("Choose papers and Research Hub will seed a structured extraction table.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Create First Table") { isCreatingTable = true }
                        .buttonStyle(.borderedProminent)
                        .tint(SolarpunkTheme.spruce)
                        .disabled(store.papers.isEmpty)
                }
                .padding(20)
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                List(selection: $selectedTableID) {
                    ForEach(store.researchState.evidenceTables) { table in
                        EvidenceTableSidebarRow(table: table)
                            .tag(table.id)
                            .contextMenu {
                                Button("Delete Table", role: .destructive) {
                                    store.deleteEvidenceTable(table.id)
                                }
                            }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }

            Divider()
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal")
                    .foregroundStyle(SolarpunkTheme.fern)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Verification matters")
                        .font(.caption.weight(.semibold))
                    Text("Check every excerpt against its source.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
        }
        .frame(minWidth: 190, idealWidth: 215, maxWidth: 235)
        .background(SolarpunkTheme.sidebar.opacity(0.55))
    }

    private var selectedTableBinding: Binding<EvidenceTable>? {
        guard let selectedTableID,
              let fallback = store.researchState.evidenceTables.first(where: { $0.id == selectedTableID }) else {
            return nil
        }
        return Binding(
            get: {
                store.researchState.evidenceTables.first(where: { $0.id == selectedTableID }) ?? fallback
            },
            set: { updated in
                guard let index = store.researchState.evidenceTables.firstIndex(where: { $0.id == selectedTableID }) else {
                    return
                }
                store.researchState.evidenceTables[index] = updated
            }
        )
    }

    private func selectInitialTable() {
        guard selectedTableID == nil else { return }
        selectedTableID = store.researchState.evidenceTables.first?.id
    }
}

private struct EvidenceTableSidebarRow: View {
    let table: EvidenceTable

    private var verifiedCount: Int { table.rows.flatMap(\.cells).filter(\.isVerified).count }
    private var cellCount: Int { table.rows.reduce(0) { $0 + $1.cells.count } }

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "tablecells")
                .foregroundStyle(SolarpunkTheme.fern)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(table.name)
                    .lineLimit(1)
                Text("\(table.rows.count) sources · \(verifiedCount)/\(cellCount) verified")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct EvidenceLandingView: View {
    let tableCount: Int
    let paperCount: Int
    let createAction: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 18) {
                    Image(systemName: "leaf.arrow.triangle.circlepath")
                        .font(.system(size: 38))
                        .foregroundStyle(SolarpunkTheme.fern)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Grow findings into comparable evidence")
                            .font(.title2.bold())
                        Text("Create a matrix from papers in your library, review the extracted claims, and preserve page-level provenance before synthesis.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(20)
                .solarpunkCard()

                HStack(spacing: 12) {
                    EvidenceMetricCard(title: "Library sources", value: "\(paperCount)", icon: "books.vertical")
                    EvidenceMetricCard(title: "Comparisons", value: "\(tableCount)", icon: "tablecells")
                    EvidenceMetricCard(title: "Default fields", value: "\(EvidenceService.defaultColumnNames.count)", icon: "rectangle.split.3x1")
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text("Evidence workflow")
                        .font(.headline)
                    EvidenceStep(number: 1, title: "Select sources", detail: "Choose two or more papers that answer a shared question.")
                    EvidenceStep(number: 2, title: "Review extraction", detail: "Research Hub seeds methods, samples, findings, and limitations from local text.")
                    EvidenceStep(number: 3, title: "Verify provenance", detail: "Attach page numbers and check every excerpt against the PDF.")
                    EvidenceStep(number: 4, title: "Move into synthesis", detail: "Use the completed table when generating an evidence-backed outline.")
                }
                .padding(18)
                .solarpunkCard()

                Button(action: createAction) {
                    Label("Create Evidence Table", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(SolarpunkTheme.spruce)
                .disabled(paperCount == 0)
            }
            .padding(24)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct EvidenceStep: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundStyle(SolarpunkTheme.spruce)
                .frame(width: 24, height: 24)
                .background(SolarpunkTheme.lichen.opacity(0.32), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct EvidenceMetricCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(SolarpunkTheme.fern)
                .frame(width: 30, height: 30)
                .background(SolarpunkTheme.lichen.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(.title3.bold())
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .solarpunkCard(cornerRadius: 10)
    }
}

private enum EvidenceRowFilter: String, CaseIterable, Identifiable {
    case all = "All sources"
    case incomplete = "Needs evidence"
    case review = "Needs verification"

    var id: String { rawValue }
}

private struct EvidenceTableDetail: View {
    @Environment(PaperStore.self) private var store
    @Binding var table: EvidenceTable
    let onOpenPaper: (Paper.ID, Int?) -> Void
    @State private var searchText = ""
    @State private var rowFilter: EvidenceRowFilter = .all
    @State private var newColumnName = ""
    @State private var isAddingSources = false
    @State private var isDeletingTable = false

    private var allCells: [EvidenceCell] { table.rows.flatMap(\.cells) }
    private var populatedCells: Int { allCells.filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count }
    private var verifiedCells: Int { allCells.filter(\.isVerified).count }
    private var coverage: Double { allCells.isEmpty ? 0 : Double(populatedCells) / Double(allCells.count) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            metrics
            Divider()
            filters
            Divider()
            evidenceGrid
        }
        .background(SolarpunkTheme.canvas)
        .sheet(isPresented: $isAddingSources) {
            EvidenceSourcePicker(
                title: "Add Sources",
                actionTitle: "Add to Table",
                papers: availablePapers,
                showsNameField: false
            ) { _, paperIDs in
                store.addPapers(paperIDs, toEvidenceTable: table.id)
            }
        }
        .confirmationDialog("Delete “\(table.name)” ?", isPresented: $isDeletingTable) {
            Button("Delete Table", role: .destructive) { store.deleteEvidenceTable(table.id) }
        } message: {
            Text("This removes the comparison table but keeps every paper in your library.")
        }
        .onAppear(perform: backfillExistingExcerpts)
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                tableTitle
                Spacer()
                tableActions
            }
            VStack(alignment: .leading, spacing: 8) {
                tableTitle
                tableActions
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(SolarpunkTheme.raisedSurface)
    }

    private var tableTitle: some View {
        VStack(alignment: .leading, spacing: 3) {
            TextField("Evidence table name", text: $table.name)
                .textFieldStyle(.plain)
                .font(.title3.bold())
                .onSubmit { table.updatedAt = Date() }
            Text("Updated \(table.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var tableActions: some View {
        HStack(spacing: 8) {
            Button { store.populateEmptyEvidenceCells(in: table.id) } label: {
                Label("Fill Empty Cells", systemImage: "sparkles")
            }
            .help("Populate empty fields from locally extracted paper text")
            Menu {
                Button("Add Sources…") { isAddingSources = true }
                    .disabled(availablePapers.isEmpty)
                Button("Export Markdown…", action: exportMarkdown)
                Button("Export CSV…", action: exportCSV)
                Divider()
                Button("Delete Table…", role: .destructive) { isDeletingTable = true }
            } label: {
                Label("Table Actions", systemImage: "ellipsis.circle")
                    .labelStyle(.iconOnly)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)
        }
    }

    private var metrics: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 135), spacing: 10)], spacing: 10) {
            EvidenceMetricCard(title: "Sources", value: "\(table.rows.count)", icon: "doc.on.doc")
            EvidenceMetricCard(title: "Fields", value: "\(table.columns.count)", icon: "rectangle.split.3x1")
            EvidenceMetricCard(title: "Coverage", value: coverage.formatted(.percent.precision(.fractionLength(0))), icon: "chart.bar.fill")
            EvidenceMetricCard(title: "Verified", value: "\(verifiedCells)/\(allCells.count)", icon: "checkmark.seal.fill")
        }
        .padding(12)
    }

    private var filters: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                searchAndFilterControls
                Spacer(minLength: 8)
                fieldAndSourceControls
            }
            VStack(spacing: 8) {
                searchAndFilterControls
                fieldAndSourceControls
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(SolarpunkTheme.surface.opacity(0.72))
    }

    private var searchAndFilterControls: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Filter sources or evidence", text: $searchText)
                .textFieldStyle(.plain)
                .frame(minWidth: 120, maxWidth: 240)
            Picker("Rows", selection: $rowFilter) {
                ForEach(EvidenceRowFilter.allCases) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden()
            .frame(width: 145)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var fieldAndSourceControls: some View {
        HStack(spacing: 8) {
            TextField("New field", text: $newColumnName)
                .frame(minWidth: 100, maxWidth: 150)
                .onSubmit(addColumn)
            Button("Add Field", action: addColumn)
                .disabled(newColumnName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button { isAddingSources = true } label: {
                Label("Add Sources", systemImage: "plus")
            }
            .disabled(availablePapers.isEmpty)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    @ViewBuilder private var evidenceGrid: some View {
        if table.rows.isEmpty {
            ContentUnavailableView {
                Label("No sources in this table", systemImage: "doc.badge.plus")
            } description: {
                Text("Add papers from your library to begin comparing evidence.")
            } actions: {
                Button("Add Sources") { isAddingSources = true }
                    .disabled(availablePapers.isEmpty)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredRows.isEmpty {
            ContentUnavailableView.search(text: searchText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView([.horizontal, .vertical]) {
                evidenceMatrix(columns: table.columns)
                    .padding(14)
                    .frame(minWidth: 190 + CGFloat(table.columns.count) * 230, alignment: .topLeading)
            }
            .scrollIndicators(.visible)
            .defaultScrollAnchor(.topLeading)
        }
    }

    private func evidenceMatrix(columns: [EvidenceColumn]) -> some View {
        Grid(alignment: .topLeading, horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                Text("SOURCE")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 190, alignment: .leading)
                ForEach(columns) { column in
                    EvidenceColumnHeader(
                        name: columnNameBinding(column.id),
                        canDelete: table.columns.count > 1,
                        deleteAction: { deleteColumn(column.id) }
                    )
                }
            }

            ForEach(filteredRows) { row in
                GridRow {
                    EvidenceSourceCard(
                        paper: paper(for: row.paperID),
                        openAction: { onOpenPaper(row.paperID, nil) },
                        removeAction: { store.removePaper(row.paperID, fromEvidenceTable: table.id) }
                    )
                    ForEach(columns) { column in
                        if let cell = row.cells.first(where: { $0.columnID == column.id }),
                           let binding = cellBinding(rowID: row.id, cellID: cell.id) {
                            EvidenceCellEditor(
                                cell: binding,
                                openSource: {
                                    onOpenPaper(row.paperID, currentCell(rowID: row.id, cellID: cell.id)?.page)
                                }
                            )
                        } else {
                            Text("Missing field")
                                .foregroundStyle(.secondary)
                                .frame(width: 220, height: 150)
                        }
                    }
                }
            }
        }
    }

    private var filteredRows: [EvidenceRow] {
        table.rows.filter { row in
            let paper = paper(for: row.paperID)
            let matchesSearch = searchText.isEmpty
                || paper?.title.localizedCaseInsensitiveContains(searchText) == true
                || paper?.authors.localizedCaseInsensitiveContains(searchText) == true
                || row.cells.contains { $0.value.localizedCaseInsensitiveContains(searchText) }
            let matchesFilter: Bool
            switch rowFilter {
            case .all: matchesFilter = true
            case .incomplete: matchesFilter = row.cells.contains { $0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            case .review: matchesFilter = row.cells.contains { !$0.value.isEmpty && !$0.isVerified }
            }
            return matchesSearch && matchesFilter
        }
    }

    private var availablePapers: [Paper] {
        let existing = Set(table.rows.map(\.paperID))
        return store.papers.filter { !existing.contains($0.id) }
    }

    private func paper(for id: Paper.ID) -> Paper? { store.papers.first { $0.id == id } }

    private func columnNameBinding(_ columnID: EvidenceColumn.ID) -> Binding<String> {
        let fallback = table.columns.first(where: { $0.id == columnID })?.name ?? "Evidence field"
        return Binding(
            get: { table.columns.first(where: { $0.id == columnID })?.name ?? fallback },
            set: { name in
                guard let index = table.columns.firstIndex(where: { $0.id == columnID }) else { return }
                table.columns[index].name = name
                table.updatedAt = Date()
            }
        )
    }

    private func cellBinding(rowID: EvidenceRow.ID, cellID: EvidenceCell.ID) -> Binding<EvidenceCell>? {
        guard let fallback = currentCell(rowID: rowID, cellID: cellID) else { return nil }
        return Binding(
            get: { currentCell(rowID: rowID, cellID: cellID) ?? fallback },
            set: { updated in
                guard let rowIndex = table.rows.firstIndex(where: { $0.id == rowID }),
                      let cellIndex = table.rows[rowIndex].cells.firstIndex(where: { $0.id == cellID }) else {
                    return
                }
                table.rows[rowIndex].cells[cellIndex] = updated
                table.updatedAt = Date()
            }
        )
    }

    private func currentCell(rowID: EvidenceRow.ID, cellID: EvidenceCell.ID) -> EvidenceCell? {
        table.rows.first(where: { $0.id == rowID })?.cells.first(where: { $0.id == cellID })
    }

    private func addColumn() {
        let clean = newColumnName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        if store.addEvidenceColumn(name: clean, to: table.id) {
            newColumnName = ""
        } else {
            store.lastError = "That evidence field already exists or has an invalid name."
        }
    }

    private func deleteColumn(_ columnID: EvidenceColumn.ID) {
        _ = store.deleteEvidenceColumn(columnID, from: table.id)
    }

    private func backfillExistingExcerpts() {
        var changed = false
        for rowIndex in table.rows.indices {
            for cellIndex in table.rows[rowIndex].cells.indices
            where table.rows[rowIndex].cells[cellIndex].quote.isEmpty
                && !table.rows[rowIndex].cells[cellIndex].value.isEmpty {
                table.rows[rowIndex].cells[cellIndex].quote = table.rows[rowIndex].cells[cellIndex].value
                changed = true
            }
        }
        if changed { table.updatedAt = Date() }
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(exportFileName)-evidence.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try EvidenceService.csv(for: table, papers: store.papers)
                    .write(to: url, atomically: true, encoding: .utf8)
                store.lastNotice = "Exported evidence table."
            } catch {
                store.lastError = "Could not export evidence: \(error.localizedDescription)"
            }
        }
    }

    private func exportMarkdown() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(exportFileName)-evidence.md"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try EvidenceService.markdown(for: table, papers: store.papers)
                    .write(to: url, atomically: true, encoding: .utf8)
                store.lastNotice = "Exported evidence table as Markdown."
            } catch {
                store.lastError = "Could not export evidence: \(error.localizedDescription)"
            }
        }
    }

    private var exportFileName: String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = table.name.components(separatedBy: invalid).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "evidence-table" : cleaned
    }

}

private struct EvidenceColumnHeader: View {
    @Binding var name: String
    let canDelete: Bool
    let deleteAction: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            TextField("Field name", text: $name)
                .textFieldStyle(.plain)
                .font(.caption.weight(.bold))
                .textCase(.uppercase)
            Menu {
                Button("Delete Field", role: .destructive, action: deleteAction)
                    .disabled(!canDelete)
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 18)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(width: 220)
        .background(SolarpunkTheme.lichen.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct EvidenceSourceCard: View {
    let paper: Paper?
    let openAction: () -> Void
    let removeAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top) {
                Image(systemName: paper?.documentKind.systemImage ?? "questionmark.square.dashed")
                    .foregroundStyle(SolarpunkTheme.fern)
                Spacer()
                Menu {
                    Button("Open Paper", action: openAction)
                    Divider()
                    Button("Remove from Table", role: .destructive, action: removeAction)
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 18)
            }
            Text(paper?.title ?? "Missing source")
                .font(.subheadline.weight(.semibold))
                .lineLimit(3)
                .onTapGesture(perform: openAction)
                .help("Open this paper")
            Text(paper?.authors.isEmpty == false ? paper!.authors : "Unknown author")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack {
                if let year = paper?.year, !year.isEmpty { Text(year) }
                Spacer()
                if let status = paper?.status {
                    Text(status.rawValue)
                        .foregroundStyle(status.color)
                }
            }
            .font(.caption2.weight(.medium))
        }
        .padding(10)
        .frame(width: 190, alignment: .topLeading)
        .frame(minHeight: 150, alignment: .topLeading)
        .solarpunkCard(cornerRadius: 9)
    }
}

private struct EvidenceCellEditor: View {
    @Binding var cell: EvidenceCell
    let openSource: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            TextField("Add extracted evidence…", text: $cell.value, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.caption)
                .lineLimit(3...6)

            Divider()

            TextField("Supporting excerpt", text: $cell.quote, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1...3)

            HStack(spacing: 7) {
                Label("Page", systemImage: "doc.text")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
                TextField("—", value: $cell.page, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 48)
                Button(action: openSource) {
                    Image(systemName: "arrow.up.forward.app")
                }
                .buttonStyle(.plain)
                .foregroundStyle(SolarpunkTheme.fern)
                .help(cell.page.map { "Open source at page \($0)" } ?? "Open source paper")
                Spacer()
                Toggle(isOn: $cell.isVerified) {
                    Image(systemName: cell.isVerified ? "checkmark.seal.fill" : "checkmark.seal")
                        .foregroundStyle(cell.isVerified ? SolarpunkTheme.fern : .secondary)
                }
                .toggleStyle(.button)
                .buttonStyle(.plain)
                .help(cell.isVerified ? "Verified against source" : "Mark as verified")
            }
        }
        .padding(10)
        .frame(width: 220, alignment: .topLeading)
        .frame(minHeight: 150, alignment: .topLeading)
        .background(
            cell.isVerified ? SolarpunkTheme.lichen.opacity(0.13) : SolarpunkTheme.surface,
            in: RoundedRectangle(cornerRadius: 9)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(cell.isVerified ? SolarpunkTheme.fern.opacity(0.4) : SolarpunkTheme.hairline)
        }
    }
}

private struct EvidenceSourcePicker: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let actionTitle: String
    let papers: [Paper]
    let showsNameField: Bool
    let completion: (String, Set<Paper.ID>) -> Void

    @State private var tableName = "Evidence Review"
    @State private var searchText = ""
    @State private var selection = Set<Paper.ID>()

    private var filteredPapers: [Paper] {
        guard !searchText.isEmpty else { return papers }
        return papers.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
                || $0.authors.localizedCaseInsensitiveContains(searchText)
                || $0.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.title3.bold())
                    Text("Choose the local sources to compare")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(selection.count) selected")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SolarpunkTheme.fern)
            }
            .padding(16)

            Divider()

            VStack(spacing: 10) {
                if showsNameField {
                    TextField("Table name", text: $tableName)
                        .font(.headline)
                }
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search title, author, or tag", text: $searchText)
                        .textFieldStyle(.plain)
                    Button(selection.count == papers.count ? "Clear All" : "Select All") {
                        selection = selection.count == papers.count ? [] : Set(papers.map(\.id))
                    }
                    .buttonStyle(.link)
                }
                .padding(8)
                .background(SolarpunkTheme.surface, in: RoundedRectangle(cornerRadius: 8))

                if papers.isEmpty {
                    ContentUnavailableView("No available papers", systemImage: "books.vertical")
                        .frame(maxHeight: .infinity)
                } else {
                    List(filteredPapers) { paper in
                        Toggle(isOn: membershipBinding(paper.id)) {
                            HStack(spacing: 10) {
                                Image(systemName: paper.documentKind.systemImage)
                                    .foregroundStyle(SolarpunkTheme.fern)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(paper.title).lineLimit(1)
                                    Text([paper.authors, paper.year].filter { !$0.isEmpty }.joined(separator: " · "))
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                    .listStyle(.inset)
                }
            }
            .padding(14)

            Divider()
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(actionTitle) {
                    completion(tableName, selection)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(SolarpunkTheme.spruce)
                .keyboardShortcut(.defaultAction)
                .disabled(selection.isEmpty || (showsNameField && tableName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            }
            .padding(14)
        }
        .frame(width: 560, height: 530)
        .background(SolarpunkTheme.canvas)
    }

    private func membershipBinding(_ id: Paper.ID) -> Binding<Bool> {
        Binding(
            get: { selection.contains(id) },
            set: { included in
                if included { selection.insert(id) } else { selection.remove(id) }
            }
        )
    }
}
