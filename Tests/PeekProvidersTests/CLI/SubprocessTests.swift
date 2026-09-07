import Foundation
import PeekCore
import Testing
@testable import PeekProviders

struct SubprocessTests {
    @Test func echoAndStdin() async throws {
        #expect(try await Subprocess(executable: "/bin/echo", arguments: ["hello"]).output() == "hello")
        let input = String(repeating: "héllo\n", count: 20_000) + "last"
        #expect(try await Subprocess(executable: "/bin/sh", arguments: ["-c", "cat"], input: Data(input.utf8)).output() == input)
    }

    @Test func lineEndingsAndEnvironment() async throws {
        let result = try await Subprocess(executable: "/bin/sh", arguments: ["-c", "printf 'one\\r\\n\\nlast'"]).output()
        #expect(result == "one\n\nlast")
        let environment = Subprocess.environment(overrides: ["HOME": "", "PATH": "", "PEEK_TEST": "yes"])
        #expect(environment["HOME"]?.isEmpty == false)
        #expect(environment["PATH"]?.contains("/usr/bin") == true)
        #expect(try await Subprocess(executable: "/bin/sh", arguments: ["-c", "printf '%s' \"$PEEK_TEST\""], environment: ["PEEK_TEST": "yes"]).output() == "yes")
    }

    @Test func drainsLargeStderrAndReportsExitAfterStdout() async throws {
        let command = Subprocess(executable: "/bin/sh", arguments: ["-c", "printf 'answer\\n'; /usr/bin/head -c 100000 /dev/zero | /usr/bin/tr '\\0' x >&2; exit 7"])
        var output: [String] = []
        do {
            for try await line in command.lines() { output.append(line) }
            Issue.record("Expected process failure")
        } catch ProviderError.processFailed(let code, let stderr) {
            #expect(code == 7)
            #expect(stderr == String(repeating: "x", count: 100_000))
        }
        #expect(output == ["answer"])
    }

    @Test func missingExecutableThrows() async {
        await #expect(throws: (any Error).self) { try await Subprocess(executable: "/missing/peek-test-executable").output() }
    }

    @Test func childCanExitBeforeReadingInput() async throws {
        #expect(try await Subprocess(executable: "/bin/sh", arguments: ["-c", "exit 0"], input: Data(repeating: 65, count: 1_000_000)).output() == "")
    }

    @Test func timeout() async {
        let start = ContinuousClock.now
        await #expect(throws: CancellationError.self) {
            try await Subprocess(executable: "/bin/sh", arguments: ["-c", "exec /bin/sleep 30"], timeout: 0.1).output()
        }
        #expect(start.duration(to: .now) < .seconds(1))
    }

    @Test(arguments: [false, true]) func cancellationTerminatesChild(ignoresTerm: Bool) async throws {
        let start = ContinuousClock.now
        let ready = AsyncStream<Int32>.makeStream()
        let script = (ignoresTerm ? "trap '' TERM; " : "") + "echo $$; exec /bin/sleep 30"
        let consumer = Task {
            for try await line in Subprocess(executable: "/bin/sh", arguments: ["-c", script]).lines() {
                if let pid = Int32(line) { ready.continuation.yield(pid) }
            }
        }
        var iterator = ready.stream.makeAsyncIterator()
        let pid = try #require(await iterator.next())
        #expect(kill(pid, 0) == 0)
        ready.continuation.finish()
        defer { if kill(pid, 0) == 0 { kill(pid, SIGKILL) } }
        consumer.cancel()
        _ = await consumer.result
        let deadline = ContinuousClock.now.advanced(by: .seconds(4))
        while kill(pid, 0) == 0, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(25)) }
        #expect(kill(pid, 0) == -1)
        #expect(start.duration(to: .now) < .seconds(5))
    }
}
