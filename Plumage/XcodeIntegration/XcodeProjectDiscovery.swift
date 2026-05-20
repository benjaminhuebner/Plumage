import Foundation

nonisolated struct XcodeProjectRef: Sendable, Equatable {
    let url: URL
    let kind: Kind

    enum Kind: Sendable, Equatable {
        case workspace
        case project
    }

    var listFlag: String {
        switch kind {
        case .workspace: return "-workspace"
        case .project: return "-project"
        }
    }

    var displayName: String { url.lastPathComponent }
}

nonisolated enum XcodeProjectDiscovery {
    static func find(in directory: URL) -> XcodeProjectRef? {
        let contents =
            (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles])) ?? []
        let workspaces =
            contents
            .filter { $0.pathExtension == "xcworkspace" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        if let ws = workspaces.first {
            return XcodeProjectRef(url: ws, kind: .workspace)
        }
        let projects =
            contents
            .filter { $0.pathExtension == "xcodeproj" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        if let proj = projects.first {
            return XcodeProjectRef(url: proj, kind: .project)
        }
        return nil
    }

    static func findAll(in directory: URL) -> [XcodeProjectRef] {
        let contents =
            (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles])) ?? []
        let workspaces =
            contents
            .filter { $0.pathExtension == "xcworkspace" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { XcodeProjectRef(url: $0, kind: .workspace) }
        let projects =
            contents
            .filter { $0.pathExtension == "xcodeproj" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { XcodeProjectRef(url: $0, kind: .project) }
        return workspaces + projects
    }
}
