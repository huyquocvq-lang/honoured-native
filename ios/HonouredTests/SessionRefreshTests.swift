import XCTest

final class SessionRefreshTests: XCTestCase {
    private actor Calls {
        private(set) var count = 0
        func next() -> Int {
            count += 1
            return count
        }
    }

    /// Holds a coalescer the way AuthSessionStore does: every call isolated.
    private actor Refresher {
        private var coalescer = RefreshCoalescer<Int>()
        let calls = Calls()

        func refresh(_ token: String) async throws -> Int {
            let task = coalescer.task(for: token) {
                Task {
                    let call = await calls.next()
                    try await Task.sleep(nanoseconds: 50_000_000)
                    return call
                }
            }
            defer { coalescer.finished(token) }
            return try await task.value
        }

        var isRunning: Bool { coalescer.isRunning }
    }

    func testCallersAskingAtTheSameTimeShareOneRefresh() async throws {
        // Supabase revokes the session when a used refresh token is used again.
        let refresher = Refresher()
        async let first = refresher.refresh("token-1")
        async let second = refresher.refresh("token-1")
        async let third = refresher.refresh("token-1")
        let results = try await [first, second, third]
        XCTAssertEqual(results, [1, 1, 1])
        let count = await refresher.calls.count
        XCTAssertEqual(count, 1)
        let running = await refresher.isRunning
        XCTAssertFalse(running)
    }

    func testANewTokenOrALaterRefreshStartsAgain() async throws {
        let refresher = Refresher()
        let first = try await refresher.refresh("token-1")
        let second = try await refresher.refresh("token-2")
        let third = try await refresher.refresh("token-1")
        XCTAssertEqual([first, second, third], [1, 2, 3])
    }

    func testFinishingAnotherTokenKeepsTheRunningRefresh() {
        var coalescer = RefreshCoalescer<Int>()
        let task = coalescer.task(for: "token-1") { Task { 1 } }
        coalescer.finished("token-0")
        XCTAssertTrue(coalescer.isRunning)
        let again = coalescer.task(for: "token-1") { Task { 2 } }
        XCTAssertEqual(task, again, "the refresh already running is shared")
        coalescer.finished("token-1")
        XCTAssertFalse(coalescer.isRunning)
    }

    func testNativeRefreshesOnlyForThePersonItHoldsTheSessionOf() {
        XCTAssertEqual(WebRefreshPolicy.decide(storedUserId: "user-a", requestUserId: "user-a"), .refresh)
        XCTAssertEqual(WebRefreshPolicy.decide(storedUserId: nil, requestUserId: "user-a"), .decline("no_session"))
        XCTAssertEqual(WebRefreshPolicy.decide(storedUserId: "user-a", requestUserId: "user-b"), .decline("other_user"))
    }
}
