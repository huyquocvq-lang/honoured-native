import { describe, expect, it } from "vitest";
import { isValidIconDraft, type IconTerms } from "@/lib/icon";
import type { IconDay, IconDayStatus, IconDaysByContract } from "@/lib/icon-days";
import type { Contract } from "@/lib/store";
import {
  ICON_END_SHOWN_FOR_MS,
  ICON_END_STRONG,
  ICON_END_TOUGH,
  MONTH_STRONG,
  MONTH_TOUGH,
  WEEK_STRONG,
  WEEK_TOUGH,
  buildRecap,
  dueIconEnds,
  dueMoments,
  dueRecaps,
  finishedIcons,
  goAgainPrefill,
  iconEnd,
  iconEndCount,
  iconEndLines,
  markSeen,
  monthOf,
  moreThanZero,
  periodLabel,
  periodTotals,
  previousPeriod,
  weekOf,
  type MomentsSeen,
} from "@/lib/icon-recap";

// Local clock; 5 Oct 2026 is a Monday.
const at = (month: number, day: number, hour = 0, minute = 0) => new Date(2026, month - 1, day, hour, minute).getTime();

function terms(over: Partial<IconTerms> = {}): IconTerms {
  return {
    weekdays: ["mon", "tue", "wed", "thu", "fri", "sat", "sun"],
    startDay: "2026-09-01",
    period: { count: 1, unit: "month" },
    deadlineTime: "21:00",
    timezone: "UTC",
    morning: "07:00",
    evening: "20:00",
    ...over,
  };
}

let n = 0;
function contract(over: Partial<Contract> = {}): Contract {
  n += 1;
  return {
    id: `c${n}`,
    createdAt: at(9, 1, 6),
    deadline: at(9, 30, 21),
    primaryType: "complete",
    primaryActivity: "Walking",
    primaryTarget: "10,000 steps",
    because: "For my knees",
    locked: false,
    standing: false,
    status: "active",
    icon: terms(),
    ...over,
  };
}

const CODE: Record<string, IconDayStatus> = { H: "honoured", B: "broken", P: "pending", A: "amended" };

/** Consecutive days from `start`, one per letter (H, B, P, A), cut-off 21:00 local. */
function daysFrom(c: Contract, start: string, codes: string): IconDay[] {
  const [y, m, d] = start.split("-").map(Number);
  return [...codes].map((code, i) => {
    const date = new Date(Date.UTC(y, m - 1, d + i));
    const day = date.toISOString().slice(0, 10);
    const cutoff = new Date(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate(), 21).getTime();
    const status = CODE[code];
    return {
      contractUuid: `uuid-${c.id}`,
      clientId: c.id,
      day,
      sessionNumber: i + 1,
      deadlineMs: cutoff,
      status,
      resolution: status === "pending" ? null : status === "amended" ? "amended" : status === "honoured" ? "target_met" : "target_missed",
      measuredValue: null,
      scoredAt: status === "pending" ? null : cutoff,
    };
  });
}

function byContract(...lists: IconDay[][]): IconDaysByContract {
  const out: IconDaysByContract = {};
  for (const list of lists) if (list.length) out[list[0].clientId] = list;
  return out;
}

const WEEK = weekOf("2026-09-28"); // Mon 28 Sep – Sun 4 Oct

