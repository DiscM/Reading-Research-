import AppKit
import Foundation
import Observation
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class PaperStore {
    var papers: [Paper] = [] {
        didSet {
            guard !isLoading else { return }
            scheduleSave()
        }
    }

    var researchState = ResearchState() {
        didSet {
            guard !isLoading else { return }
            scheduleResearchSave()
        }
    }

    var lastError: String?
    var lastNotice: String?
    var isImporting = false
    var enrichmentCount = 0

    private let fileManager = FileManager.default
    private let appDirectory: URL
    private let papersDirectory: URL
    private let imagesDirectory: URL
    private let databaseURL: URL
    private let researchDatabaseURL: URL
    private var isLoading = false
    private var saveTask: Task<Void, Never>?
    private var researchSaveTask: Task<Void, Never>?
    private var importTask: Task<Void, Never>?
    private var alertMonitorTask: Task<Void, Never>?

    init(baseDirectory: URL? = nil) {
        if let baseDirectory {
            appDirectory = baseDirectory
        } else {
            let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            appDirectory = base.appendingPathComponent("ResearchPaperReader", isDirectory: true)
        }
        papersDirectory = appDirectory.appendingPathComponent("Papers", isDirectory: true)
        imagesDirectory = appDirectory.appendingPathComponent("Images", isDirectory: true)
        databaseURL = appDirectory.appendingPathComponent("library.json")
        researchDatabaseURL = appDirectory.appendingPathComponent("research-state.json")

        try? fileManager.createDirectory(at: papersDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        load()
        loadResearchState()
        startAlertMonitoring()
    }

    func importWithOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            Task { @MainActor in
                self?.importDocuments(panel.urls)
            }
        }
    }

    func importDocuments(_ urls: [URL]) {
        guard !urls.isEmpty, !isImporting else { return }
        isImporting = true
        enrichmentCount = 0

        var reservedPaths = Set<String>()
        let jobs = urls.map { sourceURL in
            let destinationURL = uniqueDestinationURL(for: sourceURL, reserving: reservedPaths)
            reservedPaths.insert(destinationURL.path)
            return (sourceURL, destinationURL)
        }

        importTask = Task { [weak self] in
            guard let self else { return }

            for (sourceURL, destinationURL) in jobs {
                guard !Task.isCancelled else { break }

                do {
                    var paper = try await Task.detached(priority: .userInitiated) {
                        try Self.prepareDocument(sourceURL: sourceURL, destinationURL: destinationURL)
                    }.value

                    if paper.documentKind == .researchPaper {
                        paper = await MetadataService.enrich(paper)
                    }

                    if let duplicateIndex = duplicatePaperIndex(matching: paper) {
                        papers[duplicateIndex] = merge(papers[duplicateIndex], with: paper)
                        try? fileManager.removeItem(at: destinationURL)
                        lastNotice = "Merged duplicate: \(paper.title)"
                    } else {
                        papers.insert(paper, at: 0)
                    }
                    enrichmentCount += 1
                    flushSave()
                } catch {
                    try? fileManager.removeItem(at: destinationURL)
                    lastError = "Could not import \(sourceURL.lastPathComponent): \(error.localizedDescription)"
                }
            }

            isImporting = false
            importTask = nil
        }
    }

    // Kept for source compatibility with existing drag-and-drop call sites.
    func importPDFs(_ urls: [URL]) {
        importDocuments(urls)
    }

    func delete(_ paper: Paper) {
        papers.removeAll { $0.id == paper.id }
        let paperID = paper.id
        researchState.collections.indices.forEach { index in
            researchState.collections[index].paperIDs.remove(paperID)
        }
        researchState.evidenceTables.indices.forEach { index in
            researchState.evidenceTables[index].rows.removeAll { $0.paperID == paperID }
        }
        researchState.workspaces.indices.forEach { index in
            researchState.workspaces[index].paperIDs.remove(paperID)
        }
        try? fileManager.removeItem(at: paper.fileURL)
        flushSave()
        saveResearchState()
    }

    // MARK: - Collections and smart folders

    func createCollection(name: String, parentID: UUID? = nil) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        researchState.collections.append(PaperCollection(name: clean, parentID: parentID))
    }

    func deleteCollection(_ id: UUID) {
        var idsToDelete: Set<UUID> = [id]
        var foundChild = true
        while foundChild {
            let children = Set(researchState.collections.filter { collection in
                collection.parentID.map(idsToDelete.contains) ?? false
            }.map(\.id))
            let previousCount = idsToDelete.count
            idsToDelete.formUnion(children)
            foundChild = idsToDelete.count > previousCount
        }
        researchState.collections.removeAll { idsToDelete.contains($0.id) }
    }

    func setPaper(_ paperID: UUID, in collectionID: UUID, included: Bool) {
        guard let index = researchState.collections.firstIndex(where: { $0.id == collectionID }) else { return }
        if included {
            researchState.collections[index].paperIDs.insert(paperID)
        } else {
            researchState.collections[index].paperIDs.remove(paperID)
        }
    }

    func papersInCollection(_ collectionID: UUID) -> [Paper] {
        guard let collection = researchState.collections.first(where: { $0.id == collectionID }) else { return [] }
        return papers.filter { collection.paperIDs.contains($0.id) }
    }

    func createSmartFolder(name: String, rules: [SmartFolderRule], matchAll: Bool = true) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !rules.isEmpty else { return }
        researchState.smartFolders.append(SmartFolder(name: clean, matchAll: matchAll, rules: rules))
    }

    func papersInSmartFolder(_ smartFolderID: UUID) -> [Paper] {
        guard let folder = researchState.smartFolders.first(where: { $0.id == smartFolderID }) else { return [] }
        return papers.filter(folder.matches)
    }

    func deleteSmartFolder(_ id: UUID) {
        researchState.smartFolders.removeAll { $0.id == id }
    }

    // MARK: - Citation library

    @discardableResult
    func importCitations(_ text: String) throws -> CitationImportReport {
        let parsed = try CitationService.parse(text)
        var imported = 0
        var mergedCount = 0
        for record in parsed {
            if let index = researchState.citations.firstIndex(where: { $0.fingerprint == record.fingerprint }) {
                researchState.citations[index] = CitationService.merged(researchState.citations[index], record)
                mergedCount += 1
            } else if let paper = papers.first(where: { CitationService.record(for: $0).fingerprint == record.fingerprint }) {
                let paperRecord = CitationService.record(for: paper)
                if !researchState.citations.contains(where: { $0.fingerprint == paperRecord.fingerprint }) {
                    researchState.citations.append(CitationService.merged(paperRecord, record))
                }
                mergedCount += 1
            } else {
                var record = record
                if record.citationKey.isEmpty { record.citationKey = CitationService.citationKey(for: record) }
                researchState.citations.append(record)
                imported += 1
            }
        }
        return CitationImportReport(imported: imported, merged: mergedCount)
    }

    func allCitationRecords() -> [CitationRecord] {
        CitationService.deduplicated(researchState.citations + papers.map(CitationService.record(for:)))
    }

    func deleteCitation(_ id: UUID) {
        researchState.citations.removeAll { $0.id == id }
    }

    @discardableResult
    func saveDiscoveryCitation(_ paper: DiscoveryPaper) -> Bool {
        var record = CitationRecord(
            title: paper.title,
            authors: paper.authors,
            year: paper.year,
            venue: paper.venue,
            doi: paper.doi,
            abstract: paper.abstract,
            source: .crossref
        )
        record.citationKey = CitationService.citationKey(for: record)
        let wasSaved = isDiscoveryCitationSaved(paper)
        researchState.citations = CitationService.deduplicated(researchState.citations + [record])
        lastNotice = wasSaved
            ? "“\(paper.title)” is already saved."
            : "Saved “\(paper.title)” to the citation library."
        return !wasSaved
    }

    func isDiscoveryCitationSaved(_ paper: DiscoveryPaper) -> Bool {
        let fingerprint = DiscoveryService.discoveryFingerprint(paper)
        return researchState.citations.contains { $0.fingerprint == fingerprint }
            || papers.contains { CitationService.record(for: $0).fingerprint == fingerprint }
    }

    func removeDiscoveryCitation(_ paper: DiscoveryPaper) {
        let fingerprint = DiscoveryService.discoveryFingerprint(paper)
        researchState.citations.removeAll { $0.fingerprint == fingerprint }
        lastNotice = "Removed “\(paper.title)” from saved citations."
    }

    var savedDiscoveryPapers: [DiscoveryPaper] {
        researchState.citations.map { record in
            DiscoveryPaper(
                title: record.title,
                authors: record.authors,
                year: record.year,
                venue: record.venue,
                doi: record.doi,
                abstract: record.abstract
            )
        }
    }
    func setDiscoveryFeedback(_ isRelevant: Bool, for paper: DiscoveryPaper) {
        researchState.discoveryFeedback[paper.id] = isRelevant
    }

    func clearDismissedDiscoveryPapers() {
        researchState.discoveryFeedback = researchState.discoveryFeedback.filter { $0.value }
        lastNotice = "Restored hidden recommendations."
    }

    // MARK: - Evidence and synthesis

    func createEvidenceTable(name: String, paperIDs: Set<UUID>) {
        let selected = papers.filter { paperIDs.contains($0.id) }
        guard !selected.isEmpty else { return }
        researchState.evidenceTables.append(EvidenceService.makeTable(name: name, papers: selected))
        lastNotice = "Created evidence table with \(selected.count) source\(selected.count == 1 ? "" : "s")."
    }

    func addPapers(_ paperIDs: Set<UUID>, toEvidenceTable tableID: UUID) {
        guard let index = researchState.evidenceTables.firstIndex(where: { $0.id == tableID }) else { return }
        let existing = Set(researchState.evidenceTables[index].rows.map(\.paperID))
        let additions = papers.filter { paperIDs.contains($0.id) && !existing.contains($0.id) }
        guard !additions.isEmpty else { return }
        let columns = researchState.evidenceTables[index].columns
        researchState.evidenceTables[index].rows.append(contentsOf: additions.map {
            EvidenceService.makeRow(for: $0, columns: columns)
        })
        researchState.evidenceTables[index].updatedAt = Date()
        lastNotice = "Added \(additions.count) source\(additions.count == 1 ? "" : "s") to the evidence table."
    }

    func removePaper(_ paperID: UUID, fromEvidenceTable tableID: UUID) {
        guard let index = researchState.evidenceTables.firstIndex(where: { $0.id == tableID }) else { return }
        researchState.evidenceTables[index].rows.removeAll { $0.paperID == paperID }
        researchState.evidenceTables[index].updatedAt = Date()
    }

    @discardableResult
    func addEvidenceColumn(name: String, to tableID: UUID) -> Bool {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty,
              let tableIndex = researchState.evidenceTables.firstIndex(where: { $0.id == tableID }),
              !researchState.evidenceTables[tableIndex].columns.contains(where: {
                  $0.name.localizedCaseInsensitiveCompare(clean) == .orderedSame
              }) else { return false }

        let column = EvidenceColumn(name: clean)
        researchState.evidenceTables[tableIndex].columns.append(column)
        for rowIndex in researchState.evidenceTables[tableIndex].rows.indices {
            let paperID = researchState.evidenceTables[tableIndex].rows[rowIndex].paperID
            let suggestion = papers.first(where: { $0.id == paperID })
                .map { EvidenceService.suggestedValue(clean, paper: $0) } ?? ""
            researchState.evidenceTables[tableIndex].rows[rowIndex].cells.append(
                EvidenceCell(columnID: column.id, value: suggestion, quote: suggestion)
            )
        }
        researchState.evidenceTables[tableIndex].updatedAt = Date()
        return true
    }

    @discardableResult
    func deleteEvidenceColumn(_ columnID: EvidenceColumn.ID, from tableID: UUID) -> Bool {
        guard let tableIndex = researchState.evidenceTables.firstIndex(where: { $0.id == tableID }),
              researchState.evidenceTables[tableIndex].columns.count > 1,
              let columnIndex = researchState.evidenceTables[tableIndex].columns.firstIndex(where: {
                  $0.id == columnID
              }) else { return false }
        researchState.evidenceTables[tableIndex].columns.remove(at: columnIndex)
        for rowIndex in researchState.evidenceTables[tableIndex].rows.indices {
            researchState.evidenceTables[tableIndex].rows[rowIndex].cells.removeAll { $0.columnID == columnID }
        }
        researchState.evidenceTables[tableIndex].updatedAt = Date()
        return true
    }

    func populateEmptyEvidenceCells(in tableID: UUID) {
        guard let index = researchState.evidenceTables.firstIndex(where: { $0.id == tableID }) else { return }
        EvidenceService.populateEmptyCells(in: &researchState.evidenceTables[index], papers: papers)
        lastNotice = "Filled available evidence from local paper text."
    }

    func deleteEvidenceTable(_ id: UUID) {
        researchState.evidenceTables.removeAll { $0.id == id }
        researchState.workspaces.indices.forEach { index in
            if researchState.workspaces[index].evidenceTableID == id {
                researchState.workspaces[index].evidenceTableID = nil
            }
        }
    }

    func createWorkspace(name: String, paperIDs: Set<UUID>, evidenceTableID: UUID? = nil) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !paperIDs.isEmpty else { return }
        researchState.workspaces.append(SynthesisWorkspace(
            name: clean,
            paperIDs: paperIDs,
            evidenceTableID: evidenceTableID
        ))
    }

    func generateOutline(for workspaceID: UUID) {
        guard let index = researchState.workspaces.firstIndex(where: { $0.id == workspaceID }) else { return }
        let workspace = researchState.workspaces[index]
        let table = workspace.evidenceTableID.flatMap { id in
            researchState.evidenceTables.first(where: { $0.id == id })
        }
        researchState.workspaces[index].outline = EvidenceService.outline(
            workspace: workspace,
            papers: papers,
            table: table
        )
        researchState.workspaces[index].updatedAt = Date()
    }

    func deleteWorkspace(_ id: UUID) {
        researchState.workspaces.removeAll { $0.id == id }
    }

    // MARK: - Alerts

    @discardableResult
    func createAlert(name: String, kind: ResearchAlertKind, query: String) -> Bool {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanQuery = kind == .citations ? rawQuery.normalizedDOI : rawQuery
        guard !cleanName.isEmpty, !cleanQuery.isEmpty else { return false }
        if kind == .citations, cleanQuery.range(of: #"^10\.\d{4,9}/\S+$"#, options: .regularExpression) == nil {
            lastError = "Incoming-citation alerts require a valid DOI."
            return false
        }
        guard !researchState.alerts.contains(where: { $0.kind == kind && $0.query.caseInsensitiveCompare(cleanQuery) == .orderedSame }) else {
            lastNotice = "An alert for “\(cleanQuery)” already exists."
            return false
        }
        researchState.alerts.append(ResearchAlert(name: cleanName, kind: kind, query: cleanQuery))
        lastNotice = "Created alert “\(cleanName)”."
        return true
    }

    func refreshAlert(_ id: UUID, notify: Bool = false) async {
        guard let alert = researchState.alerts.first(where: { $0.id == id }) else { return }
        do {
            let updated = try await DiscoveryService.refresh(alert)
            guard let index = researchState.alerts.firstIndex(where: { $0.id == id }) else { return }
            let existingIDs = Set(researchState.alerts[index].matches.map(\.id))
            let newMatches = updated.matches.filter { !existingIDs.contains($0.id) }
            researchState.alerts[index] = updated
            if notify, !newMatches.isEmpty {
                await DiscoveryNotificationService.post(alertName: alert.name, matches: newMatches)
            }
        } catch {
            lastError = "Could not refresh \(alert.name): \(error.localizedDescription)"
        }
    }

    func deleteAlert(_ id: UUID) {
        researchState.alerts.removeAll { $0.id == id }
    }

    private func startAlertMonitoring() {
        alertMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if UserDefaults.standard.bool(forKey: "automaticResearchAlerts") {
                    let storedInterval = UserDefaults.standard.double(forKey: "researchAlertIntervalHours")
                    let intervalHours = storedInterval > 0 ? storedInterval : 24
                    let interval = intervalHours * 3_600
                    let stale = self.researchState.alerts.filter { alert in
                        guard alert.isEnabled else { return false }
                        guard let checked = alert.lastChecked else { return true }
                        return Date().timeIntervalSince(checked) >= interval
                    }
                    for alert in stale {
                        await self.refreshAlert(alert.id, notify: true)
                    }
                }
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    func reEnrich(_ paper: Paper) async {
        guard let index = papers.firstIndex(where: { $0.id == paper.id }) else { return }
        let enriched = await MetadataService.enrich(papers[index])
        papers[index] = enriched
        scheduleSave()
    }

    func generateSummary(for paper: Paper) async {
        guard let index = papers.firstIndex(where: { $0.id == paper.id }) else { return }
        let summary = await LocalPaperAI.summary(for: papers[index])
        guard let updatedIndex = papers.firstIndex(where: { $0.id == paper.id }) else { return }
        papers[updatedIndex].aiSummary = summary
    }

    func generateExtraction(for paper: Paper, kind: HighlightKind) async -> String {
        await LocalPaperAI.extraction(for: paper, kind: kind)
    }

    func addNote(
        to paper: Paper,
        kind: HighlightKind,
        quote: String,
        body: String,
        page: Int?,
        isAreaNote: Bool = false,
        rectX: Double? = nil,
        rectY: Double? = nil,
        rectWidth: Double? = nil,
        rectHeight: Double? = nil,
        imageFileName: String? = nil
    ) {
        guard let index = papers.firstIndex(where: { $0.id == paper.id }) else { return }
        let note = PaperNote(
            kind: kind,
            quote: quote,
            body: body,
            page: page,
            isAreaNote: isAreaNote,
            rectX: rectX,
            rectY: rectY,
            rectWidth: rectWidth,
            rectHeight: rectHeight,
            imageFileName: imageFileName
        )
        papers[index].notes.insert(note, at: 0)
    }

    func deleteNote(_ note: PaperNote, from paper: Paper) {
        guard let paperIndex = papers.firstIndex(where: { $0.id == paper.id }) else { return }
        papers[paperIndex].notes.removeAll { $0.id == note.id }
        
        if let imageFileName = note.imageFileName {
            let fileURL = imagesDirectory.appendingPathComponent(imageFileName)
            try? fileManager.removeItem(at: fileURL)
        }
        flushSave()
    }

    func imageUrl(for fileName: String) -> URL {
        imagesDirectory.appendingPathComponent(fileName)
    }

    func saveAreaNoteImage(from page: PDFPage, rect: CGRect) -> String? {
        let imageSize = rect.size
        let scale: CGFloat = 2.0
        let targetSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        
        let image = NSImage(size: targetSize)
        image.lockFocus()
        guard let context = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            return nil
        }
        
        // Fill white background
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(origin: .zero, size: targetSize))
        
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -rect.origin.x, y: -rect.origin.y)
        
        page.draw(with: .mediaBox, to: context)
        image.unlockFocus()
        
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }
        
        let fileUUID = UUID()
        let fileName = "\(fileUUID.uuidString).png"
        let fileURL = imagesDirectory.appendingPathComponent(fileName)
        
        do {
            try pngData.write(to: fileURL)
            return fileName
        } catch {
            lastError = "Could not save cropped area image: \(error.localizedDescription)"
            return nil
        }
    }

    func exportMarkdown(for paper: Paper) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(paper.title.sanitizedFileName)-notes.md"

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                do {
                    try self?.markdown(for: paper).write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    self?.lastError = "Could not export notes: \(error.localizedDescription)"
                }
            }
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self?.save()
            } catch { return }
        }
    }

    private func flushSave() {
        saveTask?.cancel()
        save()
    }

    private func scheduleResearchSave() {
        researchSaveTask?.cancel()
        researchSaveTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self?.saveResearchState()
            } catch { return }
        }
    }

    func saveResearchState() {
        do {
            let data = try JSONEncoder.researchPaperReader.encode(researchState)
            try fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true)
            try data.write(to: researchDatabaseURL, options: [.atomic])
        } catch {
            lastError = "Could not save research workspace: \(error.localizedDescription)"
        }
    }

    func save() {
        do {
            let data = try JSONEncoder.researchPaperReader.encode(papers)
            try fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true)
            try data.write(to: databaseURL, options: [.atomic])
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func load() {
        guard fileManager.fileExists(atPath: databaseURL.path) else { return }

        do {
            isLoading = true
            let data = try Data(contentsOf: databaseURL)
            papers = try JSONDecoder.researchPaperReader.decode([Paper].self, from: data)
            isLoading = false
        } catch {
            isLoading = false
            lastError = "The library could not be loaded. Its data was preserved at \(databaseURL.path). \(error.localizedDescription)"
        }
    }

    private func loadResearchState() {
        guard fileManager.fileExists(atPath: researchDatabaseURL.path) else { return }
        do {
            isLoading = true
            let data = try Data(contentsOf: researchDatabaseURL)
            researchState = try JSONDecoder.researchPaperReader.decode(ResearchState.self, from: data)
            isLoading = false
        } catch {
            isLoading = false
            lastError = "Research workspace data could not be loaded. Its data was preserved at \(researchDatabaseURL.path). \(error.localizedDescription)"
        }
    }

    private func uniqueDestinationURL(for sourceURL: URL, reserving reservedPaths: Set<String> = []) -> URL {
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let ext = sourceURL.pathExtension.isEmpty ? "pdf" : sourceURL.pathExtension
        var candidate = papersDirectory.appendingPathComponent("\(baseName).\(ext)")
        var counter = 2

        while fileManager.fileExists(atPath: candidate.path) || reservedPaths.contains(candidate.path) {
            candidate = papersDirectory.appendingPathComponent("\(baseName)-\(counter).\(ext)")
            counter += 1
        }

        return candidate
    }

    private func duplicatePaperIndex(matching candidate: Paper) -> Int? {
        let candidateDOI = candidate.doi.normalizedDOI
        if !candidateDOI.isEmpty {
            for (index, paper) in papers.enumerated() {
                if paper.doi.normalizedDOI == candidateDOI {
                    return index
                }
            }
        }
        if !candidate.arxivId.isEmpty {
            for (index, paper) in papers.enumerated() {
                if paper.arxivId.caseInsensitiveCompare(candidate.arxivId) == .orderedSame {
                    return index
                }
            }
        }
        let normalized = candidate.title.lowercased().filter { $0.isLetter || $0.isNumber }
        guard normalized.count > 8 else { return nil }
        for (index, paper) in papers.enumerated() {
            let other = paper.title.lowercased().filter { $0.isLetter || $0.isNumber }
            if other == normalized && (candidate.year.isEmpty || paper.year.isEmpty || candidate.year == paper.year) {
                return index
            }
        }
        return nil
    }

    private func merge(_ existing: Paper, with candidate: Paper) -> Paper {
        var result = existing
        if result.authors.isEmpty { result.authors = candidate.authors }
        if result.year.isEmpty { result.year = candidate.year }
        if result.abstract.isEmpty { result.abstract = candidate.abstract }
        if result.doi.isEmpty { result.doi = candidate.doi }
        if result.arxivId.isEmpty { result.arxivId = candidate.arxivId }
        if result.venue.isEmpty { result.venue = candidate.venue }
        if result.sections.isEmpty { result.sections = candidate.sections }
        if result.allText.isEmpty {
            result.allText = candidate.allText
            result.allTextPageOffsets = candidate.allTextPageOffsets
        }
        result.tags = Array(Set(result.tags + candidate.tags)).sorted()
        return result
    }

    private nonisolated static func prepareDocument(sourceURL: URL, destinationURL: URL) throws -> Paper {
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)

        let metadata = extractMetadata(from: destinationURL)
        let extracted = extractAllText(from: destinationURL)
        let documentKind = inferDocumentKind(
            filename: sourceURL.deletingPathExtension().lastPathComponent,
            text: extracted.text,
            doi: metadata.doi,
            arxivId: metadata.arxivId
        )
        let sections = documentKind == .researchPaper
            ? LocalPaperAI.sections(from: extracted.text, pageOffsets: extracted.offsets)
            : []
        let fallbackTitle = sourceURL.deletingPathExtension().lastPathComponent.readableDocumentTitle

        return Paper(
            documentKind: documentKind,
            title: metadata.title.isEmpty ? fallbackTitle : metadata.title,
            authors: metadata.authors,
            year: metadata.year,
            abstract: documentKind == .researchPaper ? metadata.abstract : "",
            filePath: destinationURL.path,
            sections: sections,
            allText: extracted.text,
            allTextPageOffsets: extracted.offsets,
            doi: metadata.doi,
            arxivId: metadata.arxivId,
            publicationNumber: metadata.publicationNumber,
            venue: metadata.venue
        )
    }

    private nonisolated static func extractAllText(from url: URL) -> (text: String, offsets: [Int]) {
        guard let document = PDFDocument(url: url) else { return ("", []) }
        var parts: [String] = []
        var offsets: [Int] = []
        var offset = 0
        for i in 0..<document.pageCount {
            offsets.append(offset)
            if let text = document.page(at: i)?.string {
                offset += text.count + 1
                parts.append(text)
            } else {
                offset += 1
                parts.append("")
            }
        }
        return (parts.joined(separator: "\n"), offsets)
    }

    private nonisolated static func extractMetadata(from url: URL) -> (title: String, authors: String, year: String, abstract: String, doi: String, arxivId: String, venue: String, publicationNumber: String) {
        let document = PDFDocument(url: url)
        let attributes = document?.documentAttributes ?? [:]
        let rawTitle = (attributes[PDFDocumentAttribute.titleAttribute] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rawAuthor = (attributes[PDFDocumentAttribute.authorAttribute] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let firstPage = document?.page(at: 0)?.string ?? ""
        let abstract = LocalPaperAI.abstractCandidate(from: firstPage)
        let doi = MetadataService.extractDOI(from: firstPage) ?? ""
        let arxivId = MetadataService.extractArxivID(from: firstPage)
            ?? MetadataService.extractArxivID(from: rawTitle)
            ?? ""

        let titleIsID = rawTitle.hasAuthorSwapPattern
        let publicationNumber: String
        let title: String
        let author: String

        if titleIsID {
            publicationNumber = arxivId.isEmpty ? rawTitle : arxivId
            title = ""
            author = ""
        } else {
            publicationNumber = arxivId.isEmpty ? doi : arxivId
            title = rawTitle.isEmpty ? "" : rawTitle
            author = rawAuthor.isEmpty ? "" : rawAuthor
        }

        return (title, author, "", abstract, doi, arxivId, "", publicationNumber)
    }

    nonisolated static func inferDocumentKind(filename: String, text: String, doi: String, arxivId: String) -> DocumentKind {
        let name = filename.lowercased()
        let sample = String(text.prefix(20_000)).lowercased()

        if !doi.isEmpty || !arxivId.isEmpty {
            return .researchPaper
        }

        if name.range(of: #"(?:lecture|slides?|slide[-_ ]?deck|week[-_ ]?\d+)"#, options: .regularExpression) != nil
            || sample.contains("learning objectives")
            || sample.contains("lecture slides") {
            return .lectureSlides
        }

        if name.range(of: #"(?:notes?|study[-_ ]?guide|handout|cheat[-_ ]?sheet|worksheet)"#, options: .regularExpression) != nil
            || sample.contains("study guide")
            || sample.contains("class notes")
            || sample.contains("course notes") {
            return .studyNotes
        }

        if name.range(of: #"(?:chapter|textbook|book)"#, options: .regularExpression) != nil
            || sample.range(of: #"\bchapter\s+\d+\b"#, options: .regularExpression) != nil {
            return .bookChapter
        }

        let researchSignals = [
            sample.contains("abstract"),
            sample.contains("introduction"),
            sample.contains("references"),
            sample.contains("methodology") || sample.contains("experimental results"),
        ].filter { $0 }.count

        return researchSignals >= 2 ? .researchPaper : .generalPDF
    }

    private func markdown(for paper: Paper) -> String {
        var lines: [String] = [
            "# \(paper.title)",
            "",
            "- Type: \(paper.documentKind.rawValue)",
            "- Status: \(paper.status.rawValue)",
            ""
        ]

        if !paper.authors.isEmpty { lines.insert("- Authors: \(paper.authors)", at: 3) }
        if !paper.year.isEmpty { lines.insert("- Year: \(paper.year)", at: paper.authors.isEmpty ? 3 : 4) }

        if !paper.abstract.isEmpty {
            lines.append("## Abstract")
            lines.append("")
            lines.append(paper.abstract)
            lines.append("")
        }

        if let aiSummary = paper.aiSummary {
            lines.append("## AI Summary")
            lines.append("")
            lines.append(aiSummary)
            lines.append("")
        }

        lines.append("## Notes")
        lines.append("")

        if paper.notes.isEmpty {
            lines.append("_No notes yet._")
        } else {
            for note in paper.notes {
                lines.append("### \(note.kind.rawValue)")
                if let page = note.page {
                    lines.append("")
                    lines.append("Page: \(page)")
                }
                if !note.quote.isEmpty {
                    lines.append("")
                    lines.append("> \(note.quote)")
                }
                lines.append("")
                lines.append(note.body)
                lines.append("")
            }
        }

        return lines.joined(separator: "\n")
    }
}

private extension String {
    var sanitizedFileName: String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = components(separatedBy: invalid).joined(separator: "-")
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "paper" : cleaned
    }
}

private extension String {
    var readableDocumentTitle: String {
        replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .joined(separator: " ")
    }
}

private extension JSONEncoder {
    static var researchPaperReader: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var researchPaperReader: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
