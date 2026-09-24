import Foundation

/// Guards Live Activity mutations for one page load and one account. Used on
/// the main thread only, where WebKit delivers script messages in the order the
/// page sent them, so every check here happens at the moment a message arrives
/// and before any asynchronous work.
///
/// - The session ID changes on every main-frame load, on sign-out and when a
///   different user signs in. A token refresh for the same user keeps it.
/// - A new page is unbound until it sends `SET_AUTH_SESSION`; mutations before
///   that are refused, so nothing meant for one account lands on another.
/// - `clientSequence` must increase. A transport retry (same requestId and
///   sequence) gets the stored reply back and repeats no side effect.
final class LiveActivityBridgeSession {
    enum Admission {
        case accepted(account: String)
        case replay(type: String, payload: [String: Any])
        /// The same request is still being processed; its reply will carry
        /// this requestId.
        case inFlight
        case rejected(LiveActivityError)
    }

    private struct StoredReply {
        let sequence: Int
        let type: String
        let payload: [String: Any]
    }

    private(set) var id: String
    private(set) var boundAccount: String?
    private var lastSequence = 0
    private var replies: [String: StoredReply] = [:]
    private var replyOrder: [String] = []
    private var inFlight: [String: Int] = [:]
    private let makeId: () -> String

    init(makeId: @escaping () -> String = { UUID().uuidString }) {
        self.makeId = makeId
        id = makeId()
    }

    /// A main-frame navigation started. Anything the old page sent is void.
    func pageWillLoad() {
        rotate()
        boundAccount = nil
    }

    /// `SET_AUTH_SESSION` arrived. Returns true when the session ID changed.
    @discardableResult
    func bind(account: String) -> Bool {
        if let boundAccount, boundAccount != account {
            rotate()
            self.boundAccount = account
            return true
        }
        boundAccount = account
        return false
    }

    /// `CLEAR_AUTH_SESSION` arrived.
    func unbind() {
        rotate()
        boundAccount = nil
    }

    func admit(_ envelope: LiveActivityProtocol.MutationEnvelope) -> Admission {
        if let stored = replies[envelope.requestId] {
            guard stored.sequence == envelope.clientSequence, envelope.bridgeSessionId == id else {
                return .rejected(.requestIdReused)
            }
            return .replay(type: stored.type, payload: stored.payload)
        }
        if let sequence = inFlight[envelope.requestId] {
            return sequence == envelope.clientSequence && envelope.bridgeSessionId == id ? .inFlight : .rejected(.requestIdReused)
        }
        guard envelope.bridgeSessionId == id else { return .rejected(.staleBridgeSession) }
        guard let boundAccount else { return .rejected(.authSessionRequired) }
        guard envelope.clientSequence > lastSequence else { return .rejected(.staleSequence) }
        lastSequence = envelope.clientSequence
        inFlight[envelope.requestId] = envelope.clientSequence
        return .accepted(account: boundAccount)
    }

    /// Stores the reply for transport retries. A reply that finishes after the
    /// session rotated is not stored: its page is gone.
    func finish(_ envelope: LiveActivityProtocol.MutationEnvelope, type: String, payload: [String: Any]) {
        guard envelope.bridgeSessionId == id, inFlight.removeValue(forKey: envelope.requestId) != nil else { return }
        replies[envelope.requestId] = StoredReply(sequence: envelope.clientSequence, type: type, payload: payload)
        replyOrder.append(envelope.requestId)
        while replyOrder.count > LiveActivityConfig.replyCacheLimit {
            replies.removeValue(forKey: replyOrder.removeFirst())
        }
    }

    private func rotate() {
        id = makeId()
        lastSequence = 0
        replies.removeAll()
        replyOrder.removeAll()
        inFlight.removeAll()
    }
}
