import Foundation

/// What the web app asked Google Sign-In for. `sign_in` needs a signed-out
/// context; `link` needs a signed-in one and must keep that user.
enum GoogleSignInIntent: String {
    case signIn = "sign_in"
    case link
}

/// A failure the bridge can report as `GOOGLE_SIGN_IN_FAILED`. Messages are
/// written here, never copied from an error that could carry token material.
struct GoogleAuthFailure: Error, Equatable {
    let code: String
    let message: String

    static let cancelled = GoogleAuthFailure(code: "cancelled", message: "Google sign-in was cancelled.")
    static let inProgress = GoogleAuthFailure(code: "in_progress", message: "Another sign-in is already in progress.")
    static let notConfigured = GoogleAuthFailure(code: "not_configured", message: "Google sign-in is not configured in this build.")
    static let unsupported = GoogleAuthFailure(code: "unsupported", message: "Google sign-in is not available on this device.")
    static let staleContext = GoogleAuthFailure(code: "stale_context", message: "The sign-in request no longer matches this page. Try again.")
    static let noCredential = GoogleAuthFailure(code: "no_credential", message: "No Google account is available on this device.")
    static let network = GoogleAuthFailure(code: "network_error", message: "Google could not be reached. Check your connection and try again.")
    static let provider = GoogleAuthFailure(code: "provider_error", message: "Google sign-in failed. Try again.")
    static let timeout = GoogleAuthFailure(code: "timeout", message: "Google sign-in took too long. Try again.")

    static func invalidPayload(_ message: String) -> GoogleAuthFailure {
        GoogleAuthFailure(code: "invalid_payload", message: message)
    }
}

/// Which document and which owner a Google request belongs to. Native issues
/// the id; it lives in memory only and carries no token.
struct GoogleAuthContext: Equatable {
    let id: String
    let userId: String?
    let documentGeneration: Int
}

/// One Google presentation, bound to the page, context, intent and request
/// that started it. The raw nonce never leaves memory.
struct GoogleAuthAttempt: Equatable {
    let requestId: String
    let contextId: String
    let intent: GoogleSignInIntent
    let documentGeneration: Int
    let rawNonce: String
}

/// Ownership rules for Google Sign-In, free of UIKit, WebKit and the Google
/// SDK so they can be tested directly. Main thread only, like the bridge.
///
/// - A new page, a different owner or an explicit clear replaces the context
///   and invalidates every attempt of the old one.
/// - A token refresh for the same user keeps the context, so a link flow in
///   progress survives it.
/// - An attempt yields at most one result, and only while it is still the
///   current attempt of the current context on the same page.
final class GoogleAuthState {
    private(set) var documentGeneration = 0
    private(set) var context: GoogleAuthContext?
    private(set) var attempt: GoogleAuthAttempt?
    private var usedRequestIds: Set<String> = []
    private let makeId: () -> String

    init(makeId: @escaping () -> String = { UUID().uuidString }) {
        self.makeId = makeId
    }

    // MARK: Context

    /// A main-frame navigation started or committed. The old document can no
    /// longer receive a credential; the new one must sync its context first.
    func documentWillChange() {
        documentGeneration += 1
        context = nil
        attempt = nil
        usedRequestIds.removeAll()
    }

    /// `SYNC_AUTH_CONTEXT`. Idempotent for the same user on the same page.
    @discardableResult
    func sync(userId: String?) -> GoogleAuthContext {
        let normalized = userId.flatMap { $0.isEmpty ? nil : $0 }
        if let context, context.userId == normalized, context.documentGeneration == documentGeneration {
            return context
        }
        return replaceContext(userId: normalized)
    }

    /// The native session changed owner (iOS `SET_AUTH_SESSION`, or
    /// `CLEAR_AUTH_SESSION` with `userId == nil`). The same owner keeps the
    /// context; anything else invalidates it until the web app resyncs.
    func sessionOwnerChanged(to userId: String?) {
        guard let context else { return }
        if let userId, context.userId == userId { return }
        invalidateContext()
    }

    /// `CLEAR_GOOGLE_SIGN_IN`: invalidate synchronously and hand back a fresh
    /// signed-out context for the same page.
    func clear() -> GoogleAuthContext {
        replaceContext(userId: nil)
    }

    private func replaceContext(userId: String?) -> GoogleAuthContext {
        attempt = nil
        usedRequestIds.removeAll()
        let next = GoogleAuthContext(id: makeId(), userId: userId, documentGeneration: documentGeneration)
        context = next
        return next
    }

    private func invalidateContext() {
        context = nil
        attempt = nil
        usedRequestIds.removeAll()
    }

    // MARK: Attempts

    /// Validates a `SIGN_IN_WITH_GOOGLE` request and records the attempt. The
    /// caller still has to acquire the presentation lock.
    func begin(
        requestId: String?,
        intent rawIntent: String?,
        contextId: String?,
        rawNonce: String
    ) -> Result<GoogleAuthAttempt, GoogleAuthFailure> {
        guard let requestId, !requestId.isEmpty else {
            return .failure(.invalidPayload("requestId is required."))
        }
        guard let rawIntent, let intent = GoogleSignInIntent(rawValue: rawIntent) else {
            return .failure(.invalidPayload("intent must be sign_in or link."))
        }
        guard let contextId, !contextId.isEmpty else {
            return .failure(.invalidPayload("authContextId is required."))
        }
        guard let context, context.id == contextId, context.documentGeneration == documentGeneration else {
            return .failure(.staleContext)
        }
        guard !usedRequestIds.contains(requestId) else {
            return .failure(.invalidPayload("This requestId was already used."))
        }
        switch intent {
        case .signIn where context.userId != nil:
            return .failure(.invalidPayload("sign_in needs a signed-out context."))
        case .link where context.userId == nil:
            return .failure(.invalidPayload("link needs a signed-in context."))
        default:
            break
        }
        guard attempt == nil else { return .failure(.inProgress) }
        usedRequestIds.insert(requestId)
        let next = GoogleAuthAttempt(
            requestId: requestId,
            contextId: contextId,
            intent: intent,
            documentGeneration: documentGeneration,
            rawNonce: rawNonce
        )
        attempt = next
        return .success(next)
    }

    /// True while `attempt` may still receive a result.
    func isCurrent(_ candidate: GoogleAuthAttempt) -> Bool {
        guard let attempt, attempt == candidate else { return false }
        guard let context, context.id == candidate.contextId else { return false }
        return candidate.documentGeneration == documentGeneration
    }

    /// Consumes the attempt: returns it once if it is still current, so the
    /// caller may deliver its result; nil means drop the result.
    func finish(_ candidate: GoogleAuthAttempt) -> GoogleAuthAttempt? {
        guard isCurrent(candidate) else { return nil }
        attempt = nil
        return candidate
    }

    /// `CANCEL_GOOGLE_SIGN_IN`. Returns the cancelled attempt so the caller can
    /// answer its pending request once; later SDK results are dropped.
    func cancel(contextId: String?, targetRequestId: String?) -> GoogleAuthAttempt? {
        guard let attempt, let context,
              context.id == contextId,
              attempt.contextId == contextId,
              attempt.requestId == targetRequestId else { return nil }
        self.attempt = nil
        return attempt
    }
}
