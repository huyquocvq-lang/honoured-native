import { describe, expect, it } from "vitest";
import type { IconTerms } from "@/lib/icon";
import type { Contract } from "@/lib/store";
import {
  CONTRACT_DAY_TAKEN,
  ICON_DAY_TAKEN,
  dayConflict,
  dayConflictMessage,
  dayReservedRefusal,
  iconDayRanges,
  upsertContractRows,
} from "@/lib/icon-exclusivity";

// Local clock: 5 Oct 2026 is a Monday.
const at = (day: number, hour: number, minute = 0) => new Date(2026, 9, day, hour, minute).getTime();

function icon(weekdays: IconTerms["weekdays"], startDay: string, deadlineTime: string): IconTerms {
  return { weekdays, startDay, period: { count: 1, unit: "week" }, deadlineTime, timezone: "UTC", morning: null, evening: null };
}

let n = 0;
function contract(over: Partial<Contract>): Contract {
  n += 1;
  return {
    id: `c${n}`,
    createdAt: at(5, 8),
    deadline: at(5, 20),
    primaryType: "complete",
    primaryActivity: `Activity ${n}`,
    because: "test",
    locked: false,
    standing: false,
    status: "active",
    ...over,
  };
}

// Signed Mon 08:00 for Mondays and Wednesdays, cut-off 09:00: holds Mon 5 and Wed 7.
const mondayIcon = contract({ createdAt: at(5, 8), deadline: at(7, 9), icon: icon(["mon", "wed"], "2026-10-05", "09:00") });

describe("held days", () => {
  it("are whole local calendar days of the Icon's schedule", () => {
    expect(iconDayRanges(mondayIcon.icon!, mondayIcon.createdAt)).toEqual([
      [at(5, 0), at(6, 0)],
      [at(7, 0), at(8, 0)],
    ]);
  });
});

describe("signing a contract", () => {
  const sign = (createdAt: number, deadline: number, standing = false) => dayConflict({ createdAt, deadline, standing }, [mondayIcon]);

  it("is refused on an Icon day, before or after its cut-off", () => {
    expect(sign(at(5, 8, 30), at(5, 8, 45))).toBe("icon");
    expect(sign(at(5, 10), at(5, 12))).toBe("icon");
  });

  it("is allowed on a day without an Icon", () => {
    expect(sign(at(6, 1), at(6, 20))).toBeNull();
  });

  it("is refused when its deadline runs into an Icon day", () => {
    expect(sign(at(6, 21), at(7, 5))).toBe("icon");
    expect(sign(at(6, 21), at(7, 0))).toBeNull();
  });

  it("is refused for a Standing contract while an Icon still holds a day ahead", () => {
    expect(sign(at(6, 1), at(6, 2), true)).toBe("icon");
    expect(sign(at(8, 1), at(8, 2), true)).toBeNull();
  });

  it("is allowed once the Icon ended early", () => {
    const ended = { ...mondayIcon, status: "amended" as const };
    expect(dayConflict({ createdAt: at(7, 1), deadline: at(7, 5), standing: false }, [ended])).toBeNull();
  });
});

describe("signing an Icon", () => {
  const signIcon = (terms: IconTerms, createdAt: number, contracts: Contract[]) =>
    dayConflict({ createdAt, deadline: at(30, 0), standing: false, icon: terms }, contracts);

  it("is refused as a whole when one of its days is held by another Icon", () => {
    expect(signIcon(icon(["wed", "fri"], "2026-10-06", "23:00"), at(6, 0, 30), [mondayIcon])).toBe("icon");
  });

  it("is allowed on days no Icon holds", () => {
    expect(signIcon(icon(["fri"], "2026-10-08", "23:00"), at(8, 0, 30), [mondayIcon])).toBeNull();
  });

  it("is refused while an active contract covers one of its days, allowed once it resolved", () => {
    const tuesday = contract({ createdAt: at(6, 1), deadline: at(6, 20) });
    const terms = icon(["tue"], "2026-10-06", "23:00");
    expect(signIcon(terms, at(6, 0, 30), [mondayIcon, tuesday])).toBe("contract");
    expect(signIcon(terms, at(6, 0, 30), [mondayIcon, { ...tuesday, status: "honoured" }])).toBeNull();
  });

  it("is refused while a Standing contract is active", () => {
    const standing = contract({ standing: true, createdAt: at(1, 0), deadline: at(2, 0) });
    expect(signIcon(icon(["sat"], "2026-10-10", "23:00"), at(10, 1), [standing])).toBe("contract");
  });

  it("prefers the Icon rule when both apply", () => {
    const wednesday = contract({ createdAt: at(7, 10), deadline: at(7, 11) });
    expect(signIcon(icon(["wed"], "2026-10-07", "23:00"), at(7, 10), [mondayIcon, wednesday])).toBe("icon");
  });
});

describe("messages and database refusals", () => {
  it("map each rule to its message", () => {
    expect(dayConflictMessage("icon")).toBe(ICON_DAY_TAKEN);
    expect(dayConflictMessage("contract")).toBe(CONTRACT_DAY_TAKEN);
    expect(ICON_DAY_TAKEN).toBe("Icon already set for this day. Finish your Icon first.");
  });

  it("read the refusal from the error detail only", () => {
    expect(dayReservedRefusal({ details: "icon_day_reserved" })).toBe("icon");
    expect(dayReservedRefusal({ details: "contract_day_reserved" })).toBe("contract");
    expect(dayReservedRefusal({ details: "something else" })).toBeNull();
    expect(dayReservedRefusal(null)).toBeNull();
  });
});

describe("saving contracts", () => {
  type Row = { client_id: string };
  const refusal = { message: ICON_DAY_TAKEN, details: "icon_day_reserved" };

  it("sends a batch once when the database accepts it", async () => {
    const calls: string[][] = [];
    const result = await upsertContractRows<Row>(async (rows) => {
      calls.push(rows.map((r) => r.client_id));
      return { error: null };
    }, [{ client_id: "a" }, { client_id: "b" }]);
    expect(result).toEqual({ error: null, refused: [] });
    expect(calls).toEqual([["a", "b"]]);
  });

  it("isolates a refused row so the others are still saved", async () => {
    const saved: string[] = [];
    const result = await upsertContractRows<Row>(async (rows) => {
      if (rows.some((r) => r.client_id === "b")) return { error: refusal };
      saved.push(...rows.map((r) => r.client_id));
      return { error: null };
    }, [{ client_id: "a" }, { client_id: "b" }, { client_id: "c" }]);
    expect(result).toEqual({ error: null, refused: [{ clientId: "b", conflict: "icon" }] });
    expect(saved).toEqual(["a", "c"]);
  });

  it("passes any other error through without retrying row by row", async () => {
    let calls = 0;
    const result = await upsertContractRows<Row>(async () => {
      calls += 1;
      return { error: { message: "network", details: null } };
    }, [{ client_id: "a" }, { client_id: "b" }]);
    expect(result.error?.message).toBe("network");
    expect(result.refused).toEqual([]);
    expect(calls).toBe(1);
  });
});
