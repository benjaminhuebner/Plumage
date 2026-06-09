import Dispatch
import Foundation
import Testing

@testable import Plumage

@Suite("ProjectKanbanModel.applyOptimisticArchive")
@MainActor
struct OptimisticArchiveTests {
    @Test("removes the card before the archiver returns and clears error")
    func successPathRemovesCard() async throws {
        let model = ProjectKanbanModel(
            archiver: { _, _ in URL(filePath: "/tmp/archive/00001-a") }
        )
        let issueA = OptimisticDropTests.makeIssue(id: 1, folder: "00001-a", status: .approved)
        let issueB = OptimisticDropTests.makeIssue(id: 2, folder: "00002-b", status: .approved)
        model._setIssuesForTesting([.valid(issueA), .valid(issueB)])

        await model.performArchiveOptimistic(
            folderName: "00001-a", projectURL: URL(filePath: "/tmp/probe"))

        #expect(model.issues.count == 1)
        #expect(model.issues.first?.id == "00002-b")
        #expect(model.lastRemovalError == nil)
    }

    @Test("archiver throw rolls back removal and records error")
    func failurePathRolledBack() async throws {
        struct DummyError: Error, LocalizedError {
            var errorDescription: String? { "volume read-only" }
        }
        let model = ProjectKanbanModel(
            archiver: { _, _ in throw DummyError() }
        )
        let issueA = OptimisticDropTests.makeIssue(id: 1, folder: "00001-a", status: .approved)
        model._setIssuesForTesting([.valid(issueA)])

        await model.performArchiveOptimistic(
            folderName: "00001-a", projectURL: URL(filePath: "/tmp/probe"))

        #expect(model.issues.count == 1)
        #expect(model.issues.first?.id == "00001-a")
        #expect(model.lastRemovalError == "volume read-only")
    }

    @Test("unknown folder is a noop and never invokes the archiver")
    func unknownFolderIsNoop() async {
        let captured = LockedBox<Int>(value: 0)
        let model = ProjectKanbanModel(
            archiver: { _, _ in
                captured.mutate { $0 += 1 }
                return URL(filePath: "/tmp/archive/x")
            }
        )
        let issueA = OptimisticDropTests.makeIssue(id: 1, folder: "00001-a", status: .approved)
        model._setIssuesForTesting([.valid(issueA)])

        await model.performArchiveOptimistic(
            folderName: "00099-missing", projectURL: URL(filePath: "/tmp/probe"))

        #expect(captured.value == 0)
        #expect(model.issues.count == 1)
        #expect(model.lastRemovalError == nil)
    }

    @Test("invalid issues are archivable too")
    func invalidIssueArchivable() async throws {
        let model = ProjectKanbanModel(
            archiver: { _, _ in URL(filePath: "/tmp/archive/00007-broken") }
        )
        let invalid: DiscoveredIssue = .invalid(
            folder: URL(filePath: "/tmp/.claude/issues/00007-broken"),
            error: .invalidEnumValue(field: "status", value: "??")
        )
        model._setIssuesForTesting([invalid])

        await model.performArchiveOptimistic(
            folderName: "00007-broken", projectURL: URL(filePath: "/tmp"))

        #expect(model.issues.isEmpty)
        #expect(model.lastRemovalError == nil)
    }

    @Test("success path sets lastRemovalCompleted to the folder name")
    func successSetsRemovalCompleted() async {
        let model = ProjectKanbanModel(
            archiver: { _, _ in URL(filePath: "/tmp/archive/00001-a") }
        )
        let issueA = OptimisticDropTests.makeIssue(id: 1, folder: "00001-a", status: .approved)
        model._setIssuesForTesting([.valid(issueA)])

        await model.performArchiveOptimistic(
            folderName: "00001-a", projectURL: URL(filePath: "/tmp/probe"))

        #expect(model.lastRemovalCompleted == "00001-a")
    }

    @Test("failure path does not set lastRemovalCompleted")
    func failureDoesNotSetCompleted() async {
        struct DummyError: Error {}
        let model = ProjectKanbanModel(archiver: { _, _ in throw DummyError() })
        let issueA = OptimisticDropTests.makeIssue(id: 1, folder: "00001-a", status: .approved)
        model._setIssuesForTesting([.valid(issueA)])

        await model.performArchiveOptimistic(
            folderName: "00001-a", projectURL: URL(filePath: "/tmp/probe"))

        #expect(model.lastRemovalCompleted == nil)
    }

