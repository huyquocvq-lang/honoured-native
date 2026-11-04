// Icon recaps and the end of an Icon (V1.2 M2-10 to M2-12). Pure decisions
// from the Icon days the server stamped (icon-days.ts) and the local
// contracts; the caller passes the clock and keeps what was already shown.
//
// Recap (M2-10): the last full week (Monday to Sunday) and the last full
// calendar month, by the Icon days' own dates, once no day in it is pending.
// Honoured and Broken count sessions; Amended counts Icons ended early in the
// period (the days an early exit releases are not sessions the person
// missed). More Honoured than Broken is a strong period, anything else a
// tough one; a period with nothing stamped Honoured or Broken has no recap.
//
// End of an Icon (M2-11): once its last cut-off has passed and every session
// is stamped, the Icon closes HONOURED when more sessions were honoured than
// broken, BROKEN otherwise, so it leaves the active list and History records
// it. Its summary invites the person to go again (M2-12): a new Icon composed
// from the same terms, starting the day it is signed, with a fresh signature.
// Nothing renews by itself.
//
// The weekly lines are scope v6; the client approved the other words (O-15).
import { localDayString, parseTime, trimTime, type IconDraft, type IconReminder } from "@/lib/icon";
import type { IconDay, IconDaysByContract } from "@/lib/icon-days";
import type { CommitmentType, Contract } from "@/lib/store";

/* ------------------------------- calendar ------------------------------- */

const DAY_MS = 86_400_000;
const pad = (n: number) => String(n).padStart(2, "0");

// Day arithmetic on YYYY-MM-DD in UTC, so a clock change never moves a day.
function utc(day: string): number {
  const [y, m, d] = day.split("-").map(Number);
  return Date.UTC(y, m - 1, d);
}
function dayOf(ms: number): string {
  const d = new Date(ms);
  return `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())}`;
}
function addDays(day: string, n: number): string {
  return dayOf(utc(day) + n * DAY_MS);
}

export type RecapKind = "week" | "month";

export interface RecapPeriod {
  kind: RecapKind;
  /** The week's Monday ("2026-09-28") or the month ("2026-09"). */
  key: string;
  /** First and last day, inclusive. */
  first: string;
  last: string;
}

/** The Monday-to-Sunday week holding `day`. */
export function weekOf(day: string): RecapPeriod {
  const first = addDays(day, -((new Date(utc(day)).getUTCDay() + 6) % 7));
  return { kind: "week", key: first, first, last: addDays(first, 6) };
}

/** The calendar month holding `day`. */
export function monthOf(day: string): RecapPeriod {
  const key = day.slice(0, 7);
  const [y, m] = key.split("-").map(Number);
  return { kind: "month", key, first: `${key}-01`, last: dayOf(Date.UTC(y, m, 0)) };
}

/** The last full week or month before the one holding `today`. */
export function previousPeriod(kind: RecapKind, today: string): RecapPeriod {
  const current = kind === "week" ? weekOf(today) : monthOf(today);
  const before = addDays(current.first, -1);
  return kind === "week" ? weekOf(before) : monthOf(before);
}

const MONTHS = [
  "January", "February", "March", "April", "May", "June",
  "July", "August", "September", "October", "November", "December",
];

/** "28 Sep – 4 Oct" or "September". */
export function periodLabel(p: RecapPeriod): string {
  if (p.kind === "month") return MONTHS[Number(p.key.slice(5, 7)) - 1];
  const short = (day: string) => `${Number(day.slice(8, 10))} ${MONTHS[Number(day.slice(5, 7)) - 1].slice(0, 3)}`;
  return `${short(p.first)} – ${short(p.last)}`;
}

/* -------------------------------- totals -------------------------------- */

export interface RecapTotals {
  honoured: number;
  amended: number;
  broken: number;
  /** Days not stamped yet: the recap waits for them. */
  pending: number;
}

const within = (day: string, p: RecapPeriod) => day >= p.first && day <= p.last;

export function periodTotals(p: RecapPeriod, contracts: readonly Contract[], days: IconDaysByContract): RecapTotals {
  const t: RecapTotals = { honoured: 0, amended: 0, broken: 0, pending: 0 };
  for (const list of Object.values(days)) {
    for (const d of list) {
      if (!within(d.day, p)) continue;
      if (d.status === "honoured") t.honoured += 1;
      else if (d.status === "broken") t.broken += 1;
      else if (d.status === "pending") t.pending += 1;
    }
  }
  for (const c of contracts) {
    if (c.icon && c.status === "amended" && c.resolvedAt !== undefined && within(localDayString(new Date(c.resolvedAt)), p)) {
      t.amended += 1;
    }
  }
  return t;
}

export type Tone = "strong" | "tough";

