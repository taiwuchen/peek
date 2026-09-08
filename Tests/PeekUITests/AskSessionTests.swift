import AppKit
import Foundation
import PeekCore
import Synchronization
import Testing
@testable import PeekUI

private struct Region: ScreenRegionCapturer {
    var capture = Capture(content: .image(Data([1, 2, 3])), anchor: nil, sourceBundleID: "test.app")
    func captureRegion() async throws -> Capture { capture }
}

private actor ControlledRegion: ScreenRegionCapturer {
    private var continuation: CheckedContinuation<Capture, Error>?
    var isWaiting: Bool { continuation != nil }
    func captureRegion() async throws -> Capture {
        try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func finish(_ result: Result<Capture, Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }
}

struct TestProvider: AIProvider {
    var id: ProviderID = .anthropicAPI
    var displayName: String = "Test"
    var supportsImages: Bool = true
    var respond: @Sendable (AIRequest) -> AsyncThrowingStream<String, Error> = { request in
        AsyncThrowingStream { continuation in
            continuation.yield("Answer: " + (request.messages.last?.text ?? ""))
            continuation.finish()
        }
    }
    func availability() async -> ProviderAvailability { .ready }
    func models() async throws -> [AIModel] { [AIModel(id: "test-model", displayName: "Test model")] }
    func stream(_ request: AIRequest) -> AsyncThrowingStream<String, Error> { respond(request) }
}

@MainActor
private func waitUntil(_ condition: () async -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(3)
    while !(await condition()) && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(1)) }
    #expect(await condition())
}

@MainActor
private func makeSession(provider: TestProvider = TestProvider(), region: any ScreenRegionCapturer = Region(),
                         settings: AppSettings = AppSettings()) -> AskSession {
    let defaults = UserDefaults(suiteName: "PeekUITests.\(UUID())")!
    let store = UserDefaultsSettingsStore(defaults: defaults)
    store.save(settings)
    return AskSession(regionCapturer: region, providers: [provider], settingsStore: store)
}

@Test @MainActor func captureAutomaticallySendsSelectedModeAndFollowUpsCarryHistory() async throws {
    let requests = Mutex<[AIRequest]>([])
    let mode = PromptMode(name: "Translate", prompt: "Translate this into French")
    let session = makeSession(provider: TestProvider(respond: { request in
        requests.withLock { $0.append(request) }
        return AsyncThrowingStream { $0.yield("Translated answer"); $0.finish() }
    }), settings: AppSettings(modes: [mode], selectedModeID: mode.id))
    session.beginCapture()
    try await waitUntil { !session.isBusy }
    #expect(session.messages.map(\.text) == [mode.prompt, "Translated answer"])
    #expect(session.messages.first?.captures == [Region().capture])
    let originalHistory = session.messages
    session.question = "What does the last word mean?"
    session.send()
    try await waitUntil { !session.isBusy }
    let sent = requests.withLock { $0 }
    #expect(sent.count == 2)
    #expect(Array(sent[1].messages.dropLast()) == originalHistory)
    #expect(sent[1].messages.last?.text == "What does the last word mean?")
    #expect(session.messages.count == 4)
    #expect(session.question.isEmpty)
}

@Test @MainActor func additionalScreenshotRetainsEarlierScreenshotAndAnswers() async throws {
    let requests = Mutex<[AIRequest]>([])
    let session = makeSession(provider: TestProvider(respond: { request in
        requests.withLock { $0.append(request) }
        return AsyncThrowingStream { $0.yield("Answer"); $0.finish() }
    }))
    session.beginCapture()
    try await waitUntil { !session.isBusy }
    let original = session.messages
    session.beginCapture()
    try await waitUntil { !session.isBusy }
    #expect(Array(session.messages.prefix(2)) == original)
    #expect(session.messages.flatMap(\.captures).count == 2)
    #expect(session.messages.count == 4)
    let sent = requests.withLock { $0 }
    #expect(sent.last?.messages.count == 3)
    #expect(sent.last?.messages.flatMap(\.captures).count == 2)
}

