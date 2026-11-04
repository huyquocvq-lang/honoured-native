import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import {
  ICON_TIMER_NOTICES,
  completeIconTimer,
  iconDayAt,
  iconTimerAvailability,
  iconTimerSeconds,
  type IconTimerDeps,
} from "@/lib/icon-timer";
import type { IconDay } from "@/lib/icon-days";
import type { IconTerms } from "@/lib/icon";
import { honourContract, readStoreState, setStoreUser, stateKeyForUser, type AppState, type Contract } from "@/lib/store";
import type { TimerState } from "@/lib/timer-store";

const at = (y: number, m: number, d: number, h = 0, mi = 0) => new Date(y, m - 1, d, h, mi).getTime();
const terms = (over: Partial<IconTerms> = {}): IconTerms => ({
  weekdays: ["tue", "thu"],
  startDay: "2026-10-06",
  period: { count: 1, unit: "month" },
  deadlineTime: "23:59",
  timezone: "Europe/London",
  morning: null,
  evening: null,
  ...over,
});
const icon = (over: Partial<Contract> = {}): Contract => ({
  id: "ic1",
  createdAt: at(2026, 10, 6, 8),
  deadline: at(2026, 11, 5, 23, 59),
  primaryType: "complete",
  primaryActivity: "Basketball",
  primaryTarget: "22 min",
  because: "x",
  locked: false,
  standing: false,
  status: "active",
  icon: terms(),
  ...over,
});
const ordinary = (over: Partial<Contract> = {}): Contract => ({ ...icon(), id: "c1", icon: undefined, ...over });
const day = (d: string, over: Partial<IconDay> = {}): IconDay => {
  const [y, m, dd] = d.split("-").map(Number);
  return {
    contractUuid: "uuid-1",
    clientId: "ic1",
    day: d,
    sessionNumber: 1,
    deadlineMs: at(y, m, dd, 23, 59),
    status: "pending",
    resolution: null,
    measuredValue: null,
    scoredAt: null,
    ...over,
  };
};
const timer = (contractId: string): TimerState => ({ contractId, totalSeconds: 60, endsAt: Date.now() + 60_000, pausedRemaining: null });

describe("iconTimerSeconds", () => {
  it("only for active, unmeasured, complete Icons with a time target", () => {
    expect(iconTimerSeconds(icon())).toBe(1320);
    expect(iconTimerSeconds(icon({ icon: terms({ metric: "exercise_minutes", target: 22, unit: "min" }) }))).toBeNull();
    expect(iconTimerSeconds(icon({ primaryType: "limit" }))).toBeNull();
    expect(iconTimerSeconds(icon({ primaryTarget: "10000 steps" }))).toBeNull();
    expect(iconTimerSeconds(ordinary())).toBeNull();
  });
});

describe("iconTimerAvailability", () => {
  const today = [day("2026-10-06")];
  const noon = at(2026, 10, 6, 12);
  it("none: not an Icon day, stamped, cut-off passed", () => {
    expect(iconTimerAvailability(icon(), [day("2026-10-08")], noon, null).kind).toBe("none");
    expect(iconTimerAvailability(icon(), [day("2026-10-06", { status: "honoured" })], noon, null).kind).toBe("none");
    expect(iconTimerAvailability(icon(), today, at(2026, 10, 6, 23, 59) + 1000, null).kind).toBe("none");
  });
  it("running / busy", () => {
    expect(iconTimerAvailability(icon(), today, noon, timer("ic1")).kind).toBe("running");
    expect(iconTimerAvailability(icon(), today, noon, { ...timer("ic1"), endsAt: null, pausedRemaining: 5 }).kind).toBe("running");
    expect(iconTimerAvailability(icon(), today, noon, timer("other")).kind).toBe("busy");
  });
  it("too_late at the boundary, ready just before", () => {
    const cut = at(2026, 10, 6, 23, 59);
    expect(iconTimerAvailability(icon(), today, cut - 1320_000, null).kind).toBe("ready");
    expect(iconTimerAvailability(icon(), today, cut - 1320_000 + 1, null).kind).toBe("too_late");
    const r = iconTimerAvailability(icon(), today, noon, null);
    expect(r).toMatchObject({ kind: "ready", seconds: 1320 });
  });
});

describe("startedFor and running", () => {
  it("never stamps a later Icon day than the one it was started for", async () => {
    const days = [
      day("2026-10-06", { deadlineMs: at(2026, 10, 7, 0) }),
      day("2026-10-07", { deadlineMs: at(2026, 10, 8, 0), sessionNumber: 2 }),
    ];
    const state = { contracts: [icon()], completionSound: false } as unknown as AppState;
    const mk = () => ({
      readState: () => state,
      readDays: () => ({ ic1: days }),
      fetchDays: vi.fn(async () => ({})),
      call: vi.fn(async () => ({ ok: true as const, status: "honoured" as const })),
      applyLocal: vi.fn(),
      reload: vi.fn(async () => {}),
      gong: vi.fn(),
      notify: vi.fn(),
    });
    const late = mk();
    expect(await completeIconTimer("ic1", at(2026, 10, 7, 0, 12), true, late, "2026-10-06")).toBe("no_session");
    expect(late.call).not.toHaveBeenCalled();
    const same = mk();
    expect(await completeIconTimer("ic1", at(2026, 10, 7, 0, 12), true, same, "2026-10-07")).toBe("honoured");
  });
  it("running even when today is stamped or past its cut-off", () => {
    const t = timer("ic1");
    expect(iconTimerAvailability(icon(), [day("2026-10-06", { status: "honoured" })], at(2026, 10, 6, 12), t).kind).toBe("running");
    expect(iconTimerAvailability(icon(), [day("2026-10-06")], at(2026, 10, 7, 1), t).kind).toBe("running");
  });
  it("Resume is disabled when the paused remainder passes the stored day's cut-off", async () => {
    const { IconTimerControls } = await import("@/components/ActiveIcons");
    const now = Date.now();
    const d = day("2026-10-06", { deadlineMs: now + 60_000 });
    const paused = (rem: number): TimerState => ({ contractId: "ic1", totalSeconds: 1320, endsAt: null, pausedRemaining: rem, iconDay: "2026-10-06" });
    const bad = renderToStaticMarkup(createElement(IconTimerControls, { contract: icon(), days: [d], now, timer: paused(600) }));
    expect(bad).toMatch(/aria-label="Resume timer" disabled=""/);
    expect(bad).toContain("Not enough time before the cut-off to finish. Cancel the timer.");
    const ok = renderToStaticMarkup(createElement(IconTimerControls, { contract: icon(), days: [d], now, timer: paused(10) }));
    expect(ok).not.toContain('disabled=""');
  }, 60_000);
});

