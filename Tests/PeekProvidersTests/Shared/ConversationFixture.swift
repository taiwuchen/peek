import Foundation
import PeekCore

struct ConversationFixture {
    let images = [Data([137, 80, 78, 71, 1]), Data([137, 80, 78, 71, 2]), Data([137, 80, 78, 71, 3])]
    let texts = ["Explain this \"warning\".\nUse plain words.", "The app needs a permission.", "Why is it needed?", "To capture a screen region.", "Compare these with the first screenshot."]

    var request: AIRequest {
        let captures = images.map { Capture(content: .image($0), anchor: nil, sourceBundleID: nil) }
        return AIRequest(messages: [
            AIMessage(role: .user, text: texts[0], captures: [captures[0]]),
            AIMessage(role: .assistant, text: texts[1]),
            AIMessage(role: .user, text: texts[2]),
            AIMessage(role: .assistant, text: texts[3]),
            AIMessage(role: .user, text: texts[4], captures: [captures[1], captures[2]]),
        ], model: "test-model")
    }
}
