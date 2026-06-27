import Foundation
import Testing

@testable import Plumage

@Suite("Agent notification signal")
struct AgentNotificationTests {
    @Test("parses a hook payload line into a signal")
    func parsesPayload() {
        let line =
            #"{"session_id":"abc","cwd":"/proj","notification_type":"idle_prompt","message":"waiting"}"#
        let signal = AgentNotificationSignal.parse(line: line)
        #expect(signal?.sessionID == "abc")
        #expect(signal?.cwd == "/proj")
        #expect(signal?.notificationType == "idle_prompt")
        #expect(signal?.message == "waiting")
    }

    @Test("ignores blank and malformed lines")
    func ignoresGarbage() {
        #expect(AgentNotificationSignal.parse(line: "") == nil)
        #expect(AgentNotificationSignal.parse(line: "   ") == nil)
        #expect(AgentNotificationSignal.parse(line: "not json") == nil)
        #expect(AgentNotificationSignal.parse(line: #"{"cwd":"/p"}"#) == nil)
    }

    @Test("settings JSON merges the theme and a shell-safe Notification hook")
    func settingsJSONHasHook() throws {
        let signalURL = URL(
            filePath: "/Users/x/Library/Application Support/Plumage/agent-notifications.jsonl")
        let json = try #require(AgentNotificationHook.settingsJSON(dark: true, signalFileURL: signalURL))
        #expect(!json.contains("\n"))
        #expect(TerminalClaudeSession.isShellSafe(json))
        #expect(json.contains("Notification"))
        #expect(json.contains(ClaudeThemeInstaller.settingsThemeValue))
        #expect(json.contains("agent-notifications.jsonl"))
        let data = try #require(json.data(using: .utf8))
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(obj?["hooks"] != nil)
    }

    @Test("settings JSON without effort overrides is byte-identical to today")
    func settingsJSONByteIdentical() throws {
        let signalURL = URL(
            filePath: "/Users/x/Library/Application Support/Plumage/agent-notifications.jsonl")
        let base = try #require(
            AgentNotificationHook.settingsJSON(dark: true, signalFileURL: signalURL))
        let empty = try #require(
            AgentNotificationHook.settingsJSON(
                dark: true, signalFileURL: signalURL, effortOverrides: [:]))
        #expect(base == empty)
        #expect(!base.contains("ultracode"))
    }

    @Test("settings JSON merges ultracode into the hooked object")
    func settingsJSONMergesUltracode() throws {
        let signalURL = URL(
            filePath: "/Users/x/Library/Application Support/Plumage/agent-notifications.jsonl")
        let json = try #require(
            AgentNotificationHook.settingsJSON(
                dark: true, signalFileURL: signalURL, effortOverrides: ["ultracode": true]))
        #expect(json.contains(#""ultracode":true"#))
        #expect(TerminalClaudeSession.isShellSafe(json))
        let data = try #require(json.data(using: .utf8))
        let obj = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any])
        // The hook and the boolean coexist in one object (implement-run case).
        #expect(obj["hooks"] != nil)
        #expect(obj["ultracode"] as? Bool == true)
    }

    @Test("maps a signal to the live run in the same checkout (parallel-safe)")
    func mapsToLiveRun() {
        let runs = [
            WorktreeImplementRun(
                checkoutRoot: URL(filePath: "/work/proj-a"),
                run: LiveImplementRun(issue: "00001-a", agentPid: 11)),
            WorktreeImplementRun(
                checkoutRoot: URL(filePath: "/work/proj-b"),
                run: LiveImplementRun(issue: "00002-b", agentPid: 22)),
        ]
        let signalB = AgentNotificationSignal(
            sessionID: "s", cwd: "/work/proj-b", notificationType: "idle_prompt", message: nil)
        #expect(AgentNotificationHook.liveRun(for: signalB, among: runs)?.run.issue == "00002-b")

        let unknown = AgentNotificationSignal(
            sessionID: "s", cwd: "/work/proj-c", notificationType: "idle_prompt", message: nil)
        #expect(AgentNotificationHook.liveRun(for: unknown, among: runs) == nil)
    }

    @MainActor
    @Test("a session given a signal URL folds the Notification hook into its spawn args")
    func sessionInjectsHook() {
        let session = TerminalClaudeSession(
            cwd: URL(filePath: "/tmp/x"),
            binaryURL: URL(filePath: "/bin/claude"),
            persistConversationID: false,
            notificationSignalURL: AgentNotificationHook.signalFileURL())
        let joined = session.shellSpawnArgs(appearanceIsDark: true).joined(separator: " ")
        #expect(joined.contains("Notification"))
        #expect(joined.contains("agent-notifications.jsonl"))
    }
}