describe("iconDayAt", () => {
  it("inside, at, after the cut-off; 00:00 cut-off is next midnight", () => {
    const d = day("2026-10-06", { deadlineMs: at(2026, 10, 6, 20) });
    expect(iconDayAt([d], at(2026, 10, 6, 10))).toBe(d);
    expect(iconDayAt([d], at(2026, 10, 6, 20))).toBe(d);
    expect(iconDayAt([d], at(2026, 10, 6, 20) + 1)).toBeNull();
    const m = day("2026-10-06", { deadlineMs: at(2026, 10, 7, 0) });
    expect(iconDayAt([m], at(2026, 10, 6, 23, 59))).toBe(m);
    expect(iconDayAt([m], at(2026, 10, 7, 0) + 1)).toBeNull();
  });
});

describe("completeIconTimer", () => {
  function deps(over: Partial<IconTimerDeps> = {}, days: IconDay[] | null = [day("2026-10-06")]) {
    const state = { contracts: [icon()], completionSound: true } as unknown as AppState;
    const d = {
      readState: () => state,
      readDays: () => (days ? { ic1: days } : {}),
      fetchDays: vi.fn(async () => ({ ic1: [day("2026-10-06")] })),
      call: vi.fn(async () => ({ ok: true as const, status: "honoured" as const })),
      applyLocal: vi.fn(),
      reload: vi.fn(async () => {}),
      gong: vi.fn(),
      notify: vi.fn(),
      ...over,
    };
    return d;
  }
  const done = at(2026, 10, 6, 12);
  it("honoured: RPC, local apply, gong only when celebrating", async () => {
    const d = deps();
    expect(await completeIconTimer("ic1", done, true, d)).toBe("honoured");
    expect(d.call).toHaveBeenCalledWith("uuid-1", "2026-10-06", true);
    expect(d.applyLocal).toHaveBeenCalled();
    expect(d.gong).toHaveBeenCalledWith(true);
    expect(d.reload).toHaveBeenCalled();
    expect(d.notify).toHaveBeenCalledWith("ic1", ICON_TIMER_NOTICES.honoured);
    const q = deps();
    await completeIconTimer("ic1", done, false, q);
    expect(q.gong).not.toHaveBeenCalled();
  });
  it("no_session after the cut-off and already_stamped make no RPC", async () => {
    const d = deps();
    expect(await completeIconTimer("ic1", at(2026, 10, 7, 0, 30), true, d)).toBe("no_session");
    const s = deps({}, [day("2026-10-06", { status: "broken" })]);
    expect(await completeIconTimer("ic1", done, true, s)).toBe("already_stamped");
    expect(d.call).not.toHaveBeenCalled();
    expect(s.call).not.toHaveBeenCalled();
    expect(d.reload).toHaveBeenCalled();
  });
  it("RPC error → failed notice", async () => {
    const d = deps({ call: vi.fn(async () => ({ ok: false as const, reason: "error" as const })) });
    expect(await completeIconTimer("ic1", done, true, d)).toBe("failed");
    expect(d.notify).toHaveBeenCalledWith("ic1", ICON_TIMER_NOTICES.failed);
    expect(d.applyLocal).not.toHaveBeenCalled();
  });
  it("fetches days when missing locally", async () => {
    const d = deps({}, null);
    expect(await completeIconTimer("ic1", done, true, d)).toBe("honoured");
    expect(d.fetchDays).toHaveBeenCalled();
  });
  it("not an Icon → no RPC", async () => {
    const d = deps();
    expect(await completeIconTimer("c1", done, true, d)).toBe("not_icon");
    expect(d.call).not.toHaveBeenCalled();
  });
});

const USER = "user-icon-timer";
function seed(contracts: Contract[]) {
  window.localStorage.setItem(stateKeyForUser(USER), JSON.stringify({ contracts, journal: [] }));
  setStoreUser(null);
  setStoreUser(USER);
}

describe("store guard", () => {
  beforeEach(() => window.localStorage.clear());
  it("honourContract on an Icon returns false and changes nothing", () => {
    seed([icon()]);
    expect(honourContract("ic1")).toBe(false);
    expect(readStoreState().contracts[0].status).toBe("active");
  });
});

describe("Contract tab with a daily contract in force", () => {
  afterEach(() => setStoreUser(null));
  it("still lists active Icons", async () => {
    seed([ordinary({ id: "daily", deadline: Date.now() + 3_600_000 }), icon()]);
    const { ContractScreen } = await import("@/components/screens/Contract");
    const html = renderToStaticMarkup(createElement(ContractScreen, { onSigned: () => {} }));
    expect(html).toContain("Your contract is in force");
    expect(html).toContain('data-testid="active-icon"');
  }, 60_000);
});
