import Foundation
import PeekCore

/// Follows tool blocks in Anthropic stream events: reports each call when it starts, then again once its input is complete.
struct AnthropicToolCalls: Sendable {
    private var open: [Int: (activity: AIActivity, input: String)] = [:]

    mutating func activity(from event: [String: Any]) -> AIActivity? {
        let index = event["index"] as? Int ?? 0
        switch event["type"] as? String {
        case "content_block_start":
            guard let block = event["content_block"] as? [String: Any],
                  ["tool_use", "server_tool_use"].contains(block["type"] as? String),
                  let kind = Self.kind(block["name"] as? String) else { return nil }
            let activity = AIActivity(id: block["id"] as? String ?? "\(index)", kind: kind)
            open[index] = (activity, "")
            return activity
        case "content_block_delta":
            guard let delta = event["delta"] as? [String: Any], delta["type"] as? String == "input_json_delta",
                  let json = delta["partial_json"] as? String else { return nil }
            open[index]?.input += json
            return nil
        case "content_block_stop":
            guard let (activity, input) = open.removeValue(forKey: index) else { return nil }
            let value = (try? JSONSerialization.jsonObject(with: Data(input.utf8))) as? [String: Any]
            return AIActivity(id: activity.id, kind: activity.kind, detail: Self.detail(activity.kind, value))
        default:
            return nil
        }
    }

    private static func kind(_ name: String?) -> AIActivity.Kind? {
        switch name {
        case "web_search", "WebSearch": .searchingWeb
        case "Read": .readingFiles
        default: nil
        }
    }

    private static func detail(_ kind: AIActivity.Kind, _ input: [String: Any]?) -> String? {
        switch kind {
        case .searchingWeb: input?["query"] as? String
        case .readingFiles: (input?["file_path"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent }
        case .runningCommand: input?["command"] as? String
        }
    }
}
