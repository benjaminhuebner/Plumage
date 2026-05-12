import Foundation

enum TempProject {
    static func make(content: String?) throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlumageTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        if let content {
            let plumage = base.appendingPathComponent(".plumage", isDirectory: true)
            try FileManager.default.createDirectory(at: plumage, withIntermediateDirectories: true)
            let configURL = plumage.appendingPathComponent("config.json")
            try content.write(to: configURL, atomically: true, encoding: .utf8)
        }
        return base
    }
}
