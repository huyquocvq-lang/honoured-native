// What the History calendar shows (client request Oct 5): every Icon day
// stamped HONOURED or BROKEN is a record on its own date, beside the resolved
// ordinary contracts, so the calendar keeps the full record the Icon day
// marks show. Pure: History renders what this returns.
//   - Ordinary contract: one entry once resolved, on the day it was resolved.
//   - Icon: one entry per day stamped HONOURED or BROKEN, on that Icon day,
//     while the Icon runs and after it ends.
//   - Icon ended early: one AMENDED entry on the day it was ended. The days
//     the exit released are not shown: they never took place.
//   - An Icon that closed at the end of its period adds no entry of its own;
//     its days are its record.
import type { IconDayResolution, IconDaysByContract } from "@/lib/icon-days";
import { sessionsHonouredText } from "@/lib/icon-recap";
import type { Contract } from "@/lib/store";

export type HistoryStatus = "honoured" | "broken" | "amended";

export interface HistoryIconDay {
  /** The Icon day, YYYY-MM-DD. */
  day: string;
  session: number;
  total: number;
  resolution: IconDayResolution;
  measuredValue: number | null;
}

export interface HistoryEntry {
  /** The contract id, or the contract id and the Icon day for an Icon day. */
  id: string;
  contract: Contract;
  status: HistoryStatus;
  /** Local midnight of the calendar date the entry belongs to. */
  date: Date;
  /** History's day key for that date: year, month index, day ("2026-9-5" is 5 Oct 2026). */
  dayKey: string;
  /** When it was decided; the list is newest first. */
  at: number;
  /** Set for an Icon day. */
  iconDay?: HistoryIconDay;
  /** Set for an Icon ended early: "2 of 17 sessions honoured". */
  sessions?: string;
}

export function historyDayKey(d: Date): string {
  return `${d.getFullYear()}-${d.getMonth()}-${d.getDate()}`;
}

function localDate(ms: number): Date {
  const d = new Date(ms);
  return new Date(d.getFullYear(), d.getMonth(), d.getDate());
}

/** An Icon day keeps its own date, whatever the time zone of the device. */
function iconDate(day: string): Date {
  const [y, m, d] = day.split("-").map(Number);
  return new Date(y, m - 1, d);
}

function entry(
  id: string,
  contract: Contract,
  status: HistoryStatus,
  date: Date,
  at: number,
  extra: Partial<HistoryEntry> = {},
): HistoryEntry {
  return { id, contract, status, date, dayKey: historyDayKey(date), at, ...extra };
}

/** Every History entry, newest first. */
export function historyEntries(contracts: readonly Contract[], iconDays: IconDaysByContract): HistoryEntry[] {
  const out: HistoryEntry[] = [];
  for (const c of contracts) {
    if (!c.icon) {
      if (c.status === "active") continue;
      const at = c.resolvedAt ?? c.createdAt;
      out.push(entry(c.id, c, c.status, localDate(at), at));
      continue;
    }
    const days = iconDays[c.id] ?? [];
    const total = days.reduce((n, d) => Math.max(n, d.sessionNumber), 0);
    for (const d of days) {
      if (d.status !== "honoured" && d.status !== "broken") continue;
      out.push(
        entry(`${c.id}|${d.day}`, c, d.status, iconDate(d.day), d.scoredAt ?? d.deadlineMs, {
          iconDay: {
            day: d.day,
            session: d.sessionNumber,
            total,
            resolution: d.resolution,
            measuredValue: d.measuredValue,
          },
        }),
      );
    }
    if (c.status === "amended") {
      const at = c.resolvedAt ?? c.createdAt;
      const honoured = days.filter((d) => d.status === "honoured").length;
      out.push(
        entry(c.id, c, "amended", localDate(at), at, total ? { sessions: sessionsHonouredText(honoured, total) } : {}),
      );
    }
  }
  return out.sort((a, b) => b.at - a.at || a.id.localeCompare(b.id));
}

/** The colour of each calendar date: its newest entry. */
export function statusByDay(entries: readonly HistoryEntry[]): Map<string, HistoryStatus> {
  const byDay = new Map<string, HistoryStatus>();
  for (const e of entries) if (!byDay.has(e.dayKey)) byDay.set(e.dayKey, e.status);
  return byDay;
}

export interface MonthTotals {
  honoured: number;
  broken: number;
  amended: number;
  total: number;
}

/** Entries of one calendar month (month index 0–11). */
export function monthTotals(entries: readonly HistoryEntry[], year: number, month: number): MonthTotals {
  const t: MonthTotals = { honoured: 0, broken: 0, amended: 0, total: 0 };
  for (const e of entries) {
    if (e.date.getFullYear() !== year || e.date.getMonth() !== month) continue;
    t[e.status] += 1;
    t.total += 1;
  }
  return t;
}
