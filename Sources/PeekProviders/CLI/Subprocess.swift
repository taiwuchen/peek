import Foundation
import PeekCore

internal struct Subprocess: Sendable {
    let executable: String
    var arguments: [String] = []
    var input: Data? = nil
    var directory: URL? = nil
    var environment: [String: String] = [:]
    var timeout: TimeInterval? = nil

    func lines() -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let run = ProcessRun(continuation: continuation)
            continuation.onTermination = { @Sendable _ in run.cancel() }
            DispatchQueue.global().async { run.start(self) }
        }
    }

    func output() async throws -> String {
        var lines: [String] = []
        for try await line in self.lines() {
            try Task.checkCancellation()
            lines.append(line)
        }
        try Task.checkCancellation()
        return lines.joined(separator: "\n")
    }

    static func environment(overrides: [String: String]) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment.merging(overrides) { _, new in new }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if environment["HOME", default: ""].isEmpty { environment["HOME"] = home }
        let paths = [environment["PATH", default: ""], "\(home)/.local/bin", "\(home)/.npm-global/bin", "\(home)/.claude/local/bin", "\(home)/.bun/bin",
                     "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        environment["PATH"] = paths.filter { !$0.isEmpty }.joined(separator: ":")
        return environment
    }
}

// The lock protects process launch, cancellation, and exit against competing callbacks.
private final class ProcessRun: @unchecked Sendable {
    private let lock = NSLock()
    private let process = Process()
    private let continuation: AsyncThrowingStream<String, Error>.Continuation
    private var cancelled = false
    private var finished = false
    private var started = false

    init(continuation: AsyncThrowingStream<String, Error>.Continuation) {
        self.continuation = continuation
    }

    func start(_ command: Subprocess) {
        let stdout = Pipe()
        let stderr = Pipe()
        let stdin = Pipe()
        // A child may close stdin early; suppress SIGPIPE only on this pipe, not app-wide.
        _ = fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        do {
            try lock.withLock {
                guard !cancelled else { throw CancellationError() }
                process.executableURL = URL(fileURLWithPath: command.executable)
                process.arguments = command.arguments
                process.currentDirectoryURL = command.directory
                process.environment = Subprocess.environment(overrides: command.environment)
                process.standardOutput = stdout
                process.standardError = stderr
                process.standardInput = stdin
                try process.run()
                started = true
            }
        } catch {
            continuation.finish(throwing: error)
            return
        }
        if let timeout = command.timeout {
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.cancel()
                self?.continuation.finish(throwing: CancellationError())
            }
        }
        let readers = DispatchGroup()
        readers.enter()
        DispatchQueue.global().async { [continuation] in
            defer { readers.leave(); try? stdout.fileHandleForReading.close() }
            var pending = Data()
            while true {
                let data = stdout.fileHandleForReading.availableData
                if data.isEmpty { break }
                pending.append(data)
                while let end = pending.firstIndex(of: 10) {
                    var line = pending[..<end]
                    if line.last == 13 { line = line.dropLast() }
                    continuation.yield(String(decoding: line, as: UTF8.self))
                    pending.removeSubrange(...end)
                }
            }
            if !pending.isEmpty { continuation.yield(String(decoding: pending, as: UTF8.self)) }
        }
        DispatchQueue.global().async {
            defer { try? stdin.fileHandleForWriting.close() }
            if let input = command.input { try? stdin.fileHandleForWriting.write(contentsOf: input) }
        }
        let errorData = (try? stderr.fileHandleForReading.readToEnd()) ?? Data()
        try? stderr.fileHandleForReading.close()
        process.waitUntilExit()
        readers.wait()
        let wasCancelled = lock.withLock {
            finished = true
            return cancelled
        }
        if wasCancelled {
            continuation.finish(throwing: CancellationError())
        } else if process.terminationStatus != 0 {
            continuation.finish(throwing: ProviderError.processFailed(
                exitCode: process.terminationStatus, stderr: String(decoding: errorData, as: UTF8.self)
            ))
        } else {
            continuation.finish()
        }
    }

    func cancel() {
        let shouldKill = lock.withLock {
            guard !finished, !cancelled else { return false }
            cancelled = true
            guard started, process.isRunning else { return false }
            process.terminate()
            return true
        }
        guard shouldKill else { return }
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [self] in
            lock.withLock {
                if !finished, process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        }
    }
}
