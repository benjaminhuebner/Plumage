import Foundation

nonisolated struct XcodebuildListing: Sendable, Equatable {
    let projectName: String
    let schemes: [String]
}

nonisolated struct XcodebuildRunner: Sendable {
    let runner: any XcodeProcessRunning
    let toolchain: @Sendable () -> URL?

    init(
        runner: any XcodeProcessRunning = ProductionXcodeProcessRunner(),
        toolchain: @escaping @Sendable () -> URL? = { ToolchainLocator.xcodebuild() }
    ) {
        self.runner = runner
        self.toolchain = toolchain
    }

    func listSchemes(at project: XcodeProjectRef) async throws -> XcodebuildListing {
        guard let binary = toolchain() else { throw XcodeProcessRunnerError.toolchainNotFound }
        let args = [project.listFlag, project.url.path, "-list", "-json"]
        let result = try await runner.run(binaryURL: binary, args: args, cwd: nil)
        guard result.exitCode == 0 else {
            let stderr = String(decoding: result.stderr, as: UTF8.self)
            throw XcodeProcessRunnerError.nonZeroExit(code: result.exitCode, stderr: stderr)
        }
        return try Self.parseListing(data: result.stdout)
    }

    static func parseListing(data: Data) throws -> XcodebuildListing {
        let decoder = JSONDecoder()
        do {
            let envelope = try decoder.decode(ListEnvelope.self, from: data)
            if let project = envelope.project {
                return XcodebuildListing(projectName: project.name, schemes: project.schemes)
            }
            if let workspace = envelope.workspace {
                return XcodebuildListing(projectName: workspace.name, schemes: workspace.schemes)
            }
            throw XcodeProcessRunnerError.parseError(
                "no `project` or `workspace` key in xcodebuild -list -json output")
        } catch let error as XcodeProcessRunnerError {
            throw error
        } catch {
            throw XcodeProcessRunnerError.parseError(error.localizedDescription)
        }
    }

    private struct ListEnvelope: Decodable {
        let project: ProjectBody?
        let workspace: WorkspaceBody?
    }

    private struct ProjectBody: Decodable {
        let name: String
        let schemes: [String]
    }

    private struct WorkspaceBody: Decodable {
        let name: String
        let schemes: [String]
    }
}
