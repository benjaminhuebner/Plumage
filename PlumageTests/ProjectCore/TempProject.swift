import Foundation

enum TempProject {
    static func make(content: String?) throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlumageTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        if let content {
            let bundle = base.appendingPathComponent("Test.plumage", isDirectory: true)
            try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
            let configURL = bundle.appendingPathComponent("config.json")
            try content.write(to: configURL, atomically: true, encoding: .utf8)
        }
        return base
    }
}
