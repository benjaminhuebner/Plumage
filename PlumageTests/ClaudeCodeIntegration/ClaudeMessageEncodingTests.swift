import Foundation
import Testing

@testable import Plumage

@Suite("ClaudeMessageEncoding")
struct ClaudeMessageEncodingTests {
    @Test("produces valid JSON with trailing newline")
    func trailingNewline() throws {
        let data = try ClaudeMessageEncoding.encode(userText: "hi")
        #expect(data.last == 0x0A)
        let withoutNewline = data.dropLast()
        _ = try JSONSerialization.jsonObject(with: withoutNewline)
    }

    @Test("envelope shape matches claude headless protocol")
    func envelopeShape() throws {
        let data = try ClaudeMessageEncoding.encode(userText: "hello")
        let object = try JSONSerialization.jsonObject(with: data.dropLast()) as? [String: Any]
        let root = try #require(object)
        #expect(root["type"] as? String == "user")
        let message = try #require(root["message"] as? [String: Any])
        #expect(message["role"] as? String == "user")
        let content = try #require(message["content"] as? [[String: Any]])
        #expect(content.count == 1)
        #expect(content[0]["type"] as? String == "text")
        #expect(content[0]["text"] as? String == "hello")
    }

    @Test("escapes special JSON characters in user text")
    func escapesSpecialChars() throws {
        let data = try ClaudeMessageEncoding.encode(userText: "quote\" and \\backslash and \nnewline")
        let object = try JSONSerialization.jsonObject(with: data.dropLast()) as? [String: Any]
        let root = try #require(object)
        let message = try #require(root["message"] as? [String: Any])
        let content = try #require(message["content"] as? [[String: Any]])
        #expect(content[0]["text"] as? String == "quote\" and \\backslash and \nnewline")
    }

    @Test("multiline user text preserves exact bytes through JSON")
    func multilinePreserved() throws {
        let input = "line one\nline two\nline three"
        let data = try ClaudeMessageEncoding.encode(userText: input)
        let object = try JSONSerialization.jsonObject(with: data.dropLast()) as? [String: Any]
        let root = try #require(object)
        let message = try #require(root["message"] as? [String: Any])
        let content = try #require(message["content"] as? [[String: Any]])
        #expect(content[0]["text"] as? String == input)
    }

    @Test("empty string still produces well-formed envelope")
    func emptyText() throws {
        let data = try ClaudeMessageEncoding.encode(userText: "")
        let object = try JSONSerialization.jsonObject(with: data.dropLast()) as? [String: Any]
        let root = try #require(object)
        let message = try #require(root["message"] as? [String: Any])
        let content = try #require(message["content"] as? [[String: Any]])
        let text = try #require(content[0]["text"] as? String)
        #expect(text.isEmpty)
    }
}
