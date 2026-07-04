import Foundation

nonisolated enum ConfigWriter {
    enum WriteError: Error, Equatable, Sendable {
        case bundleMissing(URL)
        case readFailed(message: String)
        case rootNotObject
        case encodeFailed(message: String)
        case writeFailed(message: String)
    }

    static func write(_ config: ProjectConfig, atBundle bundle: URL) throws {
        // Read the on-disk JSON as a generic dictionary first so every key
        // outside the writable subsections survives untouched.
        let configURL = try guardedConfigURL(atBundle: bundle)
        var rootObject = try readRootObject(at: configURL)

        // Encode only the writable subsections and overlay them onto disk.
        // workflows/models are fully Plumage-owned: a nil section removes the
        // key from disk; a present section overwrites the on-disk value
        // wholesale (no sub-field deep-merge, since unknown sub-fields under
        // `models`/`workflows` are explicitly out of contract).
        try overlay(key: "workflows", value: config.workflows, into: &rootObject)
        try overlay(key: "models", value: config.models, into: &rootObject)
        try overlay(key: "efforts", value: config.efforts, into: &rootObject)

        // `git` is different: only `defaultBranch` is app-writable, so deep-merge
        // just that sub-key and leave sibling keys (agentFilesInGit, branchPrefix,
        // githubAccountID, any unmodeled ones) exactly as they sit on disk.
        mergeGitDefaultBranch(config.git?.defaultBranch, into: &rootObject)

        try writeRootObject(rootObject, to: configURL)
    }

    private static func mergeGitDefaultBranch(
        _ defaultBranch: String?, into root: inout [String: Any]
    ) {
        guard let defaultBranch else { return }
        var git = root["git"] as? [String: Any] ?? [:]
        git["defaultBranch"] = defaultBranch
        root["git"] = git
    }

    // Persists the display `name` only. The debounced settings auto-save must
    // never touch `name` — a rename moves the bundle folder too, which only
    // ProjectRenamer coordinates.
    static func writeName(_ name: String, atBundle bundle: URL) throws {
        let configURL = try guardedConfigURL(atBundle: bundle)
        var rootObject = try readRootObject(at: configURL)
        rootObject["name"] = name
        try writeRootObject(rootObject, to: configURL)
    }

    private static func guardedConfigURL(atBundle bundle: URL) throws -> URL {
        guard FileManager.default.fileExists(atPath: bundle.path) else {
            throw WriteError.bundleMissing(bundle)
        }
        return bundle.appendingPathComponent(ConfigLoader.configFileName)
    }

    // Loads config.json as a generic dictionary. A missing or empty file
    // starts from an empty dictionary so the caller's overlay still produces a
    // valid file.
    private static func readRootObject(at configURL: URL) throws -> [String: Any] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: configURL.path) else { return [:] }
        let existing: Data
        do {
            existing = try Data(contentsOf: configURL)
        } catch {
            throw WriteError.readFailed(message: error.localizedDescription)
        }
        if existing.isEmpty { return [:] }
        let parsed: Any
        do {
            parsed = try JSONSerialization.jsonObject(with: existing)
        } catch {
            throw WriteError.readFailed(message: error.localizedDescription)
        }
        guard let dict = parsed as? [String: Any] else {
            throw WriteError.rootNotObject
        }
        return dict
    }

    // Pretty-print so the on-disk file stays human-readable; sortedKeys keeps
    // diffs stable across writes that touch the same logical state.
    private static func writeRootObject(_ rootObject: [String: Any], to configURL: URL) throws {
        let outData: Data
        do {
            outData = try JSONSerialization.data(
                withJSONObject: rootObject,
                options: [.prettyPrinted, .sortedKeys]
            )
        } catch {
            throw WriteError.encodeFailed(message: error.localizedDescription)
        }
        do {
            try outData.write(to: configURL, options: [.atomic])
        } catch {
            throw WriteError.writeFailed(message: error.localizedDescription)
        }
    }

    private static func overlay<T: Encodable>(
        key: String, value: T?, into root: inout [String: Any]
    ) throws {
        guard let value else {
            root.removeValue(forKey: key)
            return
        }
        let encoded: Data
        do {
            encoded = try JSONEncoder().encode(value)
        } catch {
            throw WriteError.encodeFailed(message: error.localizedDescription)
        }
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: encoded)
        } catch {
            throw WriteError.encodeFailed(message: error.localizedDescription)
        }
        root[key] = object
    }
}
