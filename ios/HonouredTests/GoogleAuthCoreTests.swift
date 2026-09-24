import XCTest

final class GoogleAuthStateTests: XCTestCase {
    private var counter = 0
    private func makeState() -> GoogleAuthState {
        GoogleAuthState(makeId: { [unowned self] in
            self.counter += 1
            return "ctx-\(self.counter)"
        })
    }

    private func begin(_ state: GoogleAuthState, _ requestId: String?, _ intent: String?, _ context: String?) -> Result<GoogleAuthAttempt, GoogleAuthFailure> {
        state.begin(requestId: requestId, intent: intent, contextId: context, rawNonce: "raw")
    }

    func testSyncIsIdempotentForTheSameUserAndPage() {
        let state = makeState()
        let a = state.sync(userId: nil)
        XCTAssertEqual(state.sync(userId: nil), a)
        XCTAssertEqual(state.sync(userId: ""), a, "an empty user id means signed out")
        let b = state.sync(userId: "user-a")
        XCTAssertNotEqual(b.id, a.id)
        XCTAssertEqual(state.sync(userId: "user-a"), b)
    }

    func testRequiresAContextFromThisPage() {
        let state = makeState()
        XCTAssertEqual(begin(state, "r1", "sign_in", "ctx-x"), .failure(.staleContext))
        let context = state.sync(userId: nil)
        state.documentWillChange()
        XCTAssertEqual(begin(state, "r1", "sign_in", context.id), .failure(.staleContext))
        XCTAssertNil(state.context)
    }

    func testValidatesPayloadAndIntentAgainstTheContext() {
        let state = makeState()
        let signedOut = state.sync(userId: nil)
        XCTAssertEqual(begin(state, nil, "sign_in", signedOut.id).failureCode, "invalid_payload")
        XCTAssertEqual(begin(state, "r1", "bogus", signedOut.id).failureCode, "invalid_payload")
        XCTAssertEqual(begin(state, "r1", "sign_in", nil).failureCode, "invalid_payload")
        XCTAssertEqual(begin(state, "r1", "link", signedOut.id).failureCode, "invalid_payload")
        let signedIn = state.sync(userId: "user-a")
        XCTAssertEqual(begin(state, "r2", "sign_in", signedIn.id).failureCode, "invalid_payload")
        XCTAssertNotNil(try? begin(state, "r3", "link", signedIn.id).get())
    }

    func testOneAttemptAtATimeAndOneResultPerRequest() throws {
        let state = makeState()
        let context = state.sync(userId: nil)
        let attempt = try begin(state, "r1", "sign_in", context.id).get()
        XCTAssertEqual(begin(state, "r2", "sign_in", context.id), .failure(.inProgress))
        XCTAssertEqual(state.finish(attempt), attempt)
        XCTAssertNil(state.finish(attempt), "a second SDK callback for the same attempt is dropped")
        XCTAssertEqual(begin(state, "r1", "sign_in", context.id).failureCode, "invalid_payload", "a used requestId is never served again")
        XCTAssertNotNil(try? begin(state, "r2", "sign_in", context.id).get())
    }

    func testReloadOwnerChangeAndClearInvalidateAnAttempt() throws {
        let state = makeState()
        var context = state.sync(userId: nil)
        var attempt = try begin(state, "r1", "sign_in", context.id).get()
        state.documentWillChange()
        XCTAssertFalse(state.isCurrent(attempt))
        XCTAssertNil(state.finish(attempt))

        context = state.sync(userId: "user-a")
        attempt = try begin(state, "r2", "link", context.id).get()
        state.sessionOwnerChanged(to: "user-a")
        XCTAssertTrue(state.isCurrent(attempt), "a token refresh for the same user keeps a link flow")
        state.sessionOwnerChanged(to: "user-b")
        XCTAssertNil(state.finish(attempt))
        XCTAssertNil(state.context)

        context = state.sync(userId: "user-b")
        attempt = try begin(state, "r3", "link", context.id).get()
        state.sessionOwnerChanged(to: nil)
        XCTAssertNil(state.finish(attempt), "sign-out invalidates")

        context = state.sync(userId: nil)
        attempt = try begin(state, "r4", "sign_in", context.id).get()
        let fresh = state.clear()
        XCTAssertNotEqual(fresh.id, context.id)
        XCTAssertNil(fresh.userId)
        XCTAssertNil(state.finish(attempt))
        XCTAssertEqual(begin(state, "r5", "sign_in", context.id), .failure(.staleContext))
    }

    func testSignInForSomeoneWhileSignedOutInvalidatesTheContext() throws {
        let state = makeState()
        let context = state.sync(userId: nil)
        let attempt = try begin(state, "r1", "sign_in", context.id).get()
        state.sessionOwnerChanged(to: "user-a")
        XCTAssertNil(state.finish(attempt))
    }

    func testCancelOnlyMatchesTheCurrentAttempt() throws {
        let state = makeState()
        let context = state.sync(userId: nil)
        let attempt = try begin(state, "r1", "sign_in", context.id).get()
        XCTAssertNil(state.cancel(contextId: "other", targetRequestId: "r1"))
        XCTAssertNil(state.cancel(contextId: context.id, targetRequestId: "r9"))
        XCTAssertEqual(state.cancel(contextId: context.id, targetRequestId: "r1"), attempt)
        XCTAssertNil(state.finish(attempt), "the SDK result after a cancel is dropped")
        XCTAssertNil(state.cancel(contextId: context.id, targetRequestId: "r1"))
    }
}

