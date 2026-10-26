import Foundation
import PeekCore

internal func cliEvent(_ line: String) throws -> [String: Any] {
    guard let value = try? JSONSerialization.jsonObject(with: Data(line.utf8)),
          let event = value as? [String: Any], event["type"] is String else {
        throw ProviderError.malformedResponse("Invalid CLI JSON event")
    }
    return event
}

internal struct ClaudeCLIEvents {
    private var hasPartialMessages = false
    private var tools = AnthropicToolCalls()

    mutating func event(from line: String) throws -> AIStreamEvent? {
        let value = try cliEvent(line)
        switch value["type"] as? String {
        case "stream_event":
            hasPartialMessages = true
            guard let event = value["event"] as? [String: Any] else {
                throw ProviderError.malformedResponse("Missing Claude stream event")
            }
            if event["type"] as? String == "error" {
                throw ProviderError.malformedResponse(String(describing: event["error"] ?? "Claude error"))
            }
            if let activity = tools.activity(from: event) { return .activity(activity) }
            guard event["type"] as? String == "content_block_delta",
                  let delta = event["delta"] as? [String: Any], delta["type"] as? String == "text_delta" else { return nil }
            guard let text = delta["text"] as? String else {
                throw ProviderError.malformedResponse("Missing Claude text delta")
            }
            return .text(text)
        case "assistant":
            guard !hasPartialMessages, let message = value["message"] as? [String: Any],
                  let content = message["content"] as? [[String: Any]] else { return nil }
            let text = content.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
            return text.isEmpty ? nil : .text(text)
        case "result":
            if value["is_error"] as? Bool == true {
                let errors = (value["errors"] as? [String])?.joined(separator: "\n")
                throw ProviderError.malformedResponse(errors ?? value["result"] as? String ?? "Claude request failed")
            }
            return nil
        case "error":
            throw ProviderError.malformedResponse(String(describing: value["error"] ?? "Claude request failed"))
        default:
            return nil
        }
    }
}

internal struct CodexCLIEvents {
    func event(from line: String) throws -> AIStreamEvent? {
        let value = try cliEvent(line)
        switch value["type"] as? String {
        case "item.started", "item.completed":
            guard let item = value["item"] as? [String: Any] else { return nil }
            let id = item["id"] as? String ?? ""
            switch item["type"] as? String {
            case "web_search":
                return .activity(AIActivity(id: id, kind: .searchingWeb, detail: item["query"] as? String))
            case "command_execution":
                return .activity(AIActivity(id: id, kind: .runningCommand, detail: (item["command"] as? String).map(Self.innerCommand)))
            case "agent_message" where value["type"] as? String == "item.completed":
                guard let text = item["text"] as? String else {
                    throw ProviderError.malformedResponse("Missing Codex assistant text")
                }
                return .text(text)
            default:
                return nil
            }
        case "error", "turn.failed":
            let error = value["error"] as? [String: Any]
            throw ProviderError.malformedResponse(error?["message"] as? String ?? value["message"] as? String ?? "Codex request failed")
        default:
            return nil
        }
    }

    /// Codex wraps each command in a login shell; shows the command itself.
    static func innerCommand(_ command: String) -> String {
        guard let match = command.wholeMatch(of: /\S+ -l?c '(.*)'/) else { return command }
        return String(match.1)
    }
}
