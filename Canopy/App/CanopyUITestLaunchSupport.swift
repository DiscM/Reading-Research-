#if DEBUG
import Foundation

/// Narrow, deterministic launch hooks for the UI-test target. Every artifact is
/// rooted below a UUID-named directory separate from Canopy's real library.
struct CanopyUITestLibraryConfiguration {
    static var isRequested: Bool {
        ProcessInfo.processInfo.environment["CANOPY_UI_TEST_MODE"] == "1"
    }

    static var current: Self? {
        let environment = ProcessInfo.processInfo.environment
        guard isRequested,
              let rawIdentifier = environment["CANOPY_UI_TEST_LIBRARY_ID"],
              let identifier = UUID(uuidString: rawIdentifier) else {
            return nil
        }
        return Self(
            identifier: identifier,
            resetsBeforeOpening: environment["CANOPY_UI_TEST_RESET_LIBRARY"] == "1",
            cleansBeforeOpening: environment["CANOPY_UI_TEST_CLEANUP_LIBRARY"] == "1"
        )
    }

    static var invalidConfigurationStoreURL: URL {
        URL.applicationSupportDirectory
            .appendingPathComponent("CanopyUITests", isDirectory: true)
            .appendingPathComponent("InvalidConfiguration", isDirectory: true)
            .appendingPathComponent("CanopyWorkspaceV1.store")
    }

    let directoryURL: URL
    let storeURL: URL
    let resetsBeforeOpening: Bool
    let cleansBeforeOpening: Bool

    func materializeAddDocumentsFixture() -> URL? {
        let environment = ProcessInfo.processInfo.environment
        guard let encoded = environment["CANOPY_UI_TEST_PDF_BASE64"],
              let data = Data(base64Encoded: encoded) else {
            return nil
        }
        let fixtureDirectory = directoryURL.appendingPathComponent("Fixtures", isDirectory: true)
        let fixtureURL = fixtureDirectory.appendingPathComponent("Canopy UI Journey.pdf")
        do {
            try FileManager.default.createDirectory(
                at: fixtureDirectory,
                withIntermediateDirectories: true
            )
            try data.write(to: fixtureURL, options: .atomic)
            return fixtureURL
        } catch {
            return nil
        }
    }

    private init(identifier: UUID, resetsBeforeOpening: Bool, cleansBeforeOpening: Bool) {
        directoryURL = URL.applicationSupportDirectory
            .appendingPathComponent("CanopyUITests", isDirectory: true)
            .appendingPathComponent(identifier.uuidString, isDirectory: true)
        storeURL = directoryURL.appendingPathComponent("CanopyWorkspaceV1.store")
        self.resetsBeforeOpening = resetsBeforeOpening
        self.cleansBeforeOpening = cleansBeforeOpening
    }
}
#endif
