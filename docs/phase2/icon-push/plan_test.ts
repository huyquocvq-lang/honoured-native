import { assertEquals, assert } from "jsr:@std/assert@1";
import {
  type Allowed, type Job, type PushToken, affirmation, classify, cut, deadlineLabel, plan, splitTarget, summarise,
  weekday,
} from "./plan.ts";

const NOW = 1791280800; // 2026-10-06 10:00 UTC = 21:00 in Sydney
const allowed: Allowed = { topics: new Set(["com.jimmy.upwork.honoured"]), environments: new Set(["sandbox", "production"]) };

function token(kind: PushToken["kind"], extra: Partial<PushToken> = {}): PushToken {
  return {
    installationId: "install-1", kind, token: kind === "device" ? "aa".repeat(32) : kind === "push_to_start" ? "bb".repeat(40) : "cc".repeat(40),
    environment: "sandbox", topic: "com.jimmy.upwork.honoured", osVersion: "18.1", liveActivitiesEnabled: true, ...extra,
  };
}

function job(slot: Job["job"], tokens: PushToken[], extra: Partial<Job> = {}): Job {
  return {
    job: slot, user_id: "u", contract_id: "11111111-1111-4111-8111-111111111111", client_id: "local-1",
    day: "2026-10-06", session_number: 5, total_sessions: 92,
    deadline_at: "2026-10-06T12:59:00+00:00", // 23:59 Sydney
    evening_at: "2026-10-06T09:00:00+00:00", status: "pending", activity: "Walking", target: "10000 steps",
    because: "Spring", timezone: "Australia/Sydney", morning_channel: null, tokens, ...extra,
  };
}

Deno.test("morning: push-to-start opens the card with the day's facts", () => {
  const sends = plan(job("morning", [token("device"), token("push_to_start")], { evening_at: "2026-10-06T11:00:00+00:00" }), NOW, allowed);
  assertEquals(sends.length, 1);
  const [send] = sends;
  assertEquals(send.channel, "live_activity_start");
  assertEquals(send.token, "bb".repeat(40));
  assertEquals(send.headers["apns-push-type"], "liveactivity");
  assertEquals(send.headers["apns-topic"], "com.jimmy.upwork.honoured.push-type.liveactivity");
  assertEquals(send.headers["apns-expiration"], String(1791291540));
  const aps = send.payload.aps as Record<string, unknown>;
  assertEquals(aps.event, "start");
  assertEquals(aps["attributes-type"], "IconActivityAttributes");
  assertEquals(aps.attributes, {
    facts: {
      contractId: "local-1", iconDay: "2026-10-06", weekday: "TUE", sessionNumber: 5, totalSessions: 92,
      targetValue: "10,000", targetUnit: "STEPS", activityName: "Walking", because: "Spring", deadline: 1791291540,
    },
  });
  assertEquals(aps["content-state"], { phase: "morning", line: "Small steps, kept promises.", updatedAt: NOW });
  assertEquals(aps["stale-date"], 1791284400);
  assertEquals(aps.alert, { title: "Icon", body: "Small steps, kept promises." });
  assertEquals(aps.timestamp, NOW);
});

Deno.test("morning: an evening reminder already past sets no stale date", () => {
  const [send] = plan(job("morning", [token("push_to_start")]), NOW, allowed);
  assert(!("stale-date" in (send.payload.aps as Record<string, unknown>)));
});

Deno.test("morning: without push-to-start a quiet alert", () => {
  const [send] = plan(job("morning", [token("device", { osVersion: "16.6" })]), NOW, allowed);
  assertEquals(send.channel, "alert");
  assertEquals(send.headers["apns-push-type"], "alert");
  assertEquals(send.headers["apns-topic"], "com.jimmy.upwork.honoured");
  assertEquals(send.payload, {
    aps: {
      alert: { title: "Icon", subtitle: "Walking · 10,000 steps", body: "Small steps, kept promises. Due 11:59 pm." },
      "thread-id": "icon-local-1",
    },
    honoured: { kind: "icon", contractId: "local-1", iconDay: "2026-10-06" },
  });
  assert(!JSON.stringify(send.payload).includes("sound"));
});

Deno.test("morning: Live Activities off falls back to the alert", () => {
  const sends = plan(job("morning", [token("device", { liveActivitiesEnabled: false }), token("push_to_start", { liveActivitiesEnabled: false })]), NOW, allowed);
  assertEquals(sends.map((s) => s.channel), ["alert"]);
});

Deno.test("morning: nothing when the app already opened the card", () => {
  assertEquals(plan(job("morning", [token("device"), token("push_to_start"), token("activity")]), NOW, allowed), []);
});

