import Foundation

nonisolated enum ConfigLoader {
    enum LoadError: Error, Equatable, Sendable {
        case noConfigFile(folder: URL)
        case schemaTooNew(version: Int, supportedUpTo: Int)
        case invalidJSON(message: String)
    }

    static let configRelativePath = ".plumage/config.json"

    static func load(at folder: URL) throws -> ProjectConfig {
        let configURL = folder.appendingPathComponent(configRelativePath)
        let fm = FileManager.default
        guard fm.fileExists(atPath: configURL.path) else {
            throw LoadError.noConfigFile(folder: folder)
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
        return config
    }

    private static func describe(_ error: Error) -> String {
        if let decoding = error as? DecodingError {
            switch decoding {
            case .keyNotFound(let key, _):
                return "missing field '\(key.stringValue)'"
            case .typeMismatch(_, let ctx):
                return "type mismatch at \(Self.pathString(ctx.codingPath)): \(ctx.debugDescription)"
            case .valueNotFound(_, let ctx):
                return "missing value at \(Self.pathString(ctx.codingPath))"
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
