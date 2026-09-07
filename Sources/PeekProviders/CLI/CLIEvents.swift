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

    mutating func text(from line: String) throws -> String? {
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
            guard event["type"] as? String == "content_block_delta",
                  let delta = event["delta"] as? [String: Any], delta["type"] as? String == "text_delta" else { return nil }
            guard let text = delta["text"] as? String else {
                throw ProviderError.malformedResponse("Missing Claude text delta")
            }
            return text
        case "assistant":
            guard !hasPartialMessages, let message = value["message"] as? [String: Any],
                  let content = message["content"] as? [[String: Any]] else { return nil }
            let text = content.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
            return text.isEmpty ? nil : text
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
    func text(from line: String) throws -> String? {
        let value = try cliEvent(line)
        switch value["type"] as? String {
        case "item.completed":
            guard let item = value["item"] as? [String: Any], item["type"] as? String == "agent_message" else { return nil }
            guard let text = item["text"] as? String else {
                throw ProviderError.malformedResponse("Missing Codex assistant text")
            }
            return text
        case "error", "turn.failed":
            let error = value["error"] as? [String: Any]
            throw ProviderError.malformedResponse(error?["message"] as? String ?? value["message"] as? String ?? "Codex request failed")
        default:
            return nil
        }
    }
}
