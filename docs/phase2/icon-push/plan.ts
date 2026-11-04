// Icon push plan (Honoured V1.2 M2-07): what one due job sends to each install.
// Pure, so it runs under `deno test` without APNs or the database.
//
// The reference for public.icon_push_plan (docs/db/icon_push_v2.sql), which
// is what runs: change this first, with its tests, then the SQL; the cases in
// parity_fixtures.ts must come out of both byte for byte.
//
// The Live Activity JSON must decode as the native app's IconActivityAttributes
// and IconLiveActivityState (ios/HonouredShared/IconLiveActivity.swift): plain
// values, dates in Unix seconds. The words match the app's IconCopy.

export type Kind = "device" | "push_to_start" | "activity";
export type Environment = "sandbox" | "production";
/** `renew-<unix seconds>`: a fresh card for the card that started then (iOS ends it at 8 hours). */
export type Renewal = `renew-${number}`;
export type Slot = "morning" | "evening" | "result" | "end" | Renewal;
export type Channel = "live_activity_start" | "live_activity_update" | "live_activity_end" | "alert";

/** One row of `tokens` in public.icon_push_jobs(). */
export interface PushToken {
  installationId: string;
  kind: Kind;
  token: string;
  environment: Environment;
  topic: string;
  osVersion: string | null;
  liveActivitiesEnabled: boolean | null;
}

/** One row of public.icon_push_jobs(). */
export interface Job {
  job: Slot;
  user_id: string;
  contract_id: string;
  client_id: string;
  day: string;
  session_number: number;
  total_sessions: number | null;
  deadline_at: string;
  evening_at: string | null;
  status: string;
  activity: string;
  target: string | null;
  because: string;
  timezone: string | null;
  morning_channel: string | null;
  /** The day's last Health total the app reported (icon_days.measured_value). */
  measured_value?: number | null;
  tokens: PushToken[];
  /** A renewal is for one install: the one whose card runs out. */
  installation_id?: string | null;
}

/** One APNs request. */
export interface Send {
  installationId: string;
  channel: Channel;
  token: string;
  environment: Environment;
  headers: Record<string, string>;
  payload: Record<string, unknown>;
  /** Housekeeping beside the slot's own send; its result never decides the slot. */
  auxiliary?: boolean;
}

export interface Allowed {
  /** Bundle ids this key may push to (APNS_TOPIC). */
  topics: Set<string>;
  /** Gateways this key may use (APNS_ENVIRONMENT). */
  environments: Set<Environment>;
}

// MARK: - Words (IconCopy in the app)

export const TITLE = "Icon";
export const EVENING_LINE = "Finish what you signed.";
export const AFFIRMATIONS = [
  "You've got this.",
  "You're closer than you think.",
  "Today is part of the promise.",
  "Keep your word to yourself.",
  "Small steps, kept promises.",
  "Become what you signed.",
  "Prove it again today.",
];

export function affirmation(sessionNumber: number): string {
  const n = Math.max(Math.trunc(sessionNumber) || 1, 1);
  return AFFIRMATIONS[(n - 1) % AFFIRMATIONS.length];
}

/** `Due 11:59 pm`, or `Due midnight` for a cut-off at 00:00, in the Icon's time zone. */
export function deadlineLabel(deadline: Date, timeZone: string | null): string {
  let parts: Intl.DateTimeFormatPart[];
  try {
    parts = new Intl.DateTimeFormat("en-US", {
      timeZone: timeZone || "UTC",
      hour: "numeric",
      minute: "2-digit",
      hourCycle: "h23",
    }).formatToParts(deadline);
  } catch {
    return "";
  }
  const hour = Number(parts.find((p) => p.type === "hour")?.value ?? "0") % 24;
  const minute = parts.find((p) => p.type === "minute")?.value ?? "00";
  if (hour === 0 && minute === "00") return "Due midnight";
  const h12 = hour % 12 === 0 ? 12 : hour % 12;
  return `Due ${h12}:${minute} ${hour < 12 ? "am" : "pm"}`;
}