describe("periods", () => {
  it("weeks run Monday to Sunday, across months, years and clock changes", () => {
    expect(weekOf("2026-10-04")).toEqual({ kind: "week", key: "2026-09-28", first: "2026-09-28", last: "2026-10-04" });
    expect(weekOf("2026-09-28").key).toBe("2026-09-28");
    expect(weekOf("2027-01-01")).toMatchObject({ first: "2026-12-28", last: "2027-01-03" });
    expect(weekOf("2026-11-01")).toMatchObject({ first: "2026-10-26", last: "2026-11-01" });
    expect(weekOf("2026-04-05")).toMatchObject({ first: "2026-03-30", last: "2026-04-05" });
  });

  it("months are calendar months", () => {
    expect(monthOf("2026-02-14")).toEqual({ kind: "month", key: "2026-02", first: "2026-02-01", last: "2026-02-28" });
    expect(monthOf("2028-02-03").last).toBe("2028-02-29");
    expect(monthOf("2026-12-31")).toMatchObject({ first: "2026-12-01", last: "2026-12-31" });
  });

  it("the previous period is the last full one", () => {
    expect(previousPeriod("week", "2026-10-05").key).toBe("2026-09-28");
    expect(previousPeriod("week", "2026-10-04").key).toBe("2026-09-21");
    expect(previousPeriod("month", "2026-10-01").key).toBe("2026-09");
    expect(previousPeriod("month", "2027-01-15").key).toBe("2026-12");
  });

  it("labels", () => {
    expect(periodLabel(WEEK)).toBe("28 Sep – 4 Oct");
    expect(periodLabel(weekOf("2026-12-31"))).toBe("28 Dec – 3 Jan");
    expect(periodLabel(monthOf("2026-09-30"))).toBe("September");
  });
});

describe("recap totals and tone", () => {
  it("a strong week (scope: 15 Honoured, 1 Broken) across Icons", () => {
    const a = contract();
    const b = contract({ primaryActivity: "Running" });
    const c = contract({ primaryActivity: "Cycling" });
    const days = byContract(daysFrom(a, "2026-09-28", "HHHHHHH"), daysFrom(b, "2026-09-28", "HHHHHHB"), daysFrom(c, "2026-10-03", "HH"));
    const recap = buildRecap(WEEK, [a, b, c], days)!;
    expect(recap.totals).toEqual({ honoured: 15, amended: 0, broken: 1, pending: 0 });
    expect(recap.tone).toBe("strong");
    expect(recap.lines).toEqual([WEEK_STRONG]);
    expect(recap.title).toBe("Your week");
    expect(recap.range).toBe("28 Sep – 4 Oct");
  });

  it("a difficult week (inverted record) acknowledges its one Honoured session", () => {
    const a = contract();
    const b = contract();
    const c = contract();
    const days = byContract(daysFrom(a, "2026-09-28", "BBBBBBB"), daysFrom(b, "2026-09-28", "BBBBBBH"), daysFrom(c, "2026-10-03", "BB"));
    const recap = buildRecap(WEEK, [a, b, c], days)!;
    expect(recap.totals).toMatchObject({ honoured: 1, broken: 15 });
    expect(recap.tone).toBe("tough");
    expect(recap.lines).toEqual([WEEK_TOUGH, "That's one more than zero."]);
  });

  it("a difficult week without any Honoured session, and a tie", () => {
    const a = contract();
    expect(buildRecap(WEEK, [a], byContract(daysFrom(a, "2026-09-28", "BBB")))!.lines).toEqual([WEEK_TOUGH]);
    const tie = buildRecap(WEEK, [a], byContract(daysFrom(a, "2026-09-28", "HHBB")))!;
    expect(tie.tone).toBe("tough");
    expect(tie.lines).toEqual([WEEK_TOUGH, "That's two more than zero."]);
  });

  it("months use the month lines", () => {
    const a = contract();
    const month = monthOf("2026-09-01");
    expect(buildRecap(month, [a], byContract(daysFrom(a, "2026-09-01", "HHHB")))!.lines).toEqual([MONTH_STRONG]);
    const tough = buildRecap(month, [a], byContract(daysFrom(a, "2026-09-01", "HBBB")))!;
    expect(tough.lines).toEqual([MONTH_TOUGH, "That's one more than zero."]);
    expect(tough.title).toBe("Your month");
    expect(tough.range).toBe("September");
  });

  it("counts only the period's own days, and pending ones", () => {
    const a = contract();
    // Sun 27 Sep … Mon 5 Oct: the first and last fall outside the week.
    const days = byContract(daysFrom(a, "2026-09-27", "BHHHHHHPB"));
    expect(periodTotals(WEEK, [a], days)).toEqual({ honoured: 6, amended: 0, broken: 0, pending: 1 });
  });

  it("Amended counts an Icon ended early in the period, not the days it released", () => {
    const ended = contract({ status: "amended", resolvedAt: at(10, 1, 10), deadline: at(10, 31, 21) });
    // Honoured, Broken, Honoured, then every day from 1 Oct amended by the exit.
    const days = byContract(daysFrom(ended, "2026-09-28", "HBH" + "A".repeat(31)));
    expect(periodTotals(WEEK, [ended], days)).toEqual({ honoured: 2, amended: 1, broken: 1, pending: 0 });
    const next = weekOf("2026-10-05");
    expect(periodTotals(next, [ended], days)).toEqual({ honoured: 0, amended: 0, broken: 0, pending: 0 });
    expect(buildRecap(next, [ended], days)).toBeNull();
  });

  it("no recap when nothing was stamped Honoured or Broken", () => {
    const ended = contract({ status: "amended", resolvedAt: at(9, 29, 9) });
    expect(buildRecap(WEEK, [ended], byContract(daysFrom(ended, "2026-09-29", "AAAAAA")))).toBeNull();
    expect(buildRecap(WEEK, [], {})).toBeNull();
  });

  it("says each count in words up to ten", () => {
    expect(moreThanZero(1)).toBe("That's one more than zero.");
    expect(moreThanZero(10)).toBe("That's ten more than zero.");
    expect(moreThanZero(12)).toBe("That's 12 more than zero.");
  });
});

