import Foundation

nonisolated enum ClaudeStreamEvent: Sendable, Equatable, Decodable {
    case systemInit(sessionID: String)
    case systemOther(subtype: String)
    case assistant([AssistantContent])
    case result(isError: Bool, text: String?)
    case rateLimit
    case unknown(typeField: String)
}

nonisolated enum AssistantContent: Sendable, Equatable {
    case text(String)
    case toolUse(name: String)
    case other
}

extension ClaudeStreamEvent {
    private nonisolated enum CodingKeys: String, CodingKey {
        case type
        case subtype
        case sessionID = "session_id"
        case message
        case isError = "is_error"
        case result
    }

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = (try? container.decode(String.self, forKey: .type)) ?? "unknown"

        switch type {
        case "system":
            let subtype = (try? container.decode(String.self, forKey: .subtype)) ?? ""
            if subtype == "init" {
                let sessionID = (try? container.decode(String.self, forKey: .sessionID)) ?? ""
                self = .systemInit(sessionID: sessionID)
            } else {
                self = .systemOther(subtype: subtype)
            }
        case "assistant":
            let message = try? container.decode(AssistantMessageEnvelope.self, forKey: .message)
            self = .assistant(message?.content ?? [])
        case "result":
            let isError = (try? container.decode(Bool.self, forKey: .isError)) ?? false
            let text = try? container.decode(String.self, forKey: .result)
            self = .result(isError: isError, text: text)
        case "rate_limit_event":
            self = .rateLimit
        default:
            self = .unknown(typeField: type)
        }
    }
}

private nonisolated struct AssistantMessageEnvelope: Decodable {
    let content: [AssistantContent]

    private nonisolated enum CodingKeys: String, CodingKey { case content }

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var blockContainer = try container.nestedUnkeyedContainer(forKey: .content)
        var blocks: [AssistantContent] = []
        while !blockContainer.isAtEnd {
            let block = try blockContainer.decode(RawContentBlock.self)
            switch block.type {
            case "text":
                blocks.append(.text(block.text ?? ""))
            case "tool_use":
                blocks.append(.toolUse(name: block.name ?? "tool"))
            default:
                blocks.append(.other)
            }
        }
        self.content = blocks
    }
}

private nonisolated struct RawContentBlock: Decodable {
    let type: String
    let text: String?
    let name: String?
}
