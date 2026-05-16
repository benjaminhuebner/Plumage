import Foundation

nonisolated enum ClaudeMessageEncoding {
    static func encode(userText: String) throws -> Data {
        let envelope = UserMessageEnvelope(
            type: "user",
            message: UserMessage(
                role: "user",
                content: [TextBlock(type: "text", text: userText)]
            )
        )
        var data = try JSONEncoder().encode(envelope)
        data.append(0x0A)
        return data
    }
}

private nonisolated struct UserMessageEnvelope: Encodable {
    let type: String
    let message: UserMessage
}

private nonisolated struct UserMessage: Encodable {
    let role: String
    let content: [TextBlock]
}

private nonisolated struct TextBlock: Encodable {
    let type: String
    let text: String
}
