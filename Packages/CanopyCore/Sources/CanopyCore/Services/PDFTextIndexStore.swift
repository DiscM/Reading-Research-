import Foundation
import SQLite3

public actor PDFTextIndexStore {
    private let database: PDFTextIndexDatabase

    public init(databaseURL: URL) throws {
        database = try PDFTextIndexDatabase(url: databaseURL)
    }

    public func prepare(
        _ key: PDFTextIndexKey,
        totalPageCount: Int
    ) throws -> PDFTextIndexPreparation {
        guard totalPageCount >= 0 else {
            throw PDFTextIndexError.invalidPageCount(totalPageCount)
        }

        return try database.transaction {
            if let existing = try statusFromDatabase(for: key) {
                guard existing.totalPageCount == totalPageCount else {
                    throw PDFTextIndexError.pageCountMismatch(
                        expected: existing.totalPageCount,
                        actual: totalPageCount
                    )
                }
                let hasAllPages = existing.indexedPageCount == existing.totalPageCount
                return PDFTextIndexPreparation(
                    disposition: hasAllPages ? .reused : .resumable,
                    status: existing
                )
            }

            try database.execute(
                """
                INSERT INTO index_jobs(
                    fingerprint, format_version, lifecycle, total_page_count, failure_description
                ) VALUES (?, ?, 'pending', ?, NULL)
                """,
                bindings: [.blob(key.fingerprint), .integer(key.formatVersion), .integer(totalPageCount)]
            )
            let status = try requiredStatus(for: key)
            return PDFTextIndexPreparation(disposition: .created, status: status)
        }
    }

    public func status(for key: PDFTextIndexKey) throws -> PDFTextIndexStatus? {
        try statusFromDatabase(for: key)
    }

    public func statuses(formatVersion: Int? = nil) throws -> [PDFTextIndexStatus] {
        if let formatVersion, formatVersion <= 0 {
            throw PDFTextIndexError.invalidFormatVersion(formatVersion)
        }
        let sql: String
        let bindings: [PDFTextIndexDatabase.Value]
        if let formatVersion {
            sql = """
                SELECT fingerprint, format_version
                FROM index_jobs
                WHERE format_version = ?
                ORDER BY fingerprint
                """
            bindings = [.integer(formatVersion)]
        } else {
            sql = """
                SELECT fingerprint, format_version
                FROM index_jobs
                ORDER BY format_version DESC, fingerprint
                """
            bindings = []
        }
        let keys = try database.query(sql, bindings: bindings) { statement in
            try PDFTextIndexKey(
                fingerprint: database.blob(statement, column: 0),
                formatVersion: database.integer(statement, column: 1)
            )
        }
        return try keys.compactMap { try statusFromDatabase(for: $0) }
    }

    @discardableResult
    public func rebuild(
        _ key: PDFTextIndexKey,
        totalPageCount: Int
    ) throws -> PDFTextIndexStatus {
        guard totalPageCount >= 0 else {
            throw PDFTextIndexError.invalidPageCount(totalPageCount)
        }
        return try database.transaction {
            _ = try requiredStatus(for: key)
            try database.execute(
                "DELETE FROM page_text WHERE fingerprint = ? AND format_version = ?",
                bindings: [.blob(key.fingerprint), .integer(key.formatVersion)]
            )
            try database.execute(
                """
                UPDATE index_jobs
                SET lifecycle = 'pending', total_page_count = ?, failure_description = NULL
                WHERE fingerprint = ? AND format_version = ?
                """,
                bindings: [
                    .integer(totalPageCount),
                    .blob(key.fingerprint),
                    .integer(key.formatVersion)
                ]
            )
            return try requiredStatus(for: key)
        }
    }

    @discardableResult
    public func storePageText(
        _ text: String,
        pageIndex: Int,
        for key: PDFTextIndexKey
    ) throws -> PDFTextIndexStatus {
        try database.transaction {
            let current = try requiredStatus(for: key)
            guard (0..<current.totalPageCount).contains(pageIndex) else {
                throw PDFTextIndexError.invalidPageIndex(
                    pageIndex: pageIndex,
                    pageCount: current.totalPageCount
                )
            }

            try database.execute(
                """
                INSERT INTO page_text(fingerprint, format_version, page_index, text)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(fingerprint, format_version, page_index)
                DO UPDATE SET text = excluded.text
                """,
                bindings: [
                    .blob(key.fingerprint),
                    .integer(key.formatVersion),
                    .integer(pageIndex),
                    .text(text)
                ]
            )
            try database.execute(
                """
                UPDATE index_jobs
                SET lifecycle = 'indexing', failure_description = NULL
                WHERE fingerprint = ? AND format_version = ?
                """,
                bindings: [.blob(key.fingerprint), .integer(key.formatVersion)]
            )
            return try requiredStatus(for: key)
        }
    }

    @discardableResult
    public func markReady(_ key: PDFTextIndexKey) throws -> PDFTextIndexStatus {
        try database.transaction {
            let current = try requiredStatus(for: key)
            guard current.indexedPageCount == current.totalPageCount else {
                throw PDFTextIndexError.incompleteIndex(
                    indexedPageCount: current.indexedPageCount,
                    totalPageCount: current.totalPageCount
                )
            }
            try setLifecycle(.ready, failureDescription: nil, for: key)
            return try requiredStatus(for: key)
        }
    }

    @discardableResult
    public func markNeedsSource(_ key: PDFTextIndexKey) throws -> PDFTextIndexStatus {
        try database.transaction {
            _ = try requiredStatus(for: key)
            try setLifecycle(.needsSource, failureDescription: nil, for: key)
            return try requiredStatus(for: key)
        }
    }

    @discardableResult
    public func markFailed(
        _ key: PDFTextIndexKey,
        reason: String
    ) throws -> PDFTextIndexStatus {
        try database.transaction {
            _ = try requiredStatus(for: key)
            try setLifecycle(.failed, failureDescription: reason, for: key)
            return try requiredStatus(for: key)
        }
    }

    public func deleteAllIndexData(forFingerprint fingerprint: Data) throws {
        guard fingerprint.count == 32 else {
            throw PDFTextIndexError.invalidFingerprintLength(fingerprint.count)
        }
        try database.transaction {
            try database.execute(
                "DELETE FROM index_jobs WHERE fingerprint = ?",
                bindings: [.blob(fingerprint)]
            )
            try database.execute(
                "DELETE FROM index_deletion_queue WHERE fingerprint = ?",
                bindings: [.blob(fingerprint)]
            )
        }
    }

    public func enqueueDeletion(forFingerprint fingerprint: Data) throws {
        guard fingerprint.count == 32 else {
            throw PDFTextIndexError.invalidFingerprintLength(fingerprint.count)
        }
        try database.execute(
            "INSERT OR IGNORE INTO index_deletion_queue(fingerprint) VALUES (?)",
            bindings: [.blob(fingerprint)]
        )
    }

    public func cancelDeletion(forFingerprint fingerprint: Data) throws {
        guard fingerprint.count == 32 else {
            throw PDFTextIndexError.invalidFingerprintLength(fingerprint.count)
        }
        try database.execute(
            "DELETE FROM index_deletion_queue WHERE fingerprint = ?",
            bindings: [.blob(fingerprint)]
        )
    }

    public func pendingDeletionFingerprints() throws -> [Data] {
        try database.query(
            "SELECT fingerprint FROM index_deletion_queue ORDER BY fingerprint"
        ) { statement in
            try database.blob(statement, column: 0)
        }
    }

    public func search(
        _ query: String,
        formatVersion: Int,
        fingerprints: [Data]? = nil,
        limit: Int = 50,
        perFingerprintLimit: Int = 5
    ) throws -> [PDFTextSearchHit] {
        guard formatVersion > 0 else {
            throw PDFTextIndexError.invalidFormatVersion(formatVersion)
        }
        guard limit > 0 else { throw PDFTextIndexError.invalidSearchLimit(limit) }
        guard perFingerprintLimit > 0 else {
            throw PDFTextIndexError.invalidSearchLimit(perFingerprintLimit)
        }
        try Task.checkCancellation()
        let matchExpression = Self.matchExpression(for: query)
        guard !matchExpression.isEmpty else { return [] }

        let scopedFingerprints = try fingerprints.map { values in
            try Set(values.map { fingerprint in
                guard fingerprint.count == 32 else {
                    throw PDFTextIndexError.invalidFingerprintLength(fingerprint.count)
                }
                return fingerprint
            })
        }
        if scopedFingerprints?.isEmpty == true { return [] }

        do {
            return try database.withTaskCancellation {
                try database.transaction {
            let usesScope = scopedFingerprints != nil
            if let scopedFingerprints {
                try database.execute("DELETE FROM search_scope")
                for fingerprint in scopedFingerprints {
                    try database.execute(
                        "INSERT OR IGNORE INTO search_scope(fingerprint) VALUES (?)",
                        bindings: [.blob(fingerprint)]
                    )
                }
            }
            defer {
                if usesScope { try? database.execute("DELETE FROM search_scope") }
            }

            let scopeJoin = usesScope
                ? "JOIN search_scope AS scope ON scope.fingerprint = pages.fingerprint"
                : ""
            let sql = """
                WITH chosen_versions AS (
                    SELECT fingerprint,
                           CASE
                               WHEN MAX(CASE WHEN format_version = ? AND lifecycle = 'ready' THEN 1 ELSE 0 END) = 1
                                   THEN ?
                               ELSE COALESCE(
                                   MAX(CASE WHEN format_version < ? AND lifecycle = 'ready' THEN format_version END),
                                   MAX(CASE WHEN format_version = ? THEN format_version END)
                               )
                           END AS format_version
                    FROM index_jobs
                    WHERE format_version <= ?
                    GROUP BY fingerprint
                ), matches AS (
                    SELECT pages.fingerprint AS fingerprint,
                           pages.format_version AS format_version,
                           pages.page_index AS page_index,
                           snippet(page_text_fts, 0, '', '', ' … ', 18) AS match_snippet,
                           bm25(page_text_fts) AS relevance_score
                    FROM page_text_fts
                    JOIN page_text AS pages ON pages.id = page_text_fts.rowid
                    JOIN chosen_versions AS chosen
                      ON chosen.fingerprint = pages.fingerprint
                     AND chosen.format_version = pages.format_version
                    \(scopeJoin)
                    WHERE page_text_fts MATCH ?
                ), ranked AS (
                    SELECT *,
                           ROW_NUMBER() OVER (
                               PARTITION BY fingerprint
                               ORDER BY relevance_score, page_index
                           ) AS fingerprint_rank
                    FROM matches
                )
                SELECT fingerprint, format_version, page_index, match_snippet, relevance_score
                FROM ranked
                WHERE fingerprint_rank <= ?
                ORDER BY relevance_score, page_index
                LIMIT ?
                """
            return try database.query(
                sql,
                bindings: [
                    .integer(formatVersion),
                    .integer(formatVersion),
                    .integer(formatVersion),
                    .integer(formatVersion),
                    .integer(formatVersion),
                    .text(matchExpression),
                    .integer(perFingerprintLimit),
                    .integer(limit)
                ]
            ) { statement in
                let fingerprint = try database.blob(statement, column: 0)
                let storedVersion = database.integer(statement, column: 1)
                let key = try PDFTextIndexKey(
                    fingerprint: fingerprint,
                    formatVersion: storedVersion
                )
                return PDFTextSearchHit(
                    key: key,
                    pageIndex: database.integer(statement, column: 2),
                    snippet: database.text(statement, column: 3),
                    relevanceScore: database.double(statement, column: 4)
                )
            }
                }
            }
        } catch {
            try Task.checkCancellation()
            throw error
        }
    }

    private func statusFromDatabase(for key: PDFTextIndexKey) throws -> PDFTextIndexStatus? {
        let jobs = try database.query(
            """
            SELECT lifecycle, total_page_count, failure_description
            FROM index_jobs
            WHERE fingerprint = ? AND format_version = ?
            """,
            bindings: [.blob(key.fingerprint), .integer(key.formatVersion)]
        ) { statement in
            (
                lifecycle: database.text(statement, column: 0),
                totalPageCount: database.integer(statement, column: 1),
                failureDescription: database.optionalText(statement, column: 2)
            )
        }
        guard let job = jobs.first else { return nil }
        guard let lifecycle = PDFTextIndexLifecycle(rawValue: job.lifecycle) else {
            throw PDFTextIndexError.database("Unknown index lifecycle '\(job.lifecycle)'.")
        }

        let indexedPages = try database.query(
            """
            SELECT page_index
            FROM page_text
            WHERE fingerprint = ? AND format_version = ?
            ORDER BY page_index
            """,
            bindings: [.blob(key.fingerprint), .integer(key.formatVersion)]
        ) { statement in
            database.integer(statement, column: 0)
        }
        var nextPageIndex = 0
        for pageIndex in indexedPages where pageIndex == nextPageIndex {
            nextPageIndex += 1
        }
        return PDFTextIndexStatus(
            key: key,
            lifecycle: lifecycle,
            totalPageCount: job.totalPageCount,
            indexedPageCount: indexedPages.count,
            nextPageIndex: nextPageIndex < job.totalPageCount ? nextPageIndex : nil,
            failureDescription: job.failureDescription
        )
    }

    private func requiredStatus(for key: PDFTextIndexKey) throws -> PDFTextIndexStatus {
        guard let status = try statusFromDatabase(for: key) else {
            throw PDFTextIndexError.missingIndex(key)
        }
        return status
    }

    private func setLifecycle(
        _ lifecycle: PDFTextIndexLifecycle,
        failureDescription: String?,
        for key: PDFTextIndexKey
    ) throws {
        try database.execute(
            """
            UPDATE index_jobs
            SET lifecycle = ?, failure_description = ?
            WHERE fingerprint = ? AND format_version = ?
            """,
            bindings: [
                .text(lifecycle.rawValue),
                failureDescription.map(PDFTextIndexDatabase.Value.text) ?? .null,
                .blob(key.fingerprint),
                .integer(key.formatVersion)
            ]
        )
    }

    private static func matchExpression(for query: String) -> String {
        let expression = try? NSRegularExpression(pattern: #"[\p{L}\p{N}_]+"#)
        let range = NSRange(query.startIndex..<query.endIndex, in: query)
        let tokens = expression?.matches(in: query, range: range).compactMap { match -> String? in
            guard let tokenRange = Range(match.range, in: query) else { return nil }
            return String(query[tokenRange])
        } ?? []
        return tokens.map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }
            .joined(separator: " AND ")
    }
}

