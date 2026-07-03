import Foundation

nonisolated enum ConfigLoader {
    enum LoadError: LocalizedError, Equatable, Sendable {
        case noConfigFile(folder: URL)
        case noBundle(folder: URL)
        case multipleBundles(found: [URL])
        case schemaTooNew(version: Int, supportedUpTo: Int)
        case invalidJSON(message: String)

        var errorDescription: String? {
            switch self {
            case .noConfigFile(let bundle):
                return "Plumage bundle at \(bundle.path) has no config.json."
            case .noBundle(let folder):
                return "No .plumage bundle found at \(folder.path)."
            case .multipleBundles(let urls):
                let names = urls.map { $0.lastPathComponent }.joined(separator: ", ")
                return "Multiple Plumage bundles found: \(names). Expected exactly one."
            case .schemaTooNew(let version, let supportedUpTo):
                return "This project needs a newer Plumage "
                    + "(config schemaVersion \(version), this build supports up to \(supportedUpTo))."
            case .invalidJSON(let message):
                return "This Plumage config is invalid: \(message)"
            }
        }
    }

    static let configFileName = "config.json"

    static func load(at projectRoot: URL) throws -> ProjectConfig {
        let bundle: URL
        do {
            bundle = try BundleResolver.findBundle(in: projectRoot)
        } catch BundleResolver.ResolveError.noBundle(let folder) {
            throw LoadError.noBundle(folder: folder)
        } catch BundleResolver.ResolveError.multipleBundles(let urls) {
            throw LoadError.multipleBundles(found: urls)
        }
        return try load(atBundle: bundle)
    }

    static func load(atBundle bundle: URL) throws -> ProjectConfig {
        let configURL = bundle.appendingPathComponent(configFileName)
        let fm = FileManager.default
        guard fm.fileExists(atPath: configURL.path) else {
            throw LoadError.noConfigFile(folder: bundle)
        }
        let data: Data
        do {
            data = try Data(contentsOf: configURL)
        } catch {
            throw LoadError.invalidJSON(message: error.localizedDescription)
        }
        let config: ProjectConfig
        do {
            config = try JSONDecoder().decode(ProjectConfig.self, from: data)
        } catch {
            throw LoadError.invalidJSON(message: Self.describe(error))
        }
        if config.schemaVersion > SchemaVersion.current {
            throw LoadError.schemaTooNew(
                version: config.schemaVersion,
                supportedUpTo: SchemaVersion.current
            )
        }
        if let padding = config.issueIdPadding, padding < 1 {
            throw LoadError.invalidJSON(message: "issueIdPadding must be >= 1, got \(padding)")
        }
        // git.defaultBranch is deliberately not validated here: the git
        // runners guard with GitBranchName.isSafe at use, and failing the
        // load would make the whole project unopenable with no in-app fix.
        return config
    }

    private static func describe(_ error: Error) -> String {
        if let decoding = error as? DecodingError {
            switch decoding {
            case .keyNotFound(let key, let ctx):
                return "missing field '\(pathString(ctx.codingPath + [key]))'"
            case .typeMismatch(_, let ctx):
                return "type mismatch at \(pathString(ctx.codingPath)): \(ctx.debugDescription)"
            case .valueNotFound(_, let ctx):
                return "missing value at \(pathString(ctx.codingPath))"
            case .dataCorrupted(let ctx):
                return "malformed JSON: \(ctx.debugDescription)"
            @unknown default:
                return decoding.localizedDescription
            }
        }
        return error.localizedDescription
    }

    private static func pathString(_ path: [CodingKey]) -> String {
        let parts = path.map { $0.stringValue }
        return parts.isEmpty ? "root" : parts.joined(separator: ".")
    }
}
