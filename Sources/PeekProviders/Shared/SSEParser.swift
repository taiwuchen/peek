struct SSEEvent: Sendable, Equatable {
    let event: String
    let data: String
}

struct SSELineSequence<Base: AsyncSequence>: AsyncSequence where Base.Element == UInt8 {
    typealias Element = String
    let bytes: Base

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(base: bytes.makeAsyncIterator())
    }

    struct AsyncIterator: AsyncIteratorProtocol {
        var base: Base.AsyncIterator
        private var buffer: [UInt8] = []
        private var previousWasCR = false

        init(base: Base.AsyncIterator) {
            self.base = base
        }

        mutating func next() async throws -> String? {
            while let byte = try await base.next() {
                if previousWasCR {
                    previousWasCR = false
                    if byte == 10 { continue }
                }
                if byte == 13 || byte == 10 {
                    previousWasCR = byte == 13
                    let line = String(decoding: buffer, as: UTF8.self)
                    buffer.removeAll(keepingCapacity: true)
                    return line
                }
                buffer.append(byte)
            }
            guard !buffer.isEmpty else { return nil }
            let line = String(decoding: buffer, as: UTF8.self)
            buffer.removeAll(keepingCapacity: true)
            return line
        }
    }
}

struct SSEParser {
    private var event = ""
    private var data: [String] = []
    private var isFirstLine = true

    mutating func consume(_ line: String) -> SSEEvent? {
        var line = line
        if isFirstLine {
            isFirstLine = false
            if line.first == "\u{FEFF}" { line.removeFirst() }
        }
        if line.isEmpty { return dispatch() }
        if line.hasPrefix(":") { return nil }
        let fields = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        var value = fields.count == 2 ? String(fields[1]) : ""
        if value.first == " " { value.removeFirst() }
        switch fields[0] {
        case "event": event = value
        case "data": data.append(value)
        default: break
        }
        return nil
    }

    private mutating func dispatch() -> SSEEvent? {
        defer {
            event = ""
            data.removeAll(keepingCapacity: true)
        }
        guard !data.isEmpty else { return nil }
        return SSEEvent(event: event.isEmpty ? "message" : event, data: data.joined(separator: "\n"))
    }
}
