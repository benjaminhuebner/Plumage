import Foundation

nonisolated enum ConfigWriter {
    enum WriteError: Error, Equatable, Sendable {
        case bundleMissing(URL)
        case readFailed(message: String)
        case rootNotObject
        case encodeFailed(message: String)
        case writeFailed(message: String)
    }

    // Top-level keys ConfigWriter is allowed to touch. Everything else on
    // disk (name, schemaVersion, issueIdPadding, git, plumageManaged, paths,
    // agentTimeouts, minPlumageVersion, projectType, createdAt, …) is
    // preserved bit-exact — including external edits to keys like
    // `git.defaultBranch` that arrived between load and save.
    static let writableKeys: Set<String> = ["workflows", "models"]

    static func write(_ config: ProjectConfig, atBundle bundle: URL) throws {
        let configURL = bundle.appendingPathComponent(ConfigLoader.configFileName)
        let fm = FileManager.default
        guard fm.fileExists(atPath: bundle.path) else {
            throw WriteError.bundleMissing(bundle)
        }

        // Read the on-disk JSON as a generic dictionary first so every key
        // outside `writableKeys` survives untouched. If the file doesn't
        // exist or is empty, start from an empty dictionary.
        var rootObject: [String: Any]
        if fm.fileExists(atPath: configURL.path) {
            let existing: Data
            do {
                existing = try Data(contentsOf: configURL)
            } catch {
                throw WriteError.readFailed(message: error.localizedDescription)
            }
            if existing.isEmpty {
                rootObject = [:]
            } else {
                let parsed: Any
                do {
                    parsed = try JSONSerialization.jsonObject(with: existing)
                } catch {
                    throw WriteError.readFailed(message: error.localizedDescription)
                }
                guard let dict = parsed as? [String: Any] else {
                    throw WriteError.rootNotObject
                }
                rootObject = dict
            }
        } else {
            rootObject = [:]
        }

        // Encode only the writable subsections and overlay them onto disk.
        // workflows/models are fully Plumage-owned: a nil section removes the
        // key from disk; a present section overwrites the on-disk value
        // wholesale (no sub-field deep-merge, since unknown sub-fields under
        // `models`/`workflows` are explicitly out of contract).
        try overlay(key: "workflows", value: config.workflows, into: &rootObject)
        try overlay(key: "models", value: config.models, into: &rootObject)

        // Pretty-print so the on-disk file stays human-readable; sortedKeys
        // keeps diffs stable across writes that touch the same logical state.
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