private final class PDFTextIndexDatabase {
    enum Value {
        case null
        case integer(Int)
        case double(Double)
        case text(String)
        case blob(Data)
    }

    private var connection: OpaquePointer?

    init(url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let openFlags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let openResult = sqlite3_open_v2(url.path, &connection, openFlags, nil)
        guard openResult == SQLITE_OK, connection != nil else {
            let message = connection.flatMap { sqlite3_errmsg($0) }.map(String.init(cString:))
                ?? "SQLite returned code \(openResult)."
            if let connection { sqlite3_close(connection) }
            connection = nil
            throw PDFTextIndexError.database(message)
        }

        do {
            try execute("PRAGMA foreign_keys = ON")
            try execute("PRAGMA journal_mode = WAL")
            try execute("PRAGMA synchronous = NORMAL")
            try execute("PRAGMA busy_timeout = 5000")
            try execute(
                """
                CREATE TABLE IF NOT EXISTS index_jobs(
                    fingerprint BLOB NOT NULL,
                    format_version INTEGER NOT NULL,
                    lifecycle TEXT NOT NULL,
                    total_page_count INTEGER NOT NULL CHECK(total_page_count >= 0),
                    failure_description TEXT,
                    PRIMARY KEY(fingerprint, format_version)
                )
                """
            )
            try execute(
                """
                CREATE TABLE IF NOT EXISTS page_text(
                    id INTEGER PRIMARY KEY,
                    fingerprint BLOB NOT NULL,
                    format_version INTEGER NOT NULL,
                    page_index INTEGER NOT NULL CHECK(page_index >= 0),
                    text TEXT NOT NULL,
                    UNIQUE(fingerprint, format_version, page_index),
                    FOREIGN KEY(fingerprint, format_version)
                        REFERENCES index_jobs(fingerprint, format_version)
                        ON DELETE CASCADE
                )
                """
            )
            try execute(
                """
                CREATE VIRTUAL TABLE IF NOT EXISTS page_text_fts
                USING fts5(text, content='page_text', content_rowid='id', tokenize='unicode61 remove_diacritics 2')
                """
            )
            try execute(
                """
                CREATE TRIGGER IF NOT EXISTS page_text_after_insert AFTER INSERT ON page_text BEGIN
                    INSERT INTO page_text_fts(rowid, text) VALUES (new.id, new.text);
                END
                """
            )
            try execute(
                """
                CREATE TRIGGER IF NOT EXISTS page_text_after_delete AFTER DELETE ON page_text BEGIN
                    INSERT INTO page_text_fts(page_text_fts, rowid, text)
                    VALUES ('delete', old.id, old.text);
                END
                """
            )
            try execute(
                """
                CREATE TRIGGER IF NOT EXISTS page_text_after_update AFTER UPDATE OF text ON page_text BEGIN
                    INSERT INTO page_text_fts(page_text_fts, rowid, text)
                    VALUES ('delete', old.id, old.text);
                    INSERT INTO page_text_fts(rowid, text) VALUES (new.id, new.text);
                END
                """
            )
            try execute(
                "CREATE TEMP TABLE IF NOT EXISTS search_scope(fingerprint BLOB PRIMARY KEY)"
            )
            try execute(
                "CREATE TABLE IF NOT EXISTS index_deletion_queue(fingerprint BLOB PRIMARY KEY)"
            )
        } catch {
            if let connection { sqlite3_close(connection) }
            connection = nil
            throw error
        }
    }

