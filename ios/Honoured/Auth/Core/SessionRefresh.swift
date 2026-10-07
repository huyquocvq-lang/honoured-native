import Foundation

// Supabase rotates the refresh token on every use, and using one that was
// already used revokes the whole session ("refresh token reuse"). The app and
// its web page share one session, so two refreshers holding copies of the same
// token signed people out and stopped the health upload (Oct 2–6). Inside the
// app, native is the only refresher: the page hands its refreshes over
// (`REFRESH_AUTH_SESSION`, docs/phase1/bridge.md, "Session refresh"), and each
// token is refreshed once however many callers ask at the same time.

/// One refresh per token: callers that ask while it runs share its result.
/// Owned by the actor that keeps the session, so every call runs isolated.
struct RefreshCoalescer<Result: Sendable> {
    private var running: (key: String, task: Task<Result, Error>)?

    /// The refresh of `key` already running, or a new one from `start`.
    mutating func task(for key: String, start: () -> Task<Result, Error>) -> Task<Result, Error> {
        if let running, running.key == key { return running.task }
        let task = start()
        running = (key, task)
        return task
    }

    /// Called by each caller once it is done; only the refresh of `key` is dropped.
    mutating func finished(_ key: String) {
        if running?.key == key { running = nil }
    }

    var isRunning: Bool { running != nil }
}

/// What native does with a refresh the page hands over.
enum WebRefreshPolicy {
    enum Decision: Equatable {
        /// Refresh native's copy, the newest of the session, and give it to the page.
        case refresh
        /// The page refreshes for itself, as it would outside the app.
        case decline(String)
    }

    /// Native refreshes only for the person it holds the session of. Without
    /// one, or for someone else (a sign-in native has not stored yet), the
    /// page's own token is the only copy, so no second refresher exists.
    static func decide(storedUserId: String?, requestUserId: String) -> Decision {
        guard let storedUserId else { return .decline("no_session") }
        guard storedUserId == requestUserId else { return .decline("other_user") }
        return .refresh
    }
}
