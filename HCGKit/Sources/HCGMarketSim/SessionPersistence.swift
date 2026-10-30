import Foundation
import HCGTrading

/// On-disk form of a saved simulated session (markets + account).
public struct SessionFile: Codable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let accountSchemaVersion: Int
    /// Wall-clock time of the save (informational only; never fed to the simulation).
    public let savedAt: Date
    public let state: SimulationState
}

public enum SessionLoadResult: Sendable {
    /// No saved session: start fresh.
    case fresh
    case restored(SimulationState, savedAt: Date)
    /// The file could not be read; it was moved aside (never deleted) and a
    /// fresh session starts.
    case recovered(backupURL: URL?, reason: String)
}

/// Saves and loads the simulated session as JSON in a directory inside the
/// app's sandbox container. Local only; nothing is uploaded.
public struct SessionPersistence: Sendable {
    public let fileURL: URL

    public init(directory: URL, fileName: String = "session.json") {
        self.fileURL = directory.appendingPathComponent(fileName)
    }

    /// `~/Library/Application Support/<folder>` (inside the sandbox container
    /// when the app is sandboxed).
    public static func applicationSupportDirectory(folder: String = "HCGOneUnleashed") -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent(folder, isDirectory: true)
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    public func load() -> SessionLoadResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .fresh }
        do {
            let data = try Data(contentsOf: fileURL)
            let file = try Self.decoder.decode(SessionFile.self, from: data)
            guard file.schemaVersion <= SessionFile.currentSchemaVersion,
                  file.accountSchemaVersion <= TradingAccount.schemaVersion else {
                return .recovered(backupURL: moveAside(), reason: "The saved session was written by a newer version of the app.")
            }
            return .restored(file.state, savedAt: file.savedAt)
        } catch {
            return .recovered(backupURL: moveAside(), reason: "The saved session could not be read (\(error.localizedDescription)).")
        }
    }

    /// Writes atomically, creating the directory if needed.
    public func save(_ state: SimulationState, savedAt: Date) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let file = SessionFile(schemaVersion: SessionFile.currentSchemaVersion,
                               accountSchemaVersion: TradingAccount.schemaVersion,
                               savedAt: savedAt, state: state)
        let data = try Self.encoder.encode(file)
        try data.write(to: fileURL, options: [.atomic])
    }

    public func delete() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Renames an unreadable file to `<name>.unreadable-<timestamp>.json`.
    private func moveAside() -> URL? {
        let stamp = Int(Date().timeIntervalSince1970)
        let backup = fileURL.deletingPathExtension().appendingPathExtension("unreadable-\(stamp).json")
        do {
            try FileManager.default.moveItem(at: fileURL, to: backup)
            return backup
        } catch {
            return nil
        }
    }
}

/// Performs saves off the main actor.
actor SessionWriter {
    private let persistence: SessionPersistence

    init(persistence: SessionPersistence) {
        self.persistence = persistence
    }

    func save(_ state: SimulationState, savedAt: Date) throws {
        try persistence.save(state, savedAt: savedAt)
    }
}
