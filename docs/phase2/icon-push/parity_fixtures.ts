// Generates the JSON the SQL port (docs/db/icon_push_v2.sql, icon_push_plan)
// must reproduce: deno run parity_fixtures.ts > parity_fixtures.json
import { type Job, type PushToken, plan } from "./plan.ts";

const NOW = 1791280800; // 2026-10-06 10:00 UTC
const TOPIC = "com.jimmy.upwork.honoured";
const t = (kind: PushToken["kind"], extra: Partial<PushToken> = {}): PushToken => ({
  installationId: "i1", kind,
  token: kind === "device" ? "dev1" : kind === "push_to_start" ? "pts1" : "card1",
  environment: "sandbox", topic: TOPIC, osVersion: "18.1", liveActivitiesEnabled: true, ...extra,
});
const second = "i2";
const job = (slot: Job["job"], tokens: PushToken[], extra: Partial<Job> = {}): Job => ({
  job: slot, user_id: "33333333-3333-4333-8333-333333333333", contract_id: "44444444-4444-4444-8444-444444444444",
  client_id: "local-1", day: "2026-10-06", session_number: 5, total_sessions: 92,
  deadline_at: "2026-10-06T12:59:00+00:00", evening_at: "2026-10-06T09:00:00+00:00", status: "pending",
  activity: "Walking", target: "10000 steps", because: "Spring", timezone: "Australia/Sydney", morning_channel: null,
  tokens, ...extra,
});
const both = ["sandbox", "production"] as const;
const cases: [string, Job, readonly string[]][] = [
  ["morning start with stale date", job("morning", [t("device"), t("push_to_start")], { evening_at: "2026-10-06T11:00:00+00:00" }), both],
  ["morning start, evening past", job("morning", [t("push_to_start")]), both],
  ["morning alert", job("morning", [t("device", { osVersion: "16.6" })]), both],
  ["morning Live Activities off", job("morning", [t("device", { liveActivitiesEnabled: false }), t("push_to_start", { liveActivitiesEnabled: false })]), both],
  ["morning card already open", job("morning", [t("device"), t("push_to_start"), t("activity")]), both],
  ["evening update", job("evening", [t("push_to_start"), t("activity")]), both],
  ["evening after a morning start", job("evening", [t("push_to_start"), t("device")], { morning_channel: "live_activity_start" }), both],
  ["evening start", job("evening", [t("push_to_start")], { morning_channel: "none" }), both],
  ["evening alert", job("evening", [t("device")], { morning_channel: "alert" }), both],
  ["evening update without push-to-start", job("evening", [t("device", { osVersion: "17.0" }), t("activity")]), both],
  ["result update", job("result", [t("activity"), t("device")], { status: "honoured" }), both],
  ["result without card", job("result", [t("device"), t("push_to_start")], { status: "honoured" }), both],
  ["end pending", job("end", [t("activity")]), both],
  ["end honoured", job("end", [t("activity")], { status: "honoured" }), both],
  ["end without card", job("end", [t("device"), t("push_to_start")]), both],
  ["allowlists", job("morning", [t("push_to_start", { topic: "com.other.app" }), t("device"), t("push_to_start", { installationId: second, environment: "production" })]), ["sandbox"]],
  ["two installs", job("morning", [t("push_to_start"), t("push_to_start", { installationId: second, token: "pts2", environment: "production" })]), both],
  ["newest token wins", job("morning", [t("push_to_start", { token: "pts3" }), t("push_to_start")]), both],
  ["long text", job("morning", [t("push_to_start")], { activity: "x".repeat(300), because: "é".repeat(500), target: "123456789012345678901234567890 kilometres and more", client_id: "c".repeat(64), session_number: 0, total_sessions: null }), both],
  ["midnight, no time zone", job("evening", [t("device")], { deadline_at: "2026-10-07T00:00:00+00:00", timezone: null }), both],
  ["midnight in Sydney", job("morning", [t("device")], { deadline_at: "2026-10-06T13:00:00+00:00", session_number: 8 }), both],
  ["morning in Sydney", job("evening", [t("device")], { deadline_at: "2026-10-05T22:05:00+00:00" }), both],
  ["bad time zone, odd targets", job("morning", [t("device")], { timezone: "Not/AZone", target: "2.5 km" }), both],
  ["text target", job("evening", [t("device")], { target: "Run every day", activity: "  Run  " }), both],
  ["no target", job("morning", [t("device")], { target: null }), both],
  ["leading zeros", job("morning", [t("device")], { target: "00100 m" }), both],
  ["comma decimal", job("morning", [t("push_to_start")], { target: "1,5 km" }), both],
  ["no tokens", job("morning", []), both],
  ["morning start with a reading", job("morning", [t("push_to_start")], { measured_value: 2410 }), both],
  ["evening start with a reading", job("evening", [t("push_to_start"), t("activity")], { measured_value: 6240.5 }), both],
  ["evening update with a reading", job("evening", [t("device", { osVersion: "17.0" }), t("activity")], { measured_value: 7000 }), both],
  ["result with a reading", job("result", [t("activity")], { status: "honoured", measured_value: 12382 }), both],
  ["end with a reading", job("end", [t("activity")], { status: "honoured", measured_value: 3218.6875 }), both],
  ["alert ignores the reading", job("morning", [t("device")], { measured_value: 900 }), both],
  ["no reading is left out", job("result", [t("activity")], { status: "honoured", measured_value: null }), both],
  ["renew a morning card", job("renew-1791253200", [t("push_to_start"), t("activity")], { installation_id: "i1", evening_at: "2026-10-06T11:00:00+00:00", measured_value: 6240 }), both],
  ["renew without a card token", job("renew-1791253200", [t("push_to_start")], { installation_id: "i1", evening_at: "2026-10-06T11:00:00+00:00" }), both],
  ["renew honoured", job("renew-1791253200", [t("push_to_start"), t("activity")], { installation_id: "i1", status: "honoured", measured_value: 12382 }), both],
  ["renew after the evening reminder", job("renew-1791253200", [t("push_to_start")], { installation_id: "i1" }), both],
  ["renew no evening reminder", job("renew-1791253200", [t("push_to_start"), t("activity")], { installation_id: "i1", evening_at: null }), both],
  ["renew the other install", job("renew-1791253200", [t("push_to_start"), t("push_to_start", { installationId: second, token: "pts2" }), t("activity", { installationId: second, token: "card2" })], { installation_id: second }), both],
  ["renew without push-to-start", job("renew-1791253200", [t("activity"), t("device")], { installation_id: "i1" }), both],
  ["renew Live Activities off", job("renew-1791253200", [t("push_to_start", { liveActivitiesEnabled: false }), t("activity")], { installation_id: "i1" }), both],
  ["renew with no install", job("renew-1791253200", [t("push_to_start")], { installation_id: null }), both],
];
const fixtures = cases.map(([name, j, envs]) => ({
  name, job: j, now: NOW, topics: [TOPIC], environments: envs,
  expected: plan(j, NOW, { topics: new Set([TOPIC]), environments: new Set(envs as ("sandbox" | "production")[]) })
    .map((s) => ({ installation_id: s.installationId, channel: s.channel, token: s.token, environment: s.environment, headers: s.headers, payload: s.payload, auxiliary: !!s.auxiliary })),
}));
console.log(JSON.stringify(fixtures));
