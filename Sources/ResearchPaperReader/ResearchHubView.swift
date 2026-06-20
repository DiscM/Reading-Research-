import AppKit
import SwiftUI

private enum ResearchHubTab: String, CaseIterable, Identifiable {
    case library = "Library"
    case evidence = "Evidence"
    case search = "Search & Chat"
    case synthesis = "Synthesis"
    case discover = "Discover"

    var id: String { rawValue }
}

struct ResearchHubView: View {
    @Environment(PaperStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: ResearchHubTab = .library
    let onOpenPaper: (Paper.ID, Int?) -> Void

    var body: some View {
        VStack(spacing: 8) {
            Picker("Research workspace", selection: $selectedTab) {
                ForEach(ResearchHubTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 520)

            GeometryReader { proxy in
                Group {
                    switch selectedTab {
                    case .library:
                        LibraryOrganizationView()
                    case .evidence:
                        EvidenceTablesView()
                    case .search:
                        LibrarySearchChatView { paperID, page in
                            onOpenPaper(paperID, page)
                            dismiss()
                        }
                    case .synthesis:
                        SynthesisWorkspacesView()
                    case .discover:
                        DiscoveryAndGraphView()
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            }
        }
        .frame(minWidth: 900, idealWidth: 1040, minHeight: 600, idealHeight: 700)
        .controlSize(.small)
        .padding(8)
        .alert(
            "Research Hub",
            isPresented: Binding(
                get: { store.lastError != nil },
                set: { if !$0 { store.lastError = nil } }
            )
        ) {
            Button("OK") { store.lastError = nil }
        } message: {
            Text(store.lastError ?? "An unknown error occurred.")
        }
    }
}

private struct LibraryOrganizationView: View {
    @Environment(PaperStore.self) private var store
    @State private var mode = 0

    var body: some View {
        VStack(spacing: 8) {
            Picker("Library tools", selection: $mode) {
                Text("Collections").tag(0)
                Text("Smart Folders").tag(1)
                Text("Citations").tag(2)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 440)

            GeometryReader { proxy in
                Group {
                    switch mode {
                    case 0: CollectionsView()
                    case 1: SmartFoldersView()
                    default: CitationLibraryView()
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct CollectionsView: View {
    @Environment(PaperStore.self) private var store
    @State private var selectedID: UUID?
    @State private var name = ""
    @State private var parentID: UUID?

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Collections").font(.headline)
                HStack {
                    TextField("Collection name", text: $name)
                    Button("Add") {
                            store.createCollection(name: name, parentID: parentID)
                            selectedID = store.researchState.collections.last?.id
                            name = ""
                        }
                        .help("Create new collection")
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Picker("Parent", selection: $parentID) {
                    Text("Top level").tag(nil as UUID?)
                    ForEach(store.researchState.collections) { collection in
                        Text(collection.name).tag(Optional(collection.id))
                    }
                }
                .pickerStyle(.menu)

                List(selection: $selectedID) {
                    ForEach(store.researchState.collections) { collection in
                        HStack {
                            Image(systemName: collection.parentID == nil ? "folder" : "folder.fill")
                            Text(collection.name)
                            Spacer()
                            Text("\(collection.paperIDs.count)").foregroundStyle(.secondary)
                        }
                        .tag(collection.id)
                        .contextMenu {
                            Button("Delete", role: .destructive) {
                                store.deleteCollection(collection.id)
                                if selectedID == collection.id { selectedID = nil }
                            }
                            .help("Delete this collection")
                        }
                    }
                }
            }
            .frame(minWidth: 220, idealWidth: 250)
            .padding(8)

            VStack(alignment: .leading, spacing: 6) {
                if let selectedID,
                   let collection = store.researchState.collections.first(where: { $0.id == selectedID }) {
                    Text(collection.name).font(.headline)
                    Text("Select the papers that belong to this collection. A paper can appear in multiple collections.")
                        .font(.caption).foregroundStyle(.secondary)
                    List(store.papers) { paper in
                        Toggle(isOn: Binding(
                            get: { collection.paperIDs.contains(paper.id) },
                            set: { store.setPaper(paper.id, in: selectedID, included: $0) }
                        )) {
                            VStack(alignment: .leading) {
                                Text(paper.title)
                                Text(paper.authors).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } else {
                    ContentUnavailableView("Select a collection", systemImage: "folder", description: Text("Create a collection, then assign papers here."))
                }
            }
            .frame(minWidth: 400)
            .padding(8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct SmartFoldersView: View {
    @Environment(PaperStore.self) private var store
    @State private var name = ""
    @State private var field: SmartFolderField = .allText
    @State private var value = ""
    @State private var selectedID: UUID?
    @State private var pendingRules: [SmartFolderRule] = []
    @State private var matchAll = true

    private var selectedFolder: SmartFolder? {
        store.researchState.smartFolders.first { $0.id == selectedID }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Smart Folders").font(.headline)
                TextField("Folder name", text: $name)
                Picker("Match", selection: $field) {
                    ForEach(SmartFolderField.allCases) { Text($0.rawValue).tag($0) }
                }
                TextField("Rule value", text: $value)
                HStack {
                    Button("Add Rule") {
                        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !clean.isEmpty else { return }
                        pendingRules.append(SmartFolderRule(field: field, value: clean))
                        value = ""
                    }
                    .help("Add this filtering rule")
                    .disabled(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Toggle("Match every rule", isOn: $matchAll).toggleStyle(.checkbox)
                }
                ForEach(pendingRules) { rule in
                    HStack {
                        Text("\(rule.field.rawValue): \(rule.value)").font(.caption)
                        Spacer()
                        Button { pendingRules.removeAll { $0.id == rule.id } } label: { Image(systemName: "xmark.circle") }
                            .buttonStyle(.plain)
                    }
                }
                    Button("Create Smart Folder") {
                    var rules = pendingRules
                    let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !clean.isEmpty { rules.append(SmartFolderRule(field: field, value: clean)) }
                    store.createSmartFolder(name: name, rules: rules, matchAll: matchAll)
                    selectedID = store.researchState.smartFolders.last?.id
                    name = ""; value = ""; pendingRules = []
                }
                .help("Create a dynamic folder that auto-filters papers by rules")
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && pendingRules.isEmpty))

                List(selection: $selectedID) {
                    ForEach(store.researchState.smartFolders) { folder in
                        Label(folder.name, systemImage: "folder.badge.gearshape").tag(folder.id)
                            .contextMenu {
                                Button("Delete", role: .destructive) { store.deleteSmartFolder(folder.id) }
                            .help("Delete this smart folder")
                            }
                    }
                }
            }
            .frame(minWidth: 230, idealWidth: 260)
            .padding(8)

            VStack(alignment: .leading, spacing: 6) {
                if let folder = selectedFolder {
                    Text(folder.name).font(.headline)
                    ForEach(folder.rules) { rule in
                        Text("\(rule.field.rawValue) contains “\(rule.value)”")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    List(store.papersInSmartFolder(folder.id)) { paper in
                        VStack(alignment: .leading) {
                            Text(paper.title)
                            Text(paper.authors).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    ContentUnavailableView("Select a smart folder", systemImage: "folder.badge.gearshape")
                }
            }
            .frame(minWidth: 400)
            .padding(8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct CitationLibraryView: View {
    @Environment(PaperStore.self) private var store
    @State private var importText = ""
    @State private var report = ""
    @State private var exportFormat = 0

    private var exportText: String {
        let records = store.allCitationRecords()
        return exportFormat == 0 ? CitationService.bibTeX(for: records) : CitationService.ris(for: records)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Import citations").font(.headline)
                Text("Paste BibTeX or RIS. Existing DOI/title matches are merged instead of duplicated.")
                    .font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $importText)
                    .font(.system(.body, design: .monospaced))
                    .overlay { RoundedRectangle(cornerRadius: 6).stroke(.quaternary) }
                HStack {
                    Button("Import File") { importFile() }
                    .help("Open a file picker to import citations")
                    Button("Import") {
                        do {
                            let result = try store.importCitations(importText)
                            report = "Imported \(result.imported), merged \(result.merged)."
                            importText = ""
                        } catch {
                            report = error.localizedDescription
                        }
                    }
                    .help("Parse and import the entered citation text")
                    .disabled(importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Text(report).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: 300)
            .padding(8)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Citation library").font(.headline)
                    Spacer()
                    Picker("Format", selection: $exportFormat) {
                        Text("BibTeX").tag(0); Text("RIS").tag(1)
                    }
                    .pickerStyle(.segmented).frame(width: 140)
                    Button("Copy Export") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(exportText, forType: .string)
                    }
                    .help("Copy citations to clipboard")
                    Button("Save Export") { saveExport() }
                    .help("Save citations to a file")
                }
                List {
                    ForEach(store.allCitationRecords()) { record in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(record.title).font(.headline)
                            Text([record.authors, record.year, record.venue].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                            if !record.doi.isEmpty { Text(record.doi).font(.caption2.monospaced()).foregroundStyle(.blue) }
                        }
                    }
                }
                Text("\(store.allCitationRecords().count) unique records")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(minWidth: 440)
            .padding(8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .data]
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let text = try String(contentsOf: url, encoding: .utf8)
                let result = try store.importCitations(text)
                report = "Imported \(result.imported), merged \(result.merged)."
            } catch {
                report = error.localizedDescription
            }
        }
    }

    private func saveExport() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = exportFormat == 0 ? "research-library.bib" : "research-library.ris"
        panel.allowedContentTypes = [.plainText]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do { try exportText.write(to: url, atomically: true, encoding: .utf8) }
            catch { store.lastError = "Could not export citations: \(error.localizedDescription)" }
        }
    }
}

private struct EvidenceTablesView: View {
    @Environment(PaperStore.self) private var store
    @State private var selectedID: UUID?
    @State private var selectedPaperIDs = Set<UUID>()
    @State private var name = "Evidence Review"

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Evidence tables").font(.headline)
                TextField("Table name", text: $name)
                ScrollView {
                    VStack(alignment: .leading) {
                        ForEach(store.papers) { paper in
                            Toggle(paper.title, isOn: membershipBinding(paper.id))
                                .toggleStyle(.checkbox).lineLimit(2)
                        }
                    }
                }
                Button("Create from Selected Papers") {
                    store.createEvidenceTable(name: name, paperIDs: selectedPaperIDs)
                    selectedID = store.researchState.evidenceTables.last?.id
                    selectedPaperIDs = []
                }
                .help("Build an evidence table from the selected papers")
                .disabled(selectedPaperIDs.isEmpty)
                Divider()
                List(selection: $selectedID) {
                    ForEach(store.researchState.evidenceTables) { table in
                        Label(table.name, systemImage: "tablecells").tag(table.id)
                            .contextMenu {
                                Button("Delete", role: .destructive) { store.deleteEvidenceTable(table.id) }
                                .help("Delete this evidence table")
                            }
                    }
                }
            }
            .frame(minWidth: 230, idealWidth: 260)
            .padding(8)

            if let selectedID,
               let index = store.researchState.evidenceTables.firstIndex(where: { $0.id == selectedID }) {
                EvidenceTableEditor(table: Binding(
                    get: { store.researchState.evidenceTables[index] },
                    set: { store.researchState.evidenceTables[index] = $0 }
                ))
            } else {
                ContentUnavailableView("Select an evidence table", systemImage: "tablecells")
                    .frame(minWidth: 500)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func membershipBinding(_ id: UUID) -> Binding<Bool> {
        Binding(get: { selectedPaperIDs.contains(id) }, set: { included in
            if included { selectedPaperIDs.insert(id) } else { selectedPaperIDs.remove(id) }
        })
    }
}

private struct EvidenceTableEditor: View {
    @Environment(PaperStore.self) private var store
    @Binding var table: EvidenceTable
    @State private var newColumn = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Table name", text: $table.name).font(.headline)
                TextField("New column", text: $newColumn).frame(width: 150)
                Button("Add Column") {
                    let clean = newColumn.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !clean.isEmpty else { return }
                    let column = EvidenceColumn(name: clean)
                    table.columns.append(column)
                    for row in table.rows.indices { table.rows[row].cells.append(EvidenceCell(columnID: column.id)) }
                    table.updatedAt = Date(); newColumn = ""
                }
                .help("Add a new evidence column to the table")
            }

            ScrollView([.horizontal, .vertical]) {
                Grid(alignment: .topLeading, horizontalSpacing: 8, verticalSpacing: 8) {
                    GridRow {
                        Text("Source").font(.subheadline.weight(.semibold)).frame(width: 160, alignment: .leading)
                        ForEach(table.columns) { column in
                            Text(column.name).font(.subheadline.weight(.semibold)).frame(width: 180, alignment: .leading)
                        }
                    }
                    Divider()
                    ForEach(table.rows.indices, id: \.self) { rowIndex in
                        GridRow {
                            Text(store.papers.first(where: { $0.id == table.rows[rowIndex].paperID })?.title ?? "Missing source")
                                .font(.caption.weight(.medium)).frame(width: 160, alignment: .leading)
                            ForEach(table.columns) { column in
                                let cellIndex = table.rows[rowIndex].cells.firstIndex(where: { $0.columnID == column.id })
                                if let cellIndex {
                                    VStack(alignment: .leading, spacing: 4) {
                                        TextField("Extracted evidence", text: $table.rows[rowIndex].cells[cellIndex].value, axis: .vertical)
                                            .lineLimit(2...5)
                                        HStack {
                                            Toggle("Verified", isOn: $table.rows[rowIndex].cells[cellIndex].isVerified)
                                                .toggleStyle(.checkbox).font(.caption)
                                            TextField("Page", value: $table.rows[rowIndex].cells[cellIndex].page, format: .number)
                                                .frame(width: 60)
                                        }
                                    }
                                    .padding(5).frame(width: 180)
                                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
                                }
                            }
                        }
                    }
                }
                .padding(8)
            }
        }
        .padding(8)
    }
}

private struct LibrarySearchChatView: View {
    @Environment(PaperStore.self) private var store
    @State private var query = ""
    @State private var results: [SemanticSearchResult] = []
    @State private var answer = ""
    let onOpen: (Paper.ID, Int?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Local semantic search and library chat").font(.headline)
            Text("Search uses on-device sentence embeddings when available and a local lexical fallback. Answers contain only retrieved library evidence.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField("Ask across your library…", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(performSearch)
                Button("Search", action: performSearch).disabled(query.count < 2)
                    .help("Search across all documents in your library")
                Button("Answer from Evidence") {
                    answer = SemanticSearchService.groundedAnswer(question: query, results: results)
                }
                .help("Generate a grounded answer from the search results")
                .disabled(results.isEmpty)
            }

            HStack(alignment: .top, spacing: 0) {
                List(results) { result in
                    Button { onOpen(result.paperID, result.page) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(result.paperTitle).font(.headline)
                                Spacer()
                                Text(String(format: "%.0f%%", result.score * 100)).font(.caption.monospacedDigit())
                            }
                            Text(result.text).lineLimit(5).foregroundStyle(.secondary)
                            if let page = result.page { Text("Page \(page)").font(.caption).foregroundStyle(.blue) }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .frame(minWidth: 400)

                VStack(alignment: .leading) {
                    Text("Grounded answer").font(.headline)
                    if answer.isEmpty {
                        ContentUnavailableView("No answer yet", systemImage: "quote.bubble", description: Text("Run a search, then build an answer from its evidence."))
                    } else {
                        ScrollView { MarkdownResultView(markdown: answer).frame(maxWidth: .infinity, alignment: .leading) }
                    }
                }
                .padding(8).frame(minWidth: 320)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(8)
    }

    private func performSearch() {
        results = SemanticSearchService.search(query: query, papers: store.papers)
        answer = ""
    }
}

private struct SynthesisWorkspacesView: View {
    @Environment(PaperStore.self) private var store
    @State private var selectedID: UUID?
    @State private var name = "Literature Synthesis"
    @State private var selectedPapers = Set<UUID>()
    @State private var evidenceTableID: UUID?

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Writing workspaces").font(.headline)
                TextField("Workspace name", text: $name)
                Picker("Evidence table", selection: $evidenceTableID) {
                    Text("None").tag(nil as UUID?)
                    ForEach(store.researchState.evidenceTables) { Text($0.name).tag(Optional($0.id)) }
                }
                ScrollView {
                    VStack(alignment: .leading) {
                        ForEach(store.papers) { paper in
                            Toggle(paper.title, isOn: Binding(
                                get: { selectedPapers.contains(paper.id) },
                                set: { if $0 { selectedPapers.insert(paper.id) } else { selectedPapers.remove(paper.id) } }
                            )).toggleStyle(.checkbox).lineLimit(2)
                        }
                    }
                }
                Button("Create Workspace") {
                    store.createWorkspace(name: name, paperIDs: selectedPapers, evidenceTableID: evidenceTableID)
                    selectedID = store.researchState.workspaces.last?.id
                    selectedPapers = []
                }.help("Create a new synthesis workspace").disabled(selectedPapers.isEmpty || name.isEmpty)
                Divider()
                List(selection: $selectedID) {
                    ForEach(store.researchState.workspaces) { workspace in
                        Label(workspace.name, systemImage: "square.and.pencil").tag(workspace.id)
                            .contextMenu { Button("Delete", role: .destructive) { store.deleteWorkspace(workspace.id) }.help("Delete this workspace") }
                    }
                }
            }
            .frame(minWidth: 230, idealWidth: 260).padding(8)

            if let selectedID,
               let index = store.researchState.workspaces.firstIndex(where: { $0.id == selectedID }) {
                WorkspaceEditor(workspace: Binding(
                    get: { store.researchState.workspaces[index] },
                    set: { store.researchState.workspaces[index] = $0 }
                ))
            } else {
                ContentUnavailableView("Select a synthesis workspace", systemImage: "square.and.pencil")
                    .frame(minWidth: 500)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct WorkspaceEditor: View {
    @Environment(PaperStore.self) private var store
    @Binding var workspace: SynthesisWorkspace

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Workspace name", text: $workspace.name).font(.headline)
                Button("Generate Evidence Outline") { store.generateOutline(for: workspace.id) }
                .help("Auto-generate an outline from collected evidence")
                Button("Copy Draft") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(workspace.draft, forType: .string)
                }.help("Copy the draft text to clipboard").disabled(workspace.draft.isEmpty)
            }
            HStack {
                Text("\(workspace.paperIDs.count) sources").font(.caption).foregroundStyle(.secondary)
                ForEach(store.papers.filter { workspace.paperIDs.contains($0.id) }.prefix(4)) { paper in
                    Text("@\(CitationService.citationKey(for: CitationService.record(for: paper)))")
                        .font(.caption.monospaced()).padding(3).background(.quaternary, in: Capsule())
                }
            }
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading) {
                    Text("Evidence outline").font(.headline)
                    TextEditor(text: $workspace.outline).font(.system(.body, design: .monospaced))
                        .overlay { RoundedRectangle(cornerRadius: 6).stroke(.quaternary) }
                }
                VStack(alignment: .leading) {
                    HStack {
                        Text("Draft").font(.headline)
                        Spacer()
                        Button("Use Outline as Draft") { workspace.draft = workspace.outline }
                            .help("Replace the draft with the current outline")
                            .disabled(workspace.outline.isEmpty)
                    }
                    TextEditor(text: $workspace.draft).font(.system(.body, design: .serif))
                        .overlay { RoundedRectangle(cornerRadius: 6).stroke(.quaternary) }
                }
            }
        }
        .padding(8)
    }
}

private struct DiscoveryAndGraphView: View {
    @State private var mode = 0

    var body: some View {
        VStack(spacing: 8) {
            Picker("Discovery tools", selection: $mode) {
                Text("Citation Graph").tag(0)
                Text("Discover Papers").tag(1)
                Text("Alerts").tag(2)
            }.pickerStyle(.segmented).frame(maxWidth: 460)
            switch mode {
            case 0: CitationGraphView()
            case 1: PaperDiscoveryView()
            default: AlertsView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct CitationGraphView: View {
    @Environment(PaperStore.self) private var store
    private var edges: [CitationEdge] { CitationGraphService.edges(for: store.papers) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Local citation graph").font(.headline)
            Text("Solid blue nodes are papers in your library; gray nodes are parsed references. Linked gray nodes can be imported from discovery.")
                .font(.caption).foregroundStyle(.secondary)
            CitationGraphCanvas(papers: store.papers, edges: edges)
                .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
            Text("\(store.papers.count) local papers · \(edges.count) parsed citation links · \(edges.filter { $0.targetPaperID != nil }.count) links resolved locally")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(8)
    }
}

private struct CitationGraphCanvas: View {
    let papers: [Paper]
    let edges: [CitationEdge]

    var body: some View {
        GeometryReader { proxy in
            let local = Array(papers.prefix(24))
            let external = Array(Dictionary(grouping: edges.filter { $0.targetPaperID == nil }, by: \.targetFingerprint).keys.prefix(36))
            let localPoints = points(count: local.count, radius: min(proxy.size.width, proxy.size.height) * 0.24, center: CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2))
            let externalPoints = points(count: external.count, radius: min(proxy.size.width, proxy.size.height) * 0.43, center: CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2))
            Canvas { context, _ in
                let localMap = Dictionary(uniqueKeysWithValues: zip(local.map(\.id), localPoints))
                let externalMap = Dictionary(uniqueKeysWithValues: zip(external, externalPoints))
                for edge in edges {
                    guard let start = localMap[edge.sourcePaperID] else { continue }
                    let end = edge.targetPaperID.flatMap { localMap[$0] } ?? externalMap[edge.targetFingerprint]
                    guard let end else { continue }
                    var path = Path(); path.move(to: start); path.addLine(to: end)
                    context.stroke(path, with: .color(.secondary.opacity(0.35)), lineWidth: 1)
                }
                for (index, paper) in local.enumerated() {
                    let point = localPoints[index]
                    context.fill(Path(ellipseIn: CGRect(x: point.x - 7, y: point.y - 7, width: 14, height: 14)), with: .color(.blue))
                    context.draw(Text(paper.title).font(.caption2).foregroundStyle(.primary), at: CGPoint(x: point.x, y: point.y + 14), anchor: .top)
                }
                for (index, fingerprint) in external.enumerated() {
                    let point = externalPoints[index]
                    context.fill(Path(ellipseIn: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)), with: .color(.gray))
                    if let edge = edges.first(where: { $0.targetFingerprint == fingerprint }) {
                        context.draw(Text(edge.targetTitle).font(.system(size: 8)).foregroundStyle(.secondary), at: CGPoint(x: point.x, y: point.y + 9), anchor: .top)
                    }
                }
            }
        }
        .frame(minHeight: 380)
    }

    private func points(count: Int, radius: CGFloat, center: CGPoint) -> [CGPoint] {
        guard count > 0 else { return [] }
        return (0..<count).map { index in
            let angle = (Double(index) / Double(count)) * Double.pi * 2 - Double.pi / 2
            return CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
        }
    }
}

private struct PaperDiscoveryView: View {
    @Environment(PaperStore.self) private var store
    @State private var query = ""
    @State private var results: [DiscoveryPaper] = []
    @State private var isSearching = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Discover papers").font(.headline)
            Text("CrossRef search is online and explicit; your local PDF text is never uploaded.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField("Topic, author, title, or DOI", text: $query).onSubmit(search)
                Button("Search", action: search).disabled(query.isEmpty || isSearching)
                .help("Search for papers on CrossRef")
                if isSearching { ProgressView().controlSize(.small) }
                Button("Save as Alert") {
                    store.createAlert(name: query, kind: .query, query: query)
                }.help("Create a recurring search alert").disabled(query.isEmpty)
            }
            List(results) { result in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(result.title).font(.headline)
                        Text([result.authors, result.year, result.venue].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                        if !result.abstract.isEmpty { Text(result.abstract).lineLimit(3).font(.callout).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("\(result.citedByCount) citations").font(.caption)
                        Button("Save Citation") {
                            var record = CitationRecord(
                                title: result.title, authors: result.authors, year: result.year,
                                venue: result.venue, doi: result.doi, abstract: result.abstract, source: .crossref
                            )
                            record.citationKey = CitationService.citationKey(for: record)
                            store.researchState.citations = CitationService.deduplicated(store.researchState.citations + [record])
                        }
                        .help("Add this paper to your citation library")
                    }
                }
            }
        }.padding(8)
    }

    private func search() {
        isSearching = true
        Task {
            do { results = try await DiscoveryService.search(query: query) }
            catch { store.lastError = "Discovery failed: \(error.localizedDescription)" }
            isSearching = false
        }
    }
}

private struct AlertsView: View {
    @Environment(PaperStore.self) private var store
    @State private var name = ""
    @State private var query = ""
    @State private var kind: ResearchAlertKind = .query

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Research alerts").font(.headline)
                TextField("Alert name", text: $name)
                Picker("Type", selection: $kind) { ForEach(ResearchAlertKind.allCases) { Text($0.rawValue).tag($0) } }
                TextField("Query, author, or DOI", text: $query)
                Button("Create Alert") {
                    store.createAlert(name: name, kind: kind, query: query)
                    name = ""; query = ""
                }.help("Create a new research alert").disabled(name.isEmpty || query.isEmpty)
                List {
                    ForEach(store.researchState.alerts) { alert in
                        VStack(alignment: .leading) {
                            Text(alert.name).font(.headline)
                            Text(alert.query).font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Button("Check Now") { Task { await store.refreshAlert(alert.id) } }
                                .help("Run this alert now")
                                Button("Delete", role: .destructive) { store.deleteAlert(alert.id) }
                                .help("Delete this alert")
                            }.buttonStyle(.borderless)
                        }
                    }
                }
            }.frame(minWidth: 240).padding(8)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(store.researchState.alerts) { alert in
                        GroupBox(alert.name) {
                            VStack(alignment: .leading, spacing: 8) {
                                if let checked = alert.lastChecked {
                                    Text("Checked \(checked.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                if alert.matches.isEmpty { Text("No cached results. Choose Check Now.").foregroundStyle(.secondary) }
                                ForEach(alert.matches.prefix(8)) { match in
                                    VStack(alignment: .leading) {
                                        Text(match.title).font(.headline)
                                        Text([match.authors, match.year].filter { !$0.isEmpty }.joined(separator: " · "))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Divider()
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }.padding(8)
            }.frame(minWidth: 460)
        }
        .task {
            let staleAlerts = store.researchState.alerts.filter { alert in
                guard alert.isEnabled else { return false }
                guard let checked = alert.lastChecked else { return true }
                return Date().timeIntervalSince(checked) > 86_400
            }
            for alert in staleAlerts {
                await store.refreshAlert(alert.id)
            }
        }
    }
}
