#if DEBUG
import Foundation
import UIKit
import WebKit
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Debug-only stand-in for the hosted web app, so bridge features can be
/// exercised on the simulator without the Lovable build having shipped them.
/// Enabled with the `-HonouredBridgeStub` launch argument; an optional
/// `-HonouredBridgeScenario <name>` runs a scripted sequence and reports
/// through `STUB_LOG`, which the bridge prints to stdout so
/// `xcrun simctl launch --console-pty` shows it. Not compiled into Release.
enum BridgeStub {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-HonouredBridgeStub")
    }

    static var scenario: String {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-HonouredBridgeScenario"),
              arguments.indices.contains(index + 1) else { return "" }
        return arguments[index + 1]
    }

    /// `-HonouredStubExitWhenDone` quits the app when the scenario finishes,
    /// so a scripted `simctl launch --console-pty` returns by itself.
    static var exitsWhenDone: Bool {
        ProcessInfo.processInfo.arguments.contains("-HonouredStubExitWhenDone")
    }

    /// The stub page is served under the configured web app origin, so the
    /// auth bridge's main-frame origin check sees exactly what it will see in
    /// production. Nothing is fetched from that origin.
    static func load(into webView: WKWebView) {
        stubWebView = webView
        let page = html
            .replacingOccurrences(of: "__SCENARIO__", with: scenario)
            .replacingOccurrences(of: "__EXIT_WHEN_DONE__", with: exitsWhenDone ? "true" : "false")
        webView.loadHTMLString(page, baseURL: AppConfig.webAppURL)
    }

    private static weak var stubWebView: WKWebView?

    /// `-HonouredFakeGoogle success|slow|cancel|error|network` replaces
    /// Google's UI with a canned result, so the auth bridge can be exercised
    /// on the simulator without client IDs or a Google account. The fake ID
    /// token embeds the hashed nonce it was asked for, which lets a scenario
    /// check the nonce round trip. Never a real token.
    static var fakeGoogleOutcome: String? {
        guard isEnabled else { return nil }
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-HonouredFakeGoogle"),
              arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    @MainActor
    static func fakeGoogle(_ outcome: String, hashedNonce: String) async -> GoogleSignInCoordinator.Outcome {
        let delay: UInt64 = outcome == "slow" ? 4_000_000_000 : 1_500_000_000
        try? await Task.sleep(nanoseconds: delay)
        switch outcome {
        case "cancel": return .failure(.cancelled)
        case "error": return .failure(.provider)
        case "network": return .failure(.network)
        default: return .success(idToken: "stub-google-id-token.nonce." + hashedNonce, accessToken: "stub-google-access-token")
        }
    }

    static func log(_ line: String) {
        print("[bridge-stub] \(line)")
    }

    /// `-HonouredFakeHealthTotals steps=9000,active_energy=300` (also settable
    /// at runtime with `simctl spawn booted defaults write com.jimmy.upwork.honoured
    /// HonouredFakeHealthTotals -string ...`, or from the stub page with
    /// `STUB_SET_FAKE_HEALTH_TOTALS`) replaces the statistics query for the
    /// listed metrics so goals and Live Activities can run without Health data.
    /// A value may also be `none` (read succeeded, no data), `locked` (protected
    /// data unavailable) or `error` (the read failed).
    static func fakeHealthRead(for metric: HealthMetric) -> HealthTotalRead? {
        guard isEnabled else { return nil }
        runtimeLock.lock()
        let runtime = runtimeFakeHealthTotals
        runtimeLock.unlock()
        guard let spec = runtime ?? UserDefaults.standard.string(forKey: "HonouredFakeHealthTotals") else { return nil }
        for pair in spec.split(separator: ",") {
            let parts = pair.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, parts[0] == metric.rawValue else { continue }
            switch parts[1] {
            case "none": return .noData
            case "locked": return .protectedDataUnavailable
            case "error": return .failed
            default: return Double(parts[1]).map(HealthTotalRead.value)
            }
        }
        return nil
    }

    private static let runtimeLock = NSLock()
    private static var runtimeFakeHealthTotals: String?

    /// Stub-only messages, reachable only while the stub page is loaded.
    static func handle(type: String, payload: [String: Any], reply: @escaping (String, [String: Any]) -> Void) {
        switch type {
        case "STUB_SET_FAKE_HEALTH_TOTALS":
            let spec = payload["spec"] as? String
            runtimeLock.lock()
            runtimeFakeHealthTotals = spec
            runtimeLock.unlock()
            Task {
                // What a collection pass with new samples does.
                let prefetched = await LiveActivityCoordinator.shared.refreshHealthProgress()
                await GoalMonitor.shared.evaluate(prefetched: prefetched)
                reply("STUB_FAKE_HEALTH_TOTALS_SET", ["spec": spec ?? NSNull()])
            }
        case "STUB_LIST_LIVE_ACTIVITIES":
            reply("STUB_LIVE_ACTIVITIES", ["activities": liveActivities()])
        case "STUB_DISMISS_LIVE_ACTIVITY":
            // Ends a card behind the engine's back, as a swipe on the Lock
            // Screen or the system time limit would.
            let contractId = payload["contractId"] as? String ?? ""
            let healthDay = payload["healthDay"] as? String ?? ""
            Task {
                let dismissed = await dismissLiveActivity(contractId: contractId, healthDay: healthDay)
                reply("STUB_LIVE_ACTIVITY_DISMISSED", ["dismissed": dismissed])
            }
        case "STUB_OPEN_DEEP_LINK":
            // Opens the card's own link through the system, like a tap, or a
            // raw `url` to try malformed and foreign links.
            let url = (payload["url"] as? String).flatMap(URL.init(string:))
                ?? cardLink(contractId: payload["contractId"] as? String, healthDay: payload["healthDay"] as? String)
            guard let url else {
                reply("STUB_DEEP_LINK_OPENED", ["handled": false])
                return
            }
            Task { @MainActor in
                let handled = await UIApplication.shared.open(url)
                reply("STUB_DEEP_LINK_OPENED", ["handled": handled, "url": url.absoluteString])
            }
        case "STUB_RELOAD":
            // A real main-frame navigation, to check that a Google result for
            // the old page never reaches the new one.
            DispatchQueue.main.async {
                if let webView = stubWebView { load(into: webView) }
            }
        case "STUB_EXIT":
            guard exitsWhenDone else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exit(0) }
        default:
            reply("ERROR", ["message": "Unknown stub message \(type)", "code": "not_implemented"])
        }
    }

    /// What ActivityKit itself holds, to check scores and content end to end.
    private static func liveActivities() -> [[String: Any]] {
        #if canImport(ActivityKit)
        guard #available(iOS 16.2, *) else { return [] }
        return Activity<HonouredActivityAttributes>.activities.map { activity in
            let content = activity.content
            var item: [String: Any] = [
                "id": activity.id,
                "contractId": activity.attributes.contractId,
                "healthDay": activity.attributes.healthDay,
                "activityState": "\(activity.activityState)",
                "relevanceScore": content.relevanceScore,
                "status": content.state.status.rawValue,
                "contractName": content.state.contractName,
                "health": content.state.health.map { part -> [String: Any] in
                    [
                        "activityId": part.activityId,
                        "value": part.value ?? NSNull(),
                        "target": part.target,
                        "reached": part.reached,
                        "dataStatus": part.dataStatus.rawValue
                    ]
                }
            ]
            if let staleDate = content.staleDate {
                item["staleDate"] = LiveActivityProtocol.iso8601.string(from: staleDate)
            }
            if let timer = content.state.timer {
                item["timer"] = [
                    "activityId": timer.activityId,
                    "endsAt": LiveActivityProtocol.iso8601.string(from: timer.endsAt),
                    "finished": timer.finished
                ]
            }
            return item
        }
        #else
        return []
        #endif
    }

    private static func dismissLiveActivity(contractId: String, healthDay: String) async -> Bool {
        #if canImport(ActivityKit)
        guard #available(iOS 16.2, *) else { return false }
        guard let activity = Activity<HonouredActivityAttributes>.activities.first(where: {
            $0.attributes.contractId == contractId && $0.attributes.healthDay == healthDay
                && ($0.activityState == .active || $0.activityState == .stale)
        }) else { return false }
        await activity.end(nil, dismissalPolicy: .immediate)
        return true
        #else
        return false
        #endif
    }

    private static func cardLink(contractId: String?, healthDay: String?) -> URL? {
        #if canImport(ActivityKit)
        guard #available(iOS 16.2, *), let contractId, let healthDay,
              let activity = Activity<HonouredActivityAttributes>.activities.first(where: {
                  $0.attributes.contractId == contractId && $0.attributes.healthDay == healthDay
              }) else { return nil }
        return ContractDeepLink.url(for: ContractDeepLink.Target(
            contractId: contractId, healthDay: healthDay, occurrenceToken: activity.attributes.occurrenceToken
        ))
        #else
        return nil
        #endif
    }

    private static let html = """
    <!doctype html>
    <html><head><meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
      body { background:#000; color:#ede7dd; font: 14px -apple-system, sans-serif; margin:0; padding:48px 12px 12px; }
      button { display:block; width:100%; margin:6px 0; padding:12px; font-size:15px; background:#222; color:#ede7dd; border:1px solid #444; border-radius:8px; }
      pre { white-space:pre-wrap; word-break:break-all; font-size:11px; color:#8a8a8a; }
    </style></head>
    <body>
    <button onclick="req('START_TIMER',{activityId:'act-1',activityName:'Cold plunge',durationSeconds:10},['TIMER_STARTED'])">START_TIMER act-1 · 10 s</button>
    <button onclick="req('START_TIMER',{activityId:'act-2',activityName:'Breathwork',durationSeconds:600},['TIMER_STARTED'])">START_TIMER act-2 · 10 min</button>
    <button onclick="req('CANCEL_TIMER',{activityId:'act-1'},['TIMER_CANCELLED'])">CANCEL_TIMER act-1</button>
    <button onclick="req('GET_TIMER_STATE',{},['TIMER_STATE'])">GET_TIMER_STATE</button>
    <button onclick="req('SET_GOALS',{goals:[{activityId:'act-3',activityName:'Walk',metric:'steps',target:8000,unit:'count'}]},['GOALS_ACCEPTED'])">SET_GOALS · 1 goal</button>
    <button onclick="req('SET_GOALS',{goals:[]},['GOALS_ACCEPTED'])">SET_GOALS · empty</button>
    <button onclick="req('ACTIVITY_COMPLETED',{activityId:'act-3',source:'manual'},['ACTIVITY_COMPLETION_ACCEPTED'])">ACTIVITY_COMPLETED act-3 manual</button>
    <button onclick="req('SET_DAY_RESET_HOUR',{hour:4},['DAY_RESET_HOUR_ACCEPTED'])">SET_DAY_RESET_HOUR 4</button>
    <button onclick="req('SET_SOUND_ENABLED',{enabled:true},['SOUND_STATE'])">SET_SOUND_ENABLED true</button>
    <button onclick="req('SET_SOUND_ENABLED',{enabled:false},['SOUND_STATE'])">SET_SOUND_ENABLED false</button>
    <button onclick="req('SIGN_IN_WITH_APPLE',{},['APPLE_SIGN_IN_SUCCESS','APPLE_SIGN_IN_FAILED'],120000)">SIGN_IN_WITH_APPLE</button>
    <button onclick="req('GET_HEALTH_STATUS',{},['HEALTH_PERMISSION_STATUS'])">GET_HEALTH_STATUS</button>
    <button onclick="req('REQUEST_HEALTH_PERMISSION',{},['HEALTH_PERMISSION_STATUS'],60000)">REQUEST_HEALTH_PERMISSION</button>
    <button onclick="laManualSetup()">LA · sign in stub-user-a + goals</button>
    <button onclick="track(demo.walk)">LA · open Walking (steps)</button>
    <button onclick="track(demo.exercise)">LA · open Exercise (minutes)</button>
    <button onclick="startTracked(demo.meditation, 120)">LA · start Meditation 2 min</button>
    <button onclick="fake('steps=6400,exercise_minutes=12')">LA · fake Health 80% / 40%</button>
    <button onclick="laList()">LA · list ActivityKit cards</button>
    <button onclick="laState()">GET_LIVE_ACTIVITY_STATE</button>
    <pre id="log"></pre>
    <script>
    const scenario = '__SCENARIO__';
    const logEl = document.getElementById('log');
    const post = (type, payload = {}) => window.webkit.messageHandlers.honouredNative.postMessage({ type, payload });
    const log = (line) => {
      logEl.textContent = line + '\\n' + logEl.textContent;
      post('STUB_LOG', { line });
    };
    const pending = new Map();
    const waiters = [];
    const redact = (type, payload) => {
      if ((type !== 'APPLE_SIGN_IN_SUCCESS' && type !== 'GOOGLE_SIGN_IN_SUCCESS') || !payload) return payload;
      const out = { ...payload };
      for (const k of ['identityToken', 'authorizationCode', 'rawNonce', 'idToken', 'accessToken']) {
        if (typeof out[k] === 'string') out[k] = `<${k} ${out[k].length} chars>`;
      }
      return out;
    };
    window.addEventListener('honoured:native', (e) => {
      const { type, payload } = e.detail;
      log('◀ ' + type + ' ' + JSON.stringify(redact(type, payload)));
      if (payload && payload.requestId && pending.has(payload.requestId)) {
        const p = pending.get(payload.requestId);
        if (p.expected.includes(type) || type === 'ERROR') { pending.delete(payload.requestId); p.resolve({ type, payload }); }
        return;
      }
      for (const w of [...waiters]) {
        if (w.types.includes(type)) { waiters.splice(waiters.indexOf(w), 1); w.resolve({ type, payload }); }
      }
    });
    let seq = 0;
    function req(type, payload, expected, timeoutMs = 8000) {
      const requestId = 'stub-' + (++seq);
      log('▶ ' + type + ' ' + JSON.stringify(payload));
      return new Promise((resolve) => {
        pending.set(requestId, { expected, resolve });
        post(type, { ...payload, requestId });
        setTimeout(() => { if (pending.delete(requestId)) resolve({ type: 'TIMEOUT', payload: { requestId } }); }, timeoutMs);
      });
    }
    function waitFor(types, timeoutMs) {
      return new Promise((resolve) => {
        const w = { types, resolve };
        waiters.push(w);
        setTimeout(() => { const i = waiters.indexOf(w); if (i >= 0) { waiters.splice(i, 1); resolve({ type: 'TIMEOUT', payload: { types } }); } }, timeoutMs);
      });
    }
    const check = (name, ok) => log((ok ? 'PASS ' : 'FAIL ') + name);
    const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
    function reqWithId(type, payload, expected, requestId, timeoutMs = 8000) {
      log('▶ ' + type + ' ' + JSON.stringify(payload));
      return new Promise((resolve) => {
        const entry = { expected, resolve };
        pending.set(requestId, entry);
        post(type, { ...payload, requestId });
        setTimeout(() => { if (pending.get(requestId) === entry) { pending.delete(requestId); resolve({ type: 'TIMEOUT', payload: { requestId } }); } }, timeoutMs);
      });
    }

    // ---- Live Activities ----
    const pad2 = (n) => String(n).padStart(2, '0');
    const today = () => { const d = new Date(); return d.getFullYear() + '-' + pad2(d.getMonth() + 1) + '-' + pad2(d.getDate()); };
    const inHours = (h) => new Date(Date.now() + h * 3600000).toISOString();
    let laSession = null;
    let laSeq = 0;
    const env = () => ({ bridgeSessionId: laSession, clientSequence: ++laSeq });
    async function laAuth(userId) {
      const r = await req('SET_AUTH_SESSION', { userId, accessToken: 'stub-access-token', refreshToken: 'stub-refresh-token', expiresAt: Math.floor(Date.now() / 1000) + 3600 }, ['AUTH_SESSION_ACCEPTED']);
      if (r.type === 'AUTH_SESSION_ACCEPTED') {
        if (r.payload.liveActivityBridgeSessionId !== laSession) laSeq = 0;
        laSession = r.payload.liveActivityBridgeSessionId;
      }
      return r;
    }
    async function laReset(userId) {
      await req('CLEAR_AUTH_SESSION', {}, ['AUTH_SESSION_CLEARED']);
      await req('STUB_SET_FAKE_HEALTH_TOTALS', { spec: null }, ['STUB_FAKE_HEALTH_TOTALS_SET'], 15000);
      const r = await laAuth(userId);
      await req('SET_DAY_RESET_HOUR', { hour: 0 }, ['DAY_RESET_HOUR_ACCEPTED']);
      return r;
    }
    const goal = (activityId, activityName, metric, target, unit) => ({ activityId, activityName, metric, target, unit });
    function healthContract(id, name, slots) {
      const activities = slots.map((s) => ({ activityId: id + ':' + s.slot, slot: s.slot, name: s.name, mode: 'health', metric: s.metric, target: s.target, unit: s.unit }));
      return { contractId: id, contractName: name, healthDay: today(), expiresAt: inHours(6), timerActivityId: id,
        completionPolicy: { kind: 'all_health_slots', requiredActivityIds: activities.map((a) => a.activityId) }, activities };
    }
    const goalsFor = (contract) => contract.activities.filter((a) => a.mode === 'health').map((a) => goal(a.activityId, a.name, a.metric, a.target, a.unit));
    function timerContract(id, name) {
      return { contractId: id, contractName: name, healthDay: today(), expiresAt: inHours(6),
        completionPolicy: { kind: 'timer_completion', timerActivityId: id },
        activities: [{ activityId: id, slot: 'primary', name, mode: 'timer' }] };
    }
    const steps = (target) => ({ slot: 'primary', name: 'Walking', metric: 'steps', target, unit: 'count' });
    const track = (contract) => req('TRACK_CONTRACT', { ...env(), reason: 'opened', contract }, ['CONTRACT_TRACKING_ACCEPTED']);
    const startTracked = (contract, seconds) => req('START_TIMER', { activityId: contract.contractId, activityName: contract.contractName, durationSeconds: seconds, trackingContext: { ...env(), timerActivityId: contract.contractId, contract } }, ['TIMER_STARTED']);
    const laState = () => req('GET_LIVE_ACTIVITY_STATE', {}, ['LIVE_ACTIVITY_STATE']);
    const laList = async () => (await req('STUB_LIST_LIVE_ACTIVITIES', {}, ['STUB_LIVE_ACTIVITIES'])).payload.activities || [];
    const fake = async (spec) => { const r = await req('STUB_SET_FAKE_HEALTH_TOTALS', { spec }, ['STUB_FAKE_HEALTH_TOTALS_SET'], 15000); await sleep(400); return r; };
    const entry = (state, id) => (state.payload.tracked || []).find((t) => t.contractId === id);
    const card = (list, id) => list.find((a) => a.contractId === id && (a.activityState === 'active' || a.activityState === 'stale'));
    const demo = {
      walk: healthContract('c-walk', 'Morning Walk', [steps(8000)]),
      exercise: healthContract('c-exercise', 'Move 30', [{ slot: 'primary', name: 'Exercise', metric: 'exercise_minutes', target: 30, unit: 'minutes' }]),
      meditation: timerContract('c-meditation', 'Meditation'),
    };
    async function laManualSetup() {
      await laReset('stub-user-a');
      await req('SET_GOALS', { goals: [...goalsFor(demo.walk), ...goalsFor(demo.exercise)] }, ['GOALS_ACCEPTED']);
      await fake('steps=2000,exercise_minutes=5');
    }

    async function sha256Hex(text) {
      const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text));
      return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, '0')).join('');
    }

    const scenarios = {
      // Run with -HonouredFakeGoogle success. Checks the auth context, intent
      // rules, one result per request, cancel, owner change, Apple/Google
      // lock, clear and that an iframe is ignored.
      async google() {
        const ready = await req('GET_PLATFORM_INFO', {}, ['PLATFORM_INFO']);
        const cap = ready.payload.capabilities && ready.payload.capabilities.googleSignIn;
        check('capability googleSignIn supported + configured + trusted-auth-v1', !!cap && cap.supported === true && cap.configured === true && cap.transport === 'trusted-auth-v1' && cap.intents.join() === 'sign_in,link');
        await req('CLEAR_AUTH_SESSION', {}, ['AUTH_SESSION_CLEARED']);

        const G = ['GOOGLE_SIGN_IN_SUCCESS', 'GOOGLE_SIGN_IN_FAILED'];
        let r = await req('SIGN_IN_WITH_GOOGLE', { intent: 'sign_in', authContextId: 'made-up' }, G);
        check('no synced context -> stale_context', r.type === 'GOOGLE_SIGN_IN_FAILED' && r.payload.code === 'stale_context');

        const c1 = (await req('SYNC_AUTH_CONTEXT', { userId: null }, ['AUTH_CONTEXT_SYNCED'])).payload.authContextId;
        const c1again = (await req('SYNC_AUTH_CONTEXT', { userId: null }, ['AUTH_CONTEXT_SYNCED'])).payload.authContextId;
        check('same user + page -> same context id', typeof c1 === 'string' && c1 === c1again);

        r = await req('SIGN_IN_WITH_GOOGLE', { intent: 'link', authContextId: c1 }, G);
        check('link on a signed-out context -> invalid_payload', r.type === 'GOOGLE_SIGN_IN_FAILED' && r.payload.code === 'invalid_payload');
        r = await req('SIGN_IN_WITH_GOOGLE', { intent: 'bogus', authContextId: c1 }, G);
        check('unknown intent -> invalid_payload', r.payload.code === 'invalid_payload');

        const first = reqWithId('SIGN_IN_WITH_GOOGLE', { intent: 'sign_in', authContextId: c1 }, G, 'g-first', 10000);
        await sleep(200);
        r = await req('SIGN_IN_WITH_GOOGLE', { intent: 'sign_in', authContextId: c1 }, G);
        check('second request while the UI is up -> in_progress', r.payload.code === 'in_progress');
        r = await req('SIGN_IN_WITH_APPLE', {}, ['APPLE_SIGN_IN_SUCCESS', 'APPLE_SIGN_IN_FAILED'], 5000);
        check('Apple while Google is up -> refused, no sheet', r.type === 'APPLE_SIGN_IN_FAILED' && r.payload.code === 'failed');
        r = await first;
        check('sign_in -> GOOGLE_SIGN_IN_SUCCESS for the same request + context', r.type === 'GOOGLE_SIGN_IN_SUCCESS' && r.payload.requestId === 'g-first' && r.payload.intent === 'sign_in' && r.payload.authContextId === c1);
        const hashed = await sha256Hex(r.payload.rawNonce || '');
        check('raw nonce is 64 hex chars and its SHA-256 is the nonce Google got', /^[0-9a-f]{64}$/.test(r.payload.rawNonce || '') && r.payload.idToken === 'stub-google-id-token.nonce.' + hashed);
        check('iOS returns an access token', typeof r.payload.accessToken === 'string');

        r = await reqWithId('SIGN_IN_WITH_GOOGLE', { intent: 'sign_in', authContextId: c1 }, G, 'g-first', 3000);
        check('reused requestId -> invalid_payload, no second credential', r.type === 'GOOGLE_SIGN_IN_FAILED' && r.payload.code === 'invalid_payload');

        const target = reqWithId('SIGN_IN_WITH_GOOGLE', { intent: 'sign_in', authContextId: c1 }, G, 'g-cancel', 10000);
        await sleep(200);
        r = await req('CANCEL_GOOGLE_SIGN_IN', { authContextId: c1, targetRequestId: 'g-cancel' }, ['GOOGLE_SIGN_IN_CANCEL_ACCEPTED']);
        check('cancel accepted', r.payload.cancelled === true && r.payload.targetRequestId === 'g-cancel');
        r = await target;
        check('cancelled request answered once with cancelled', r.type === 'GOOGLE_SIGN_IN_FAILED' && r.payload.code === 'cancelled');
        const late = waitFor(['GOOGLE_SIGN_IN_SUCCESS'], 2500);
        check('the SDK result after cancel is dropped', (await late).type === 'TIMEOUT');

        await laAuth('stub-google-user-a');
        const cA = (await req('SYNC_AUTH_CONTEXT', { userId: 'stub-google-user-a' }, ['AUTH_CONTEXT_SYNCED'])).payload.authContextId;
        check('a different owner gets a new context', cA !== c1);
        r = await req('SIGN_IN_WITH_GOOGLE', { intent: 'sign_in', authContextId: c1 }, G);
        check('the old context is stale', r.payload.code === 'stale_context');
        const link = reqWithId('SIGN_IN_WITH_GOOGLE', { intent: 'link', authContextId: cA }, G, 'g-link', 10000);
        await sleep(200);
        await laAuth('stub-google-user-a');
        r = await link;
        check('token refresh for the same user keeps the link attempt', r.type === 'GOOGLE_SIGN_IN_SUCCESS' && r.payload.intent === 'link' && r.payload.authContextId === cA);

        const lost = reqWithId('SIGN_IN_WITH_GOOGLE', { intent: 'link', authContextId: cA }, G, 'g-lost', 3500);
        await sleep(200);
        await laAuth('stub-google-user-b');
        r = await lost;
        check('owner change during the attempt -> result dropped', r.type === 'TIMEOUT');
        r = await req('SIGN_IN_WITH_GOOGLE', { intent: 'link', authContextId: cA }, G);
        check('then the old context is stale', r.payload.code === 'stale_context');

        const cB = (await req('SYNC_AUTH_CONTEXT', { userId: 'stub-google-user-b' }, ['AUTH_CONTEXT_SYNCED'])).payload.authContextId;
        r = await req('CLEAR_GOOGLE_SIGN_IN', { authContextId: cB }, ['GOOGLE_SIGN_IN_CLEARED']);
        const cleared = r.payload.authContextId;
        check('clear -> new context, provider cleared', typeof cleared === 'string' && cleared !== cB && r.payload.providerCleared === true);
        r = await req('SIGN_IN_WITH_GOOGLE', { intent: 'link', authContextId: cB }, G);
        check('context before clear is stale', r.payload.code === 'stale_context');

        const frame = document.createElement('iframe');
        frame.srcdoc = '<script>window.webkit.messageHandlers.honouredNative.postMessage({type:"SYNC_AUTH_CONTEXT",payload:{requestId:"from-iframe",userId:null}})</' + 'script>';
        const iframeReply = new Promise((resolve) => { pending.set('from-iframe', { expected: ['AUTH_CONTEXT_SYNCED', 'ERROR'], resolve }); setTimeout(() => resolve({ type: 'TIMEOUT' }), 2000); });
        document.body.appendChild(frame);
        check('same-origin iframe gets no reply', (await iframeReply).type === 'TIMEOUT');

        await req('CLEAR_AUTH_SESSION', {}, ['AUTH_SESSION_CLEARED']);
        log('SCENARIO DONE');
      },

      // Run with -HonouredFakeGoogle slow. Starts a sign-in, reloads the page
      // while Google's UI is up, and checks the new page never receives it.
      async 'google-reload'() {
        if (sessionStorage.getItem('google-reload') !== 'reloaded') {
          const c = (await req('SYNC_AUTH_CONTEXT', { userId: null }, ['AUTH_CONTEXT_SYNCED'])).payload.authContextId;
          post('SIGN_IN_WITH_GOOGLE', { requestId: 'g-reload', intent: 'sign_in', authContextId: c });
          await sleep(300);
          sessionStorage.setItem('google-reload', 'reloaded');
          log('reloading while the Google UI is up');
          post('STUB_RELOAD', {});
          await sleep(10000);
          return;
        }
        sessionStorage.removeItem('google-reload');
        const any = waitFor(['GOOGLE_SIGN_IN_SUCCESS', 'GOOGLE_SIGN_IN_FAILED'], 6000);
        check('no Google result reaches the reloaded page', (await any).type === 'TIMEOUT');
        const c = (await req('SYNC_AUTH_CONTEXT', { userId: null }, ['AUTH_CONTEXT_SYNCED'])).payload.authContextId;
        const r = await req('SIGN_IN_WITH_GOOGLE', { intent: 'sign_in', authContextId: c }, ['GOOGLE_SIGN_IN_SUCCESS', 'GOOGLE_SIGN_IN_FAILED'], 10000);
        check('the new page can sign in once the old UI has closed', r.type === 'GOOGLE_SIGN_IN_SUCCESS' && r.payload.requestId && r.payload.authContextId === c);
        log('SCENARIO DONE');
      },
      async 'timer-foreground'() {
        let r = await req('GET_TIMER_STATE', {}, ['TIMER_STATE']);
        check('initial state inactive', r.type === 'TIMER_STATE' && r.payload.active === false);

        const completed = waitFor(['TIMER_COMPLETED'], 12000);
        r = await req('START_TIMER', { activityId: 'act-1', activityName: 'Cold plunge', durationSeconds: 5 }, ['TIMER_STARTED']);
        check('TIMER_STARTED act-1 with endsAt', r.type === 'TIMER_STARTED' && r.payload.activityId === 'act-1' && typeof r.payload.endsAt === 'string');
        const endsAt = Date.parse(r.payload.endsAt);
        check('endsAt ≈ now + 5 s', Math.abs(endsAt - (Date.now() + 5000)) < 1500);

        r = await req('GET_TIMER_STATE', {}, ['TIMER_STATE']);
        check('state active act-1', r.type === 'TIMER_STATE' && r.payload.active === true && r.payload.activityId === 'act-1');

        r = await completed;
        check('TIMER_COMPLETED act-1 notified:false (app active)', r.type === 'TIMER_COMPLETED' && r.payload.activityId === 'act-1' && r.payload.notified === false);
        check('completedAt == endsAt', r.type === 'TIMER_COMPLETED' && Date.parse(r.payload.completedAt) === endsAt);

        const dup = await waitFor(['TIMER_COMPLETED'], 2500);
        check('no duplicate TIMER_COMPLETED', dup.type === 'TIMEOUT');

        r = await req('GET_TIMER_STATE', {}, ['TIMER_STATE']);
        check('state inactive after completion', r.payload.active === false);

        // Replacing a running timer: broadcast TIMER_CANCELLED for the old one first.
        const cancelledA = waitFor(['TIMER_CANCELLED'], 3000);
        r = await req('START_TIMER', { activityId: 'act-A', activityName: 'A', durationSeconds: 60 }, ['TIMER_STARTED']);
        check('start act-A', r.type === 'TIMER_STARTED');
        r = await req('START_TIMER', { activityId: 'act-B', activityName: 'B', durationSeconds: 60 }, ['TIMER_STARTED']);
        check('start act-B replaces A', r.type === 'TIMER_STARTED' && r.payload.activityId === 'act-B');
        const c = await cancelledA;
        check('broadcast TIMER_CANCELLED act-A (no requestId)', c.type === 'TIMER_CANCELLED' && c.payload.activityId === 'act-A' && !c.payload.requestId);

        r = await req('CANCEL_TIMER', { activityId: 'act-A' }, ['TIMER_CANCELLED']);
        check('CANCEL_TIMER for non-running act-A → ERROR timer_not_active', r.type === 'ERROR' && r.payload.code === 'timer_not_active');
        r = await req('CANCEL_TIMER', { activityId: 'act-B' }, ['TIMER_CANCELLED']);
        check('CANCEL_TIMER act-B', r.type === 'TIMER_CANCELLED' && r.payload.activityId === 'act-B');
        r = await req('CANCEL_TIMER', { activityId: 'act-B' }, ['TIMER_CANCELLED']);
        check('CANCEL_TIMER act-B again is idempotent', r.type === 'TIMER_CANCELLED');
        r = await req('GET_TIMER_STATE', {}, ['TIMER_STATE']);
        check('state inactive after cancel', r.payload.active === false);

        r = await req('START_TIMER', { activityId: '', activityName: 'x', durationSeconds: 5 }, ['TIMER_STARTED']);
        check('invalid START_TIMER → ERROR invalid_timer', r.type === 'ERROR' && r.payload.code === 'invalid_timer');
        r = await req('START_TIMER', { activityId: 'act-Z', activityName: 'Z', durationSeconds: 0 }, ['TIMER_STARTED']);
        check('zero duration → ERROR invalid_timer', r.type === 'ERROR' && r.payload.code === 'invalid_timer');
        log('SCENARIO DONE');
      },
      async 'timer-background-start'() {
        const r = await req('START_TIMER', { activityId: 'act-bg', activityName: 'Background', durationSeconds: 20 }, ['TIMER_STARTED']);
        check('started act-bg 20 s', r.type === 'TIMER_STARTED');
        log('SCENARIO DONE');
      },
      // Start, cancel, then background the app: no banner may appear at endsAt.
      async 'timer-cancel-background'() {
        let r = await req('START_TIMER', { activityId: 'act-cx', activityName: 'Cancelled', durationSeconds: 15 }, ['TIMER_STARTED']);
        check('started act-cx 15 s', r.type === 'TIMER_STARTED');
        r = await req('CANCEL_TIMER', { activityId: 'act-cx' }, ['TIMER_CANCELLED']);
        check('cancelled act-cx', r.type === 'TIMER_CANCELLED');
        r = await req('GET_TIMER_STATE', {}, ['TIMER_STATE']);
        check('state inactive after cancel', r.payload.active === false);
        log('SCENARIO DONE');
      },
      async 'timer-state'() {
        const r = await req('GET_TIMER_STATE', {}, ['TIMER_STATE']);
        log('STATE ' + JSON.stringify(r.payload));
        log('SCENARIO DONE');
      },
      // Needs a human on the simulator: the Apple sheet must be completed or
      // cancelled by hand. Logs never contain the token, code or nonce.
      async 'apple'() {
        const first = req('SIGN_IN_WITH_APPLE', {}, ['APPLE_SIGN_IN_SUCCESS', 'APPLE_SIGN_IN_FAILED'], 120000);
        await sleep(300);
        const second = await req('SIGN_IN_WITH_APPLE', {}, ['APPLE_SIGN_IN_SUCCESS', 'APPLE_SIGN_IN_FAILED'], 5000);
        check('second request while the sheet is up fails immediately', second.type === 'APPLE_SIGN_IN_FAILED' && second.payload.code === 'failed');
        const r = await first;
        if (r.type === 'APPLE_SIGN_IN_SUCCESS') {
          const p = r.payload;
          check('success carries identityToken, rawNonce and user.id', typeof p.identityToken === 'string' && p.identityToken.length > 100 && typeof p.rawNonce === 'string' && p.rawNonce.length === 64 && typeof p.user?.id === 'string');
          check('identityToken looks like a JWT', p.identityToken.split('.').length === 3);
        } else if (r.type === 'APPLE_SIGN_IN_FAILED') {
          check('failure has code cancelled|failed and a message', ['cancelled', 'failed'].includes(r.payload.code) && typeof r.payload.message === 'string');
          log('RESULT ' + r.payload.code + ': ' + r.payload.message);
        } else {
          check('sheet answered within 120 s', false);
        }
        log('SCENARIO DONE');
      },
      async 'sound'() {
        let r = await req('SET_SOUND_ENABLED', { enabled: true }, ['SOUND_STATE']);
        check('SOUND_STATE enabled:true', r.type === 'SOUND_STATE' && r.payload.enabled === true && typeof r.payload.gongBundled === 'boolean');
        log('gongBundled=' + r.payload.gongBundled);
        r = await req('SET_SOUND_ENABLED', { enabled: 1 }, ['SOUND_STATE']);
        check('numeric enabled → ERROR invalid_sound_state', r.type === 'ERROR' && r.payload.code === 'invalid_sound_state');
        r = await req('SET_SOUND_ENABLED', { enabled: 'yes' }, ['SOUND_STATE']);
        check('string enabled → ERROR invalid_sound_state', r.type === 'ERROR' && r.payload.code === 'invalid_sound_state');
        // A running timer must survive the toggle with the same endsAt.
        r = await req('START_TIMER', { activityId: 'act-snd', activityName: 'Sound check', durationSeconds: 120 }, ['TIMER_STARTED']);
        const endsAt = r.payload.endsAt;
        r = await req('SET_SOUND_ENABLED', { enabled: false }, ['SOUND_STATE']);
        check('SOUND_STATE enabled:false', r.type === 'SOUND_STATE' && r.payload.enabled === false);
        await sleep(500);
        r = await req('GET_TIMER_STATE', {}, ['TIMER_STATE']);
        check('timer still running with the same endsAt after toggling sound', r.payload.active === true && r.payload.endsAt === endsAt);
        r = await req('CANCEL_TIMER', { activityId: 'act-snd' }, ['TIMER_CANCELLED']);
        log('SCENARIO DONE');
      },
      // Launch with -HonouredFakeHealthTotals steps=9000,active_energy=250
      async 'goals'() {
        const walk = { activityId: 'act-walk', activityName: 'Walk', metric: 'steps', target: 8000, unit: 'count' };
        const burn = { activityId: 'act-burn', activityName: 'Burn', metric: 'active_energy', target: 400, unit: 'kcal' };
        const swim = { activityId: 'act-swim', activityName: 'Swim', metric: 'distance_swimming', target: 500, unit: 'meters' };

        let reached = waitFor(['GOAL_REACHED'], 4000);
        let r = await req('SET_GOALS', { goals: [walk, burn, swim] }, ['GOALS_ACCEPTED']);
        check('GOALS_ACCEPTED count 3', r.type === 'GOALS_ACCEPTED' && r.payload.count === 3);
        r = await reached;
        check('GOAL_REACHED act-walk (9000 ≥ 8000) notified:false in-app', r.type === 'GOAL_REACHED' && r.payload.activityId === 'act-walk' && r.payload.value === 9000 && r.payload.target === 8000 && r.payload.metric === 'steps' && r.payload.notified === false && typeof r.payload.reachedAt === 'string');
        let extra = await waitFor(['GOAL_REACHED'], 2500);
        check('no GOAL_REACHED for act-burn (250 < 400) or act-swim (no data)', extra.type === 'TIMEOUT');

        r = await req('SET_GOALS', { goals: [walk, burn, swim] }, ['GOALS_ACCEPTED']);
        extra = await waitFor(['GOAL_REACHED'], 2500);
        check('re-sending goals does not repeat GOAL_REACHED act-walk (marker)', extra.type === 'TIMEOUT');

        r = await req('ACTIVITY_COMPLETED', { activityId: 'act-burn', source: 'manual' }, ['ACTIVITY_COMPLETION_ACCEPTED']);
        check('ACTIVITY_COMPLETED act-burn accepted', r.type === 'ACTIVITY_COMPLETION_ACCEPTED' && r.payload.activityId === 'act-burn');
        // A timer completion names the contract id; its goal slots must go quiet too.
        r = await req('SET_GOALS', { goals: [walk, burn, swim, { activityId: 'ctr-7:primary', activityName: 'Row', metric: 'steps', target: 100000, unit: 'count' }] }, ['GOALS_ACCEPTED']);
        r = await req('ACTIVITY_COMPLETED', { activityId: 'ctr-7', source: 'timer' }, ['ACTIVITY_COMPLETION_ACCEPTED']);
        r = await req('SET_GOALS', { goals: [walk, burn, swim, { activityId: 'ctr-7:primary', activityName: 'Row', metric: 'steps', target: 10, unit: 'count' }] }, ['GOALS_ACCEPTED']);
        extra = await waitFor(['GOAL_REACHED'], 2500);
        check('slot goal ctr-7:primary stays silent after ACTIVITY_COMPLETED for ctr-7', extra.type === 'TIMEOUT');
        r = await req('SET_GOALS', { goals: [walk, burn, swim] }, ['GOALS_ACCEPTED']);
        r = await req('ACTIVITY_COMPLETED', { activityId: 'act-x', source: 'bogus' }, ['ACTIVITY_COMPLETION_ACCEPTED']);
        check('ACTIVITY_COMPLETED with unknown source → ERROR', r.type === 'ERROR' && r.payload.code === 'invalid_activity_completion');

        // Lower the burn target below the fake total: act-burn is now met but was
        // celebrated by the web already, so it must stay silent.
        r = await req('SET_GOALS', { goals: [walk, { ...burn, target: 200 }, swim] }, ['GOALS_ACCEPTED']);
        extra = await waitFor(['GOAL_REACHED'], 2500);
        check('celebrated act-burn stays silent after target lowered', extra.type === 'TIMEOUT');

        // A brand-new activity on the same metric fires immediately.
        reached = waitFor(['GOAL_REACHED'], 4000);
        r = await req('SET_GOALS', { goals: [walk, { activityId: 'act-burn-2', activityName: 'Burn 2', metric: 'active_energy', target: 200, unit: 'kcal' }] }, ['GOALS_ACCEPTED']);
        r = await reached;
        check('GOAL_REACHED act-burn-2 (250 ≥ 200)', r.type === 'GOAL_REACHED' && r.payload.activityId === 'act-burn-2' && r.payload.value === 250);

        // Changing the reset hour clears markers and re-evaluates in-app.
        const hour = (new Date().getHours() + 2) % 24;
        const reannounced = [];
        const collector = (e) => { if (e.detail.type === 'GOAL_REACHED') reannounced.push(e.detail.payload); };
        window.addEventListener('honoured:native', collector);
        r = await req('SET_DAY_RESET_HOUR', { hour }, ['DAY_RESET_HOUR_ACCEPTED']);
        check('DAY_RESET_HOUR_ACCEPTED', r.type === 'DAY_RESET_HOUR_ACCEPTED' && r.payload.hour === hour);
        await sleep(3000);
        window.removeEventListener('honoured:native', collector);
        const ids = reannounced.map((p) => p.activityId).sort().join(',');
        check('after reset-hour change both met goals are re-announced in-app once (act-burn-2, act-walk; notified:false)', ids === 'act-burn-2,act-walk' && reannounced.every((p) => p.notified === false));
        r = await req('SET_DAY_RESET_HOUR', { hour }, ['DAY_RESET_HOUR_ACCEPTED']);
        extra = await waitFor(['GOAL_REACHED'], 2500);
        check('same reset hour again does not re-announce', extra.type === 'TIMEOUT');

        r = await req('SET_GOALS', { goals: [] }, ['GOALS_ACCEPTED']);
        check('empty goals accepted', r.type === 'GOALS_ACCEPTED' && r.payload.count === 0);
        r = await req('SET_DAY_RESET_HOUR', { hour: 0 }, ['DAY_RESET_HOUR_ACCEPTED']);
        log('SCENARIO DONE');
      },
      // The acceptance table of docs/live-activities-plan.vi.md, section 1.
      async 'live-activities-multiple'() {
        let r = await laReset('stub-user-a');
        check('SET_AUTH_SESSION returns a Live Activity session id', r.type === 'AUTH_SESSION_ACCEPTED' && typeof laSession === 'string' && laSession.length > 0);
        let s = await laState();
        check('capability: supported and enabled', s.payload.supported === true && s.payload.enabled === true && s.payload.liveActivityBridgeSessionId === laSession);
        const { walk, exercise, meditation } = demo;
        r = await req('SET_GOALS', { goals: [...goalsFor(walk), ...goalsFor(exercise)] }, ['GOALS_ACCEPTED']);
        check('goals accepted', r.type === 'GOALS_ACCEPTED' && r.payload.count === 2);
        await fake('steps=2000,exercise_minutes=5');

        r = await track(walk);
        check('open Walking: active and focused', r.type === 'CONTRACT_TRACKING_ACCEPTED' && r.payload.presentationStatus === 'active' && r.payload.focused === true);
        r = await track(exercise);
        check('open Exercise: active and focused', r.payload.presentationStatus === 'active' && r.payload.focused === true);
        s = await laState();
        check('Walking keeps its card but loses focus', entry(s, 'c-walk')?.presentationStatus === 'active' && entry(s, 'c-walk')?.focused === false);

        r = await startTracked(meditation, 600);
        check('Start Meditation 10 min: TIMER_STARTED with liveActivityStatus active', r.type === 'TIMER_STARTED' && r.payload.liveActivityStatus === 'active');
        await sleep(800);
        let list = await laList();
        check('three separate cards', ['c-walk', 'c-exercise', 'c-meditation'].every((id) => card(list, id)));
        check('relevance: Meditation 100, Exercise 99, Walking 98', card(list, 'c-meditation')?.relevanceScore === 100 && card(list, 'c-exercise')?.relevanceScore === 99 && card(list, 'c-walk')?.relevanceScore === 98);
        check('Meditation card counts down', !!card(list, 'c-meditation')?.timer && card(list, 'c-meditation').timer.finished === false);
        check('Walking shows 2000 of 8000 steps, fresh', card(list, 'c-walk')?.health?.[0]?.value === 2000 && card(list, 'c-walk').health[0].target === 8000 && card(list, 'c-walk').health[0].dataStatus === 'fresh');

        r = await track(walk);
        check('reopen Walking: focused', r.payload.focused === true);
        await sleep(800);
        list = await laList();
        check('all three kept; Walking 100, Meditation 99, Exercise 98', card(list, 'c-walk')?.relevanceScore === 100 && card(list, 'c-meditation')?.relevanceScore === 99 && card(list, 'c-exercise')?.relevanceScore === 98);
        r = await req('GET_TIMER_STATE', {}, ['TIMER_STATE']);
        check('Meditation still counting after focus moved', r.payload.active === true && r.payload.activityId === 'c-meditation');

        const reached = waitFor(['GOAL_REACHED'], 8000);
        const changed = waitFor(['LIVE_ACTIVITY_STATE_CHANGED'], 8000);
        await fake('steps=2000,exercise_minutes=31');
        r = await reached;
        check('GOAL_REACHED c-exercise:primary', r.type === 'GOAL_REACHED' && r.payload.activityId === 'c-exercise:primary');
        r = await changed;
        check('LIVE_ACTIVITY_STATE_CHANGED is a broadcast', r.type === 'LIVE_ACTIVITY_STATE_CHANGED' && !r.payload.requestId);
        s = await laState();
        check('Exercise ended as completed; Walking and Meditation untouched', entry(s, 'c-exercise')?.presentationStatus === 'ended' && entry(s, 'c-exercise')?.reason === 'completed' && entry(s, 'c-walk')?.presentationStatus === 'active' && entry(s, 'c-meditation')?.presentationStatus === 'active');
        check('Walking keeps priority', s.payload.focusedOccurrence?.contractId === 'c-walk');
        list = await laList();
        const done = list.find((a) => a.contractId === 'c-exercise');
        check('Exercise final content says completed', !!done && done.status === 'completed' && done.activityState === 'ended');

        r = await req('CLEAR_AUTH_SESSION', {}, ['AUTH_SESSION_CLEARED']);
        await sleep(800);
        s = await laState();
        list = await laList();
        check('logout removes every card and every tracked contract', (s.payload.tracked || []).length === 0 && list.length === 0);
        log('SCENARIO DONE');
      },
      async 'live-activities-focus-race'() {
        await laReset('stub-user-a');
        const a = healthContract('c-a', 'Contract A', [steps(5000)]);
        const b = healthContract('c-b', 'Contract B', [{ slot: 'primary', name: 'Energy', metric: 'active_energy', target: 300, unit: 'kcal' }]);
        await req('SET_GOALS', { goals: [...goalsFor(a), ...goalsFor(b)] }, ['GOALS_ACCEPTED']);
        await fake('steps=1000,active_energy=50');
        // Open A then B without waiting for either reply.
        const envA = env();
        const envB = env();
        const idA = 'race-a-' + Date.now();
        const idB = 'race-b-' + Date.now();
        const pa = reqWithId('TRACK_CONTRACT', { ...envA, reason: 'opened', contract: a }, ['CONTRACT_TRACKING_ACCEPTED'], idA);
        const pb = reqWithId('TRACK_CONTRACT', { ...envB, reason: 'opened', contract: b }, ['CONTRACT_TRACKING_ACCEPTED'], idB);
        const [ra, rb] = await Promise.all([pa, pb]);
        check('both opens accepted', ra.type === 'CONTRACT_TRACKING_ACCEPTED' && rb.type === 'CONTRACT_TRACKING_ACCEPTED');
        let s = await laState();
        check('B, opened last, has priority', s.payload.focusedOccurrence?.contractId === 'c-b');
        const retry = await reqWithId('TRACK_CONTRACT', { ...envA, reason: 'opened', contract: a }, ['CONTRACT_TRACKING_ACCEPTED'], idA);
        check('transport retry of A replays the first reply', retry.type === 'CONTRACT_TRACKING_ACCEPTED' && JSON.stringify(retry.payload) === JSON.stringify(ra.payload));
        s = await laState();
        check('the retry does not move priority back to A', s.payload.focusedOccurrence?.contractId === 'c-b');
        let r = await reqWithId('TRACK_CONTRACT', { ...envA, reason: 'opened', contract: a }, ['CONTRACT_TRACKING_ACCEPTED'], 'late-' + Date.now());
        check('an old clientSequence under a new requestId: stale_sequence', r.type === 'ERROR' && r.payload.code === 'stale_sequence');
        r = await req('TRACK_CONTRACT', { bridgeSessionId: 'not-this-session', clientSequence: 999999, reason: 'opened', contract: a }, ['CONTRACT_TRACKING_ACCEPTED']);
        check('unknown bridgeSessionId: stale_bridge_session', r.type === 'ERROR' && r.payload.code === 'stale_bridge_session');
        r = await req('TRACK_CONTRACT', { reason: 'opened', contract: a }, ['CONTRACT_TRACKING_ACCEPTED']);
        check('missing envelope: invalid_envelope', r.type === 'ERROR' && r.payload.code === 'invalid_envelope');
        r = await req('TRACK_CONTRACT', { ...env(), reason: 'opened', contract: { ...a, activities: [{ ...a.activities[0], target: 9999 }] } }, ['CONTRACT_TRACKING_ACCEPTED']);
        check('a target that disagrees with SET_GOALS: goal_definition_mismatch', r.type === 'ERROR' && r.payload.code === 'goal_definition_mismatch');
        r = await req('TRACK_CONTRACT', { ...env(), reason: 'opened', contract: { ...a, healthDay: '2020-01-01' } }, ['CONTRACT_TRACKING_ACCEPTED']);
        check('another health day: health_day_mismatch', r.type === 'ERROR' && r.payload.code === 'health_day_mismatch' && r.payload.expectedHealthDay === today());
        r = await req('TRACK_CONTRACT', { ...env(), reason: 'opened', contract: { ...a, completionPolicy: { kind: 'all_health_slots', requiredActivityIds: [] } } }, ['CONTRACT_TRACKING_ACCEPTED']);
        check('a policy that is not every Health slot: invalid_contract', r.type === 'ERROR' && r.payload.code === 'invalid_contract');
        r = await req('SYNC_TRACKED_CONTRACTS', { ...env(), contracts: [a, b] }, ['TRACKED_CONTRACTS_SYNCED']);
        check('SYNC lists both occurrences', r.type === 'TRACKED_CONTRACTS_SYNCED' && r.payload.tracked.length === 2);
        s = await laState();
        check('SYNC does not change priority', s.payload.focusedOccurrence?.contractId === 'c-b');
        r = await req('SYNC_TRACKED_CONTRACTS', { ...env(), contracts: [a] }, ['TRACKED_CONTRACTS_SYNCED']);
        await sleep(600);
        s = await laState();
        const list = await laList();
        check('B left the snapshot: no longer tracked, card gone', !entry(s, 'c-b') && !card(list, 'c-b'));
        check('priority falls back to A', s.payload.focusedOccurrence?.contractId === 'c-a' && card(list, 'c-a')?.relevanceScore === 100);
        r = await req('STOP_TRACKING_CONTRACT', { ...env(), contractId: 'c-a', healthDay: today(), reason: 'user_stopped' }, ['CONTRACT_TRACKING_STOPPED']);
        check('STOP_TRACKING_CONTRACT', r.type === 'CONTRACT_TRACKING_STOPPED' && r.payload.stopped === true);
        r = await req('STOP_TRACKING_CONTRACT', { ...env(), contractId: 'c-a', healthDay: today(), reason: 'user_stopped' }, ['CONTRACT_TRACKING_STOPPED']);
        check('STOP_TRACKING_CONTRACT again is idempotent', r.type === 'CONTRACT_TRACKING_STOPPED' && r.payload.stopped === true);
        await req('CLEAR_AUTH_SESSION', {}, ['AUTH_SESSION_CLEARED']);
        log('SCENARIO DONE');
      },
      async 'live-activities-health'() {
        await laReset('stub-user-a');
        const two = healthContract('c-two', 'Walk and burn', [steps(8000),
          { slot: 'secondary', name: 'Active energy', metric: 'active_energy', target: 400, unit: 'kcal' }]);
        await req('SET_GOALS', { goals: goalsFor(two) }, ['GOALS_ACCEPTED']);
        await fake('steps=none,active_energy=none');
        let r = await track(two);
        check('two Health slots: tracked', r.payload.presentationStatus === 'active');
        await sleep(800);
        let list = await laList();
        check('two slots, one card', list.filter((a) => a.contractId === 'c-two').length === 1);
        let c = card(list, 'c-two');
        check('no data is not zero: value null, noData', c?.health?.length === 2 && c.health.every((h) => h.value === null && h.dataStatus === 'noData'));
        await fake('steps=2000,active_energy=100');
        c = card(await laList(), 'c-two');
        check('25%: 2000 steps and 100 kcal, fresh', c.health[0].value === 2000 && c.health[1].value === 100 && c.health.every((h) => h.dataStatus === 'fresh'));
        await fake('steps=locked,active_energy=locked');
        c = card(await laList(), 'c-two');
        check('locked device keeps the last reading, marked unavailable', c.health[0].value === 2000 && c.health[0].dataStatus === 'unavailable' && c.health[1].value === 100);
        await fake('steps=error,active_energy=error');
        c = card(await laList(), 'c-two');
        check('a failed read keeps it too', c.health[0].value === 2000 && c.health[0].dataStatus === 'unavailable');
        await fake('steps=6400,active_energy=320');
        c = card(await laList(), 'c-two');
        check('80%: 6400 steps, 320 kcal, nothing reached', c.health[0].value === 6400 && c.health[1].value === 320 && !c.health[0].reached && !c.health[1].reached);
        await fake('steps=1500,active_energy=320');
        c = card(await laList(), 'c-two');
        check('deleted samples: the total may go down', c.health[0].value === 1500);
        await fake('steps=9000,active_energy=320');
        let s = await laState();
        c = card(await laList(), 'c-two');
        check('primary reached, secondary not: the contract is not honoured', entry(s, 'c-two')?.presentationStatus === 'active' && c.health[0].reached === true && c.health[1].reached === false && c.status === 'active');
        const changed = waitFor(['LIVE_ACTIVITY_STATE_CHANGED'], 8000);
        await fake('steps=9000,active_energy=450');
        await changed;
        s = await laState();
        check('both slots reached: completed', entry(s, 'c-two')?.presentationStatus === 'ended' && entry(s, 'c-two')?.reason === 'completed');
        const done = (await laList()).find((a) => a.contractId === 'c-two');
        check('final content: completed, both reached', done?.status === 'completed' && done.health.every((h) => h.reached));
        await req('SET_GOALS', { goals: [] }, ['GOALS_ACCEPTED']);
        await req('CLEAR_AUTH_SESSION', {}, ['AUTH_SESSION_CLEARED']);
        log('SCENARIO DONE');
      },
      async 'live-activities-timer'() {
        await laReset('stub-user-a');
        await req('SET_GOALS', { goals: [] }, ['GOALS_ACCEPTED']);
        const med = timerContract('c-med', 'Meditation');
        let r = await track(med);
        check('opening a timer-only contract records it without an empty card', r.payload.presentationStatus === 'awaiting_timer');
        check('no card yet', !card(await laList(), 'c-med'));
        const e = env();
        const rid = 'start-med-' + Date.now();
        const body = { activityId: 'c-med', activityName: 'Meditation', durationSeconds: 120, trackingContext: { ...e, timerActivityId: 'c-med', contract: med } };
        r = await reqWithId('START_TIMER', body, ['TIMER_STARTED'], rid);
        check('START_TIMER with tracking: active card', r.type === 'TIMER_STARTED' && r.payload.liveActivityStatus === 'active');
        const endsAt = r.payload.endsAt;
        await sleep(1500);
        const retry = await reqWithId('START_TIMER', body, ['TIMER_STARTED'], rid);
        check('retrying the same START_TIMER replays it: same endsAt', retry.type === 'TIMER_STARTED' && retry.payload.endsAt === endsAt);
        r = await req('GET_TIMER_STATE', {}, ['TIMER_STATE']);
        check('the timer was not restarted', r.payload.active === true && r.payload.endsAt === endsAt);
        check('one card with the countdown', card(await laList(), 'c-med')?.timer?.finished === false);
        r = await req('CANCEL_TIMER', { activityId: 'c-med', reason: 'paused', trackingContext: env() }, ['TIMER_CANCELLED']);
        check('pause: TIMER_CANCELLED with reason paused', r.type === 'TIMER_CANCELLED' && r.payload.reason === 'paused');
        await sleep(600);
        let s = await laState();
        check('a timer-only card ends while paused', entry(s, 'c-med')?.presentationStatus === 'awaiting_timer' && !card(await laList(), 'c-med'));
        const completed = waitFor(['TIMER_COMPLETED'], 20000);
        r = await startTracked(med, 4);
        check('resume (a new start): new card', r.payload.liveActivityStatus === 'active');
        const resumedEndsAt = r.payload.endsAt;
        await sleep(5500);
        // In the foreground with nothing covering the app the deadline task
        // completes it right away; under a system alert, or suspended, the
        // countdown sits at zero until the next reconcile processes it.
        s = await laState();
        check('at zero: stale until processed, or already completed', ['stale', 'ended'].includes(entry(s, 'c-med')?.presentationStatus));
        r = await req('GET_TIMER_STATE', {}, ['TIMER_STATE']);
        check('reconcile after the deadline: timer inactive', r.payload.active === false);
        r = await completed;
        check('TIMER_COMPLETED reaches the web with completedAt = endsAt', r.type === 'TIMER_COMPLETED' && r.payload.activityId === 'c-med' && Date.parse(r.payload.completedAt) === Date.parse(resumedEndsAt) && typeof r.payload.notified === 'boolean');
        check('…exactly once', (await waitFor(['TIMER_COMPLETED'], 1500)).type === 'TIMEOUT');
        await sleep(800);
        s = await laState();
        check('natural finish under timer_completion: completed', entry(s, 'c-med')?.presentationStatus === 'ended' && entry(s, 'c-med')?.reason === 'completed');
        const fin = (await laList()).find((a) => a.contractId === 'c-med' && a.status === 'completed');
        check('final content shows the finished timer', !!fin && fin.timer?.finished === true);

        const walk = healthContract('c-walk2', 'Walk', [steps(8000)]);
        await req('SET_GOALS', { goals: goalsFor(walk) }, ['GOALS_ACCEPTED']);
        await fake('steps=3000');
        r = await startTracked(walk, 300);
        check('Health contract with a running timer: one card', r.payload.liveActivityStatus === 'active');
        const replacedBroadcast = waitFor(['TIMER_CANCELLED'], 5000);
        r = await startTracked(timerContract('c-med2', 'Breathwork'), 300);
        const rb = await replacedBroadcast;
        check('another start broadcasts TIMER_CANCELLED for the first timer', rb.type === 'TIMER_CANCELLED' && rb.payload.activityId === 'c-walk2' && !rb.payload.requestId);
        await sleep(600);
        const list = await laList();
        check('the replaced contract keeps its Health card, without the timer', !!card(list, 'c-walk2') && !card(list, 'c-walk2').timer && card(list, 'c-walk2').health[0].value === 3000);
        check('the new timer leads', card(list, 'c-med2')?.relevanceScore === 100);
        r = await req('START_TIMER', { activityId: 'c-x', activityName: 'X', durationSeconds: 60, trackingContext: { bridgeSessionId: 'stale', clientSequence: 1, contract: med } }, ['TIMER_STARTED']);
        check('a stale tracking context is refused before the timer is touched', r.type === 'ERROR' && r.payload.code === 'stale_bridge_session');
        r = await req('GET_TIMER_STATE', {}, ['TIMER_STATE']);
        check('…so c-med2 is still the running timer', r.payload.activityId === 'c-med2');
        await req('CANCEL_TIMER', { activityId: 'c-med2' }, ['TIMER_CANCELLED']);
        await req('CLEAR_AUTH_SESSION', {}, ['AUTH_SESSION_CLEARED']);
        log('SCENARIO DONE');
      },
      async 'live-activities-account'() {
        await laReset('stub-user-a');
        const walk = healthContract('c-acct', 'Walk A', [steps(8000)]);
        await req('SET_GOALS', { goals: goalsFor(walk) }, ['GOALS_ACCEPTED']);
        await fake('steps=1234');
        let r = await track(walk);
        check("user A's card is active", r.payload.presentationStatus === 'active');
        const oldSession = laSession;
        const oldEnv = env();
        await laAuth('stub-user-a');
        check('a token refresh for the same user keeps the session id', laSession === oldSession);
        let s = await laState();
        check('…and the tracking', entry(s, 'c-acct')?.presentationStatus === 'active');
        await laAuth('stub-user-b');
        check('another user gets a new session id', laSession !== oldSession);
        await sleep(800);
        s = await laState();
        const list = await laList();
        check("switching user ends every card of user A", (s.payload.tracked || []).length === 0 && list.length === 0);
        r = await req('TRACK_CONTRACT', { ...oldEnv, reason: 'opened', contract: walk }, ['CONTRACT_TRACKING_ACCEPTED']);
        check("user A's session id is refused for user B", r.type === 'ERROR' && r.payload.code === 'stale_bridge_session');
        r = await req('CLEAR_AUTH_SESSION', {}, ['AUTH_SESSION_CLEARED']);
        const cleared = r.payload.liveActivityBridgeSessionId;
        check('CLEAR_AUTH_SESSION returns a fresh session id', typeof cleared === 'string' && cleared !== laSession);
        r = await req('TRACK_CONTRACT', { bridgeSessionId: cleared, clientSequence: 1, reason: 'opened', contract: walk }, ['CONTRACT_TRACKING_ACCEPTED']);
        check('signed out: nothing is tracked until a session is set', r.type === 'ERROR' && r.payload.code === 'auth_session_required');
        log('SCENARIO DONE');
      },
      // Leaves three cards up for screenshots: background the app after READY
      // FOR BACKGROUND, bring it back, and Walking is reopened and takes the lead.
      async 'live-activities-demo'() {
        await laManualSetup();
        await track(demo.walk);
        await track(demo.exercise);
        await startTracked(demo.meditation, 1200);
        await sleep(800);
        log('READY FOR BACKGROUND');
        await new Promise((resolve) => {
          const onChange = () => { if (document.visibilityState === 'visible') { document.removeEventListener('visibilitychange', onChange); resolve(); } };
          document.addEventListener('visibilitychange', onChange);
        });
        const r = await track(demo.walk);
        check('reopened Walking leads', r.payload.focused === true);
        await sleep(800);
        log('READY FOR BACKGROUND AGAIN');
      },
      // Background the app right after READY FOR BACKGROUND and bring it back
      // after about 20 s: the card must sit at zero, stale, until the app runs
      // again, and only then end as completed.
      async 'live-activities-suspended-timer'() {
        await laReset('stub-user-a');
        await req('SET_GOALS', { goals: [] }, ['GOALS_ACCEPTED']);
        const sit = timerContract('c-bg', 'Evening sit');
        const completed = waitFor(['TIMER_COMPLETED'], 600000);
        let r = await startTracked(sit, 15);
        check('card with a 15 s countdown', r.type === 'TIMER_STARTED' && r.payload.liveActivityStatus === 'active');
        const endsAt = Date.parse(r.payload.endsAt);
        log('READY FOR BACKGROUND');
        // JavaScript stops while the app is suspended and resumes when it returns.
        while (Date.now() < endsAt + 3000) await sleep(500);
        r = await completed;
        check('the finish is processed once the app runs again, completedAt = endsAt', r.type === 'TIMER_COMPLETED' && Date.parse(r.payload.completedAt) === endsAt);
        log('notified=' + r.payload.notified + ' processedAfterMs=' + (Date.now() - endsAt));
        await sleep(800);
        const s = await laState();
        check('only then does the card end as completed', entry(s, 'c-bg')?.reason === 'completed');
        log('SCENARIO DONE');
      },
      // Run, terminate the app, then launch with live-activities-restore-check.
      async 'live-activities-restore-setup'() {
        await laReset('stub-user-a');
        const walk = healthContract('c-restore', 'Walk', [steps(8000)]);
        const gone = healthContract('c-gone', 'Energy', [{ slot: 'primary', name: 'Energy', metric: 'active_energy', target: 300, unit: 'kcal' }]);
        await req('SET_GOALS', { goals: [...goalsFor(walk), ...goalsFor(gone)] }, ['GOALS_ACCEPTED']);
        await fake('steps=4321,active_energy=10');
        await track(gone);
        const r = await track(walk);
        check('two cards before relaunch', r.payload.presentationStatus === 'active' && !!card(await laList(), 'c-gone'));
        const d = await req('STUB_DISMISS_LIVE_ACTIVITY', { contractId: 'c-gone', healthDay: today() }, ['STUB_LIVE_ACTIVITY_DISMISSED']);
        check('simulated swipe on c-gone', d.payload.dismissed === true);
        await sleep(1000);
        const s = await laState();
        check('a removed card is recorded as dismissed', entry(s, 'c-gone')?.presentationStatus === 'dismissed');
        check('priority stays with the remaining card', s.payload.focusedOccurrence?.contractId === 'c-restore');
        log('SCENARIO DONE');
      },
      async 'live-activities-restore-check'() {
        await laAuth('stub-user-a');
        const walk = healthContract('c-restore', 'Walk', [steps(8000)]);
        const gone = healthContract('c-gone', 'Energy', [{ slot: 'primary', name: 'Energy', metric: 'active_energy', target: 300, unit: 'kcal' }]);
        let s = await laState();
        check('after relaunch the surviving card is adopted as active', entry(s, 'c-restore')?.presentationStatus === 'active');
        check('the dismissed one stays dismissed', entry(s, 'c-gone')?.presentationStatus === 'dismissed');
        check('no duplicate card', (await laList()).filter((a) => a.contractId === 'c-restore' && a.activityState === 'active').length === 1);
        let r = await req('SYNC_TRACKED_CONTRACTS', { ...env(), contracts: [walk, gone] }, ['TRACKED_CONTRACTS_SYNCED']);
        await sleep(500);
        s = await laState();
        check('a sync does not bring the dismissed card back', r.type === 'TRACKED_CONTRACTS_SYNCED' && entry(s, 'c-gone')?.presentationStatus === 'dismissed' && !card(await laList(), 'c-gone'));
        r = await track(gone);
        check('an explicit open does', r.payload.presentationStatus === 'active');
        await req('CLEAR_AUTH_SESSION', {}, ['AUTH_SESSION_CLEARED']);
        log('SCENARIO DONE');
      },
      async 'live-activities-deeplink'() {
        await laReset('stub-user-a');
        const walk = healthContract('c-link', 'Walk', [steps(8000)]);
        await req('SET_GOALS', { goals: goalsFor(walk) }, ['GOALS_ACCEPTED']);
        await fake('steps=100');
        await track(walk);
        const opened = waitFor(['LIVE_ACTIVITY_OPENED'], 6000);
        let r = await req('STUB_OPEN_DEEP_LINK', { contractId: 'c-link', healthDay: today() }, ['STUB_DEEP_LINK_OPENED']);
        check('the card link opens through the system', r.payload.handled === true && r.payload.url.indexOf('honoured://contract/c-link?') === 0);
        r = await opened;
        check('LIVE_ACTIVITY_OPENED with eventId, contractId and healthDay', r.type === 'LIVE_ACTIVITY_OPENED' && typeof r.payload.eventId === 'string' && r.payload.contractId === 'c-link' && r.payload.healthDay === today());
        let none = waitFor(['LIVE_ACTIVITY_OPENED'], 2500);
        await req('STUB_OPEN_DEEP_LINK', { url: 'honoured://contract/c-link?day=' + today() + '&occurrence=00000000-0000-0000-0000-000000000000' }, ['STUB_DEEP_LINK_OPENED']);
        check('a token that is not ours opens nothing', (await none).type === 'TIMEOUT');
        none = waitFor(['LIVE_ACTIVITY_OPENED'], 2500);
        await req('STUB_OPEN_DEEP_LINK', { url: 'honoured://contract/c-link/extra?day=bad' }, ['STUB_DEEP_LINK_OPENED']);
        check('a malformed link is ignored', (await none).type === 'TIMEOUT');
        await req('CLEAR_AUTH_SESSION', {}, ['AUTH_SESSION_CLEARED']);
        log('SCENARIO DONE');
      },
    };

    post('APP_READY', {});
    const exitWhenDone = __EXIT_WHEN_DONE__;
    if (scenario && scenarios[scenario]) {
      setTimeout(() => scenarios[scenario]()
        .catch((e) => log('SCENARIO ERROR ' + e))
        .finally(() => { if (exitWhenDone) post('STUB_EXIT', {}); }), 300);
    }
    </script>
    </body></html>
    """
}
#endif
