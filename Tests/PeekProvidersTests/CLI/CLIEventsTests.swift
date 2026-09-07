import Foundation
import PeekCore
import Testing
@testable import PeekProviders

struct CLIEventsTests {
    @Test func claudeRecordedStreamDoesNotDuplicateSnapshots() throws {
        var parser = ClaudeCLIEvents()
        let text = try CLIJSONFixtures.claude.split(separator: "\n").compactMap { try parser.text(from: String($0)) }
        #expect(text == ["O", "K"])
    }

    @Test func claudeSnapshotWithoutPartialEvents() throws {
        var parser = ClaudeCLIEvents()
        let snapshots = CLIJSONFixtures.claude.split(separator: "\n").filter { $0.hasPrefix("{\"type\":\"assistant\"") }
        let text = try snapshots.compactMap { try parser.text(from: String($0)) }
        #expect(text == ["OK"])
    }

    @Test func codexRecordedStream() throws {
        let parser = CodexCLIEvents()
        let text = try CLIJSONFixtures.codex.split(separator: "\n").compactMap { try parser.text(from: String($0)) }
        #expect(text == ["OK"])
    }

    @Test func ignoresToolsAndThinking() throws {
        var claude = ClaudeCLIEvents()
        #expect(try claude.text(from: #"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"private"}}}"#) == nil)
        #expect(try claude.text(from: #"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"input_json_delta","partial_json":"{}"}}}"#) == nil)
        #expect(try CodexCLIEvents().text(from: #"{"type":"item.completed","item":{"type":"command_execution","text":"tool output"}}"#) == nil)
    }

    @Test func reportsErrors() {
        #expect(throws: ProviderError.malformedResponse("quota")) {
            var parser = ClaudeCLIEvents()
            _ = try parser.text(from: #"{"type":"result","is_error":true,"errors":["quota"]}"#)
        }
        for line in [#"{"type":"turn.failed","error":{"message":"quota"}}"#, #"{"type":"error","message":"quota"}"#] {
            #expect(throws: ProviderError.malformedResponse("quota")) { try CodexCLIEvents().text(from: line) }
        }
        #expect(throws: ProviderError.self) { try CodexCLIEvents().text(from: "not JSON") }
        #expect(throws: ProviderError.self) { try CodexCLIEvents().text(from: #"{"type":"item.completed","item":{"type":"agent_message"}}"#) }
    }
}
