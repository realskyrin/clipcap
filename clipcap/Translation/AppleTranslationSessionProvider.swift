import AppKit
import Foundation

/// Narrow interface used by the AppKit translation panel. The concrete bridge
/// is isolated below because macOS 15-25 only vend TranslationSession through a
/// SwiftUI view modifier; no public AppKit session initializer exists there.
@MainActor
protocol AppleTranslationSessionProviding: AnyObject {
    var hostView: NSView { get }
    func translate(text: String, target: TranslationLanguage) async throws -> String
    func cancel()
}

@MainActor
enum AppleTranslationSessionProviderFactory {
    static func makeProvider() -> AppleTranslationSessionProviding? {
#if canImport(Translation) && canImport(SwiftUI)
        guard #available(macOS 15.0, *) else { return nil }
        return AppleTranslationSessionProvider()
#else
        return nil
#endif
    }
}

#if canImport(Translation) && canImport(SwiftUI)
import SwiftUI
import Translation

@available(macOS 15.0, *)
@MainActor
private final class AppleTranslationSessionProvider: AppleTranslationSessionProviding {
    private let model = AppleTranslationBridgeModel()

    lazy var hostView: NSView = {
        NSHostingView(rootView: AppleTranslationBridgeView(model: model))
    }()

    func translate(text: String, target: TranslationLanguage) async throws -> String {
        try await model.translate(text: text, target: target)
    }

    func cancel() {
        model.cancel()
    }
}

@available(macOS 15.0, *)
@MainActor
private final class AppleTranslationBridgeModel: ObservableObject {
    @Published var configuration: TranslationSession.Configuration?

    private struct PendingRequest {
        let id: UUID
        let text: String
        let continuation: CheckedContinuation<String, Error>
    }

    private var pendingRequest: PendingRequest?

    func translate(text: String, target: TranslationLanguage) async throws -> String {
        try Task.checkCancellation()
        // Never ask the system to download models: only installed language pairs
        // may proceed to a session, keeping image text entirely on device
        let availability: LanguageAvailability
        if #available(macOS 26.4, *) {
            availability = LanguageAvailability(preferredStrategy: .lowLatency)
        } else {
            availability = LanguageAvailability()
        }
        let status = try await availability.status(for: text, to: Locale.Language(identifier: target.localeIdentifier))
        switch status {
        case .installed: break
        case .supported: throw OfflineTranslationError.modelsMissing
        case .unsupported: throw OfflineTranslationError.unsupported
        @unknown default: throw OfflineTranslationError.unsupported
        }
        try Task.checkCancellation()
        let requestID = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pendingRequest?.continuation.resume(throwing: CancellationError())
                pendingRequest = PendingRequest(
                    id: requestID,
                    text: text,
                    continuation: continuation
                )

                let targetLanguage = Locale.Language(identifier: target.localeIdentifier)
                var nextConfiguration = TranslationSession.Configuration(
                    source: nil,
                    target: targetLanguage
                )
                if #available(macOS 26.4, *) {
                    nextConfiguration.preferredStrategy = .lowLatency
                }
                if let current = configuration,
                   current.source == nil,
                   current.target == targetLanguage {
                    nextConfiguration = current
                    nextConfiguration.invalidate()
                }
                configuration = nextConfiguration
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancel(requestID: requestID)
            }
        }
    }

    func performPendingTranslation(using session: TranslationSession) async {
        guard let request = pendingRequest else { return }
        do {
            let response = try await session.translate(request.text)
            finish(requestID: request.id, result: .success(response.targetText))
        } catch {
            finish(requestID: request.id, result: .failure(error))
        }
    }

    func cancel() {
        guard let request = pendingRequest else {
            configuration = nil
            return
        }
        pendingRequest = nil
        configuration = nil
        request.continuation.resume(throwing: CancellationError())
    }

    private func cancel(requestID: UUID) {
        guard pendingRequest?.id == requestID else { return }
        cancel()
    }

    private func finish(requestID: UUID, result: Result<String, Error>) {
        guard let request = pendingRequest, request.id == requestID else { return }
        pendingRequest = nil
        configuration = nil
        request.continuation.resume(with: result)
    }
}

@available(macOS 15.0, *)
private struct AppleTranslationBridgeView: View {
    @ObservedObject var model: AppleTranslationBridgeModel

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .translationTask(model.configuration) { session in
                await model.performPendingTranslation(using: session)
            }
    }
}
#endif

/// Localized errors deliberately avoid exposing framework messages with punctuation
enum OfflineTranslationError: LocalizedError {
    case modelsMissing, unsupported
    var errorDescription: String? {
        switch self {
        case .modelsMissing: return L10n.translationModelsMissing
        case .unsupported: return L10n.translationUnsupported
        }
    }
}
