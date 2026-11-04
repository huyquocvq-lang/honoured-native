import { describe, expect, it } from "vitest";
import type { IconTerms } from "@/lib/icon";
import type { IconDay, IconDayStatus, IconDaysByContract } from "@/lib/icon-days";
import { historyDayKey, historyEntries, monthTotals, statusByDay } from "@/lib/history-entries";
import { sessionsHonouredText } from "@/lib/icon-recap";
import type { Contract } from "@/lib/store";

// Local clock; 5 Oct 2026 is a Monday.
const at = (month: number, day: number, hour = 0, minute = 0) => new Date(2026, month - 1, day, hour, minute).getTime();

const terms: IconTerms = {
  weekdays: ["mon", "tue", "wed", "thu", "fri", "sat", "sun"],
  startDay: "2026-10-05",
  period: { count: 1, unit: "week" },
  deadlineTime: "00:00",
  timezone: "UTC",
  morning: "07:00",
  evening: "20:00",
};

let n = 0;
function contract(over: Partial<Contract> = {}): Contract {
  n += 1;
  return {
    id: `c${n}`,
    createdAt: at(10, 5, 6),
    deadline: at(10, 5, 21),
    primaryType: "complete",
    primaryActivity: "Walking",
    primaryTarget: "10000 steps",
    because: "For my knees",
    locked: false,
    standing: false,
    status: "active",
    ...over,
  };
}

const CODE: Record<string, IconDayStatus> = { H: "honoured", B: "broken", P: "pending", A: "amended" };

/** Consecutive Icon days from `start` with a 00:00 cut-off (the midnight that ends the day). */
function daysFrom(c: Contract, start: string, codes: string): IconDay[] {
  const [y, m, d] = start.split("-").map(Number);
  return [...codes].map((code, i) => {
    const date = new Date(Date.UTC(y, m - 1, d + i));
    const cutoff = new Date(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate() + 1).getTime();
    const status = CODE[code];
    return {
      contractUuid: `uuid-${c.id}`,
      clientId: c.id,
      day: date.toISOString().slice(0, 10),
      sessionNumber: i + 1,
      deadlineMs: cutoff,
      status,
      resolution: status === "pending" ? null : status === "amended" ? "amended" : status === "honoured" ? "target_met" : "target_missed",
      measuredValue: status === "pending" || status === "amended" ? null : status === "honoured" ? 12382 : 6240,
      // Stamped an hour after the cut-off, i.e. on the next calendar day.
      scoredAt: status === "pending" ? null : cutoff + 3_600_000,
    };
  });
}

const key = (month: number, day: number) => historyDayKey(new Date(2026, month - 1, day));

