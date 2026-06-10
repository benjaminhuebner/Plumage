import Foundation
import Testing

@testable import Plumage

@Suite("ClaudeStreamEvent decoding")
struct ClaudeStreamEventTests {
    @Test("system/init carries session_id")
    func systemInit() throws {
        let json = #"{"type":"system","subtype":"init","cwd":"/tmp","session_id":"abc-123","tools":[],"model":"opus"}"#
        let event = try decode(json)
        #expect(event == .systemInit(sessionID: "abc-123"))
    }

    @Test("system/hook_started maps to systemOther with subtype")
    func systemHookStarted() throws {
        let json = #"{"type":"system","subtype":"hook_started","hook_name":"SessionStart:startup"}"#
        let event = try decode(json)
        #expect(event == .systemOther(subtype: "hook_started"))
    }

    @Test("assistant text content extracts text string")
    func assistantText() throws {
        let json = #"""
            {"type":"assistant","message":{"model":"opus","role":"assistant","content":[{"type":"text","text":"Hello there"}]}}
            """#
        let event = try decode(json)
        #expect(event == .assistant([.text("Hello there")]))
    }

    @Test("assistant tool_use content extracts tool name")
    func assistantToolUse() throws {
        let json = #"""
            {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_01","name":"Bash","input":{"cmd":"ls"}}]}}
            """#
        let event = try decode(json)
        #expect(event == .assistant([.toolUse(name: "Bash")]))
    }

    @Test("assistant message with mixed text and tool_use yields both blocks in order")
    func assistantMixedContent() throws {
        let json = #"""
            {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Let me check"},{"type":"tool_use","id":"t","name":"Read"}]}}
            """#
        let event = try decode(json)
        #expect(event == .assistant([.text("Let me check"), .toolUse(name: "Read")]))
    }

    @Test("assistant unknown content type maps to .other")
    func assistantUnknownContent() throws {
        let json = #"""
            {"type":"assistant","message":{"role":"assistant","content":[{"type":"thinking","summary":"…"}]}}
            """#
        let event = try decode(json)
        #expect(event == .assistant([.other]))
    }

    @Test("result/success extracts is_error=false and result text")
    func resultSuccess() throws {
        let json = #"""
            {"type":"result","subtype":"success","is_error":false,"result":"OK","total_cost_usd":0.01}
            """#
        let event = try decode(json)
        #expect(event == .result(isError: false, text: "OK"))
    }

    @Test("result with is_error=true sets the flag")
    func resultError() throws {
        let json = #"{"type":"result","subtype":"error","is_error":true}"#
        let event = try decode(json)
        #expect(event == .result(isError: true, text: nil))
    }

    @Test("result without is_error defaults to success")
    func resultMissingIsError() throws {
        let json = #"{"type":"result","subtype":"success","result":"OK"}"#
        let event = try decode(json)
        #expect(event == .result(isError: false, text: "OK"))
    }

    @Test("result with type-changed is_error stays deliverable and degrades to error, not success")
    func resultTypeChangedIsErrorDegradesToError() throws {
        let json = #"{"type":"result","subtype":"error","is_error":"yes"}"#
        let event = try decode(json)
        #expect(event == .result(isError: true, text: nil))
    }

    @Test("rate_limit_event maps to .rateLimit")
    func rateLimit() throws {
        let json = #"{"type":"rate_limit_event","rate_limit_info":{"status":"allowed"}}"#
        let event = try decode(json)
        #expect(event == .rateLimit)
    }

    @Test("unrecognised type lands in .unknown")
    func unknownType() throws {
        let json = #"{"type":"future_feature","payload":{}}"#
        let event = try decode(json)
        #expect(event == .unknown(typeField: "future_feature"))
    }

    @Test("missing type field decodes as unknown")
    func missingType() throws {
        let json = #"{"payload":{}}"#
        let event = try decode(json)
        #expect(event == .unknown(typeField: "unknown"))
    }

    private func decode(_ jsonString: String) throws -> ClaudeStreamEvent {
        let data = try #require(jsonString.data(using: .utf8))
        return try JSONDecoder().decode(ClaudeStreamEvent.self, from: data)
    }
}