@Test @MainActor func streamingRejectsOverlappingSubmitsAndCapturesAndStopRetainsPartialAnswer() async throws {
    let (stream, continuation) = AsyncThrowingStream<String, Error>.makeStream()
    let cancelled = Mutex(false)
    continuation.onTermination = { reason in
        if case .cancelled = reason { cancelled.withLock { $0 = true } }
    }
    let session = makeSession(provider: TestProvider(respond: { _ in stream }))
    session.beginCapture()
    try await waitUntil { session.isStreaming }
    continuation.yield("First")
    try await waitUntil { session.messages.last?.text == "First" }
    session.question = "Follow up"
    session.send()
    session.beginCapture()
    #expect(session.messages.count == 2)
    #expect(session.question == "Follow up")
    session.stop()
    continuation.yield(" stale")
    try await waitUntil { cancelled.withLock { $0 } }
    #expect(session.messages.last?.text == "First")
    #expect(session.responseNotes[session.messages.last!.id] == "Stopped")
    #expect(session.canRetry)
    #expect(!session.isBusy)
}

@Test @MainActor func retryReplacesOnlyIncompleteAnswerWithoutDuplicatingUserTurn() async throws {
    let requests = Mutex<[AIRequest]>([])
    let session = makeSession(provider: TestProvider(respond: { request in
        let attempt = requests.withLock { $0.append(request); return $0.count }
        return AsyncThrowingStream {
            if attempt == 2 {
                $0.yield("Incomplete")
                $0.finish(throwing: ProviderError.http(status: 500, body: "failure"))
            } else {
                $0.yield("Complete")
                $0.finish()
            }
        }
    }))
    session.beginCapture()
    try await waitUntil { !session.isBusy }
    let original = session.messages
    session.question = "Follow up"
    session.send()
    try await waitUntil { !session.isBusy }
    #expect(session.canRetry)
    let failedID = try #require(session.messages.last?.id)
    #expect(session.responseNotes[failedID] == "Incomplete response")
    session.retry()
    try await waitUntil { !session.isBusy }
    let sent = requests.withLock { $0 }
    #expect(sent[1].messages == sent[2].messages)
    #expect(Array(session.messages.prefix(2)) == original)
    #expect(session.messages.count == 4)
    #expect(session.messages.last?.text == "Complete")
    #expect(session.messages.last?.id == failedID)
    #expect(session.responseNotes[failedID] == nil)
    #expect(!session.canRetry)
}

@Test @MainActor func cancelledAndFailedCapturesPreserveHistoryAndDraft() async throws {
    let region = ControlledRegion()
    let session = makeSession(region: region)
    session.beginCapture()
    try await waitUntil { await region.isWaiting }
    await region.finish(.success(Region().capture))
    try await waitUntil { !session.isBusy }
    let history = session.messages
    session.question = "Draft follow up"
    session.beginCapture()
    try await waitUntil { await region.isWaiting }
    await region.finish(.failure(CaptureError.cancelled))
    try await waitUntil { !session.isBusy }
    #expect(session.messages == history)
    #expect(session.message == nil)
    session.beginCapture()
    try await waitUntil { await region.isWaiting }
    await region.finish(.failure(CaptureError.screenRecordingPermissionDenied))
    try await waitUntil { !session.isBusy }
    #expect(session.messages == history)
    #expect(session.question == "Draft follow up")
    #expect(session.needsScreenRecordingPermission)
    #expect(session.message?.contains("Screen Recording") == true)
}

@Test @MainActor func cancelledInitialCaptureDoesNotPresentPanel() async throws {
    let region = ControlledRegion()
    let session = makeSession(region: region)
    var presented = false
    session.onPresent = { presented = true }
    session.beginCapture()
    try await waitUntil { await region.isWaiting }
    await region.finish(.failure(CaptureError.cancelled))
    try await waitUntil { !session.isBusy }
    #expect(!presented)
    #expect(session.messages.isEmpty)
    #expect(session.message == nil)
}

@Test @MainActor func cancelStopsStreamKeepsPartialAnswerAndIgnoresLateDeltas() async throws {
    let (stream, continuation) = AsyncThrowingStream<String, Error>.makeStream()
    let cancelled = Mutex(false)
    continuation.onTermination = { reason in
        if case .cancelled = reason { cancelled.withLock { $0 = true } }
    }
    let session = makeSession(provider: TestProvider(respond: { _ in stream }))
    session.beginCapture()
    try await waitUntil { session.isStreaming }
    continuation.yield("Old answer")
    try await waitUntil { session.messages.count == 2 }
    session.cancel()
    #expect(!session.isBusy)
    continuation.yield(" stale")
    try await waitUntil { cancelled.withLock { $0 } }
    try await Task.sleep(for: .milliseconds(10))
    #expect(session.messages.last?.text == "Old answer")
}

