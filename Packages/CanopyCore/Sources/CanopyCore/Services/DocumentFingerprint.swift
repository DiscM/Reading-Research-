import CryptoKit
import Foundation

public enum DocumentFingerprint {
    public static func sha256(of url: URL, didReadBytes: ((Int) -> Void)? = nil) throws -> Data {
        try Task.checkCancellation()
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        var totalBytesRead = 0
        while true {
            try Task.checkCancellation()
            guard let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty else {
                break
            }
            hasher.update(data: chunk)
            totalBytesRead += chunk.count
            didReadBytes?(totalBytesRead)
        }
        try Task.checkCancellation()
        return Data(hasher.finalize())
    }
}
