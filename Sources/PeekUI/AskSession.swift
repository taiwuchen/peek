import Foundation
import Observation
import PeekCore

@MainActor @Observable
final class AskSession {
    let providers: [any AIProvider]
    var question = ""
    private(set) var messages: [AIMessage] = []
    private(set) var responseNotes: [UUID: String] = [:]
    private(set) var message: String?
    private(set) var needsScreenRecordingPermission = false
    private(set) var isStreaming = false
    private(set) var isCapturing = false
    private(set) var providerID: ProviderID
    private(set) var model: String
    private(set) var modes: [PromptMode]
    private(set) var selectedModeID: UUID?
    var onPresent: (() -> Void)?
    var onSettingsChange: (() -> Void)?
    @ObservationIgnored private let regionCapturer: any ScreenRegionCapturer
    @ObservationIgnored private let settingsStore: any SettingsStore
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    private var retryUserID: UUID?
    private var responseID: UUID?

    var isBusy: Bool { isCapturing || isStreaming }
    var canRetry: Bool { retryUserID != nil && !isBusy }
    var canSend: Bool { !isBusy && !messages.isEmpty && !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var latestCapture: Capture? { messages.last(where: { !$0.captures.isEmpty })?.captures.last }

    init(regionCapturer: any ScreenRegionCapturer, providers: [any AIProvider], settingsStore: any SettingsStore) {
        self.regionCapturer = regionCapturer
        self.providers = providers
        self.settingsStore = settingsStore
        let settings = settingsStore.load()
        providerID = settings.provider
        model = settings.model
        modes = settings.modes
        selectedModeID = settings.selectedMode?.id
    }

    func refreshSettings() {
        let settings = settingsStore.load()
        modes = settings.modes
        selectedModeID = settings.selectedMode?.id
        guard !isBusy else { return }
        providerID = settings.provider
        model = settings.model
    }

    func selectMode(_ id: UUID?) {
        guard !isBusy else { return }
        var settings = settingsStore.load()
        guard settings.modes.contains(where: { $0.id == id }) else { return }
        settings.selectedModeID = id
        settingsStore.save(settings)
        refreshSettings()
        onSettingsChange?()
    }

    func beginCapture() {
        guard !isBusy else { return }
        guard let prompt = screenshotPrompt() else { return }
        let token = UUID()
        generation = token
        isCapturing = true
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let capture = try await regionCapturer.captureRegion()
                guard generation == token, !Task.isCancelled else { return }
                isCapturing = false
                appendScreenshots([capture], prompt: prompt)
                onPresent?()
                await stream(token: token)
            } catch {
                guard generation == token, !Task.isCancelled else { return }
                isCapturing = false
                task = nil
                switch error {
                case CaptureError.cancelled, is CancellationError: return
                case CaptureError.screenRecordingPermissionDenied:
                    needsScreenRecordingPermission = true
                    message = "Allow Screen Recording access so Peek can capture a screen region."
                case CaptureError.failed(let detail):
                    needsScreenRecordingPermission = false
                    message = detail
                default:
                    needsScreenRecordingPermission = false
                    message = error.localizedDescription
                }
                onPresent?()
            }
        }
    }

    func addScreenshots(_ pngImages: [Data]) {
        guard !pngImages.isEmpty else { return }
        guard !isBusy else {
            reportInputError("Stop the current response before adding a screenshot.")
            return
        }
        guard let prompt = screenshotPrompt() else { return }
        let captures = pngImages.map { Capture(content: .image($0), anchor: nil, sourceBundleID: nil) }
        appendScreenshots(captures, prompt: prompt)
        startResponse()
        onPresent?()
    }

    func reportInputError(_ text: String) {
        message = text
        needsScreenRecordingPermission = false
    }

    private func screenshotPrompt() -> String? {
        refreshSettings()
        guard let mode = modes.first(where: { $0.id == selectedModeID }),
              !mode.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !mode.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            reportInputError("Add a mode with a name and prompt in Settings before capturing a screenshot.")
            onPresent?()
            return nil
        }
        return mode.prompt
    }

    private func appendScreenshots(_ captures: [Capture], prompt: String) {
        messages.append(AIMessage(role: .user, text: prompt, captures: captures))
        retryUserID = messages.last?.id
        responseID = nil
        message = nil
        needsScreenRecordingPermission = false
    }

    func send() {
        guard canSend else { return }
        refreshSettings()
        messages.append(AIMessage(role: .user, text: question.trimmingCharacters(in: .whitespacesAndNewlines)))
        question = ""
        retryUserID = messages.last?.id
        responseID = nil
        startResponse()
    }

    func retry() {
        guard canRetry else { return }
        refreshSettings()
        startResponse()
    }

    func stop() {
        guard isBusy else { return }
        let wasStreaming = isStreaming
        invalidateOperation()
        if wasStreaming {
            message = "Response stopped."
            if let responseID { responseNotes[responseID] = "Stopped" }
        }
    }

    func close() {
        invalidateOperation()
        messages = []
        responseNotes = [:]
        question = ""
        message = nil
        needsScreenRecordingPermission = false
        retryUserID = nil
        responseID = nil
    }

    private func invalidateOperation() {
        generation = UUID()
        task?.cancel()
        task = nil
        isStreaming = false
        isCapturing = false
    }

    private func startResponse() {
        let token = UUID()
        generation = token
        isStreaming = true
        task = Task { [weak self] in await self?.stream(token: token) }
    }

    private func stream(token: UUID) async {
        guard generation == token, !Task.isCancelled,
              let userIndex = messages.firstIndex(where: { $0.id == retryUserID }) else { return }
        isStreaming = true
        message = nil
        needsScreenRecordingPermission = false
        defer {
            if generation == token {
                isStreaming = false
                task = nil
            }
        }
        guard let provider = providers.first(where: { $0.id == providerID }), !model.isEmpty else {
            message = "Choose and configure a provider in Settings."
            return
        }
        let request = AIRequest(messages: Array(messages[...userIndex]), model: model)
        let assistantID = responseID ?? UUID()
        responseID = assistantID
        messages.removeAll { $0.id == assistantID }
        responseNotes[assistantID] = nil
        do {
            for try await delta in provider.stream(request) {
                guard generation == token, !Task.isCancelled else { return }
                if let index = messages.firstIndex(where: { $0.id == assistantID }) {
                    messages[index].text += delta
                } else if !delta.isEmpty {
                    messages.append(AIMessage(id: assistantID, role: .assistant, text: delta))
                }
            }
            guard generation == token, !Task.isCancelled else { return }
            retryUserID = nil
            responseID = nil
        } catch {
            guard generation == token, !Task.isCancelled else { return }
            if error is CancellationError || (error as? ProviderError) == .cancelled {
                message = "Response stopped."
                responseNotes[assistantID] = "Stopped"
            } else {
                message = providerErrorMessage(error)
                responseNotes[assistantID] = "Incomplete response"
            }
        }
    }
}

func providerErrorMessage(_ error: any Error) -> String {
    switch error {
    case ProviderError.notAvailable: "This provider is not available. Configure it in Settings."
    case ProviderError.imagesNotSupported: "This provider cannot read images. Choose another provider."
    case ProviderError.http(let status, _): "The provider returned an HTTP \(status) error. Try again or check Settings."
    case ProviderError.processFailed(let code, _): "The provider CLI exited with code \(code). Check its installation and login in Settings."
    case ProviderError.malformedResponse: "The provider returned an unreadable response. Please try again."
    default: error.localizedDescription
    }
}