    @Test("failed removal restores only its own card, not the whole prior snapshot")
    func failedRemovalRestoresOnlyOwnCard() async throws {
        struct DummyError: Error, LocalizedError {
            var errorDescription: String? { "boom" }
        }
        let model = ProjectKanbanModel(archiver: { _, _ in throw DummyError() })
        let issueA = OptimisticDropTests.makeIssue(id: 1, folder: "00001-a", status: .approved)
        let issueB = OptimisticDropTests.makeIssue(id: 2, folder: "00002-b", status: .approved)
        model._setIssuesForTesting([.valid(issueA), .valid(issueB)])
        let projectURL = URL(filePath: "/tmp/probe")

        model.applyOptimisticArchive(folderName: "00001-a", projectURL: projectURL)
        // Another card moves while the failing archive is in flight; the
        // rollback must not clobber its newer state with the prior snapshot.
        let issueBMoved = OptimisticDropTests.makeIssue(id: 2, folder: "00002-b", status: .done)
        model._setIssuesForTesting([.valid(issueBMoved)])
        await model.performArchiveOptimistic(folderName: "00001-a", projectURL: projectURL)

        #expect(model.issues.contains { $0.id == "00001-a" })
        let cardB = try #require(model.issues.first { $0.id == "00002-b" })
        guard case .valid(let restoredB) = cardB else {
            Issue.record("expected .valid card for 00002-b, got \(cardB)")
            return
        }
        #expect(restoredB.status == .done)
        #expect(model.lastRemovalError == "boom")
    }

    @Test("rollback after a single removal does not stick lastRemovalError across a clear")
    func errorClearsAfterClearRemovalError() async {
        struct DummyError: Error, LocalizedError {
            var errorDescription: String? { "boom" }
        }
        let model = ProjectKanbanModel(archiver: { _, _ in throw DummyError() })
        let issueA = OptimisticDropTests.makeIssue(id: 1, folder: "00001-a", status: .approved)
        model._setIssuesForTesting([.valid(issueA)])

        await model.performArchiveOptimistic(
            folderName: "00001-a", projectURL: URL(filePath: "/tmp/probe"))
        #expect(model.lastRemovalError == "boom")
        model.clearRemovalError()
        #expect(model.lastRemovalError == nil)
    }

    @Test("archiver receives folder URL + archive root derived from projectURL")
    func archiverReceivesExpectedURLs() async throws {
        let receivedFolder = LockedBox<URL?>(value: nil)
        let receivedRoot = LockedBox<URL?>(value: nil)
        let model = ProjectKanbanModel(
            archiver: { folderURL, archiveRoot in
                receivedFolder.mutate { $0 = folderURL }
                receivedRoot.mutate { $0 = archiveRoot }
                return folderURL
            }
        )
        let issueA = OptimisticDropTests.makeIssue(id: 1, folder: "00001-a", status: .approved)
        model._setIssuesForTesting([.valid(issueA)])
        let projectURL = URL(filePath: "/tmp/probe")

        await model.performArchiveOptimistic(folderName: "00001-a", projectURL: projectURL)

        let folder = try #require(receivedFolder.value)
        let root = try #require(receivedRoot.value)
        #expect(folder.path.hasSuffix(".claude/issues/00001-a"))
        #expect(root.path.hasSuffix(".claude/issues/archive"))
    }
}

@Suite("ProjectKanbanModel.applyOptimisticTrash")
@MainActor
struct OptimisticTrashTests {
    @Test("removes the card before the trasher returns")
    func successPathRemovesCard() async throws {
        let model = ProjectKanbanModel(
            trasher: { _ in URL(filePath: "/Users/me/.Trash/00001-a") }
        )
        let issueA = OptimisticDropTests.makeIssue(id: 1, folder: "00001-a", status: .approved)
        let issueB = OptimisticDropTests.makeIssue(id: 2, folder: "00002-b", status: .approved)
        model._setIssuesForTesting([.valid(issueA), .valid(issueB)])

        await model.performTrashOptimistic(
            folderName: "00001-a", projectURL: URL(filePath: "/tmp/probe"))

        #expect(model.issues.count == 1)
        #expect(model.issues.first?.id == "00002-b")
        #expect(model.lastRemovalError == nil)
    }