describe("which recaps are due", () => {
  const a = contract();
  // Every day of September and the week to Sun 4 Oct, all stamped.
  const stamped = byContract(daysFrom(a, "2026-09-01", "H".repeat(34)));
  const monday = at(10, 5, 10);

  it("on Monday 5 Oct: September, then the week to Sunday", () => {
    const due = dueRecaps([a], stamped, monday, {});
    expect(due.map((r) => r.period.key)).toEqual(["2026-09", "2026-09-28"]);
  });

  it("once each", () => {
    expect(dueRecaps([a], stamped, monday, { month: "2026-09", week: "2026-09-28" })).toEqual([]);
    expect(dueRecaps([a], stamped, monday, { month: "2026-08", week: "2026-09-21" })).toHaveLength(2);
  });

  it("waits until every day of the period is stamped", () => {
    const sundayPending = byContract(daysFrom(a, "2026-09-01", "H".repeat(33) + "P"));
    expect(dueRecaps([a], sundayPending, monday, {}).map((r) => r.period.key)).toEqual(["2026-09"]);
  });

  it("offers only the period just before the current one", () => {
    // Wednesday 14 Oct: last week (5–11 Oct) had no Icon day.
    expect(dueRecaps([a], stamped, at(10, 14, 9), { month: "2026-09" })).toEqual([]);
  });

  it("nothing without Icon days", () => {
    expect(dueRecaps([], {}, monday, {})).toEqual([]);
  });
});