Deno.test("evening: the morning card is closed and a fresh card opens on the evening line", () => {
  const sends = plan(job("evening", [token("push_to_start"), token("activity")]), NOW, allowed);
  assertEquals(sends.map((s) => [s.channel, s.token, !!s.auxiliary]), [
    ["live_activity_end", "cc".repeat(40), true],
    ["live_activity_start", "bb".repeat(40), false],
  ]);
  assertEquals(sends[0].payload, {
    aps: {
      timestamp: NOW, event: "end", "dismissal-date": NOW,
      "content-state": { phase: "evening", line: "Finish what you signed.", updatedAt: NOW },
    },
  });
  const aps = sends[1].payload.aps as Record<string, unknown>;
  assertEquals(aps["content-state"], { phase: "evening", line: "Finish what you signed.", updatedAt: NOW });
  assertEquals(aps.alert, { title: "Icon", body: "Finish what you signed." });
  assert(!("stale-date" in aps));
});

Deno.test("evening: a card the morning started appears again, even without its token", () => {
  const sends = plan(job("evening", [token("push_to_start"), token("device")], { morning_channel: "live_activity_start" }), NOW, allowed);
  assertEquals(sends.map((s) => s.channel), ["live_activity_start"]);
});

Deno.test("evening: without push-to-start the running card is updated, with an alert", () => {
  const [send] = plan(job("evening", [token("device", { osVersion: "17.0" }), token("activity")]), NOW, allowed);
  assertEquals(send.channel, "live_activity_update");
  assertEquals(send.payload, {
    aps: {
      timestamp: NOW, event: "update",
      "content-state": { phase: "evening", line: "Finish what you signed.", updatedAt: NOW },
      alert: { title: "Icon", body: "Finish what you signed." },
    },
  });
});

Deno.test("evening: with no card yet, one opens on the evening line", () => {
  const [send] = plan(job("evening", [token("push_to_start")], { morning_channel: "none" }), NOW, allowed);
  assertEquals(send.channel, "live_activity_start");
  const aps = send.payload.aps as Record<string, unknown>;
  assertEquals(aps["content-state"], { phase: "evening", line: "Finish what you signed.", updatedAt: NOW });
  assert(!("stale-date" in aps));
});

Deno.test("evening: alert fallback", () => {
  const [send] = plan(job("evening", [token("device")], { morning_channel: "alert" }), NOW, allowed);
  assertEquals((send.payload.aps as { alert: { body: string } }).alert.body, "Finish what you signed. Due 11:59 pm.");
});

Deno.test("result: HONOURED on the card, quietly; nothing without a card", () => {
  const [send] = plan(job("result", [token("activity"), token("device")], { status: "honoured" }), NOW, allowed);
  assertEquals(send.payload, {
    aps: { timestamp: NOW, event: "update", "content-state": { phase: "result", line: "HONOURED", result: "honoured", updatedAt: NOW } },
  });
  assertEquals(plan(job("result", [token("device"), token("push_to_start")], { status: "honoured" }), NOW, allowed), []);
});

Deno.test("end: the card closes at once", () => {
  const [send] = plan(job("end", [token("activity")]), NOW, allowed);
  assertEquals(send.channel, "live_activity_end");
  assertEquals(send.headers["apns-expiration"], String(1791291540 + 4 * 3600));
  assertEquals(send.payload, {
    aps: {
      timestamp: NOW, event: "end", "dismissal-date": NOW,
      "content-state": { phase: "evening", line: "Finish what you signed.", updatedAt: NOW },
    },
  });
  const [honoured] = plan(job("end", [token("activity")], { status: "honoured" }), NOW, allowed);
  assertEquals((honoured.payload.aps as Record<string, unknown>)["content-state"], {
    phase: "result", line: "HONOURED", result: "honoured", updatedAt: NOW,
  });
  assertEquals(plan(job("end", [token("device"), token("push_to_start")]), NOW, allowed), []);
});

Deno.test("only allowed topics and gateways; every install separately", () => {
  const sends = plan(job("morning", [
    token("push_to_start", { topic: "com.other.app" }),
    token("device"),
    token("push_to_start", { installationId: "install-2", environment: "production" }),
  ]), NOW, { topics: allowed.topics, environments: new Set(["sandbox"]) });
  assertEquals(sends.map((s) => `${s.installationId}:${s.channel}`), ["install-1:alert"]);
  const both = plan(job("morning", [token("push_to_start"), token("push_to_start", { installationId: "install-2" })]), NOW, allowed);
  assertEquals(both.map((s) => s.installationId), ["install-1", "install-2"]);
});

