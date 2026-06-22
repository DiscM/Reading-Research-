import AppKit
import SwiftUI

private enum ResearchHubTab: String, CaseIterable, Identifiable {
    case library = "Library"
    case research = "Research"
    case discover = "Discover"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .library: "books.vertical"
        case .research: "text.magnifyingglass"
        case .discover: "point.3.connected.trianglepath.dotted"
        }
    }

    var subtitle: String {
        switch self {
        case .library: "Organize sources"
        case .research: "Find, compare, and write"
        case .discover: "Follow connections"
        }
    }
}

struct ResearchHubView: View {
    @Environment(PaperStore.self) private var store
    @State private var selectedTab: ResearchHubTab = .library
    @State private var noticeTask: Task<Void, Never>?
    let onOpenPaper: (Paper.ID, Int?) -> Void

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Research Hub", systemImage: "leaf.circle.fill")
                        .font(.title2.bold())
                        .foregroundStyle(SolarpunkTheme.spruce)
                    Text("From source to synthesis")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)

                VStack(spacing: 4) {
                    ForEach(ResearchHubTab.allCases) { tab in
                        Button {
                            withAnimation(.easeInOut(duration: 0.16)) {
                                selectedTab = tab
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: tab.systemImage)
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(tab.rawValue)
                                        .font(.subheadline.weight(.semibold))
                                    Text(tab.subtitle)
                                        .font(.caption2)
                                        .foregroundStyle(selectedTab == tab ? SolarpunkTheme.spruce.opacity(0.75) : .secondary)
                                }
                                Spacer()
                            }
                            .foregroundStyle(selectedTab == tab ? SolarpunkTheme.spruce : .primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(
                                selectedTab == tab ? SolarpunkTheme.lichen.opacity(0.28) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 10)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer()

                VStack(alignment: .leading, spacing: 5) {
                    Label("Local-first", systemImage: "lock.shield.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(SolarpunkTheme.fern)
                    Text("Your papers stay rooted on this Mac.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(SolarpunkTheme.surface.opacity(0.75), in: RoundedRectangle(cornerRadius: 10))
            }
            .padding(12)
            .frame(width: 205)
            .background(SolarpunkTheme.sidebar)

            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedTab.rawValue)
                            .font(.title2.bold())
                        Text(selectedTab.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(SolarpunkTheme.raisedSurface)

                Divider()

                GeometryReader { proxy in
                    Group {
                        switch selectedTab {
                        case .library:
                            LibraryOrganizationView(onOpenPaper: onOpenPaper)
                        case .research:
                            ResearchWorkspaceView { paperID, page in
                                onOpenPaper(paperID, page)
                            }
                        case .discover:
                            DiscoveryAndGraphView(onOpenPaper: onOpenPaper)
                        }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                }
            }
            .background(SolarpunkTheme.canvas)
        }
        .frame(minWidth: 1100, idealWidth: 1200, minHeight: 600, idealHeight: 700)
        .controlSize(.small)
        .overlay(alignment: .bottom) {
            if let notice = store.lastNotice {
                Label(notice, systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().stroke(SolarpunkTheme.hairline))
                    .shadow(radius: 6, y: 2)
                    .padding(.bottom, 14)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onChange(of: store.lastNotice) { _, notice in
            noticeTask?.cancel()
            guard let notice else { return }
            noticeTask = Task {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled, store.lastNotice == notice else { return }
                withAnimation { store.lastNotice = nil }
            }
        }
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
    let onOpenPaper: (Paper.ID, Int?) -> Void

    var body: some View {
        VStack(spacing: 10) {
            Picker("Library tools", selection: $mode) {
                Text("Collections").tag(0)
                Text("Smart Folders").tag(1)
                Text("Citations").tag(2)
                Text("Ask Library").tag(3)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 560)
            .padding(.top, 10)

            GeometryReader { proxy in
                Group {
                    switch mode {
                    case 0: CollectionsView()
                    case 1: SmartFoldersView()
                    case 2: CitationLibraryView()
                    default: LibraryResearchAssistant(onOpen: onOpenPaper)
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

private enum ResearchWorkingView: String, CaseIterable, Identifiable {
    case evidence = "Evidence"
    case synthesis = "Synthesis"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .evidence: "tablecells"
        case .synthesis: "square.and.pencil"
        }
    }
}

private struct ResearchWorkspaceView: View {
    @Environment(PaperStore.self) private var store
    @State private var workingView: ResearchWorkingView = .evidence
    let onOpenPaper: (Paper.ID, Int?) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Label("Research flow", systemImage: "leaf.arrow.triangle.circlepath")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SolarpunkTheme.spruce)

                Picker("Working view", selection: $workingView) {
                    ForEach(ResearchWorkingView.allCases) { view in
                        Label(view.rawValue, systemImage: view.systemImage).tag(view)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 260)

                Text(workflowSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(SolarpunkTheme.raisedSurface)

            Divider()

            Group {
                switch workingView {
                case .evidence:
                    EvidenceWorkspaceView(onOpenPaper: onOpenPaper)
                case .synthesis:
                    SynthesisWorkspacesView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SolarpunkTheme.canvas)
    }

    private var workflowSummary: String {
        "\(store.researchState.evidenceTables.count) evidence tables · \(store.researchState.workspaces.count) drafts · Ask Your Library in Library tools"
    }
}

private struct LibraryResearchAssistant: View {
    @Environment(PaperStore.self) private var store
    @State private var query = ""
    @State private var results: [SemanticSearchResult] = []
    @State private var answer = ""
    let onOpen: (Paper.ID, Int?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Ask your library", systemImage: "sparkle.magnifyingglass")
                    .font(.headline)
                    .foregroundStyle(SolarpunkTheme.spruce)
                Text("Search publication bodies and build an answer grounded only in the passages below. Bibliographies are excluded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("Ask across your library…", text: $query)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(SolarpunkTheme.surface, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(SolarpunkTheme.hairline))
                    .onSubmit(performSearch)

                HStack {
                    Button("Search", action: performSearch)
                        .buttonStyle(.borderedProminent)
                        .tint(SolarpunkTheme.spruce)
                        .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
                        .help("Search across all documents in your library")
                    Button("Build Answer") {
                        answer = SemanticSearchService.groundedAnswer(question: query, results: results)
                    }
                    .disabled(results.isEmpty)
                    .help("Generate a grounded answer from the retrieved passages")
                    Spacer()
                    if !answer.isEmpty {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(answer, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .help("Copy grounded answer")
                    }
                }
            }
            .padding(12)

            Divider()

            if !answer.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Label("Grounded answer", systemImage: "quote.bubble.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SolarpunkTheme.spruce)
                    ScrollView {
                        MarkdownResultView(markdown: answer)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 90, idealHeight: 150, maxHeight: 210)
                }
                .padding(12)
                .background(SolarpunkTheme.surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(SolarpunkTheme.hairline))
                .padding(10)

                Divider()
            }

            HStack {
                Text(results.isEmpty ? "Retrieved passages" : "Retrieved passages (\(results.count))")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if !results.isEmpty {
                    Text("Open to verify")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)

            if results.isEmpty {
                ContentUnavailableView(
                    "Search your sources",
                    systemImage: "text.magnifyingglass",
                    description: Text("Relevant passages and page links will stay here while you compare evidence or write.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(results) { result in
                    Button { onOpen(result.paperID, result.page) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(result.paperTitle)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(2)
                                Spacer(minLength: 6)
                                Text(String(format: "%.0f%%", result.score * 100))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Text(result.text)
                                .font(.caption)
                                .lineLimit(5)
                                .foregroundStyle(.secondary)
                            if let page = result.page {
                                Label("Page \(page)", systemImage: "arrow.up.right.square")
                                    .font(.caption2)
                                    .foregroundStyle(.blue)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .background(SolarpunkTheme.sidebar.opacity(0.55))
    }

    private func performSearch() {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanQuery.count >= 2 else { return }
        results = SemanticSearchService.search(query: cleanQuery, papers: store.papers)
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
        HStack(spacing: 0) {
            synthesisSidebar
            Divider()

            if let selectedID,
               let index = store.researchState.workspaces.firstIndex(where: { $0.id == selectedID }) {
                WorkspaceEditor(workspace: Binding(
                    get: { store.researchState.workspaces[index] },
                    set: { store.researchState.workspaces[index] = $0 }
                ))
            } else {
                SynthesisLandingView(
                    draftCount: store.researchState.workspaces.count,
                    sourceCount: store.papers.count
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SolarpunkTheme.canvas)
        .onAppear(perform: selectInitialWorkspace)
        .onChange(of: store.researchState.workspaces.map(\.id)) { _, ids in
            if let selectedID, ids.contains(selectedID) { return }
            selectedID = ids.first
        }
    }

    private var synthesisSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Synthesis drafts")
                            .font(.headline)
                        Text("\(store.researchState.workspaces.count) writing workspaces")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "square.and.pencil")
                        .foregroundStyle(SolarpunkTheme.fern)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("New draft")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(SolarpunkTheme.spruce)
                    TextField("Workspace name", text: $name)
                        .textFieldStyle(.plain)
                        .padding(7)
                        .background(SolarpunkTheme.surface, in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(SolarpunkTheme.hairline))
                    Picker("Evidence", selection: $evidenceTableID) {
                        Text("No evidence table").tag(nil as UUID?)
                        ForEach(store.researchState.evidenceTables) {
                            Text($0.name).tag(Optional($0.id))
                        }
                    }

                    Text("Sources")
                        .font(.caption.weight(.semibold))
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(store.papers) { paper in
                                Toggle(paper.title, isOn: paperSelectionBinding(paper.id))
                                    .toggleStyle(.checkbox)
                                    .font(.caption)
                                    .lineLimit(2)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 125)

                    Button {
                        createWorkspace()
                    } label: {
                        Label("Create Draft", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(SolarpunkTheme.spruce)
                    .disabled(selectedPapers.isEmpty || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help("Create a synthesis draft from the selected sources")
                }
                .padding(10)
                .background(SolarpunkTheme.surface.opacity(0.72), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(SolarpunkTheme.hairline))
            }
            .padding(12)

            Divider()

            if store.researchState.workspaces.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.title2)
                        .foregroundStyle(SolarpunkTheme.fern)
                    Text("No drafts yet")
                        .font(.subheadline.weight(.semibold))
                    Text("Select sources above to begin a synthesis.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(18)
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                List(selection: $selectedID) {
                    ForEach(store.researchState.workspaces) { workspace in
                        SynthesisWorkspaceSidebarRow(workspace: workspace)
                            .tag(workspace.id)
                            .contextMenu {
                                Button("Delete Draft", role: .destructive) {
                                    store.deleteWorkspace(workspace.id)
                                }
                            }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }

            Divider()
            Label("Evidence-backed writing", systemImage: "leaf.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(SolarpunkTheme.fern)
                .padding(12)
        }
        .frame(width: 245)
        .background(SolarpunkTheme.sidebar.opacity(0.55))
    }

    private func paperSelectionBinding(_ id: Paper.ID) -> Binding<Bool> {
        Binding(
            get: { selectedPapers.contains(id) },
            set: { included in
                if included {
                    selectedPapers.insert(id)
                } else {
                    selectedPapers.remove(id)
                }
            }
        )
    }

    private func createWorkspace() {
        store.createWorkspace(name: name, paperIDs: selectedPapers, evidenceTableID: evidenceTableID)
        selectedID = store.researchState.workspaces.last?.id
        selectedPapers = []
    }

    private func selectInitialWorkspace() {
        guard selectedID == nil else { return }
        selectedID = store.researchState.workspaces.first?.id
    }
}

private struct SynthesisWorkspaceSidebarRow: View {
    let workspace: SynthesisWorkspace

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "square.and.pencil")
                .foregroundStyle(SolarpunkTheme.fern)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(workspace.name)
                    .lineLimit(1)
                Text("\(workspace.paperIDs.count) sources · \(workspace.draft.isEmpty ? "outline" : "draft in progress")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct SynthesisLandingView: View {
    let draftCount: Int
    let sourceCount: Int

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    Image(systemName: "text.badge.sparkles")
                        .font(.system(size: 34))
                        .foregroundStyle(SolarpunkTheme.fern)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Shape evidence into an argument")
                            .font(.title2.bold())
                        Text("Select sources, connect an evidence table, and grow a structured outline into a polished draft.")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(20)
                .solarpunkCard()

                HStack(spacing: 12) {
                    ResearchMetricCard(title: "Library sources", value: "\(sourceCount)", icon: "books.vertical")
                    ResearchMetricCard(title: "Drafts", value: "\(draftCount)", icon: "square.and.pencil")
                }
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct WorkspaceEditor: View {
    @Environment(PaperStore.self) private var store
    @Binding var workspace: SynthesisWorkspace

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    TextField("Workspace name", text: $workspace.name)
                        .textFieldStyle(.plain)
                        .font(.title3.bold())
                    Text("Updated \(workspace.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    store.generateOutline(for: workspace.id)
                } label: {
                    Label("Generate Outline", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .tint(SolarpunkTheme.spruce)
                .help("Auto-generate an outline from collected evidence")
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(workspace.draft, forType: .string)
                } label: {
                    Label("Copy Draft", systemImage: "doc.on.doc")
                }
                .help("Copy the draft text to clipboard")
                .disabled(workspace.draft.isEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(SolarpunkTheme.raisedSurface)

            Divider()

            HStack(spacing: 7) {
                Label("\(workspace.paperIDs.count) sources", systemImage: "books.vertical")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SolarpunkTheme.spruce)
                ForEach(store.papers.filter { workspace.paperIDs.contains($0.id) }.prefix(4)) { paper in
                    Text("@\(CitationService.citationKey(for: CitationService.record(for: paper)))")
                        .font(.caption2.monospaced())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(SolarpunkTheme.lichen.opacity(0.22), in: Capsule())
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SolarpunkTheme.surface.opacity(0.55))

            Divider()

            VSplitView {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Evidence outline", systemImage: "list.bullet.rectangle")
                        .font(.headline)
                        .foregroundStyle(SolarpunkTheme.spruce)
                    TextEditor(text: $workspace.outline)
                        .font(.system(.body, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(7)
                        .background(SolarpunkTheme.surface, in: RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(SolarpunkTheme.hairline))
                }
                .padding(12)
                .frame(minHeight: 180)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Draft", systemImage: "doc.richtext")
                            .font(.headline)
                            .foregroundStyle(SolarpunkTheme.spruce)
                        Spacer()
                        Button("Use Outline as Draft") { workspace.draft = workspace.outline }
                            .help("Replace the draft with the current outline")
                            .disabled(workspace.outline.isEmpty)
                    }
                    TextEditor(text: $workspace.draft)
                        .font(.system(.body, design: .serif))
                        .scrollContentBackground(.hidden)
                        .padding(7)
                        .background(SolarpunkTheme.surface, in: RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(SolarpunkTheme.hairline))
                }
                .padding(12)
                .frame(minHeight: 180)
            }
        }
        .background(SolarpunkTheme.canvas)
    }
}

private struct ResearchMetricCard: View {
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

private struct DiscoveryAndGraphView: View {
    @State private var mode = 0
    let onOpenPaper: (Paper.ID, Int?) -> Void

    var body: some View {
        VStack(spacing: 8) {
            Picker("Discovery tools", selection: $mode) {
                Text("Citation Graph").tag(0)
                Text("Discover Papers").tag(1)
                Text("Alerts").tag(2)
            }.pickerStyle(.segmented).frame(maxWidth: 460)
            switch mode {
            case 0: CitationGraphView(onOpenPaper: onOpenPaper)
            case 1: PaperDiscoveryView()
            default: AlertsView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct CitationGraphView: View {
    @Environment(PaperStore.self) private var store
    @State private var selectedNode: CitationGraphNode?
    @State private var relatedResults: [DiscoveryPaper] = []
    @State private var isLoadingRelated = false
    private var edges: [CitationEdge] { CitationGraphService.edges(for: store.papers) }
    let onOpenPaper: (Paper.ID, Int?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Local citation graph").font(.headline)
                    Text("Click a node to inspect it. Drag to pan, pinch or use the controls to zoom.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(store.papers.count) local · \(edges.count) links · \(edges.filter { $0.targetPaperID != nil }.count) resolved")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }

            HSplitView {
                CitationGraphCanvas(papers: store.papers, edges: edges, selection: $selectedNode)
                    .frame(minWidth: 480)
                    .background(SolarpunkTheme.surface, in: RoundedRectangle(cornerRadius: 10))

                GraphNodeInspector(
                    node: selectedNode,
                    relatedResults: relatedResults,
                    isLoadingRelated: isLoadingRelated,
                    onOpenLocal: { id in onOpenPaper(id, nil) },
                    onOpenOnline: openOnline,
                    onFindRelated: findRelated
                )
                .frame(minWidth: 250, idealWidth: 290, maxWidth: 340)
            }
        }
        .padding(10)
    }

    private func findRelated(_ node: CitationGraphNode) {
        isLoadingRelated = true
        relatedResults = []
        Task {
            do {
                if let paperID = node.localPaperID,
                   let paper = store.papers.first(where: { $0.id == paperID }) {
                    relatedResults = try await DiscoveryService.recommendations(for: paper, rows: 6)
                } else {
                    relatedResults = try await DiscoveryService.recommendations(for: node.discoveryPaper, rows: 6)
                }
            } catch {
                store.lastError = "Could not find related papers: \(error.localizedDescription)"
            }
            isLoadingRelated = false
        }
    }

    private func openOnline(_ paper: DiscoveryPaper) {
        if let url = DiscoveryLinkService.onlineURL(for: paper) { NSWorkspace.shared.open(url) }
    }
}

private struct CitationGraphNode: Identifiable, Equatable {
    let id: String
    let title: String
    let authors: String
    let year: String
    let venue: String
    let doi: String
    let localPaperID: Paper.ID?
    let fingerprint: String

    var isLocal: Bool { localPaperID != nil }
    var discoveryPaper: DiscoveryPaper { DiscoveryPaper(title: title, authors: authors, year: year, venue: venue, doi: doi) }
}

private struct CitationGraphCanvas: View {
    let papers: [Paper]
    let edges: [CitationEdge]
    @Binding var selection: CitationGraphNode?
    @State private var hoveredNodeID: String?
    @State private var scale: CGFloat = 1
    @State private var liveScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var liveDrag: CGSize = .zero

    private var nodes: [CitationGraphNode] {
        let local = papers.prefix(60).map { paper in
            CitationGraphNode(
                id: "local:\(paper.id.uuidString)", title: paper.title,
                authors: paper.authors, year: paper.year, venue: paper.venue,
                doi: paper.doi, localPaperID: paper.id,
                fingerprint: CitationService.record(for: paper).fingerprint
            )
        }
        var seen = Set<String>()
        let external = edges.filter { $0.targetPaperID == nil }.compactMap { edge -> CitationGraphNode? in
            guard seen.insert(edge.targetFingerprint).inserted else { return nil }
            return CitationGraphNode(
                id: "external:\(edge.targetFingerprint)", title: edge.targetTitle,
                authors: edge.targetAuthors, year: edge.targetYear, venue: edge.targetVenue,
                doi: edge.targetDOI, localPaperID: nil, fingerprint: edge.targetFingerprint
            )
        }.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        return Array(local) + Array(external.prefix(100))
    }

    var body: some View {
        GeometryReader { proxy in
            let layout = nodeLayout(in: proxy.size)
            let pointMap = Dictionary(uniqueKeysWithValues: layout.map { ($0.node.id, $0.point) })
            let localIDMap = Dictionary(uniqueKeysWithValues: nodes.compactMap { node in node.localPaperID.map { ($0, node.id) } })
            let fingerprintMap = nodes.reduce(into: [String: String]()) { result, node in
                result[node.fingerprint] = result[node.fingerprint] ?? node.id
            }
            Canvas { context, _ in
                for edge in edges {
                    guard let startID = localIDMap[edge.sourcePaperID], let start = pointMap[startID] else { continue }
                    let endID = edge.targetPaperID.flatMap { localIDMap[$0] } ?? fingerprintMap[edge.targetFingerprint]
                    guard let endID, let end = pointMap[endID] else { continue }
                    var path = Path(); path.move(to: start); path.addLine(to: end)
                    let emphasized = selection?.id == startID || selection?.id == endID
                    context.stroke(path, with: .color(emphasized ? SolarpunkTheme.fern.opacity(0.85) : .secondary.opacity(0.22)), lineWidth: emphasized ? 2 : 1)
                }
                for item in layout {
                    let active = selection?.id == item.node.id
                    let hovered = hoveredNodeID == item.node.id
                    let radius: CGFloat = item.node.isLocal ? 8 : 5
                    let rect = CGRect(x: item.point.x - radius, y: item.point.y - radius, width: radius * 2, height: radius * 2)
                    if active || hovered {
                        context.fill(Path(ellipseIn: rect.insetBy(dx: -5, dy: -5)), with: .color(SolarpunkTheme.sunlight.opacity(0.22)))
                    }
                    context.fill(Path(ellipseIn: rect), with: .color(item.node.isLocal ? SolarpunkTheme.fern : .secondary))
                    if active || hovered || layout.count < 28 {
                        context.draw(
                            Text(item.node.title).font(.caption2.weight(active ? .semibold : .regular)).foregroundStyle(.primary),
                            at: CGPoint(x: item.point.x, y: item.point.y + radius + 5), anchor: .top
                        )
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(layout: layout))
            .simultaneousGesture(magnifyGesture)
            .onContinuousHover { phase in
                switch phase {
                case .active(let location): hoveredNodeID = nearestNode(to: location, in: layout, tolerance: 18)?.id
                case .ended: hoveredNodeID = nil
                }
            }
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 4) {
                    Button { scale = max(0.55, scale / 1.2) } label: { Image(systemName: "minus") }
                    Button { scale = 1; offset = .zero } label: { Image(systemName: "scope") }
                    Button { scale = min(2.8, scale * 1.2) } label: { Image(systemName: "plus") }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(8)
            }
        }
        .frame(minHeight: 380)
    }

    private func nodeLayout(in size: CGSize) -> [(node: CitationGraphNode, point: CGPoint)] {
        let local = nodes.filter(\.isLocal)
        let external = nodes.filter { !$0.isLocal }
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let effectiveScale = scale * liveScale
        let effectiveOffset = CGSize(width: offset.width + liveDrag.width, height: offset.height + liveDrag.height)
        func ring(_ values: [CitationGraphNode], radius: CGFloat) -> [(CitationGraphNode, CGPoint)] {
            guard !values.isEmpty else { return [] }
            return values.enumerated().map { index, node in
                let angle = (Double(index) / Double(values.count)) * Double.pi * 2 - Double.pi / 2
                let base = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
                return (node, CGPoint(
                    x: center.x + (base.x - center.x) * effectiveScale + effectiveOffset.width,
                    y: center.y + (base.y - center.y) * effectiveScale + effectiveOffset.height
                ))
            }
        }
        let unit = min(size.width, size.height)
        return ring(local, radius: unit * 0.23) + ring(external, radius: unit * 0.41)
    }

    private func dragGesture(layout: [(node: CitationGraphNode, point: CGPoint)]) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if hypot(value.translation.width, value.translation.height) > 5 { liveDrag = value.translation }
            }
            .onEnded { value in
                if hypot(value.translation.width, value.translation.height) <= 5 {
                    selection = nearestNode(to: value.location, in: layout, tolerance: 22)
                } else {
                    offset.width += value.translation.width
                    offset.height += value.translation.height
                }
                liveDrag = .zero
            }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in liveScale = value.magnification }
            .onEnded { value in
                scale = min(2.8, max(0.55, scale * value.magnification))
                liveScale = 1
            }
    }

    private func nearestNode(
        to location: CGPoint,
        in layout: [(node: CitationGraphNode, point: CGPoint)],
        tolerance: CGFloat
    ) -> CitationGraphNode? {
        layout.min { lhs, rhs in
            hypot(lhs.point.x - location.x, lhs.point.y - location.y)
                < hypot(rhs.point.x - location.x, rhs.point.y - location.y)
        }.flatMap { item in
            hypot(item.point.x - location.x, item.point.y - location.y) <= tolerance ? item.node : nil
        }
    }
}

private struct GraphNodeInspector: View {
    @Environment(PaperStore.self) private var store
    let node: CitationGraphNode?
    let relatedResults: [DiscoveryPaper]
    let isLoadingRelated: Bool
    let onOpenLocal: (Paper.ID) -> Void
    let onOpenOnline: (DiscoveryPaper) -> Void
    let onFindRelated: (CitationGraphNode) -> Void

    var body: some View {
        ScrollView {
            if let node {
                VStack(alignment: .leading, spacing: 12) {
                    Label(node.isLocal ? "In your library" : "External reference", systemImage: node.isLocal ? "books.vertical.fill" : "network")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(node.isLocal ? SolarpunkTheme.fern : .secondary)
                    Text(node.title).font(.title3.bold()).textSelection(.enabled)
                    if !node.authors.isEmpty { Text(node.authors).font(.subheadline).foregroundStyle(.secondary) }
                    if !node.year.isEmpty { Text(node.year).foregroundStyle(.secondary) }
                    if !node.venue.isEmpty { Text(node.venue).font(.caption).foregroundStyle(.secondary) }
                    if !node.doi.isEmpty { Text(node.doi).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled) }

                    if let id = node.localPaperID {
                        Button("Open Paper") { onOpenLocal(id) }.buttonStyle(.borderedProminent)
                    } else if store.isDiscoveryCitationSaved(node.discoveryPaper) {
                        HStack {
                            Label("Saved", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(SolarpunkTheme.fern)
                            Button("Remove", role: .destructive) { store.removeDiscoveryCitation(node.discoveryPaper) }
                        }
                    } else {
                        Button("Save Citation") { store.saveDiscoveryCitation(node.discoveryPaper) }.buttonStyle(.borderedProminent)
                    }
                    HStack {
                        Button("Open Online") { onOpenOnline(node.discoveryPaper) }
                        Button("More Like This") { onFindRelated(node) }
                    }
                    if isLoadingRelated { ProgressView("Finding related papers…").controlSize(.small) }
                    ForEach(relatedResults.filter { store.researchState.discoveryFeedback[$0.id] != false }) { paper in
                        let isSaved = store.isDiscoveryCitationSaved(paper)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(paper.title).font(.subheadline.weight(.semibold))
                            Text([paper.authors, paper.year].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                            HStack {
                                if isSaved {
                                    Label("Saved", systemImage: "checkmark.circle.fill")
                                        .font(.caption).foregroundStyle(SolarpunkTheme.fern)
                                } else {
                                    Button("Save Citation") { store.saveDiscoveryCitation(paper) }
                                }
                                Button("Open") { onOpenOnline(paper) }
                                Button { store.setDiscoveryFeedback(false, for: paper) } label: {
                                    Image(systemName: "hand.thumbsdown")
                                }
                                .help("Not relevant")
                            }.buttonStyle(.borderless)
                        }
                        Divider()
                    }
                }
                .padding(12)
            } else {
                ContentUnavailableView("Select a node", systemImage: "cursorarrow.click.2", description: Text("Inspect a paper or parsed reference, then open, save, or find related work."))
                    .padding()
            }
        }
        .background(SolarpunkTheme.raisedSurface)
    }
}

private struct PaperDiscoveryView: View {
    @Environment(PaperStore.self) private var store
    @State private var discoveryMode = 0
    @State private var query = ""
    @State private var results: [DiscoveryPaper] = []
    @State private var isSearching = false
    @State private var seedPaperID: Paper.ID?
    @State private var recommendationSource: DiscoveryPaper?
    @State private var resultLimit = 20

    private var visibleResults: [DiscoveryPaper] {
        if discoveryMode == 2 { return store.savedDiscoveryPapers }
        return results.filter { store.researchState.discoveryFeedback[$0.id] != false }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Discover papers").font(.headline)
                    Text("CrossRef search is explicit; local PDF text is never uploaded.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Discovery mode", selection: $discoveryMode) {
                    Text("Search").tag(0)
                    Text("Recommended").tag(1)
                    Text("Saved \(store.savedDiscoveryPapers.count)").tag(2)
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
            }

            if discoveryMode == 0 {
                HStack {
                    TextField("Topic, author, title, or DOI", text: $query).onSubmit(search)
                    Button("Search", action: search).disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
                    .help("Search for papers on CrossRef")
                    Button("Save as Alert") {
                        store.createAlert(name: query, kind: .query, query: query)
                    }.help("Create a recurring search alert").disabled(query.isEmpty)
                }
            } else if discoveryMode == 1 {
                HStack {
                    Picker("Based on", selection: $seedPaperID) {
                        Text("Choose a library paper").tag(nil as Paper.ID?)
                        ForEach(store.papers) { paper in Text(paper.title).tag(Optional(paper.id)) }
                    }
                    Button("Find Similar", action: recommend).disabled(seedPaperID == nil || isSearching)
                    if store.researchState.discoveryFeedback.values.contains(false) {
                        Button("Restore Hidden") { store.clearDismissedDiscoveryPapers() }
                    }
                }
            } else {
                HStack {
                    Label("Saved citations", systemImage: "bookmark.fill")
                        .foregroundStyle(SolarpunkTheme.fern)
                    Spacer()
                    Text("Available from Library → Citations")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if isSearching { ProgressView(discoveryMode == 0 ? "Searching CrossRef…" : "Growing recommendations…").controlSize(.small) }

            List(visibleResults) { result in
                let isSaved = store.isDiscoveryCitationSaved(result)
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(result.title).font(.headline)
                        Text([result.authors, result.year, result.venue].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                        if !result.abstract.isEmpty { Text(result.abstract).lineLimit(3).font(.callout).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        Text("\(result.citedByCount) citations").font(.caption)
                        HStack {
                            if discoveryMode == 2 {
                                Button("Remove", role: .destructive) { store.removeDiscoveryCitation(result) }
                            } else if isSaved {
                                Label("Saved", systemImage: "checkmark.circle.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(SolarpunkTheme.fern)
                            } else {
                                Button("Save Citation") { store.saveDiscoveryCitation(result) }
                            }
                            Button("Open") { openOnline(result) }
                        }
                        HStack {
                            Button("More Like This") { findMoreLike(result) }
                            if discoveryMode != 2 {
                                Button { dismiss(result) } label: { Image(systemName: "hand.thumbsdown") }
                                    .help("Not relevant")
                            }
                        }
                    }
                    .buttonStyle(.borderless)
                }
            }
            .overlay {
                if visibleResults.isEmpty && !isSearching {
                    ContentUnavailableView(
                        emptyTitle,
                        systemImage: emptySystemImage,
                        description: Text(emptyDescription)
                    )
                }
            }

            if discoveryMode != 2 && !results.isEmpty {
                HStack {
                    Text("Showing \(visibleResults.count) result\(visibleResults.count == 1 ? "" : "s")")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Load More") { loadMore() }
                        .disabled(isSearching || resultLimit >= 50)
                }
            }
        }
        .padding(10)
        .onChange(of: discoveryMode) { _, newMode in
            resultLimit = 20
            if newMode == 0 || (newMode == 1 && !isSearching) {
                results = []
                recommendationSource = nil
            }
        }
    }

    private var emptyTitle: String {
        switch discoveryMode {
        case 0: "Search the literature"
        case 1: "Choose a seed paper"
        default: "No saved citations"
        }
    }

    private var emptySystemImage: String {
        switch discoveryMode {
        case 0: "magnifyingglass"
        case 1: "leaf.arrow.triangle.circlepath"
        default: "bookmark"
        }
    }

    private var emptyDescription: String {
        switch discoveryMode {
        case 0: "Search by topic, author, title, or DOI."
        case 1: "Recommendations use a paper title and abstract—not its full PDF text."
        default: "Saved recommendations, graph references, and alert matches will appear here."
        }
    }

    private func search() {
        resultLimit = max(20, resultLimit)
        isSearching = true
        Task {
            do { results = try await DiscoveryService.search(query: query, rows: resultLimit) }
            catch { store.lastError = "Discovery failed: \(error.localizedDescription)" }
            isSearching = false
        }
    }

    private func recommend() {
        guard let seedPaperID, let paper = store.papers.first(where: { $0.id == seedPaperID }) else { return }
        recommendationSource = nil
        resultLimit = max(20, resultLimit)
        isSearching = true
        Task {
            do { results = try await DiscoveryService.recommendations(for: paper, rows: resultLimit) }
            catch { store.lastError = "Recommendations failed: \(error.localizedDescription)" }
            isSearching = false
        }
    }

    private func findMoreLike(_ paper: DiscoveryPaper) {
        findMoreLike(paper, resetLimit: true)
    }

    private func dismiss(_ paper: DiscoveryPaper) {
        store.setDiscoveryFeedback(false, for: paper)
        store.lastNotice = "Hidden “\(paper.title)” from recommendations."
    }

    private func loadMore() {
        resultLimit = min(50, resultLimit + 15)
        if discoveryMode == 0 {
            search()
        } else if let recommendationSource {
            findMoreLike(recommendationSource, resetLimit: false)
        } else {
            recommend()
        }
    }

    private func findMoreLike(_ paper: DiscoveryPaper, resetLimit: Bool) {
        isSearching = true
        discoveryMode = 1
        recommendationSource = paper
        seedPaperID = nil
        if resetLimit { resultLimit = 20 }
        Task {
            do { results = try await DiscoveryService.recommendations(for: paper, rows: resultLimit) }
            catch { store.lastError = "Recommendations failed: \(error.localizedDescription)" }
            isSearching = false
        }
    }

    private func openOnline(_ paper: DiscoveryPaper) {
        if let url = DiscoveryLinkService.onlineURL(for: paper) { NSWorkspace.shared.open(url) }
    }
}

private struct AlertsView: View {
    @Environment(PaperStore.self) private var store
    @AppStorage("automaticResearchAlerts") private var automaticResearchAlerts = false
    @State private var name = ""
    @State private var query = ""
    @State private var kind: ResearchAlertKind = .query
    @State private var checkingAlertIDs = Set<ResearchAlert.ID>()
    @State private var isCheckingAll = false
    @State private var expandedAlertIDs = Set<ResearchAlert.ID>()

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Research alerts").font(.headline)
                    Spacer()
                    if automaticResearchAlerts {
                        Label("Automatic", systemImage: "bell.badge.fill")
                            .font(.caption).foregroundStyle(SolarpunkTheme.fern)
                    }
                }
                TextField("Alert name", text: $name)
                Picker("Type", selection: $kind) { ForEach(ResearchAlertKind.allCases) { Text($0.rawValue).tag($0) } }
                TextField(alertQueryPrompt, text: $query)
                Button("Create Alert") {
                    if store.createAlert(name: name, kind: kind, query: query) {
                        name = ""; query = ""
                    }
                }.help("Create a new research alert").disabled(name.isEmpty || query.isEmpty)
                Button("Check All Now") {
                    checkAll()
                }
                .disabled(store.researchState.alerts.isEmpty || isCheckingAll)
                if isCheckingAll { ProgressView("Checking alerts…").controlSize(.small) }
                List {
                    ForEach(store.researchState.alerts) { alert in
                        VStack(alignment: .leading) {
                            Toggle(isOn: Binding(
                                get: { store.researchState.alerts.first(where: { $0.id == alert.id })?.isEnabled ?? false },
                                set: { enabled in
                                    guard let index = store.researchState.alerts.firstIndex(where: { $0.id == alert.id }) else { return }
                                    store.researchState.alerts[index].isEnabled = enabled
                                }
                            )) {
                                Text(alert.name).font(.headline)
                            }
                            .toggleStyle(.checkbox)
                            Text(alert.query).font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Button("Check Now") { check(alert.id) }
                                .help("Run this alert now")
                                .disabled(checkingAlertIDs.contains(alert.id))
                                if checkingAlertIDs.contains(alert.id) { ProgressView().controlSize(.mini) }
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
                                ForEach(Array(alert.matches.prefix(expandedAlertIDs.contains(alert.id) ? alert.matches.count : 8))) { match in
                                    let isSaved = store.isDiscoveryCitationSaved(match)
                                    HStack(alignment: .top) {
                                        VStack(alignment: .leading) {
                                            Text(match.title).font(.headline)
                                            Text([match.authors, match.year].filter { !$0.isEmpty }.joined(separator: " · "))
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        HStack {
                                            if isSaved {
                                                Label("Saved", systemImage: "checkmark.circle.fill")
                                                    .font(.caption).foregroundStyle(SolarpunkTheme.fern)
                                            } else {
                                                Button("Save Citation") { store.saveDiscoveryCitation(match) }
                                            }
                                            Button("Open") { openOnline(match) }
                                        }
                                        .buttonStyle(.borderless)
                                    }
                                    Divider()
                                }
                                if alert.matches.count > 8 {
                                    Button(expandedAlertIDs.contains(alert.id) ? "Show Less" : "Show All \(alert.matches.count)") {
                                        if expandedAlertIDs.contains(alert.id) {
                                            expandedAlertIDs.remove(alert.id)
                                        } else {
                                            expandedAlertIDs.insert(alert.id)
                                        }
                                    }
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

    private var alertQueryPrompt: String {
        switch kind {
        case .query: "Topic or keywords"
        case .author: "Author name"
        case .citations: "DOI, e.g. 10.1000/example"
        }
    }

    private func check(_ id: ResearchAlert.ID) {
        guard checkingAlertIDs.insert(id).inserted else { return }
        Task {
            await store.refreshAlert(id)
            checkingAlertIDs.remove(id)
        }
    }

    private func checkAll() {
        isCheckingAll = true
        Task {
            for alert in store.researchState.alerts where alert.isEnabled {
                checkingAlertIDs.insert(alert.id)
                await store.refreshAlert(alert.id)
                checkingAlertIDs.remove(alert.id)
            }
            isCheckingAll = false
        }
    }

    private func openOnline(_ paper: DiscoveryPaper) {
        if let url = DiscoveryLinkService.onlineURL(for: paper) { NSWorkspace.shared.open(url) }
    }
}