describe("end of an Icon", () => {
  // Every day from Thu 1 Oct to Sun 18 Oct: 18 sessions, last cut-off 18 Oct 21:00.
  const make = (codes: string, over: Partial<Contract> = {}) => {
    const c = contract({ createdAt: at(10, 1, 6), deadline: at(10, 18, 21), icon: terms({ startDay: "2026-10-01" }), ...over });
    return { c, days: daysFrom(c, "2026-10-01", codes) };
  };
  const after = at(10, 19, 8);

  it("ends once the last cut-off has passed and every session is stamped", () => {
    const { c, days } = make("HHHHHHHHBHHHHHHHBH");
    expect(iconEnd(c, days, after)).toEqual({
      contract: c,
      honoured: 16,
      broken: 2,
      total: 18,
      tone: "strong",
      status: "honoured",
      endedAt: at(10, 18, 21),
    });
    expect(iconEndCount(iconEnd(c, days, after)!)).toBe("16 of 18 sessions honoured");
    expect(iconEndLines(iconEnd(c, days, after)!)).toEqual([ICON_END_STRONG]);
  });

  it("not before the last cut-off, even when the last session is already Honoured", () => {
    const { c, days } = make("H".repeat(18));
    expect(iconEnd(c, days, at(10, 18, 12))).toBeNull();
  });

  it("not while a session is pending", () => {
    const { c, days } = make("H".repeat(17) + "P");
    expect(iconEnd(c, days, after)).toBeNull();
  });

  it("a tough record closes BROKEN, a tie too", () => {
    const tough = make("HHHBBBBB", { deadline: at(10, 8, 21) });
    const end = iconEnd(tough.c, tough.days, after)!;
    expect(end).toMatchObject({ honoured: 3, broken: 5, tone: "tough", status: "broken" });
    expect(iconEndLines(end)).toEqual([ICON_END_TOUGH, "That's three more than zero."]);
    const tie = make("HHHHBBBB", { deadline: at(10, 8, 21) });
    expect(iconEnd(tie.c, tie.days, after)!.status).toBe("broken");
    const none = make("BB", { deadline: at(10, 2, 21) });
    expect(iconEndLines(iconEnd(none.c, none.days, after)!)).toEqual([ICON_END_TOUGH]);
    expect(iconEndCount(iconEnd(none.c, none.days, after)!)).toBe("0 of 2 sessions honoured");
  });

  it("never from an incomplete list of days", () => {
    const { c, days } = make("H".repeat(18));
    expect(iconEnd(c, days.filter((d) => d.sessionNumber !== 5), after)).toBeNull();
    // The contract's own last cut-off is later than any day loaded.
    expect(iconEnd({ ...c, deadline: at(10, 25, 21) }, days, after)).toBeNull();
    expect(iconEnd(c, [], after)).toBeNull();
    expect(iconEnd(c, undefined, after)).toBeNull();
  });

  it("not for an Icon ended early, nor an ordinary contract", () => {
    const { c, days } = make("HHHH" + "A".repeat(14));
    expect(iconEnd(c, days, after)).toBeNull();
    const daily = contract({ icon: undefined, deadline: at(10, 1, 21) });
    expect(iconEnd(daily, daysFrom(daily, "2026-10-01", "H"), after)).toBeNull();
  });

  it("one session", () => {
    const { c, days } = make("H", { deadline: at(10, 1, 21) });
    expect(iconEndCount(iconEnd(c, days, after)!)).toBe("1 of 1 session honoured");
  });

  it("finishedIcons lists only active Icons", () => {
    const done = make("H".repeat(18));
    const closed = make("H".repeat(18), { status: "honoured" });
    const running = make("H".repeat(17) + "P");
    const days = byContract(done.days, closed.days, running.days);
    expect(finishedIcons([done.c, closed.c, running.c], days, after).map((e) => e.contract.id)).toEqual([done.c.id]);
  });

  it("the summary is due for a closed Icon, once, for 14 days", () => {
    const closed = make("H".repeat(18), { status: "honoured", resolvedAt: at(10, 18, 21) });
    const ended = make("HHHH" + "A".repeat(14), { status: "amended", resolvedAt: at(10, 4, 12) });
    const running = make("H".repeat(18));
    const days = byContract(closed.days, ended.days, running.days);
    const all = [closed.c, ended.c, running.c];
    expect(dueIconEnds(all, days, after, {}).map((e) => e.contract.id)).toEqual([closed.c.id]);
    expect(dueIconEnds(all, days, after, { icons: [closed.c.id] })).toEqual([]);
    expect(dueIconEnds(all, days, at(10, 18, 21) + ICON_END_SHOWN_FOR_MS, {})).toHaveLength(1);
    expect(dueIconEnds(all, days, at(10, 18, 21) + ICON_END_SHOWN_FOR_MS + 1, {})).toEqual([]);
  });
});