    deinit {
        if let connection { sqlite3_close(connection) }
    }

    func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do {
            let result = try body()
            try execute("COMMIT")
            return result
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func execute(_ sql: String, bindings: [Value] = []) throws {
        try withStatement(sql, bindings: bindings) { statement in
            while true {
                switch sqlite3_step(statement) {
                case SQLITE_ROW:
                    continue
                case SQLITE_DONE:
                    return
                default:
                    throw errorForConnection()
                }
            }
        }
    }

    func query<T>(
        _ sql: String,
        bindings: [Value] = [],
        transform: (OpaquePointer) throws -> T
    ) throws -> [T] {
        try withStatement(sql, bindings: bindings) { statement in
            var results: [T] = []
            while true {
                switch sqlite3_step(statement) {
                case SQLITE_ROW:
                    results.append(try transform(statement))
                case SQLITE_DONE:
                    return results
                default:
                    throw errorForConnection()
                }
            }
        }
    }

    func withTaskCancellation<T>(_ body: () throws -> T) throws -> T {
        guard let connection else {
            throw PDFTextIndexError.database("The SQLite connection is closed.")
        }
        sqlite3_progress_handler(
            connection,
            500,
            { _ in Task<Never, Never>.isCancelled ? 1 : 0 },
            nil
        )
        defer { sqlite3_progress_handler(connection, 0, nil, nil) }
        return try body()
    }

    func integer(_ statement: OpaquePointer, column: Int32) -> Int {
        Int(sqlite3_column_int64(statement, column))
    }

    func double(_ statement: OpaquePointer, column: Int32) -> Double {
        sqlite3_column_double(statement, column)
    }

    func text(_ statement: OpaquePointer, column: Int32) -> String {
        guard let value = sqlite3_column_text(statement, column) else { return "" }
        return String(cString: value)
    }

    func optionalText(_ statement: OpaquePointer, column: Int32) -> String? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL else { return nil }
        return text(statement, column: column)
    }

