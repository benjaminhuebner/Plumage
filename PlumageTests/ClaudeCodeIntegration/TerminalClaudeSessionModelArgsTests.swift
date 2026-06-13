import Foundation
import Testing

@testable import Plumage

@Suite("TerminalClaudeSession --model threading")
@MainActor
struct TerminalClaudeSessionModelArgsTests {
    private func makeSession(model: ModelChoice) -> TerminalClaudeSession {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("TCSModel-\(UUID().uuidString)", isDirectory: true)
        return TerminalClaudeSession(
            cwd: tmp,
            binaryURL: URL(filePath: "/usr/bin/true"),
            modelChoice: model,
            persistConversationID: false
        )
    }

    @Test("default model adds no --model flag")
    func defaultOmitsFlag() {
        let session = makeSession(model: .default)
        let args = session.shellSpawnArgs()
        let joined = args.joined(separator: " ")
        #expect(!joined.contains("--model"))
    }

    @Test("opus injects --model opus")
    func opusInjects() {
        let session = makeSession(model: .opus)
        let args = session.shellSpawnArgs()
        #expect(args.joined(separator: " ").contains("'--model' 'opus'"))
    }

    @Test("sonnet injects --model sonnet")
    func sonnetInjects() {
        let session = makeSession(model: .sonnet)
        let args = session.shellSpawnArgs()
        #expect(args.joined(separator: " ").contains("'--model' 'sonnet'"))
    }

    @Test("haiku injects --model haiku")
    func haikuInjects() {
        let session = makeSession(model: .haiku)
        let args = session.shellSpawnArgs()
        #expect(args.joined(separator: " ").contains("'--model' 'haiku'"))
    }

    @Test("permission mode plus model coexist")
    func permissionAndModelCoexist() {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("TCSModel-\(UUID().uuidString)", isDirectory: true)
        let session = TerminalClaudeSession(
            cwd: tmp,
            binaryURL: URL(filePath: "/usr/bin/true"),
            modelChoice: .opus,
            persistConversationID: false,
            permissionMode: .plan
        )
        let joined = session.shellSpawnArgs().joined(separator: " ")
        #expect(joined.contains("'--permission-mode' 'plan'"))
        #expect(joined.contains("'--model' 'opus'"))
    }

    private func makeSession(model: ModelChoice, effort: EffortLevel) -> TerminalClaudeSession {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("TCSEffort-\(UUID().uuidString)", isDirectory: true)
        return TerminalClaudeSession(
            cwd: tmp,
            binaryURL: URL(filePath: "/usr/bin/true"),
            modelChoice: model,
            effortChoice: effort,
            persistConversationID: false
        )
    }

    @Test("default effort adds no --effort flag")
    func defaultEffortOmitsFlag() {
        let joined = makeSession(model: .default, effort: .default).shellSpawnArgs()
            .joined(separator: " ")
        #expect(!joined.contains("--effort"))
    }

    @Test("a non-default effort injects --effort <level>")
    func effortInjects() {
        let joined = makeSession(model: .default, effort: .max).shellSpawnArgs()
            .joined(separator: " ")
        #expect(joined.contains("'--effort' 'max'"))
    }

    @Test("model and effort coexist in the spawn args")
    func modelAndEffortCoexist() {
        let joined = makeSession(model: .opus, effort: .high).shellSpawnArgs()
            .joined(separator: " ")
        #expect(joined.contains("'--model' 'opus'"))
        #expect(joined.contains("'--effort' 'high'"))
    }
}
