import Foundation
import Testing

@testable import Plumage

struct WorktreeProvisionerTests {
    private func makeTmpDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorktreeProvisionerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func listerReturning(porcelain: String) -> GitWorktreeLister {
        let mock = MockGitProcessRunner()
        mock.stdoutForArgs = [["worktree", "list", "--porcelain"]: porcelain]
        return GitWorktreeLister(runner: mock, resolveBinary: { URL(filePath: "/usr/bin/git") })
    }

    @Test("missing bundled script throws scriptMissing")
    func missingScriptThrows() async throws {
        let root = try makeTmpDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let projectRoot = root.appending(component: "Proj", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        let missing = root.appending(component: "nope.sh")
        let provisioner = WorktreeProvisioner(
            runner: MockGitProcessRunner(),
            lister: listerReturning(porcelain: ""),
            scriptURL: missing
        )

        await #expect(throws: WorktreeProvisionError.scriptMissing(path: missing.path)) {
            _ = try await provisioner.provision(slug: "00042-x", projectRoot: projectRoot)
        }
    }

    @Test("script failure surfaces the script's stderr")
    func scriptFailureSurfacesStderr() async throws {
        let root = try makeTmpDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let projectRoot = root.appending(component: "Proj", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        let script = root.appending(component: "setup-worktree.sh")
        try "#!/bin/bash\n".write(to: script, atomically: true, encoding: .utf8)
        let mock = MockGitProcessRunner()
        let args = [script.path, "00042-x"]
        mock.exitCodeForArgs = [args: 1]
        mock.stderrForArgs = [args: "error: no issue folder matches '00042-x'\n"]
        let provisioner = WorktreeProvisioner(
            runner: mock,
            lister: listerReturning(porcelain: ""),
            scriptURL: script
        )

        await #expect(
            throws: WorktreeProvisionError.scriptFailed(
                message: "error: no issue folder matches '00042-x'")
        ) {
            _ = try await provisioner.provision(slug: "00042-x", projectRoot: projectRoot)
        }
    }

    @Test("occupied target that is not a worktree throws pathOccupied")
    func occupiedTargetThrows() async throws {
        let root = try makeTmpDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let projectRoot = root.appending(component: "Proj", directoryHint: .isDirectory)
        let target = root.appending(component: "Proj-00042-x", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let provisioner = WorktreeProvisioner(
            runner: MockGitProcessRunner(),
            lister: listerReturning(porcelain: "worktree \(projectRoot.path)\nbranch refs/heads/main"),
            scriptURL: root.appending(component: "irrelevant.sh")
        )

        await #expect(throws: WorktreeProvisionError.pathOccupied(path: target.path)) {
            _ = try await provisioner.provision(slug: "00042-x", projectRoot: projectRoot)
        }
    }

    @Test("existing worktree at the target is reused without running the script")
    func existingWorktreeIsReused() async throws {
        let root = try makeTmpDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let projectRoot = root.appending(component: "Proj", directoryHint: .isDirectory)
        let target = root.appending(component: "Proj-00042-x", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let scriptRunner = MockGitProcessRunner()
        let porcelain = "worktree \(projectRoot.path)\nbranch refs/heads/main\n\nworktree \(target.path)\ndetached"
        let provisioner = WorktreeProvisioner(
            runner: scriptRunner,
            lister: listerReturning(porcelain: porcelain),
            scriptURL: root.appending(component: "irrelevant.sh")
        )

        let result = try await provisioner.provision(slug: "00042-x", projectRoot: projectRoot)

        #expect(result.reusedExisting)
        #expect(Self.sameLocation(result.worktreeRoot, target))
        #expect(scriptRunner.recordedCalls.isEmpty)
    }

    @Test(
        "bundled script provisions a real worktree, second call reuses it",
        .tags(.integration),
        .enabled(if: ToolchainLocator.git() != nil)
    )
    func provisionsRealWorktree() async throws {
        let repo = try await TmpGitRepo.make()
        let binary = try #require(ToolchainLocator.git())
        let runner = ProductionGitProcessRunner()
        // TmpGitRepo leaves the issue branch checked out; the script refuses a
        // slug whose branch is checked out anywhere.
        let checkout = try await runner.run(
            binaryURL: binary, args: ["checkout", repo.mainBranch], cwd: repo.tmpDir)
        try #require(checkout.exitCode == 0)
        let bundleDir = repo.tmpDir.appending(component: "Test.plumage", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: bundleDir, withIntermediateDirectories: true)
        try #"{"git": {"defaultBranch": "main"}}"#.write(
            to: bundleDir.appending(component: "config.json"), atomically: true, encoding: .utf8)
        let target = WorktreeProvisioner.expectedWorktreeRoot(
            projectRoot: repo.tmpDir, slug: repo.folderName)
        defer { try? FileManager.default.removeItem(at: target) }

        let provisioner = WorktreeProvisioner()
        let first = try await provisioner.provision(slug: repo.folderName, projectRoot: repo.tmpDir)

        #expect(first.reusedExisting == false)
        #expect(FileManager.default.fileExists(atPath: target.appending(component: ".git").path))
        #expect(
            FileManager.default.fileExists(
                atPath: target.appending(component: "Test.plumage/config.json").path))

        let second = try await provisioner.provision(slug: repo.folderName, projectRoot: repo.tmpDir)
        #expect(second.reusedExisting)
    }

    private static func sameLocation(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.resolvingSymlinksInPath().standardizedFileURL.path
            == rhs.resolvingSymlinksInPath().standardizedFileURL.path
    }
}