describe("moments", () => {
  it("Icon summaries first, then the month, then the week; each once", () => {
    const closed = contract({
      status: "broken",
      resolvedAt: at(10, 4, 21),
      createdAt: at(9, 1, 6),
      deadline: at(10, 4, 21),
    });
    const days = byContract(daysFrom(closed, "2026-09-01", "B".repeat(20) + "H".repeat(14)));
    let seen: MomentsSeen = {};
    const now = at(10, 5, 8);
    const due = dueMoments([closed], days, now, seen);
    expect(due.map((m) => (m.kind === "recap" ? m.recap.period.key : m.end.contract.id))).toEqual([closed.id, "2026-09", "2026-09-28"]);
    for (const m of due) seen = markSeen(seen, m);
    expect(seen).toEqual({ icons: [closed.id], month: "2026-09", week: "2026-09-28" });
    expect(dueMoments([closed], days, now, seen)).toEqual([]);
  });

  it("keeps the 50 most recent Icon summaries", () => {
    let seen: MomentsSeen = { icons: Array.from({ length: 50 }, (_, i) => `old${i}`) };
    const end = { contract: contract(), honoured: 1, broken: 0, total: 1, tone: "strong" as const, status: "honoured" as const, endedAt: 0 };
    seen = markSeen(seen, { kind: "icon-end", end });
    expect(seen.icons).toHaveLength(50);
    expect(seen.icons![0]).toBe("old1");
    expect(seen.icons![49]).toBe(end.contract.id);
    seen = markSeen({ icons: [end.contract.id, "x"] }, { kind: "icon-end", end });
    expect(seen.icons).toEqual(["x", end.contract.id]);
  });
});

describe("go again", () => {
  const finished = contract({
    status: "honoured",
    icon: terms({ weekdays: ["tue", "thu", "sat"], period: { count: 3, unit: "month" }, deadlineTime: "21:30:00", morning: "06:45:00", evening: "19:00" }),
  });

  it("prefills the same terms, unsigned", () => {
    const p = goAgainPrefill(finished, at(10, 5, 10))!;
    expect(p).toEqual({
      primaryType: "complete",
      primaryActivity: "Walking",
      primaryTarget: "10,000 steps",
      because: "For my knees",
      draft: {
        days: ["tue", "thu", "sat"],
        period: { count: 3, unit: "month" },
        reminders: [
          { hour: 6, minute: 45 },
          { hour: 19, minute: 0 },
        ],
      },
      deadline: at(10, 5, 21, 30),
    });
    expect(isValidIconDraft(p.draft)).toBe(true);
    expect(p).not.toHaveProperty("signaturePng");
    p.draft.days.push("mon");
    expect(finished.icon!.weekdays).toEqual(["tue", "thu", "sat"]);
  });

  it("the deadline is the next occurrence of the daily cut-off", () => {
    expect(goAgainPrefill(finished, at(10, 5, 22))!.deadline).toBe(at(10, 6, 21, 30));
    const midnight = contract({ icon: terms({ deadlineTime: "00:00" }) });
    expect(goAgainPrefill(midnight, at(10, 5, 10))!.deadline).toBe(at(10, 6, 0, 0));
  });

  it("keeps only the reminders that were on", () => {
    const eveningOnly = contract({ icon: terms({ morning: null, evening: "20:15" }) });
    expect(goAgainPrefill(eveningOnly, at(10, 5, 10))!.draft.reminders).toEqual([{ hour: 20, minute: 15 }]);
    const none = contract({ icon: terms({ morning: null, evening: null }), primaryTarget: undefined });
    const p = goAgainPrefill(none, at(10, 5, 10))!;
    expect(p.draft.reminders).toEqual([]);
    expect(p).not.toHaveProperty("primaryTarget");
  });

  it("only for an Icon", () => {
    expect(goAgainPrefill(contract({ icon: undefined }), at(10, 5, 10))).toBeNull();
  });
});