// MARK: - Card facts (IconCardFacts in the app)

export function cut(text: string | null | undefined, limit: number): string {
  const trimmed = (text ?? "").trim();
  const chars = Array.from(trimmed);
  if (chars.length <= limit) return trimmed;
  return chars.slice(0, limit - 1).join("").trim() + "…";
}

/** `10000 steps` → `10,000` and `STEPS`; text with no leading number stays whole. */
export function splitTarget(target: string): { value: string; unit: string } {
  const trimmed = target.trim();
  const match = /^\d+(?:[.,]\d+)?/.exec(trimmed);
  if (!match) return { value: trimmed, unit: "" };
  const number = match[0];
  const unit = trimmed.slice(number.length).trim().toUpperCase();
  if (number.includes(",") || number.includes(".")) return { value: number, unit };
  const whole = Number.parseInt(number, 10);
  if (!Number.isSafeInteger(whole)) return { value: number, unit };
  return { value: String(whole).replace(/\B(?=(\d{3})+(?!\d))/g, ","), unit };
}

/** `2026-10-06` → `TUE`. */
export function weekday(day: string): string {
  const date = new Date(`${day}T00:00:00Z`);
  if (Number.isNaN(date.getTime())) return "";
  return ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"][date.getUTCDay()];
}

export function seconds(iso: string): number {
  return Math.floor(Date.parse(iso) / 1000);
}

export function facts(job: Job) {
  const target = splitTarget(job.target ?? "");
  const session = Math.max(1, Math.trunc(job.session_number) || 1);
  return {
    contractId: job.client_id,
    iconDay: job.day,
    weekday: weekday(job.day),
    sessionNumber: session,
    totalSessions: Math.max(session, job.total_sessions ?? session),
    targetValue: cut(target.value, 16),
    targetUnit: cut(target.unit, 16).toUpperCase(),
    activityName: cut(job.activity, 40),
    because: cut(job.because, 120),
    deadline: seconds(job.deadline_at),
  };
}

// MARK: - Card states (IconLiveActivityState in the app)

type State = { phase: "morning" | "evening" | "result"; line: string; result?: "honoured"; updatedAt: number; value?: number };

/** The day's last reported Health total rides along, for the Dynamic Island (client, Oct 5). */
function withValue(state: State, job: Job): State {
  const value = job.measured_value;
  return typeof value === "number" && Number.isFinite(value) ? { ...state, value } : state;
}

export function morningState(job: Job, now: number): State {
  return withValue({ phase: "morning", line: affirmation(job.session_number), updatedAt: now }, job);
}

export function eveningState(job: Job, now: number): State {
  return withValue({ phase: "evening", line: EVENING_LINE, updatedAt: now }, job);
}

export function honouredState(job: Job, now: number): State {
  return withValue({ phase: "result", line: "HONOURED", result: "honoured", updatedAt: now }, job);
}

/** What a renewed card shows: the day as it stands now. */
export function currentState(job: Job, now: number): State {
  if (job.status === "honoured") return honouredState(job, now);
  const evening = job.evening_at ? seconds(job.evening_at) : null;
  return evening !== null && evening <= now ? eveningState(job, now) : morningState(job, now);
}

export function isRenewal(slot: string): slot is Renewal {
  return /^renew-\d+$/.test(slot);
}

// MARK: - Plan

interface Install {
  id: string;
  device?: PushToken;
  pushToStart?: PushToken;
  card?: PushToken;
  liveActivitiesOn: boolean;
}

/** Tokens arrive newest first; the newest of each kind wins. */
export function installs(tokens: PushToken[], allowed: Allowed): Install[] {
  const byId = new Map<string, Install>();
  for (const token of tokens) {
    let install = byId.get(token.installationId);
    if (!install) {
      install = { id: token.installationId, liveActivitiesOn: true };
      byId.set(token.installationId, install);
    }
    if (token.kind !== "activity" && token.liveActivitiesEnabled === false) install.liveActivitiesOn = false;
    if (!allowed.topics.has(token.topic) || !allowed.environments.has(token.environment)) continue;
    if (token.kind === "device") install.device ??= token;
    else if (token.kind === "push_to_start") install.pushToStart ??= token;
    else install.card ??= token;
  }
  return [...byId.values()];
}

