import CoreText
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

    @Test(arguments: [ProviderID.claudeCLI, .codexCLI]) func conversationUsesPrivateImagesAndCleansUp(id: ProviderID) async throws {
        let event = id == .claudeCLI
            ? #"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"answer"}}}"#
            : #"{"type":"item.completed","item":{"type":"agent_message","text":"answer"}}"#
        let fake = try FakeCLI(script: """
        record="$(dirname "$0")"
        pwd > "$record/cwd"
        printf '%s\\n' "$@" > "$record/args"
        cat > "$record/prompt"
        stat -f '%Lp' . > "$record/directory-mode"
        for image in *.png; do
            cat "$image" > "$record/$image"
            stat -f '%Lp' "$image" >> "$record/image-modes"
        done
        printf '%s\\n' '\(event)'
        """)
        defer { fake.remove() }
        let settings = CLISettings()
        settings.save(AppSettings(claudePath: fake.executable, codexPath: fake.executable))
        let provider = try #require(cliProviders(settings: settings).first { $0.id == id })
        let conversation = ConversationFixture()
        var text = ""
        for try await delta in provider.stream(conversation.request) { text += delta }
        #expect(text == "answer")
        let names = ["turn-1-capture-1.png", "turn-5-capture-1.png", "turn-5-capture-2.png"]
        for (index, name) in names.enumerated() {
            #expect(try Data(contentsOf: fake.directory.appendingPathComponent(name)) == conversation.images[index])
        }
        let cwd = try record("cwd", from: fake).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(!FileManager.default.fileExists(atPath: cwd))
        #expect(try record("directory-mode", from: fake) == "700\n")
        #expect(try record("image-modes", from: fake) == "600\n600\n600\n")
        let prompt = try record("prompt", from: fake)
        let json = try #require(prompt.components(separatedBy: "Conversation JSON:\n").last)
        let messages = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]])
        #expect(messages.compactMap { $0["role"] as? String } == ["user", "assistant", "user", "assistant", "user"])
        #expect(messages.compactMap { $0["text"] as? String } == conversation.texts)
        let paths = names.map { canonicalScreenshotPath(URL(fileURLWithPath: cwd).appendingPathComponent($0).path) }
        let expectedScreenshots: [[[String: Any]]] = [
            [["attachment": 1, "path": paths[0]]], [], [], [],
            [["attachment": 2, "path": paths[1]], ["attachment": 3, "path": paths[2]]],
        ]
        try #require(messages.count == expectedScreenshots.count)
        for (index, message) in messages.enumerated() {
            var screenshots = try #require(message["screenshots"] as? [[String: Any]])
            for index in screenshots.indices {
                let path = try #require(screenshots[index]["path"] as? String)
                screenshots[index]["path"] = canonicalScreenshotPath(path)
            }
            #expect(NSArray(array: screenshots).isEqual(to: expectedScreenshots[index]))
        }
        let arguments = try record("args", from: fake).components(separatedBy: "\n")
        #expect(arguments.contains("test-model"))
        #expect((arguments.joined(separator: "\n") + prompt).contains(AIRequest.systemPrompt))
        #expect(!arguments.contains("resume"))
        #expect(!arguments.contains("--resume"))
        #expect(!arguments.contains("--continue"))
        if id == .codexCLI {
            let attached = arguments.indices.filter { arguments[$0] == "-i" }.map {
                canonicalScreenshotPath(arguments[$0 + 1])
            }
            #expect(attached == paths)
            #expect(arguments.contains("--ephemeral"))
            #expect(arguments.contains("--ignore-user-config"))
        } else {
            #expect(arguments.contains("--no-session-persistence"))
            #expect(arguments.contains("--safe-mode"))
            #expect(arguments.contains("Read"))
            #expect(prompt.contains("View the screenshot and PDF files"))
        }
    }

    @Test func claudeOmitsSafeModeWhenToggleIsOff() async throws {
        let fake = try FakeCLI(script: """
        printf '%s\\n' "$@" > "$(dirname "$0")/args"
        cat > /dev/null
        """)
        defer { fake.remove() }
        let settings = CLISettings()
        settings.save(AppSettings(claudePath: fake.executable, claudeIgnoresInstructions: false))
        let request = AIRequest(messages: [AIMessage(role: .user, text: "Explain")], model: "test")
        for try await _ in ClaudeCLIProvider(settings: settings).stream(request) {}
        #expect(!(try record("args", from: fake).components(separatedBy: "\n").contains("--safe-mode")))
    }

    @Test(arguments: [ProviderID.claudeCLI, .codexCLI]) func pdfAndTextFilesReachTheCLI(id: ProviderID) async throws {
        let fake = try FakeCLI(script: """
        record="$(dirname "$0")"
        printf '%s\\n' "$@" > "$record/args"
        cat > "$record/prompt"
        for pdf in *.pdf; do [ -f "$pdf" ] && cat "$pdf" > "$record/$pdf"; done
        exit 0
        """)
        defer { fake.remove() }
        let settings = CLISettings()
        settings.save(AppSettings(claudePath: fake.executable, codexPath: fake.executable))
        let provider = try #require(cliProviders(settings: settings).first { $0.id == id })
        let pdf = pdfData(text: "Quarterly total 42")
        let captures = [Capture(content: .pdf(name: "report.pdf", data: pdf), anchor: nil, sourceBundleID: nil),
                        Capture(content: .text(name: "notes.txt", text: "Line one"), anchor: nil, sourceBundleID: nil)]
        let request = AIRequest(messages: [AIMessage(role: .user, text: "Explain this", captures: captures)], model: "test")
        for try await _ in provider.stream(request) {}
        let prompt = try record("prompt", from: fake)
        let json = try #require(prompt.components(separatedBy: "Conversation JSON:\n").last)
        let messages = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]])
        let files = try #require(messages.first?["files"] as? [[String: String]])
        try #require(files.count == 2)
        #expect(files[0]["name"] == "report.pdf")
        #expect(files[1] == ["name": "notes.txt", "text": "Line one"])
        let arguments = try record("args", from: fake).components(separatedBy: "\n")
        if id == .claudeCLI {
            #expect(try Data(contentsOf: fake.directory.appendingPathComponent("turn-1-file-1.pdf")) == pdf)
            #expect(files[0]["path"]?.hasSuffix("turn-1-file-1.pdf") == true)
            #expect(arguments.contains("Read"))
        } else {
            #expect(files[0]["text"]?.contains("Quarterly total 42") == true)
            #expect(files[0]["path"] == nil)
            #expect(!arguments.contains("-i"))
        }
    }

    private func pdfData(text: String) -> Data {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 300, height: 100)
        let context = CGContext(consumer: CGDataConsumer(data: data)!, mediaBox: &box, nil)!
        context.beginPDFPage(nil)
        let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
        context.textPosition = CGPoint(x: 10, y: 50)
        CTLineDraw(line, context)
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    private func record(_ name: String, from fake: FakeCLI) throws -> String {
        try String(contentsOf: fake.directory.appendingPathComponent(name), encoding: .utf8)
    }

    private func canonicalScreenshotPath(_ path: String) -> String {
        let image = URL(fileURLWithPath: path)
        let directory = image.deletingLastPathComponent()
        // Resolve the existing parent because the request directory has already been removed.
        return directory.deletingLastPathComponent().resolvingSymlinksInPath()
            .appendingPathComponent(directory.lastPathComponent).appendingPathComponent(image.lastPathComponent).path
    }

    @Test(arguments: [ProviderID.claudeCLI, .codexCLI], [false, true]) func conversationAndProcessFailureCleansUp(id: ProviderID, images: Bool) async throws {
        let fake = try FakeCLI(script: """
        record="$(dirname "$0")"
        pwd > "$record/cwd"
        printf '%s\\n' "$@" > "$record/args"
        cat > "$record/prompt"
        printf 'failed' >&2
        exit 9
        """)
        defer { fake.remove() }
        let settings = CLISettings()
        settings.save(AppSettings(claudePath: fake.executable, codexPath: fake.executable))
        let provider = try #require(cliProviders(settings: settings).first { $0.id == id })
        let request = images ? ConversationFixture().request : AIRequest(messages: [AIMessage(role: .user, text: "Explain")], model: "test")
        await #expect(throws: ProviderError.processFailed(exitCode: 9, stderr: "failed")) {
            for try await _ in provider.stream(request) {}
        }
        let prompt = try String(contentsOf: fake.directory.appendingPathComponent("prompt"), encoding: .utf8)
        let cwd = try record("cwd", from: fake).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(!FileManager.default.fileExists(atPath: cwd))
        let json = try #require(prompt.components(separatedBy: "Conversation JSON:\n").last)
        let messages = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]])
        #expect(messages.compactMap { $0["text"] as? String } == request.messages.map(\.text))
        if !images {
            let arguments = try record("args", from: fake).components(separatedBy: "\n")
            #expect(!arguments.contains("-i"))
            #expect(!arguments.contains("Read"))
        }
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
        let ready = AsyncStream<Void>.makeStream()
        let consumer = Task {
            for try await _ in provider.stream(ConversationFixture().request) {
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
