import Foundation

public enum MetadataValidator {
    public static func usableTitle(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let title = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.count >= 3 else { return nil }

        let lowered = title.lowercased()
        let rejected = ["untitled", "unknown", "document"]
        guard !rejected.contains(lowered) else { return nil }
        guard !lowered.hasPrefix("http://"), !lowered.hasPrefix("https://") else { return nil }
        guard title.range(of: #"^(arxiv:\s*)?\d{4}\.\d{4,5}(v\d+)?$"#, options: [.regularExpression, .caseInsensitive]) == nil else { return nil }
        guard title.range(of: #"^10\.\d{4,9}/\S+$"#, options: .regularExpression) == nil else { return nil }
        guard title.range(of: #"^[0-9a-f]{8}-[0-9a-f-]{27,}$"#, options: [.regularExpression, .caseInsensitive]) == nil else { return nil }
        return title
    }
}

