import Foundation
import Observation
import PeekCore

@MainActor @Observable
final class AskSession {
    enum CaptureKind { case selection, region }
    enum Permission: String { case accessibility, screenRecording }

    let providers: [any AIProvider]
    var question = "Explain this"
    private(set) var capture: Capture?
    private(set) var answer = ""
    private(set) var message: String?
    private(set) var permission: Permission?
    private(set) var isStreaming = false
    private(set) var providerID: ProviderID
    private(set) var model: String
    var onPresent: (() -> Void)?
    @ObservationIgnored private let selectionReader: any SelectionReader
    @ObservationIgnored private let regionCapturer: any ScreenRegionCapturer
    @ObservationIgnored private let settingsStore: any SettingsStore
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()

    init(selectionReader: any SelectionReader, regionCapturer: any ScreenRegionCapturer,
         providers: [any AIProvider], settingsStore: any SettingsStore) {
        self.selectionReader = selectionReader
        self.regionCapturer = regionCapturer
        self.providers = providers
        self.settingsStore = settingsStore
        let settings = settingsStore.load()
        providerID = settings.provider
        model = settings.model
    }

    func begin(_ kind: CaptureKind) {
        cancel()
        let token = generation
        capture = nil
        answer = ""
        message = nil
        permission = nil
        let settings = settingsStore.load()
        question = settings.defaultQuestion
        providerID = settings.provider
        model = settings.model
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let result: Capture
                switch kind {
                case .selection: result = try await selectionReader.readSelection()
                case .region: result = try await regionCapturer.captureRegion()
                }
                guard generation == token, !Task.isCancelled else { return }
                capture = result
                onPresent?()
                await stream(token: token)
            } catch {
                guard generation == token, !Task.isCancelled else { return }
                switch error {
                case CaptureError.cancelled, is CancellationError: return
                case CaptureError.accessibilityPermissionDenied:
                    permission = .accessibility
                    message = "Allow Accessibility access so Peek can read selected text."
                case CaptureError.screenRecordingPermissionDenied:
                    permission = .screenRecording
                    message = "Allow Screen Recording access so Peek can capture a screen region."
                case CaptureError.noSelection: message = "Select some text, then ask Peek again."
                case CaptureError.failed(let detail): message = detail
                default: message = error.localizedDescription
                }
                onPresent?()
            }
        }
    }

    func send() {
        guard capture != nil, !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        cancel()
        let token = generation
        task = Task { [weak self] in await self?.stream(token: token) }
    }

    func selectProvider(_ id: ProviderID) {
        cancel()
        providerID = id
        model = ""
        answer = ""
        message = nil
        let token = generation
        task = Task { [weak self] in
            guard let self, let provider = providers.first(where: { $0.id == id }) else { return }
            do {
                let models = try await provider.models()
                guard generation == token, !Task.isCancelled else { return }
                guard let first = models.first else {
                    message = "No models available. Configure this provider in Settings."
                    return
                }
                model = first.id
            } catch {
                guard generation == token, !Task.isCancelled else { return }
                message = providerErrorMessage(error)
            }
        }
    }

    func cancel() {
        generation = UUID()
        task?.cancel()
        task = nil
        isStreaming = false
    }

    private func stream(token: UUID) async {
        answer = ""
        message = nil
        guard let provider = providers.first(where: { $0.id == providerID }), !model.isEmpty else {
            message = "Choose and configure a provider in Settings."
            return
        }
        isStreaming = true
        defer { if generation == token { isStreaming = false } }
        do {
            for try await delta in provider.stream(AIRequest(question: question, capture: capture, model: model)) {
                guard generation == token, !Task.isCancelled else { return }
                answer += delta
            }
        } catch {
            guard generation == token, !Task.isCancelled else { return }
            if error is CancellationError || (error as? ProviderError) == .cancelled { return }
            message = providerErrorMessage(error)
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