describe("History entries", () => {
  it("an ordinary contract appears once resolved, on the day it was resolved", () => {
    const done = contract({ status: "honoured", resolvedAt: at(10, 3, 18) });
    const running = contract();
    const entries = historyEntries([done, running], {});
    expect(entries).toHaveLength(1);
    expect(entries[0]).toMatchObject({ id: done.id, status: "honoured", dayKey: key(10, 3) });
    expect(entries[0].iconDay).toBeUndefined();
  });

  it("each stamped day of a running Icon appears on its own date", () => {
    const icon = contract({ icon: terms, deadline: at(10, 12, 0) });
    const days: IconDaysByContract = { [icon.id]: daysFrom(icon, "2026-10-05", "HBP") };
    const entries = historyEntries([icon], days);
    expect(entries.map((e) => [e.dayKey, e.status])).toEqual([
      [key(10, 6), "broken"],
      [key(10, 5), "honoured"],
    ]);
    expect(entries[1].iconDay).toEqual({
      day: "2026-10-05",
      session: 1,
      total: 3,
      resolution: "target_met",
      measuredValue: 12382,
    });
    expect(entries[1].id).toBe(`${icon.id}|2026-10-05`);
  });

  it("an Icon day stays on its own date even when it was stamped the next day", () => {
    const icon = contract({ icon: terms });
    const entries = historyEntries([icon], { [icon.id]: daysFrom(icon, "2026-10-05", "H") });
    expect(entries[0].dayKey).toBe(key(10, 5));
    expect(entries[0].date.getTime()).toBe(at(10, 5));
  });

  it("an Icon closed at the end of its period adds no entry of its own", () => {
    const icon = contract({ icon: terms, status: "honoured", resolvedAt: at(10, 7, 0) });
    const entries = historyEntries([icon], { [icon.id]: daysFrom(icon, "2026-10-05", "HHB") });
    expect(entries).toHaveLength(3);
    expect(entries.every((e) => e.iconDay)).toBe(true);
  });

  it("an Icon ended early: its stamped days, plus one AMENDED entry on the day it was ended", () => {
    const icon = contract({ icon: terms, status: "amended", resolvedAt: at(10, 7, 10) });
    const entries = historyEntries([icon], { [icon.id]: daysFrom(icon, "2026-10-05", "HB" + "A".repeat(5)) });
    expect(entries.map((e) => [e.dayKey, e.status])).toEqual([
      [key(10, 7), "amended"],
      [key(10, 6), "broken"],
      [key(10, 5), "honoured"],
    ]);
    expect(entries[0]).toMatchObject({ id: icon.id, sessions: "1 of 7 sessions honoured" });
    expect(entries[0].iconDay).toBeUndefined();
  });

  it("an Icon without loaded days shows nothing yet, except an early exit", () => {
    const running = contract({ icon: terms });
    const ended = contract({ icon: terms, status: "amended", resolvedAt: at(10, 6, 9) });
    const entries = historyEntries([running, ended], {});
    expect(entries).toEqual([expect.objectContaining({ id: ended.id, status: "amended", dayKey: key(10, 6) })]);
    expect(entries[0].sessions).toBeUndefined();
  });

  it("days of a contract that is not on this device are skipped", () => {
    const ghost = contract({ icon: terms });
    expect(historyEntries([], { [ghost.id]: daysFrom(ghost, "2026-10-05", "HH") })).toEqual([]);
  });

  it("lists newest first", () => {
    const old = contract({ status: "broken", resolvedAt: at(9, 30, 22) });
    const icon = contract({ icon: terms });
    const entries = historyEntries([old, icon], { [icon.id]: daysFrom(icon, "2026-10-05", "HH") });
    expect(entries.map((e) => e.dayKey)).toEqual([key(10, 6), key(10, 5), key(9, 30)]);
  });
});

describe("calendar colours and month totals", () => {
  it("a date takes the colour of its newest entry", () => {
    const morning = contract({ status: "broken", resolvedAt: at(10, 3, 9) });
    const evening = contract({ status: "honoured", resolvedAt: at(10, 3, 20) });
    const byDay = statusByDay(historyEntries([morning, evening], {}));
    expect(byDay.get(key(10, 3))).toBe("honoured");
  });

  it("Icon days colour their own dates", () => {
    const icon = contract({ icon: terms, status: "amended", resolvedAt: at(10, 8, 12) });
    const byDay = statusByDay(historyEntries([icon], { [icon.id]: daysFrom(icon, "2026-10-05", "HBH" + "AAAA") }));
    expect([...byDay.entries()].sort()).toEqual(
      [
        [key(10, 5), "honoured"],
        [key(10, 6), "broken"],
        [key(10, 7), "honoured"],
        [key(10, 8), "amended"],
      ].sort(),
    );
  });

  it("month totals count every entry by its date", () => {
    const sept = contract({ status: "honoured", resolvedAt: at(9, 30, 10) });
    const icon = contract({ icon: terms });
    // 30 Sep … 3 Oct: the first day belongs to September.
    const entries = historyEntries([sept, icon], { [icon.id]: daysFrom(icon, "2026-09-30", "BHHB") });
    expect(monthTotals(entries, 2026, 8)).toEqual({ honoured: 1, broken: 1, amended: 0, total: 2 });
    expect(monthTotals(entries, 2026, 9)).toEqual({ honoured: 2, broken: 1, amended: 0, total: 3 });
    expect(monthTotals(entries, 2026, 10)).toEqual({ honoured: 0, broken: 0, amended: 0, total: 0 });
  });

  it("session wording", () => {
    expect(sessionsHonouredText(1, 1)).toBe("1 of 1 session honoured");
    expect(sessionsHonouredText(16, 18)).toBe("16 of 18 sessions honoured");
  });
});
