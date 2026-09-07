import Testing
@testable import PeekProviders

struct SSELineSequenceTests {
    @Test(arguments: ["\n", "\r\n", "\r"])
    func preservesEmptyLines(separator: String) async throws {
        let input = "data: Hello\(separator)\(separator)data: 世界\(separator)\(separator)"
        #expect(try await lines(input) == ["data: Hello", "", "data: 世界", ""])
    }

    @Test func handlesMixedLineEndingsAndTrailingContent() async throws {
        #expect(try await lines("a\r\nb\rc\n\r\nfinal") == ["a", "b", "c", "", "final"])
    }

    @Test func handlesEmptyInputAndLeadingBlankLines() async throws {
        #expect(try await lines("") == [])
        #expect(try await lines("\n\ntext") == ["", "", "text"])
    }

    @Test func keepsUnicodeSeparatorsInsideData() async throws {
        #expect(try await lines("data: text\u{2028}more\n\n") == ["data: text\u{2028}more", ""])
    }

    @Test func propagatesByteStreamFailure() async throws {
        let bytes = AsyncThrowingStream<UInt8, Error> { continuation in
            continuation.finish(throwing: Failure.expected)
        }
        await #expect(throws: Failure.expected) {
            for try await _ in SSELineSequence(bytes: bytes) {}
        }
    }

    private enum Failure: Error { case expected }

    private func lines(_ input: String) async throws -> [String] {
        let bytes = AsyncStream<UInt8> { continuation in
            for byte in input.utf8 { continuation.yield(byte) }
            continuation.finish()
        }
        var result: [String] = []
        for try await line in SSELineSequence(bytes: bytes) { result.append(line) }
        return result
    }
}
