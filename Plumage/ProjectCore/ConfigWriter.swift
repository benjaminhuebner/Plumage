import Foundation

nonisolated enum ConfigWriter {
    enum WriteError: Error, Equatable, Sendable {
        case bundleMissing(URL)
        case readFailed(message: String)
        case rootNotObject
        case encodeFailed(message: String)
        case writeFailed(message: String)
    }

    // Known top-level keys ConfigWriter owns. Anything else on disk
    // (plumageManaged, paths, agentTimeouts, minPlumageVersion, projectType,
    // createdAt, createdWithPlumageVersion, …) is preserved bit-exact across
    // a write/decode/write round-trip.
    static let knownKeys: Set<String> = [
        "name", "schemaVersion", "issueIdPadding", "git", "workflows", "models",
    ]

    // Top-level keys whose sub-trees may contain unknown sibling fields that
    // ConfigWriter should preserve. `git` carries third-party config keys
    // (`branchPrefix`, `agentFilesInGit`, …) that ProjectConfig.GitConfig
    // doesn't model; `workflows`/`models` are fully Plumage-owned so we overwrite
    // them wholesale to honor nil-means-remove semantics for sub-fields.
    static let deepMergeKeys: Set<String> = ["git"]

    static func write(_ config: ProjectConfig, atBundle bundle: URL) throws {
        let configURL = bundle.appendingPathComponent(ConfigLoader.configFileName)
        let fm = FileManager.default
        guard fm.fileExists(atPath: bundle.path) else {
            throw WriteError.bundleMissing(bundle)
        }

        // Read the on-disk JSON as a generic dictionary first so unknown keys
        // survive. If the file doesn't exist or is empty, start from an empty
        // dictionary — the encode-known step below produces a valid config.
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

        // Encode the known portion of ProjectConfig and overwrite only those
        // keys in rootObject. Nil fields drop out by virtue of JSONEncoder's
        // default behavior (synthesized Codable skips nil for optionals).
        let encoded: Data
        do {
            encoded = try JSONEncoder().encode(config)
        } catch {
            throw WriteError.encodeFailed(message: error.localizedDescription)
        }
        let knownObject: Any
        do {
            knownObject = try JSONSerialization.jsonObject(with: encoded)
        } catch {
            throw WriteError.encodeFailed(message: error.localizedDescription)
        }
        guard let knownDict = knownObject as? [String: Any] else {
            throw WriteError.encodeFailed(message: "encoded config is not an object")
        }

        // Two-phase merge: first delete known keys that no longer have a value
        // (config.workflows == nil should remove the workflows section from
        // disk rather than leaving the previous value behind), then overlay
        // the keys present in the encoded form — deep-merging for object
        // values so unknown nested keys (e.g. `git.branchPrefix`) survive.
        for key in knownKeys where knownDict[key] == nil {
            rootObject.removeValue(forKey: key)
        }
        for (key, value) in knownDict {
            if deepMergeKeys.contains(key),
                let existing = rootObject[key] as? [String: Any],
                let new = value as? [String: Any]
            {
                rootObject[key] = deepMerge(existing: existing, overlay: new)
            } else {
                rootObject[key] = value
            }
        }

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

    private static func deepMerge(
        existing: [String: Any], overlay: [String: Any]
    ) -> [String: Any] {
        var result = existing
        for (key, value) in overlay {
            if let existingValue = result[key] as? [String: Any],
                let newValue = value as? [String: Any]
            {
                result[key] = deepMerge(existing: existingValue, overlay: newValue)
            } else {
                result[key] = value
            }
        }
        return result
    }
}