final class AuthSupportTests: XCTestCase {
    func testPresentationGateIsExclusiveAndIgnoresStaleReleases() {
        let gate = ProviderPresentationGate()
        let apple = gate.acquire(.apple)
        XCTAssertNotNil(apple)
        XCTAssertNil(gate.acquire(.google))
        XCTAssertNil(gate.acquire(.googleCleanup))
        gate.release(apple!)
        let google = gate.acquire(.google)
        XCTAssertNotNil(google)
        gate.release(apple!)
        XCTAssertEqual(gate.holder, .google, "an old token cannot release a newer holder")
        gate.release(google!)
        XCTAssertNil(gate.holder)
    }

    func testNonceIsRandomHexAndHashedWithSHA256() {
        let a = AuthNonce.make()
        let b = AuthNonce.make()
        XCTAssertEqual(a.raw.count, 64)
        XCTAssertTrue(a.raw.allSatisfy { $0.isHexDigit })
        XCTAssertNotEqual(a.raw, b.raw)
        XCTAssertEqual(a.hashed, AuthNonce.sha256Hex(a.raw))
        XCTAssertEqual(AuthNonce.sha256Hex("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    private let ios = "123-abc.apps.googleusercontent.com"
    private let web = "123-web.apps.googleusercontent.com"
    private let scheme = "com.googleusercontent.apps.123-abc"

    func testClientConfigNeedsBothIDsAndTheRegisteredCallbackScheme() {
        XCTAssertEqual(
            GoogleClientConfig.validate(clientID: " \(ios) ", serverClientID: web, registeredSchemes: ["honoured", scheme]),
            GoogleClientConfig(clientID: ios, serverClientID: web, callbackScheme: scheme)
        )
        XCTAssertNil(GoogleClientConfig.validate(clientID: ios, serverClientID: web, registeredSchemes: ["honoured"]))
        XCTAssertNil(GoogleClientConfig.validate(clientID: "", serverClientID: web, registeredSchemes: [scheme]))
        XCTAssertNil(GoogleClientConfig.validate(clientID: ios, serverClientID: "", registeredSchemes: [scheme]))
        XCTAssertNil(GoogleClientConfig.validate(clientID: "$(GOOGLE_IOS_CLIENT_ID)", serverClientID: web, registeredSchemes: [scheme]))
        XCTAssertNil(GoogleClientConfig.validate(clientID: ios, serverClientID: ios, registeredSchemes: [scheme]), "the server audience must be the web client")
        XCTAssertNil(GoogleClientConfig.validate(clientID: ".apps.googleusercontent.com", serverClientID: web, registeredSchemes: [scheme]))
    }

    func testURLRoutingKeepsContractLinksAwayFromGoogle() {
        let contract = URL(string: "honoured://contract/c-walk?day=2026-09-24&occurrence=x")!
        let google = URL(string: "\(scheme):/oauth2redirect/google?code=x")!
        XCTAssertEqual(AppURLRoute.classify(contract, googleCallbackScheme: scheme), .app)
        XCTAssertEqual(AppURLRoute.classify(google, googleCallbackScheme: scheme), .googleCallback)
        XCTAssertEqual(AppURLRoute.classify(google, googleCallbackScheme: nil), .app, "unconfigured: nothing reaches the SDK")
        XCTAssertEqual(AppURLRoute.classify(URL(string: "https://evil.example/\(scheme)")!, googleCallbackScheme: scheme), .app)
    }

    func testTrustedOriginIsExact() {
        let origin = TrustedWebOrigin(url: URL(string: "https://honour-your-word.lovable.app/path?q=1")!)!
        XCTAssertTrue(origin.matches(scheme: "https", host: "honour-your-word.lovable.app", port: 0))
        XCTAssertTrue(origin.matches(scheme: "HTTPS", host: "Honour-Your-Word.lovable.app", port: 443))
        XCTAssertTrue(origin.matches(url: URL(string: "https://honour-your-word.lovable.app/settings")))
        XCTAssertFalse(origin.matches(scheme: "http", host: "honour-your-word.lovable.app", port: 0))
        XCTAssertFalse(origin.matches(scheme: "https", host: "evil.honour-your-word.lovable.app", port: 0))
        XCTAssertFalse(origin.matches(scheme: "https", host: "honour-your-word.lovable.app.evil.com", port: 0))
        XCTAssertFalse(origin.matches(scheme: "https", host: "honour-your-word.lovable.app", port: 8443))
        XCTAssertFalse(origin.matches(scheme: "", host: "", port: 0))
        XCTAssertFalse(origin.matches(url: nil))
        XCTAssertNil(TrustedWebOrigin(url: URL(string: "http://honour-your-word.lovable.app")!), "only HTTPS can be trusted")
    }

    func testSerialQueueRunsInSubmissionOrderEvenWhenEarlierWorkIsSlower() async {
        let queue = SerialAsyncQueue()
        let log = Log()
        let done = expectation(description: "all ran")
        done.expectedFulfillmentCount = 3
        queue.enqueue {
            try? await Task.sleep(nanoseconds: 150_000_000)
            await log.add("logout A")
            done.fulfill()
        }
        queue.enqueue {
            await log.add("sign in B")
            done.fulfill()
        }
        let value = await queue.run { () -> Int in
            await log.add("identify B")
            done.fulfill()
            return 7
        }
        await fulfillment(of: [done], timeout: 2)
        XCTAssertEqual(value, 7)
        let entries = await log.entries
        XCTAssertEqual(entries, ["logout A", "sign in B", "identify B"])
    }

    private actor Log {
        var entries: [String] = []
        func add(_ entry: String) { entries.append(entry) }
    }
}

private extension Result where Failure == GoogleAuthFailure {
    var failureCode: String? {
        if case .failure(let failure) = self { return failure.code }
        return nil
    }
}

extension GoogleAuthAttempt: CustomStringConvertible {
    public var description: String { "attempt \(requestId)" }
}
