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

    @Test("opusPlan injects --model opusplan")
    func opusPlanInjects() {
        let session = makeSession(model: .opusPlan)
        let args = session.shellSpawnArgs()
        #expect(args.joined(separator: " ").contains("'--model' 'opusplan'"))
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
}