Deno.test("the newest token of each kind wins", () => {
  const [send] = plan(job("morning", [token("push_to_start", { token: "dd".repeat(40) }), token("push_to_start")]), NOW, allowed);
  assertEquals(send.token, "dd".repeat(40));
});

Deno.test("words match the app", () => {
  assertEquals(affirmation(1), "You've got this.");
  assertEquals(affirmation(8), "You've got this.");
  assertEquals(affirmation(0), "You've got this.");
  assertEquals(splitTarget("10000 steps"), { value: "10,000", unit: "STEPS" });
  assertEquals(splitTarget("2.5 km"), { value: "2.5", unit: "KM" });
  assertEquals(splitTarget("1,5 km"), { value: "1,5", unit: "KM" });
  assertEquals(splitTarget("00100 m"), { value: "100", unit: "M" });
  assertEquals(splitTarget("Run every day"), { value: "Run every day", unit: "" });
  assertEquals(weekday("2026-10-06"), "TUE");
  assertEquals(weekday("nope"), "");
  assertEquals(cut("a".repeat(130), 120), "a".repeat(119) + "…");
  assertEquals(cut("  short  ", 120), "short");
  assertEquals(deadlineLabel(new Date("2026-10-06T13:00:00Z"), "Australia/Sydney"), "Due midnight");
  assertEquals(deadlineLabel(new Date("2026-10-06T12:59:00Z"), "Australia/Sydney"), "Due 11:59 pm");
  assertEquals(deadlineLabel(new Date("2026-10-05T22:05:00Z"), "Australia/Sydney"), "Due 9:05 am");
  assertEquals(deadlineLabel(new Date("2026-10-06T12:00:00Z"), "UTC"), "Due 12:00 pm");
  assertEquals(deadlineLabel(new Date("2026-10-06T12:00:00Z"), "Not/AZone"), "");
});

Deno.test("APNs answers", () => {
  assertEquals(classify(200), "sent");
  assertEquals(classify(410, "Unregistered"), "drop-token");
  assertEquals(classify(400, "BadDeviceToken"), "drop-token");
  assertEquals(classify(403, "ExpiredProviderToken"), "new-provider-token");
  assertEquals(classify(403, "InvalidProviderToken"), "new-provider-token");
  assertEquals(classify(429, "TooManyProviderTokenUpdates"), "retry");
  assertEquals(classify(503, "ServiceUnavailable"), "retry");
  assertEquals(classify(0, "TimeoutError"), "retry");
  assertEquals(classify(400, "DeviceTokenNotForTopic"), "failed");
  assertEquals(classify(400, "BadTopic"), "failed");
  assertEquals(classify(413, "PayloadTooLarge"), "failed");
});

Deno.test("one log row per job", () => {
  const [start] = plan(job("morning", [token("push_to_start")]), NOW, allowed);
  const [alert] = plan(job("morning", [token("device", { installationId: "install-2" })]), NOW, allowed);
  assertEquals(summarise([]), { record: true, channel: "none", status: "skipped" });
  assertEquals(summarise([{ send: alert, outcome: "sent", status: 200 }, { send: start, outcome: "sent", status: 200 }]),
    { record: true, channel: "live_activity_start", status: "sent", apnsStatus: 200 });
  assertEquals(summarise([{ send: start, outcome: "retry", status: 503 }, { send: alert, outcome: "sent", status: 200 }]),
    { record: true, channel: "alert", status: "sent", apnsStatus: 200 });
  assertEquals(summarise([{ send: start, outcome: "drop-token", status: 410 }]), { record: false });
  assertEquals(summarise([{ send: start, outcome: "failed", status: 400, reason: "BadTopic" }, { send: alert, outcome: "retry", status: 0 }]), { record: false });
  assertEquals(summarise([{ send: start, outcome: "failed", status: 400, reason: "BadTopic" }]),
    { record: true, channel: "live_activity_start", status: "failed", apnsStatus: 400, reason: "BadTopic" });
});

Deno.test("closing the morning card never decides the evening slot", () => {
  const [close, open] = plan(job("evening", [token("push_to_start"), token("activity")]), NOW, allowed);
  assertEquals(summarise([{ send: close, outcome: "sent", status: 200 }, { send: open, outcome: "retry", status: 503 }]), { record: false });
  assertEquals(summarise([{ send: close, outcome: "drop-token", status: 410 }, { send: open, outcome: "sent", status: 200 }]),
    { record: true, channel: "live_activity_start", status: "sent", apnsStatus: 200 });
});

Deno.test("the longest card fits the 4 KB Live Activity payload", () => {
  const long = job("morning", [token("push_to_start")], {
    activity: "x".repeat(300), because: "é".repeat(500), target: "123456789012345678901234567890 kilometres and more",
    client_id: "c".repeat(64),
  });
  const [send] = plan(long, NOW, allowed);
  assert(new TextEncoder().encode(JSON.stringify(send.payload)).length < 4096);
});

