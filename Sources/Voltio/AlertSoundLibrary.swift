import Foundation
import os

/// Copies user-imported alert sounds into the app's own container and returns
/// the stored path.
///
/// The app is sandboxed, so a path chosen through `NSOpenPanel` is only
/// readable for the lifetime of the Powerbox grant on that specific URL — a
/// bare path persisted in `UserDefaults` (`.custom(path)`) stops working after
/// relaunch. Verified directly: a sandboxed process can `stat` an outside file
/// (`exists = true`) but reading it returns `nil` (`readable = false`).
///
/// Copying into Application Support fixes this without any extra entitlement
/// and additionally keeps the alert working if the user later moves or deletes
/// the original file. Files are bounded in size on import, and the copy keeps
/// the original extension so `NSSound` can decode it.
enum AlertSoundLibrary {
    private static let logger = Logger(subsystem: "com.voltio.app", category: "AlertSoundLibrary")

    /// Imported sounds larger than this are rejected. Alert clips are expected
    /// to be short; the cap keeps a stray multi-hundred-MB file out of the
    /// container (and out of every settings export).
    static let maxImportBytes = 20 * 1024 * 1024

    /// Absolute paths of everything currently in the library. Anything stored
    /// as `.custom` but missing from this set predates the container copy and
    /// is treated as unavailable.
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Voltio/Sounds", isDirectory: true)
    }

    /// Outcome of an import attempt, so the caller can tell the user why an
    /// import was refused instead of silently storing a dead path.
    enum ImportResult: Equatable {
        case imported(path: String)
        case tooLarge(bytes: Int)
        case failed(String)
    }

    /// Copies `source` into the library and returns the stored file's path.
    ///
    /// The destination is named from a UUID plus the source extension, so
    /// importing two files with the same name never collides and the original
    /// filename never leaks into the container.
    static func importSound(from source: URL) -> ImportResult {
        let size = (try? FileManager.default.attributesOfItem(atPath: source.path))?[.size] as? Int
        if let size, size > maxImportBytes {
            return .tooLarge(bytes: size)
        }
        let directory = self.directory
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            logger.error("Could not create sound library directory: \(error.localizedDescription)")
            return .failed(error.localizedDescription)
        }
        let destination = directory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(source.pathExtension)
        do {
            try FileManager.default.copyItem(at: source, to: destination)
        } catch {
            logger.error("Could not import alert sound: \(error.localizedDescription)")
            return .failed(error.localizedDescription)
        }
        return .imported(path: destination.path)
    }

    /// Removes a stored sound. Best-effort: a missing file is not an error
    /// (the user may have cleared the container, or the entry predates the
    /// library).
    static func removeSound(at path: String) {
        guard isInLibrary(path) else { return }
        try? FileManager.default.removeItem(atPath: path)
    }

    /// True when `path` lives inside the sound library. Used to avoid deleting
    /// arbitrary files if a stored path was tampered with.
    static func isInLibrary(_ path: String) -> Bool {
        URL(fileURLWithPath: path)
            .standardizedFileURL
            .path
            .hasPrefix(directory.standardizedFileURL.path + "/")
    }

    /// Whether the file backing a `.custom` entry can still be read. Reports
    /// `false` for pre-container paths that no longer resolve.
    static func isAvailable(_ path: String) -> Bool {
        FileManager.default.isReadableFile(atPath: path)
    }
}
