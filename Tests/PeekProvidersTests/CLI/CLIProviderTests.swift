import Foundation
import PeekCore
import Testing
@testable import PeekProviders

private final class CLISettings: SettingsStore, @unchecked Sendable {
    private let lock = NSLock()
    private var value = AppSettings()

    func load() -> AppSettings { lock.withLock { value } }
    func save(_ settings: AppSettings) { lock.withLock { value = settings } }
}

private struct FakeCLI {
    let directory: URL
    var executable: String { directory.appendingPathComponent("fake-cli").path }

    init(script: String) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        try ("#!/bin/sh\n" + script).write(to: directory.appendingPathComponent("fake-cli"), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable)
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }
}

struct CLIProviderTests {
    @Test func availabilityReadsSettingsAtCallTime() async throws {
        let ready = try FakeCLI(script: #"printf '{"loggedIn":true}'"#)
        let loggedOut = try FakeCLI(script: #"printf '{"loggedIn":false}'; exit 1"#)
        defer { ready.remove(); loggedOut.remove() }
        let settings = CLISettings()
        let providers = cliProviders(settings: settings)
        #expect(providers.map(\.id) == [.claudeCLI, .codexCLI])
        #expect(providers.allSatisfy { $0.supportsImages })
        settings.save(AppSettings(claudePath: ready.executable, codexPath: ready.executable))
        for provider in providers { #expect(await provider.availability() == .ready) }
        settings.save(AppSettings(claudePath: loggedOut.executable, codexPath: loggedOut.executable))
        for provider in providers { #expect(await provider.availability() == .cliNotLoggedIn) }
    }

    @Test func codexCatalogAndFallback() async throws {
        let catalog = try FakeCLI(script: #"printf '{"models":[{"slug":"visible","display_name":"Visible","visibility":"list"},{"slug":"hidden","display_name":"Hidden","visibility":"hide"}]}'"#)
        let unsupported = try FakeCLI(script: "exit 2")
        defer { catalog.remove(); unsupported.remove() }
        let settings = CLISettings()
        let provider = CodexCLIProvider(settings: settings)
        settings.save(AppSettings(codexPath: catalog.executable))
        #expect(try await provider.models() == [AIModel(id: "visible", displayName: "Visible")])
        settings.save(AppSettings(codexPath: unsupported.executable))
        #expect(try await provider.models().map(\.id) == ["gpt-5.6-sol", "gpt-5.5"])
    }

    @Test(arguments: [ProviderID.claudeCLI, .codexCLI]) func imageRequestUsesTemporaryDirectoryAndCleansUp(id: ProviderID) async throws {
        let event = id == .claudeCLI
            ? #"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"answer"}}}"#
            : #"{"type":"item.completed","item":{"type":"agent_message","text":"answer"}}"#
        let fake = try FakeCLI(script: """
        record="$(dirname "$0")"
        pwd > "$record/cwd"
        printf '%s\\n' "$@" > "$record/args"
        cat > "$record/prompt"
        test -f capture.png || exit 8
        cat capture.png > "$record/image"
        printf '%s\\n' '\(event)'
        """)
        defer { fake.remove() }
        let settings = CLISettings()
        settings.save(AppSettings(claudePath: fake.executable, codexPath: fake.executable))
        let provider = try #require(cliProviders(settings: settings).first { $0.id == id })
        let data = Data([1, 2, 3])
        let capture = Capture(content: .image(data), anchor: nil, sourceBundleID: nil)
        var text = ""
        for try await delta in provider.stream(AIRequest(question: "Describe it", capture: capture, model: "test-model")) { text += delta }
        #expect(text == "answer")
        #expect(try Data(contentsOf: fake.directory.appendingPathComponent("image")) == data)
        let cwd = try String(contentsOf: fake.directory.appendingPathComponent("cwd"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(!FileManager.default.fileExists(atPath: cwd))
        let prompt = try String(contentsOf: fake.directory.appendingPathComponent("prompt"), encoding: .utf8)
        #expect(prompt.contains("Describe it"))
        let arguments = try String(contentsOf: fake.directory.appendingPathComponent("args"), encoding: .utf8)
        #expect(arguments.contains("test-model"))
        #expect((arguments + prompt).contains(AIRequest.systemPrompt))
    }

    @Test(arguments: [ProviderID.claudeCLI, .codexCLI]) func textCaptureAndProcessFailure(id: ProviderID) async throws {
        let fake = try FakeCLI(script: """
        cat > "$(dirname "$0")/prompt"
        printf 'failed' >&2
        exit 9
        """)
        defer { fake.remove() }
        let settings = CLISettings()
        settings.save(AppSettings(claudePath: fake.executable, codexPath: fake.executable))
        let provider = try #require(cliProviders(settings: settings).first { $0.id == id })
        let request = AIRequest(question: "Explain", capture: Capture(content: .text("selection"), anchor: nil, sourceBundleID: nil), model: "test")
        await #expect(throws: ProviderError.processFailed(exitCode: 9, stderr: "failed")) {
            for try await _ in provider.stream(request) {}
        }
        let prompt = try String(contentsOf: fake.directory.appendingPathComponent("prompt"), encoding: .utf8)
        #expect(prompt.contains(request.userText))
    }

    @Test(arguments: [ProviderID.claudeCLI, .codexCLI]) func cancellationReachesProcessAndRemovesImage(id: ProviderID) async throws {
        let event = id == .claudeCLI
            ? #"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"ready"}}}"#
            : #"{"type":"item.completed","item":{"type":"agent_message","text":"ready"}}"#
        let fake = try FakeCLI(script: """
        record="$(dirname "$0")"
        echo $$ > "$record/pid"
        pwd > "$record/cwd"
        printf '%s\\n' '\(event)'
        exec /bin/sleep 30
        """)
        defer { fake.remove() }
        let settings = CLISettings()
        settings.save(AppSettings(claudePath: fake.executable, codexPath: fake.executable))
        let provider = try #require(cliProviders(settings: settings).first { $0.id == id })
        let capture = Capture(content: .image(Data([1])), anchor: nil, sourceBundleID: nil)
        let ready = AsyncStream<Void>.makeStream()
        let consumer = Task {
            for try await _ in provider.stream(AIRequest(question: "image", capture: capture, model: "test")) {
                ready.continuation.yield(())
            }
        }
        var iterator = ready.stream.makeAsyncIterator()
        _ = await iterator.next()
        ready.continuation.finish()
        let pidText = try String(contentsOf: fake.directory.appendingPathComponent("pid"), encoding: .utf8)
        let pid = try #require(Int32(pidText.trimmingCharacters(in: .whitespacesAndNewlines)))
        defer { if kill(pid, 0) == 0 { kill(pid, SIGKILL) } }
        let cwd = try String(contentsOf: fake.directory.appendingPathComponent("cwd"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        consumer.cancel()
        _ = await consumer.result
        let deadline = ContinuousClock.now.advanced(by: .seconds(4))
        while (kill(pid, 0) == 0 || FileManager.default.fileExists(atPath: cwd)), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(kill(pid, 0) == -1)
        #expect(!FileManager.default.fileExists(atPath: cwd))
    }
}