@Test @MainActor func cancelAndStopIgnoreCaptureThatCompletesAfterCancellation() async throws {
    for cancel in [false, true] {
        let region = ControlledRegion()
        let session = makeSession(region: region)
        var presented = false
        session.onPresent = { presented = true }
        session.beginCapture()
        try await waitUntil { await region.isWaiting }
        if cancel { session.cancel() } else { session.stop() }
        await region.finish(.success(Region().capture))
        try await Task.sleep(for: .milliseconds(10))
        #expect(session.messages.isEmpty)
        #expect(!session.isBusy)
        #expect(!presented)
    }
}

@Test @MainActor func modeSelectionPersistsAndReloadsSettingsBeforeCapture() async throws {
    let defaults = UserDefaults(suiteName: "PeekUIModes.\(UUID())")!
    let store = UserDefaultsSettingsStore(defaults: defaults)
    let explain = PromptMode(name: "Explain", prompt: "Explain this")
    let translate = PromptMode(name: "Translate", prompt: "Translate this")
    store.save(AppSettings(modes: [explain, translate], selectedModeID: explain.id))
    let session = AskSession(regionCapturer: Region(), providers: [TestProvider()], settingsStore: store)
    session.selectMode(translate.id)
    #expect(store.load().selectedModeID == translate.id)
    var settings = store.load()
    settings.modes[1].prompt = "Translate into French"
    store.save(settings)
    session.beginCapture()
    try await waitUntil { !session.isBusy }
    #expect(session.messages.first?.text == "Translate into French")
    #expect(session.modes[1].prompt == "Translate into French")
}

@Test @MainActor func missingModeShowsSettingsActionWithoutCapturing() {
    let session = makeSession(settings: AppSettings(modes: []))
    session.beginCapture()
    #expect(!session.isBusy)
    #expect(session.messages.isEmpty)
    #expect(session.message?.contains("Add a mode") == true)
}

@Test @MainActor func panelPersistsOnEscapeAndDeactivationAndPreservesPosition() async throws {
    let session = makeSession()
    session.beginCapture()
    try await waitUntil { !session.isBusy }
    let history = session.messages
    let panel = AnswerPanel(session: session, openSettings: {})
    var closed = 0
    panel.onClose = { closed += 1 }
    defer { panel.close() }
    #expect(!panel.styleMask.contains(.titled))
    #expect(panel.standardWindowButton(.closeButton) == nil)
    #expect(panel.styleMask.contains(.resizable))
    #expect(!panel.hidesOnDeactivate)
    panel.present(anchor: nil)
    panel.setFrameOrigin(CGPoint(x: 70, y: 80))
    let movedFrame = panel.frame
    panel.cancelOperation(nil)
    panel.resignKey()
    #expect(panel.isVisible)
    #expect(session.messages == history)
    panel.present(anchor: CGRect(x: 900, y: 500, width: 100, height: 100))
    #expect(panel.frame == movedFrame)
    panel.close()
    #expect(!panel.isVisible)
    #expect(closed == 1)
    #expect(session.messages == history)
}

@Test @MainActor func eachCaptureOpensItsOwnWindowAndCancelledCapturesLeaveNone() async throws {
    let region = ControlledRegion()
    let defaults = UserDefaults(suiteName: "PeekUIController.\(UUID())")!
    let store = UserDefaultsSettingsStore(defaults: defaults)
    store.save(AppSettings())
    let continuations = Mutex<[AsyncThrowingStream<String, Error>.Continuation]>([])
    let controller = AppController(regionCapturer: region, providers: [TestProvider(respond: { _ in
        AsyncThrowingStream { continuation in continuations.withLock { $0.append(continuation) } }
    })], settingsStore: store, credentials: InMemoryCredentialStore())
    defer { controller.conversations.forEach { $0.close() } }
    controller.askRegion()
    controller.askRegion()
    #expect(controller.conversations.count == 1)
    try await waitUntil { await region.isWaiting }
    await region.finish(.failure(CaptureError.cancelled))
    try await waitUntil { controller.conversations.isEmpty }

    controller.askRegion()
    try await waitUntil { await region.isWaiting }
    await region.finish(.success(Region().capture))
    let first = try #require(controller.conversations.first)
    try await waitUntil { first.isVisible && first.session.isStreaming }

    controller.askRegion()
    #expect(controller.conversations.count == 2)
    try await waitUntil { await region.isWaiting }
    await region.finish(.success(Region().capture))
    let second = try #require(controller.conversations.last)
    try await waitUntil { second.isVisible }
    #expect(second !== first)
    #expect(second.session !== first.session)
    #expect(first.session.isStreaming)

    first.close()
    #expect(controller.conversations == [second])
    continuations.withLock { $0.forEach { $0.finish() } }
}