/** Null when nothing was stamped Honoured or Broken. */
export function toneOf(honoured: number, broken: number): Tone | null {
  if (honoured + broken === 0) return null;
  return honoured > broken ? "strong" : "tough";
}

/* --------------------------------- words --------------------------------- */

/** Scope v6, weekly recap. */
export const WEEK_STRONG = "You slayed it this week.";
export const WEEK_TOUGH =
  "I believe in you even though this week has been challenging. Keep the dream alive and chase it. Let's start this week energized and use last week as kindle to start the flame.";
/** The weekly lines, for a month (client-approved, O-15). */
export const MONTH_STRONG = "You slayed it this month.";
export const MONTH_TOUGH =
  "I believe in you even though this month has been challenging. Keep the dream alive and chase it. Let's start this month energized and use last month as kindle to start the flame.";
/** Client-approved (O-15). */
export const RECAP_TITLE: Record<RecapKind, string> = { week: "Your week", month: "Your month" };

/** Client-approved (O-15). */
export const ICON_END_TITLE = "Icon complete";
export const ICON_END_STRONG = "You kept your word. You became an Icon.";
export const ICON_END_TOUGH =
  "This Icon tested you, and you saw it through. Keep the dream alive and use these days as kindle to start the next flame.";
export const GO_AGAIN = "Go again";
export const NOT_NOW = "Not now";

const NUMBER_WORDS = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"];

/** "That's one more than zero." is scope v6; the other counts are client-approved (O-15). */
export function moreThanZero(honoured: number): string {
  return `That's ${NUMBER_WORDS[honoured] ?? String(honoured)} more than zero.`;
}

/** A tough record still acknowledges every Honoured session. */
function toneLines(tone: Tone, honoured: number, strong: string, tough: string): string[] {
  if (tone === "strong") return [strong];
  return honoured > 0 ? [tough, moreThanZero(honoured)] : [tough];
}

/* --------------------------------- recap --------------------------------- */

export interface Recap {
  period: RecapPeriod;
  totals: RecapTotals;
  tone: Tone;
  title: string;
  /** "28 Sep – 4 Oct" or "September". */
  range: string;
  lines: string[];
}

/** The recap of a period, or null when nothing in it was stamped Honoured or Broken. */
export function buildRecap(p: RecapPeriod, contracts: readonly Contract[], days: IconDaysByContract): Recap | null {
  const totals = periodTotals(p, contracts, days);
  const tone = toneOf(totals.honoured, totals.broken);
  if (!tone) return null;
  const week = p.kind === "week";
  return {
    period: p,
    totals,
    tone,
    title: RECAP_TITLE[p.kind],
    range: periodLabel(p),
    lines: toneLines(tone, totals.honoured, week ? WEEK_STRONG : MONTH_STRONG, week ? WEEK_TOUGH : MONTH_TOUGH),
  };
}

/** What this device already showed the account (kept in its AppState). */
export interface MomentsSeen {
  /** Key of the last week and month recap shown. */
  week?: string;
  month?: string;
  /** Icons whose end summary was shown, newest last. */
  icons?: string[];
}

const SEEN_ICONS_KEPT = 50;

/**
 * The last full month, then the last full week, once every day in it is
 * stamped and if not shown yet. Only the period just before the current one
 * is offered: a recap never arrives weeks late.
 */
export function dueRecaps(
  contracts: readonly Contract[],
  days: IconDaysByContract,
  nowMs: number,
  seen: MomentsSeen,
): Recap[] {
  const today = localDayString(new Date(nowMs));
  const out: Recap[] = [];
  for (const kind of ["month", "week"] as const) {
    const p = previousPeriod(kind, today);
    const last = seen[kind];
    if (last !== undefined && last >= p.key) continue;
    const recap = buildRecap(p, contracts, days);
    if (recap && recap.totals.pending === 0) out.push(recap);
  }
  return out;
}

/* ------------------------------ end of Icon ------------------------------ */

export interface IconEnd {
  contract: Contract;
  honoured: number;
  broken: number;
  /** Sessions in the Icon. */
  total: number;
  tone: Tone;
  /** The status the Icon closes with. */
  status: "honoured" | "broken";
  /** Cut-off of the last session. */
  endedAt: number;
}

/**
 * The end of an Icon whose last cut-off has passed with every session
 * stamped, or null. An Icon ended early (AMENDED days) never ends here, and
 * an incomplete list of days (a session missing) never ends an Icon.
 */
