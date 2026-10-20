import Foundation
import Testing
@testable import Voltio

/// Verifies the custom alert-sound library: imported files are copied into the
/// app container, bounded in size, and paths outside the library can never be
/// deleted through it.
///
/// This is the fix for the sandbox bug where a bare `NSOpenPanel` path stopped
/// being readable after relaunch (`exists = true`, `readable = false`).
@Suite("Alert sound library")
struct AlertSoundLibraryTests {

    /// A throwaway source file outside the library, mimicking a user-picked
    /// sound on the Desktop.
    private func makeSourceFile(bytes: Int = 64) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voltio-sound-\(UUID().uuidString).aiff")
        try Data(repeating: 0, count: bytes).write(to: url)
        return url
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    @Test("Import copies the file into the library and it stays readable")
    func importCopiesFile() throws {
        let source = try makeSourceFile()
        defer { cleanup(source) }

        guard case .imported(let path) = AlertSoundLibrary.importSound(from: source) else {
            Issue.record("Expected a successful import")
            return
        }
        defer { AlertSoundLibrary.removeSound(at: path) }

        #expect(AlertSoundLibrary.isInLibrary(path))
        #expect(path != source.path)
        #expect(AlertSoundLibrary.isAvailable(path))
        // The original may be deleted afterwards — the alert keeps working
        // because we own a copy.
        cleanup(source)
        #expect(AlertSoundLibrary.isAvailable(path))
    }

    @Test("Imported files keep their extension so NSSound can decode them")
    func importPreservesExtension() throws {
        let source = try makeSourceFile()
        defer { cleanup(source) }

        guard case .imported(let path) = AlertSoundLibrary.importSound(from: source) else {
            Issue.record("Expected a successful import")
            return
        }
        defer { AlertSoundLibrary.removeSound(at: path) }

        #expect(URL(fileURLWithPath: path).pathExtension == "aiff")
    }

    @Test("Two imports of the same name never collide")
    func importDoesNotCollide() throws {
        let first = try makeSourceFile()
        let second = try makeSourceFile()
        defer { cleanup(first); cleanup(second) }

        guard case .imported(let pathA) = AlertSoundLibrary.importSound(from: first),
              case .imported(let pathB) = AlertSoundLibrary.importSound(from: second)
        else {
            Issue.record("Expected both imports to succeed")
            return
        }
        defer {
            AlertSoundLibrary.removeSound(at: pathA)
            AlertSoundLibrary.removeSound(at: pathB)
        }

        #expect(pathA != pathB)
    }

    @Test("Oversized files are rejected instead of copied")
    func oversizedFileRejected() throws {
        let source = try makeSourceFile(bytes: AlertSoundLibrary.maxImportBytes + 1)
        defer { cleanup(source) }

        guard case .tooLarge(let bytes) = AlertSoundLibrary.importSound(from: source) else {
            Issue.record("Expected the import to be refused")
            return
        }
        #expect(bytes > AlertSoundLibrary.maxImportBytes)
    }

    @Test("removeSound refuses paths outside the library")
    func removeRejectsOutsidePaths() throws {
        // A file the user picked elsewhere must never be deleted by us.
        let outsider = try makeSourceFile()
        defer { cleanup(outsider) }

        AlertSoundLibrary.removeSound(at: outsider.path)
        #expect(FileManager.default.fileExists(atPath: outsider.path))
    }

    @Test("Custom sounds report availability; presets always do")
    func availabilityReporting() throws {
        let missing = AlertSoundLibrary.directory
            .appendingPathComponent("does-not-exist.aiff")
            .path
        #expect(AlertSound.custom(missing).isAvailable == false)
        #expect(AlertSound.system("Glass").isAvailable)
        #expect(AlertSound.none.isAvailable)
    }
}