@Test @MainActor func importedScreenshotsAutomaticallyUseModeAndPreserveHistoryAndDraft() async throws {
    let requests = Mutex<[AIRequest]>([])
    let mode = PromptMode(name: "Translate", prompt: "Translate this into French")
    let session = makeSession(provider: TestProvider(respond: { request in
        requests.withLock { $0.append(request) }
        return AsyncThrowingStream { $0.yield("Translated answer"); $0.finish() }
    }), settings: AppSettings(modes: [mode], selectedModeID: mode.id))
    session.beginCapture()
    try await waitUntil { !session.isBusy }
    let history = session.messages
    session.question = "My next question"
    let images = [Data([4, 5, 6]), Data([7, 8, 9])]
    session.addScreenshots(images)
    try await waitUntil { !session.isBusy }
    #expect(Array(session.messages.prefix(2)) == history)
    #expect(session.messages.count == 4)
    #expect(session.messages[2].text == mode.prompt)
    #expect(session.messages[2].captures.map(\.content) == images.map(Capture.Content.image))
    #expect(session.question == "My next question")
    let sent = requests.withLock { $0 }
    #expect(sent.count == 2)
    #expect(sent[1].messages.flatMap(\.captures).count == 3)
    #expect(sent[1].messages.last?.text == mode.prompt)
}

@Test @MainActor func screenshotImportRejectsBusyOrInvalidModeWithoutDiscardingConversation() async throws {
    let (stream, continuation) = AsyncThrowingStream<String, Error>.makeStream()
    defer { continuation.finish() }
    let session = makeSession(provider: TestProvider(respond: { _ in stream }))
    session.addScreenshots([Data([1])])
    try await waitUntil { session.isStreaming }
    let history = session.messages
    session.addScreenshots([Data([2])])
    #expect(session.messages == history)
    #expect(session.message?.contains("Stop") == true)
    #expect(session.isStreaming)
    session.stop()
    let invalid = makeSession(settings: AppSettings(modes: []))
    invalid.addScreenshots([Data([1])])
    #expect(invalid.messages.isEmpty)
    #expect(!invalid.isBusy)
    #expect(invalid.message?.contains("name and prompt") == true)
}

@Test @MainActor func blankModeCannotCapture() {
    for mode in [PromptMode(name: " ", prompt: "Explain"), PromptMode(name: "Explain", prompt: " ")] {
        let session = makeSession(settings: AppSettings(modes: [mode], selectedModeID: mode.id))
        session.beginCapture()
        #expect(!session.isBusy)
        #expect(session.messages.isEmpty)
        #expect(session.message?.contains("name and prompt") == true)
    }
}

@Test @MainActor func zeroDeltaFailureDoesNotSendEmptyAssistantInNextRequest() async throws {
    let requests = Mutex<[AIRequest]>([])
    let session = makeSession(provider: TestProvider(respond: { request in
        requests.withLock { $0.append(request) }
        return AsyncThrowingStream { $0.finish(throwing: ProviderError.malformedResponse("Empty")) }
    }))
    session.beginCapture()
    try await waitUntil { !session.isBusy }
    #expect(session.messages.count == 1)
    session.question = "Follow up"
    session.send()
    try await waitUntil { !session.isBusy }
    let sent = requests.withLock { $0 }
    #expect(sent.count == 2)
    #expect(sent[1].messages.count == 2)
    #expect(sent[1].messages.allSatisfy { $0.role == .user })
    #expect(sent[1].messages.first?.captures == [Region().capture])
}
