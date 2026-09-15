#if DEBUG
import Foundation
import WebKit

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

    static func load(into webView: WKWebView) {
        let page = html.replacingOccurrences(of: "__SCENARIO__", with: scenario)
        webView.loadHTMLString(page, baseURL: nil)
    }

    static func log(_ line: String) {
        print("[bridge-stub] \(line)")
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
    <button onclick="req('GET_HEALTH_STATUS',{},['HEALTH_PERMISSION_STATUS'])">GET_HEALTH_STATUS</button>
    <button onclick="req('REQUEST_HEALTH_PERMISSION',{},['HEALTH_PERMISSION_STATUS'],60000)">REQUEST_HEALTH_PERMISSION</button>
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
    window.addEventListener('honoured:native', (e) => {
      const { type, payload } = e.detail;
      log('◀ ' + type + ' ' + JSON.stringify(payload));
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

    const scenarios = {
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
      async 'timer-state'() {
        const r = await req('GET_TIMER_STATE', {}, ['TIMER_STATE']);
        log('STATE ' + JSON.stringify(r.payload));
        log('SCENARIO DONE');
      },
    };

    post('APP_READY', {});
    if (scenario && scenarios[scenario]) {
      setTimeout(() => scenarios[scenario]().catch((e) => log('SCENARIO ERROR ' + e)), 300);
    }
    </script>
    </body></html>
    """
}
#endif
