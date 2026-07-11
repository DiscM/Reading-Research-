import CryptoKit
import Foundation

public enum DocumentFingerprint {
    public static func sha256(of url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return Data(hasher.finalize())
    }
}