export function iconEnd(c: Contract, days: readonly IconDay[] | undefined, nowMs: number): IconEnd | null {
  if (!c.icon || !days?.length || c.deadline > nowMs) return null;
  let honoured = 0;
  let broken = 0;
  let endedAt = 0;
  const sessions = new Set<number>();
  for (const d of days) {
    if (d.status === "honoured") honoured += 1;
    else if (d.status === "broken") broken += 1;
    else return null;
    sessions.add(d.sessionNumber);
    endedAt = Math.max(endedAt, d.deadlineMs);
  }
  if (endedAt > nowMs || sessions.size !== days.length || Math.max(...sessions) !== days.length) return null;
  const tone: Tone = honoured > broken ? "strong" : "tough";
  return {
    contract: c,
    honoured,
    broken,
    total: days.length,
    tone,
    status: tone === "strong" ? "honoured" : "broken",
    endedAt,
  };
}

/** Active Icons ready to close. */
export function finishedIcons(contracts: readonly Contract[], days: IconDaysByContract, nowMs: number): IconEnd[] {
  return contracts.flatMap((c) => {
    const end = c.status === "active" ? iconEnd(c, days[c.id], nowMs) : null;
    return end ? [end] : [];
  });
}

/** How long after its last cut-off an Icon's summary may still appear. */
export const ICON_END_SHOWN_FOR_MS = 14 * DAY_MS;

/** Icons that closed at the end of their period, recently, whose summary was not shown. */
export function dueIconEnds(
  contracts: readonly Contract[],
  days: IconDaysByContract,
  nowMs: number,
  seen: MomentsSeen,
): IconEnd[] {
  const shown = new Set(seen.icons ?? []);
  return contracts.flatMap((c) => {
    if ((c.status !== "honoured" && c.status !== "broken") || shown.has(c.id)) return [];
    const end = iconEnd(c, days[c.id], nowMs);
    return end && nowMs - end.endedAt <= ICON_END_SHOWN_FOR_MS ? [end] : [];
  });
}

/** "16 of 18 sessions honoured" (client-approved, O-15). */
export function sessionsHonouredText(honoured: number, total: number): string {
  return `${honoured} of ${total} ${total === 1 ? "session" : "sessions"} honoured`;
}

export function iconEndCount(e: IconEnd): string {
  return sessionsHonouredText(e.honoured, e.total);
}

export function iconEndLines(e: IconEnd): string[] {
  return toneLines(e.tone, e.honoured, ICON_END_STRONG, ICON_END_TOUGH);
}

/* -------------------------------- moments -------------------------------- */

export type Moment = { kind: "icon-end"; end: IconEnd } | { kind: "recap"; recap: Recap };

/** In the order to show them: Icon summaries, then the month, then the week. */
export function dueMoments(
  contracts: readonly Contract[],
  days: IconDaysByContract,
  nowMs: number,
  seen: MomentsSeen,
): Moment[] {
  return [
    ...dueIconEnds(contracts, days, nowMs, seen).map((end): Moment => ({ kind: "icon-end", end })),
    ...dueRecaps(contracts, days, nowMs, seen).map((recap): Moment => ({ kind: "recap", recap })),
  ];
}

/** `seen` once `m` has been shown. */
export function markSeen(seen: MomentsSeen, m: Moment): MomentsSeen {
  if (m.kind === "recap") return { ...seen, [m.recap.period.kind]: m.recap.period.key };
  const id = m.end.contract.id;
  return { ...seen, icons: [...(seen.icons ?? []).filter((x) => x !== id), id].slice(-SEEN_ICONS_KEPT) };
}

/* -------------------------------- go again -------------------------------- */

/** What "Go again" puts in the composer: the finished Icon's terms, all editable, unsigned. */
export interface GoAgainPrefill {
  primaryType: CommitmentType;
  primaryActivity: string;
  primaryTarget?: string;
  because: string;
  /** Same days, period and reminders; the new period starts on the day it is signed. */
  draft: IconDraft;
  /** The next local occurrence of the daily cut-off. */
  deadline: number;
}

export function goAgainPrefill(c: Contract, nowMs: number): GoAgainPrefill | null {
  const cut = c.icon ? parseTime(trimTime(c.icon.deadlineTime) ?? "") : null;
  if (!c.icon || !cut) return null;
  const reminders = [c.icon.morning, c.icon.evening]
    .map((t) => parseTime(trimTime(t) ?? ""))
    .filter((r): r is IconReminder => r !== null);
  const now = new Date(nowMs);
  const deadline = new Date(now.getFullYear(), now.getMonth(), now.getDate(), cut.hour, cut.minute);
  if (deadline.getTime() <= nowMs) deadline.setDate(deadline.getDate() + 1);
  return {
    primaryType: c.primaryType,
    primaryActivity: c.primaryActivity,
    ...(c.primaryTarget ? { primaryTarget: c.primaryTarget } : {}),
    because: c.because,
    draft: { days: [...c.icon.weekdays], period: { ...c.icon.period }, reminders },
    deadline: deadline.getTime(),
  };
}