/**
 * What each install gets for one job:
 *   morning  push-to-start the card; without Live Activities, a quiet alert
 *   evening  a fresh card on the evening line, closing the morning one: iOS
 *            ends a Live Activity 8 hours after it starts, so the morning card
 *            cannot be trusted to reach the cut-off (the evening reminder is
 *            set within 8 hours of it). Without push-to-start, the running
 *            card is updated, or a quiet alert sent.
 *   result   show HONOURED on the card
 *   end      close the card at the cut-off
 *   renew-…  for one install, a fresh card before iOS ends the running one at
 *            8 hours, closing it; due from the job when the card would
 *            otherwise run out before the cut-off (client, Oct 6). Starting a
 *            card by push must carry an alert (Apple), so it repeats the card's
 *            line, silently. Without push-to-start nothing is sent: an update
 *            does not extend the 8 hours.
 */
export function plan(job: Job, now: number, allowed: Allowed): Send[] {
  const deadline = seconds(job.deadline_at);
  const sends: Send[] = [];
  for (const install of installs(job.tokens, allowed)) {
    const card = install.liveActivitiesOn ? install.card : undefined;
    const pushToStart = install.liveActivitiesOn ? install.pushToStart : undefined;
    const device = install.device;
    switch (job.job) {
      case "morning": {
        if (card) break; // the app already opened today's card
        if (pushToStart) {
          const evening = job.evening_at ? seconds(job.evening_at) : null;
          sends.push(start(install.id, pushToStart, job, morningState(job, now), evening && evening > now ? evening : null, now, deadline));
        } else if (device) {
          sends.push(alert(install.id, device, job, affirmation(job.session_number), deadline));
        }
        break;
      }
      case "evening": {
        if (pushToStart) {
          if (card) sends.push({ ...end(install.id, card, eveningState(job, now), now, deadline), auxiliary: true });
          sends.push(start(install.id, pushToStart, job, eveningState(job, now), null, now, deadline));
        } else if (card) {
          sends.push(update(install.id, card, eveningState(job, now), true, now, deadline));
        } else if (device) {
          sends.push(alert(install.id, device, job, EVENING_LINE, deadline));
        }
        break;
      }
      case "result": {
        if (card) sends.push(update(install.id, card, honouredState(job, now), false, now, deadline));
        break;
      }
      case "end": {
        if (card) {
          const state = job.status === "honoured" ? honouredState(job, now) : eveningState(job, now);
          sends.push(end(install.id, card, state, now, deadline));
        }
        break;
      }
      default: {
        if (!isRenewal(job.job) || install.id !== job.installation_id || !pushToStart) break;
        const state = currentState(job, now);
        const evening = job.evening_at ? seconds(job.evening_at) : null;
        const staleDate = state.phase === "morning" && evening !== null && evening > now ? evening : null;
        if (card) sends.push({ ...end(install.id, card, state, now, deadline), auxiliary: true });
        sends.push(start(install.id, pushToStart, job, state, staleDate, now, deadline));
        break;
      }
    }
  }
  return sends;
}

function liveActivityHeaders(token: PushToken, expiration: number): Record<string, string> {
  return {
    "apns-push-type": "liveactivity",
    "apns-topic": `${token.topic}.push-type.liveactivity`,
    "apns-priority": "10",
    "apns-expiration": String(expiration),
  };
}