    @Test("trasher throw rolls back removal and records error")
    func failurePathRolledBack() async throws {
        struct DummyError: Error, LocalizedError {
            var errorDescription: String? { "no trash on this volume" }
        }
        let model = ProjectKanbanModel(trasher: { _ in throw DummyError() })
        let issueA = OptimisticDropTests.makeIssue(id: 1, folder: "00001-a", status: .approved)
        model._setIssuesForTesting([.valid(issueA)])

        await model.performTrashOptimistic(
            folderName: "00001-a", projectURL: URL(filePath: "/tmp/probe"))

        #expect(model.issues.count == 1)
        #expect(model.issues.first?.id == "00001-a")
        #expect(model.lastRemovalError == "no trash on this volume")
    }

    @Test("unknown folder is a noop and never invokes the trasher")
    func unknownFolderIsNoop() async {
        let captured = LockedBox<Int>(value: 0)
        let model = ProjectKanbanModel(
            trasher: { _ in
                captured.mutate { $0 += 1 }
                return URL(filePath: "/Users/me/.Trash/x")
            }
        )
        let issueA = OptimisticDropTests.makeIssue(id: 1, folder: "00001-a", status: .approved)
        model._setIssuesForTesting([.valid(issueA)])

        await model.performTrashOptimistic(
            folderName: "00099-missing", projectURL: URL(filePath: "/tmp/probe"))

        #expect(captured.value == 0)
        #expect(model.issues.count == 1)
        #expect(model.lastRemovalError == nil)
    }

    @Test("trasher receives folder URL derived from projectURL")
    func trasherReceivesExpectedURL() async throws {
        let receivedFolder = LockedBox<URL?>(value: nil)
        let model = ProjectKanbanModel(
            trasher: { folderURL in
                receivedFolder.mutate { $0 = folderURL }
                return folderURL
            }
        )
        let issueA = OptimisticDropTests.makeIssue(id: 1, folder: "00001-a", status: .approved)
        model._setIssuesForTesting([.valid(issueA)])

        await model.performTrashOptimistic(
            folderName: "00001-a", projectURL: URL(filePath: "/tmp/probe"))

        let folder = try #require(receivedFolder.value)
        #expect(folder.path.hasSuffix(".claude/issues/00001-a"))
    }
}

@Suite("ProjectKanbanModel removal cancellation discipline")
@MainActor
struct RemovalCancellationTests {
    @Test("second archive cancels first; first's throw does not roll back second's removal")
    func secondArchiveSuppressesFirstRollback() async throws {
        let firstEntered = AsyncGate()
        let firstProceed = AsyncGate()
        let secondEntered = AsyncGate()
        let secondProceed = AsyncGate()
        let callCount = LockedBox<Int>(value: 0)

        let model = ProjectKanbanModel(
            archiver: { folderURL, _ in
                var call = 0
                callCount.mutate { value in
                    value += 1
                    call = value
                }
                if call == 1 {
                    firstEntered.signal()
                    firstProceed.waitSync()
                    throw NSError(
                        domain: "RemovalCancellationTests", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "first should be swallowed"]
                    )
                }
                secondEntered.signal()
                secondProceed.waitSync()
                return URL(filePath: "/tmp/archive/\(folderURL.lastPathComponent)")
            }
        )

        let issueA = OptimisticDropTests.makeIssue(id: 1, folder: "00001-a", status: .approved)
        let issueB = OptimisticDropTests.makeIssue(id: 2, folder: "00002-b", status: .approved)
        model._setIssuesForTesting([.valid(issueA), .valid(issueB)])

        model.applyOptimisticArchive(
            folderName: "00001-a", projectURL: URL(filePath: "/tmp/probe"))
        await firstEntered.wait()
        #expect(model.issues.map(\.id) == ["00002-b"])

        async let secondCompletion: Void = model.performArchiveOptimistic(
            folderName: "00002-b", projectURL: URL(filePath: "/tmp/probe"))
        await secondEntered.wait()
        #expect(model.issues.isEmpty)

        // First's throw must hit the !Task.isCancelled guard, not roll back.
        firstProceed.signal()
        secondProceed.signal()
        await secondCompletion

        #expect(model.issues.isEmpty)
        #expect(model.lastRemovalError == nil)
        #expect(model.lastRemovalCompleted == "00002-b")
    }
}