    func blob(_ statement: OpaquePointer, column: Int32) throws -> Data {
        let count = Int(sqlite3_column_bytes(statement, column))
        guard count > 0, let bytes = sqlite3_column_blob(statement, column) else {
            throw PDFTextIndexError.database("An indexed fingerprint was empty.")
        }
        return Data(bytes: bytes, count: count)
    }

    private func withStatement<T>(
        _ sql: String,
        bindings: [Value],
        body: (OpaquePointer) throws -> T
    ) throws -> T {
        guard let connection else {
            throw PDFTextIndexError.database("The SQLite connection is closed.")
        }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw errorForConnection()
        }
        defer { sqlite3_finalize(statement) }
        for (offset, binding) in bindings.enumerated() {
            try bind(binding, to: statement, index: Int32(offset + 1))
        }
        return try body(statement)
    }

    private func bind(_ value: Value, to statement: OpaquePointer, index: Int32) throws {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let result: Int32
        switch value {
        case .null:
            result = sqlite3_bind_null(statement, index)
        case let .integer(value):
            result = sqlite3_bind_int64(statement, index, sqlite3_int64(value))
        case let .double(value):
            result = sqlite3_bind_double(statement, index, value)
        case let .text(value):
            result = value.withCString { pointer in
                sqlite3_bind_text(statement, index, pointer, -1, transient)
            }
        case let .blob(value):
            result = value.withUnsafeBytes { bytes in
                sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(bytes.count), transient)
            }
        }
        guard result == SQLITE_OK else { throw errorForConnection() }
    }

    private func errorForConnection() -> PDFTextIndexError {
        guard let connection else {
            return .database("The SQLite connection is closed.")
        }
        return .database(String(cString: sqlite3_errmsg(connection)))
    }
}
