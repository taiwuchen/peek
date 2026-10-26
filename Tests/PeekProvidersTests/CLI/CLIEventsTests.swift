import Foundation
import PeekCore
import Testing
@testable import PeekProviders

struct CLIEventsTests {
    @Test func claudeRecordedStreamDoesNotDuplicateSnapshots() throws {
        var parser = ClaudeCLIEvents()
        let text = try CLIJSONFixtures.claude.split(separator: "\n").compactMap { try parser.event(from: String($0)) }
        #expect(text == [.text("O"), .text("K")])
    }

    @Test func claudeSnapshotWithoutPartialEvents() throws {
        var parser = ClaudeCLIEvents()
        let snapshots = CLIJSONFixtures.claude.split(separator: "\n").filter { $0.hasPrefix("{\"type\":\"assistant\"") }
        let text = try snapshots.compactMap { try parser.event(from: String($0)) }
        #expect(text == [.text("OK")])
    }

    @Test func codexRecordedStream() throws {
        let parser = CodexCLIEvents()
        let text = try CLIJSONFixtures.codex.split(separator: "\n").compactMap { try parser.event(from: String($0)) }
        #expect(text == [.text("OK")])
    }

    @Test func claudeReportsToolCallThenItsInput() throws {
        var claude = ClaudeCLIEvents()
        let start = #"{"type":"stream_event","event":{"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_1","name":"NAME","input":{}}}}"#
        let delta = #"{"type":"stream_event","event":{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"JSON"}}}"#
        let stop = #"{"type":"stream_event","event":{"type":"content_block_stop","index":1}}"#
        #expect(try claude.event(from: start.replacingOccurrences(of: "NAME", with: "WebSearch")) == .activity(AIActivity(id: "toolu_1", kind: .searchingWeb)))
        #expect(try claude.event(from: delta.replacingOccurrences(of: "JSON", with: #"{\"query\": \"swift "#)) == nil)
        #expect(try claude.event(from: delta.replacingOccurrences(of: "JSON", with: #"release\"}"#)) == nil)
        #expect(try claude.event(from: stop) == .activity(AIActivity(id: "toolu_1", kind: .searchingWeb, detail: "swift release")))
        #expect(try claude.event(from: start.replacingOccurrences(of: "NAME", with: "Read")) == .activity(AIActivity(id: "toolu_1", kind: .readingFiles)))
        _ = try claude.event(from: delta.replacingOccurrences(of: "JSON", with: #"{\"file_path\": \"/tmp/x/capture-1.png\"}"#))
        #expect(try claude.event(from: stop) == .activity(AIActivity(id: "toolu_1", kind: .readingFiles, detail: "capture-1.png")))
        #expect(try claude.event(from: start.replacingOccurrences(of: "NAME", with: "mcp__other")) == nil)
        #expect(try claude.event(from: stop) == nil)
    }

    @Test func codexReportsToolCallThenItsDetail() throws {
        let codex = CodexCLIEvents()
        #expect(try codex.event(from: #"{"type":"item.started","item":{"id":"item_1","type":"web_search","query":"","action":{"type":"other"}}}"#)
                == .activity(AIActivity(id: "item_1", kind: .searchingWeb)))
        #expect(try codex.event(from: #"{"type":"item.completed","item":{"id":"item_1","type":"web_search","query":"swift release"}}"#)
                == .activity(AIActivity(id: "item_1", kind: .searchingWeb, detail: "swift release")))
        #expect(try codex.event(from: #"{"type":"item.started","item":{"id":"item_2","type":"command_execution","command":"/bin/zsh -lc 'cat notes.md'"}}"#)
                == .activity(AIActivity(id: "item_2", kind: .runningCommand, detail: "cat notes.md")))
        #expect(CodexCLIEvents.innerCommand("ls -la") == "ls -la")
    }

    @Test func ignoresToolsAndThinking() throws {
        var claude = ClaudeCLIEvents()
        #expect(try claude.event(from: #"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"private"}}}"#) == nil)
        #expect(try claude.event(from: #"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"input_json_delta","partial_json":"{}"}}}"#) == nil)
        #expect(try CodexCLIEvents().event(from: #"{"type":"item.completed","item":{"type":"reasoning","text":"private"}}"#) == nil)
    }

    @Test func reportsErrors() {
        #expect(throws: ProviderError.malformedResponse("quota")) {
            var parser = ClaudeCLIEvents()
            _ = try parser.event(from: #"{"type":"result","is_error":true,"errors":["quota"]}"#)
        }
        for line in [#"{"type":"turn.failed","error":{"message":"quota"}}"#, #"{"type":"error","message":"quota"}"#] {
            #expect(throws: ProviderError.malformedResponse("quota")) { try CodexCLIEvents().event(from: line) }
        }
        #expect(throws: ProviderError.self) { try CodexCLIEvents().event(from: "not JSON") }
        #expect(throws: ProviderError.self) { try CodexCLIEvents().event(from: #"{"type":"item.completed","item":{"type":"agent_message"}}"#) }
    }
}
