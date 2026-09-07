import Foundation
import PeekCore
import Testing
@testable import PeekUI

private struct Reader: SelectionReader {
    var error: CaptureError?
    func readSelection() async throws -> Capture {
        if let error { throw error }
        return Capture(content: .text("Selected text"), anchor: nil, sourceBundleID: "test.app")
    }
}

private struct Region: ScreenRegionCapturer {
    var error: CaptureError = .cancelled
    func captureRegion() async throws -> Capture { throw error }
}

struct TestProvider: AIProvider {
    var id: ProviderID = .anthropicAPI
    var displayName: String = "Test"
    var supportsImages: Bool = true
    var respond: @Sendable (AIRequest) -> AsyncThrowingStream<String, Error> = { request in
        AsyncThrowingStream { continuation in
            for word in request.question.split(separator: " ") { continuation.yield(String(word) + " ") }
            continuation.finish()
        }
    }
    func availability() async -> ProviderAvailability { .ready }
    func models() async throws -> [AIModel] { [AIModel(id: "test-model", displayName: "Test model")] }
    func stream(_ request: AIRequest) -> AsyncThrowingStream<String, Error> { respond(request) }
}

@MainActor
private func waitUntil(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(3)
    while !condition() && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(1)) }
    #expect(condition())
}

@MainActor
private func makeSession(provider: TestProvider = TestProvider(), error: CaptureError? = nil,
                         regionError: CaptureError = .cancelled) -> AskSession {
    let defaults = UserDefaults(suiteName: "PeekUITests.\(UUID())")!
    return AskSession(selectionReader: Reader(error: error), regionCapturer: Region(error: regionError),
                      providers: [provider], settingsStore: UserDefaultsSettingsStore(defaults: defaults))
}

@Test @MainActor func accumulatesDeltasAndKeepsCaptureForFollowUp() async throws {
    let session = makeSession()
    session.begin(.selection)
    try await waitUntil { session.answer == "Explain this " && !session.isStreaming }
    #expect(session.capture?.content == .text("Selected text"))
    session.question = "Follow up"
    session.send()
    try await waitUntil { session.answer == "Follow up " && !session.isStreaming }
    #expect(session.capture?.sourceBundleID == "test.app")
}

@Test @MainActor func showsStreamingDeltasBeforeCompletion() async throws {
    let (stream, continuation) = AsyncThrowingStream<String, Error>.makeStream()
    let session = makeSession(provider: TestProvider(respond: { _ in stream }))
    session.begin(.selection)
    try await waitUntil { session.isStreaming }
    continuation.yield("First")
    try await waitUntil { session.answer == "First" }
    #expect(session.isStreaming)
    continuation.yield(" second")
    continuation.finish()
    try await waitUntil { !session.isStreaming }
    #expect(session.answer == "First second")
}

@Test @MainActor func replacesAndCancelsOldStreamOnNewQuestion() async throws {
    let (oldStream, oldContinuation) = AsyncThrowingStream<String, Error>.makeStream()
    let (newStream, newContinuation) = AsyncThrowingStream<String, Error>.makeStream()
    let (terminated, termination) = AsyncStream<Bool>.makeStream()
    oldContinuation.onTermination = { reason in
        if case .cancelled = reason { termination.yield(true) }
        termination.finish()
    }
    let session = makeSession(provider: TestProvider(respond: { request in
        request.question == "Explain this" ? oldStream : newStream
    }))
    session.begin(.selection)
    oldContinuation.yield("Old answer")
    try await waitUntil { session.answer == "Old answer" }
    session.question = "New question"
    session.send()
    newContinuation.yield("New answer")
    newContinuation.finish()
    oldContinuation.yield(" stale delta")
    try await waitUntil { session.answer == "New answer" && !session.isStreaming }
    var iterator = terminated.makeAsyncIterator()
    #expect(await iterator.next() == true)
    #expect(session.answer == "New answer")
}

@Test @MainActor func providerErrorsSurfaceInline() async throws {
    let session = makeSession(provider: TestProvider(respond: { _ in
        AsyncThrowingStream { $0.finish(throwing: ProviderError.notAvailable(.needsAPIKey)) }
    }))
    session.begin(.selection)
    try await waitUntil { session.message != nil }
    #expect(session.message?.contains("Settings") == true)
    #expect(!session.isStreaming)
}

@Test @MainActor func capturePermissionErrorsPresentMatchingAction() async throws {
    let session = makeSession(error: .accessibilityPermissionDenied)
    var presented = false
    session.onPresent = { presented = true }
    session.begin(.selection)
    try await waitUntil { presented }
    #expect(session.permission == .accessibility)
    #expect(session.capture == nil)
    let region = makeSession(regionError: .screenRecordingPermissionDenied)
    region.begin(.region)
    try await waitUntil { region.permission == .screenRecording }
}

@Test @MainActor func noSelectionPresentsHelpfulMessage() async throws {
    let session = makeSession(error: .noSelection)
    session.begin(.selection)
    try await waitUntil { session.message != nil }
    #expect(session.message == "Select some text, then ask Peek again.")
}

@Test @MainActor func cancelledCaptureDoesNotPresentPanel() async throws {
    let session = makeSession()
    var presented = false
    session.onPresent = { presented = true }
    session.begin(.region)
    try await Task.sleep(for: .milliseconds(30))
    #expect(!presented)
    #expect(session.message == nil)
    #expect(session.capture == nil)
}

@Test @MainActor func providerSwitchLoadsItsModelWithoutSavingSessionChoice() async throws {
    let session = makeSession()
    session.selectProvider(.anthropicAPI)
    try await waitUntil { session.model == "test-model" }
    #expect(session.message == nil)
}
