import Foundation

public enum MetadataValidator {
    public static func usableTitle(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let title = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }

        let lowered = title.lowercased()
        let rejected = [
            "untitled", "unknown", "document", "fulltext", "full text",
            "paper", "article", "manuscript", "main"
        ]
        guard !rejected.contains(lowered) else { return nil }
        let sourceFilenameExtensions = [
            ".pdf", ".doc", ".docx", ".rtf", ".tex", ".odt", ".pages", ".ppt", ".pptx", ".key",
            ".md", ".txt", ".html", ".htm", ".xml", ".csv"
        ]
        guard !sourceFilenameExtensions.contains(where: lowered.hasSuffix) else { return nil }
        guard lowered.range(
            of: #"^(?:microsoft\s+(?:word|powerpoint)|libreoffice(?:\s+(?:writer|impress|draw|calc))?|google\s+(?:docs|slides|sheets)|pdf\s*creator|adobe\s+acrobat|acrobat\s+pdfmaker)(?:\s*[-–—:].*)?$"#,
            options: .regularExpression
        ) == nil else { return nil }
        guard !lowered.hasPrefix("http://"), !lowered.hasPrefix("https://") else { return nil }
        guard title.range(
            of: #"^(?:arxiv:\s*)?\d{4}\.\d{4,5}(?:v\d+)?(?:\s+\[[^\]]+\])?(?:\s+\d{1,2}\s+[a-z]{3,9}\s+\d{4})?$"#,
            options: [.regularExpression, .caseInsensitive]
        ) == nil else { return nil }
        guard title.range(of: #"^10\.\d{4,9}/\S+$"#, options: .regularExpression) == nil else { return nil }
        guard title.range(of: #"^[0-9a-f]{8}-[0-9a-f-]{27,}$"#, options: [.regularExpression, .caseInsensitive]) == nil else { return nil }
        return title
    }

    public static func normalizedDOI(_ rawValue: String?) -> String? {
        guard var value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !value.isEmpty else {
            return nil
        }
        for prefix in ["https://doi.org/", "http://doi.org/", "doi:"] where value.hasPrefix(prefix) {
            value.removeFirst(prefix.count)
        }
        guard value.range(of: #"^10\.\d{4,9}/\S+$"#, options: .regularExpression) != nil else { return nil }
        return value
    }

    public static func normalizedArxivID(_ rawValue: String?) -> String? {
        guard var value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !value.isEmpty else {
            return nil
        }
        if value.hasPrefix("arxiv:") {
            value.removeFirst("arxiv:".count)
            value = value.trimmingCharacters(in: .whitespaces)
        }
        guard value.range(of: #"^(\d{4}\.\d{4,5}|[a-z-]+/\d{7})(v\d+)?$"#, options: .regularExpression) != nil else { return nil }
        return value
    }

    public static func validPublicationYear(_ year: Int?, now: Date = .now) -> Bool {
        guard let year else { return true }
        let nextYear = Calendar(identifier: .gregorian).component(.year, from: now) + 1
        return (1000...nextYear).contains(year)
    }

    public static func inferredFamilyName(_ displayName: String) -> String {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.contains(",") {
            return name.split(separator: ",", maxSplits: 1)
                .first
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? name
        }
        return name.split(whereSeparator: \Character.isWhitespace).last.map(String.init) ?? name
    }
}