function start(installationId: string, token: PushToken, job: Job, state: State, staleDate: number | null, now: number, deadline: number): Send {
  const aps: Record<string, unknown> = {
    timestamp: now,
    event: "start",
    "content-state": state,
    "attributes-type": "IconActivityAttributes",
    attributes: { facts: facts(job) },
    alert: { title: TITLE, body: state.line },
    // iOS 18: ask for the started card's update token (ignored before).
    "input-push-token": 1,
  };
  if (staleDate) aps["stale-date"] = staleDate;
  return {
    installationId, channel: "live_activity_start", token: token.token, environment: token.environment,
    headers: liveActivityHeaders(token, deadline), payload: { aps },
  };
}

function update(installationId: string, token: PushToken, state: State, alerting: boolean, now: number, deadline: number): Send {
  const aps: Record<string, unknown> = { timestamp: now, event: "update", "content-state": state };
  if (alerting) aps.alert = { title: TITLE, body: state.line };
  return {
    installationId, channel: "live_activity_update", token: token.token, environment: token.environment,
    headers: liveActivityHeaders(token, deadline), payload: { aps },
  };
}

function end(installationId: string, token: PushToken, state: State, now: number, deadline: number): Send {
  return {
    installationId, channel: "live_activity_end", token: token.token, environment: token.environment,
    headers: liveActivityHeaders(token, deadline + 4 * 3600),
    payload: { aps: { timestamp: now, event: "end", "content-state": state, "dismissal-date": now } },
  };
}

/** The fallback without Live Activities: a quiet notification. */
function alert(installationId: string, token: PushToken, job: Job, line: string, deadline: number): Send {
  const target = splitTarget(job.target ?? "");
  const goal = [target.value, target.unit.toLowerCase()].filter(Boolean).join(" ");
  const due = deadlineLabel(new Date(deadline * 1000), job.timezone);
  return {
    installationId, channel: "alert", token: token.token, environment: token.environment,
    headers: {
      "apns-push-type": "alert",
      "apns-topic": token.topic,
      "apns-priority": "10",
      "apns-expiration": String(deadline),
    },
    payload: {
      aps: {
        alert: {
          title: TITLE,
          subtitle: [cut(job.activity, 40), goal].filter(Boolean).join(" · "),
          body: [line, due && `${due}.`].filter(Boolean).join(" "),
        },
        "thread-id": `icon-${job.client_id}`,
      },
      honoured: { kind: "icon", contractId: job.client_id, iconDay: job.day },
    },
  };
}

// MARK: - Results

export type Outcome = "sent" | "drop-token" | "new-provider-token" | "retry" | "failed";

/** What an APNs answer means for the job and the token. */
export function classify(status: number, reason?: string): Outcome {
  if (status === 200) return "sent";
  if (status === 410 || reason === "BadDeviceToken" || reason === "Unregistered") return "drop-token";
  if (reason === "ExpiredProviderToken" || reason === "InvalidProviderToken" || reason === "MissingProviderToken") {
    return "new-provider-token";
  }
  if (status === 0 || status === 429 || status >= 500) return "retry";
  return "failed";
}

const CHANNEL_RANK: Channel[] = ["live_activity_start", "live_activity_update", "live_activity_end", "alert"];

/**
 * One log row per job: sent if any install got it; nothing recorded while a
 * send may still succeed on the next run; failed only for answers a retry
 * cannot change.
 */
export function summarise(all: { send: Send; outcome: Outcome; status: number; reason?: string }[]):
  | { record: true; channel: Channel | "none"; status: "sent" | "failed" | "skipped"; apnsStatus?: number; reason?: string }
  | { record: false } {
  const results = all.filter((r) => !r.send.auxiliary);
  if (results.length === 0) return { record: true, channel: "none", status: "skipped" };
  const sent = results.filter((r) => r.outcome === "sent");
  if (sent.length > 0) {
    const channel = CHANNEL_RANK.find((c) => sent.some((r) => r.send.channel === c))!;
    return { record: true, channel, status: "sent", apnsStatus: 200 };
  }
  if (results.some((r) => r.outcome !== "failed")) return { record: false };
  const first = results[0];
  return { record: true, channel: first.send.channel, status: "failed", apnsStatus: first.status, reason: first.reason };
}