Deno.test("the day's last reported Health total rides along for the Dynamic Island", () => {
  const stateOf = (j: Job) => (plan(j, NOW, allowed).find((s) => !s.auxiliary)!.payload.aps as Record<string, unknown>)["content-state"];
  assertEquals(stateOf(job("result", [token("activity")], { status: "honoured", measured_value: 12382 })),
    { phase: "result", line: "HONOURED", result: "honoured", updatedAt: NOW, value: 12382 });
  assertEquals(stateOf(job("evening", [token("push_to_start"), token("activity")], { measured_value: 6240.5 })),
    { phase: "evening", line: "Finish what you signed.", updatedAt: NOW, value: 6240.5 });
  assertEquals(stateOf(job("morning", [token("push_to_start")], { measured_value: 2410 })),
    { phase: "morning", line: "Small steps, kept promises.", updatedAt: NOW, value: 2410 });
  // No reading: no key, so an older app decodes the state exactly as before.
  assertEquals(stateOf(job("result", [token("activity")], { status: "honoured", measured_value: null })),
    { phase: "result", line: "HONOURED", result: "honoured", updatedAt: NOW });
  assertEquals(stateOf(job("result", [token("activity")], { status: "honoured" })),
    { phase: "result", line: "HONOURED", result: "honoured", updatedAt: NOW });
  // The quiet notification never carries it.
  const alertSend = plan(job("morning", [token("device")], { measured_value: 900 }), NOW, allowed)[0];
  assertEquals(alertSend.channel, "alert");
  assert(!JSON.stringify(alertSend.payload).includes("900"));
});

// Renewal (client, Oct 6): iOS ends a card 8 hours after it starts, so a fresh
// one replaces it before then, for the install whose card runs out.
const renewal = "renew-1791253200" as const; // the card started 02:20 UTC

Deno.test("renew: the running card closes and a fresh one opens with the day as it stands", () => {
  const sends = plan(job(renewal, [token("push_to_start"), token("activity")], {
    installation_id: "install-1", evening_at: "2026-10-06T11:00:00+00:00", measured_value: 6240,
  }), NOW, allowed);
  assertEquals(sends.map((s) => [s.channel, !!s.auxiliary]), [["live_activity_end", true], ["live_activity_start", false]]);
  const [close, open] = sends;
  assertEquals(close.token, "cc".repeat(40));
  const aps = open.payload.aps as Record<string, unknown>;
  assertEquals(aps["content-state"], { phase: "morning", line: "Small steps, kept promises.", updatedAt: NOW, value: 6240 });
  assertEquals(aps["stale-date"], 1791284400);
  // Apple requires an alert to start a card by push; it repeats the card's line, without sound.
  assertEquals(aps.alert, { title: "Icon", body: "Small steps, kept promises." });
  assert(!JSON.stringify(open.payload).includes("sound"));
});

Deno.test("renew: HONOURED stays HONOURED; after the evening reminder, the evening line", () => {
  const honoured = plan(job(renewal, [token("push_to_start")], { installation_id: "install-1", status: "honoured", measured_value: 12382 }), NOW, allowed);
  assertEquals(honoured.length, 1);
  const aps = honoured[0].payload.aps as Record<string, unknown>;
  assertEquals(aps["content-state"], { phase: "result", line: "HONOURED", result: "honoured", updatedAt: NOW, value: 12382 });
  assert(!("stale-date" in aps));
  const evening = plan(job(renewal, [token("push_to_start")], { installation_id: "install-1" }), NOW, allowed);
  assertEquals((evening[0].payload.aps as Record<string, unknown>)["content-state"], { phase: "evening", line: "Finish what you signed.", updatedAt: NOW });
});

Deno.test("renew: only the named install, only with push-to-start and Live Activities on", () => {
  const other = token("push_to_start", { installationId: "install-2", token: "dd".repeat(40) });
  assertEquals(plan(job(renewal, [token("push_to_start"), other], { installation_id: "install-2" }), NOW, allowed).map((s) => s.token), ["dd".repeat(40)]);
  // An update cannot outlive the 8 hours, and there is no alert fallback.
  assertEquals(plan(job(renewal, [token("activity"), token("device")], { installation_id: "install-1" }), NOW, allowed), []);
  assertEquals(plan(job(renewal, [token("push_to_start", { liveActivitiesEnabled: false }), token("activity")], { installation_id: "install-1" }), NOW, allowed), []);
  assertEquals(plan(job(renewal, [token("push_to_start")], { installation_id: null }), NOW, allowed), []);
});
