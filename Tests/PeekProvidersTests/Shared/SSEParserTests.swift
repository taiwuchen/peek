import Testing
@testable import PeekProviders

struct SSEParserTests {
    @Test func dispatchesOnlyOnBlankLines() {
        var parser = SSEParser()
        #expect(parser.consume("event: delta") == nil)
        #expect(parser.consume("data: hello") == nil)
        #expect(parser.consume("") == SSEEvent(event: "delta", data: "hello"))
        #expect(parser.consume("") == nil)
    }

    @Test func joinsDataLinesAndPreservesWhitespaceAndColons() {
        var parser = SSEParser()
        #expect(parser.consume("data:  first: value ") == nil)
        #expect(parser.consume("data:second") == nil)
        #expect(parser.consume("data:") == nil)
        #expect(parser.consume("") == SSEEvent(event: "message", data: " first: value \nsecond\n"))
    }

    @Test func ignoresCommentsAndUnknownFields() {
        var parser = SSEParser()
        for line in [": keepalive", "id: 123", "retry: 1000", "other: value", "", ":"] {
            #expect(parser.consume(line) == nil)
        }
        #expect(parser.consume("data: ok") == nil)
        #expect(parser.consume(": comment between data lines") == nil)
        #expect(parser.consume("") == SSEEvent(event: "message", data: "ok"))
    }

    @Test func resetsEventNameAfterEveryDispatch() {
        var parser = SSEParser()
        for line in ["event: ignored", "", "data: default"] { #expect(parser.consume(line) == nil) }
        #expect(parser.consume("") == SSEEvent(event: "message", data: "default"))
        for line in ["event: first", "event: last", "data: named"] { #expect(parser.consume(line) == nil) }
        #expect(parser.consume("") == SSEEvent(event: "last", data: "named"))
        for line in ["event:", "data: default again"] { #expect(parser.consume(line) == nil) }
        #expect(parser.consume("") == SSEEvent(event: "message", data: "default again"))
    }

    @Test func dispatchesEmptyDataFieldWithoutColon() {
        var parser = SSEParser()
        #expect(parser.consume("data") == nil)
        #expect(parser.consume("") == SSEEvent(event: "message", data: ""))
    }

    @Test func stripsInitialBOMOnly() {
        var parser = SSEParser()
        #expect(parser.consume("\u{FEFF}data: first") == nil)
        #expect(parser.consume("") == SSEEvent(event: "message", data: "first"))
        #expect(parser.consume("data: \u{FEFF}second") == nil)
        #expect(parser.consume("") == SSEEvent(event: "message", data: "\u{FEFF}second"))
    }
}
