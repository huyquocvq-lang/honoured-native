import { beforeEach, describe, expect, it, vi } from "vitest";

const { completeIconTimer } = vi.hoisted(() => ({ completeIconTimer: vi.fn(async (..._a: unknown[]) => "honoured" as const) }));
vi.mock("@/lib/icon-timer", () => ({ completeIconTimer, setIconTimerNotice: () => {} }));

import { applyNativeTimerCompletion, syncNativeTimerState, testamentTimer } from "@/lib/timer-store";
import * as bridge from "@/lib/native-bridge";
import { readStoreState, setStoreUser, stateKeyForUser, type Contract } from "@/lib/store";

const USER = "user-ts";
const base = (id: string, icon: boolean): Contract => ({
  id,
  createdAt: Date.now(),
  deadline: Date.now() + 3_600_000,
  primaryType: "complete",
  primaryActivity: "Basketball",
  primaryTarget: "22 min",
  because: "x",
  locked: false,
  standing: false,
  status: "active",
  ...(icon
    ? {
        icon: {
          weekdays: ["tue"],
          startDay: "2026-10-06",
          period: { count: 1, unit: "month" },
          deadlineTime: "23:59",
          timezone: "UTC",
          morning: null,
          evening: null,
        },
      }
    : {}),
}) as Contract;

beforeEach(() => {
  completeIconTimer.mockClear();
  window.localStorage.clear();
  window.localStorage.setItem(
    stateKeyForUser(USER),
    JSON.stringify({ contracts: [base("ic1", true), base("c1", false)], journal: [] }),
  );
  setStoreUser(null);
  setStoreUser(USER);
});

describe("TIMER_COMPLETED routing", () => {
  it("an Icon goes to completeIconTimer and keeps its status", () => {
    const at = Date.now();
    expect(applyNativeTimerCompletion({ activityId: "ic1", completedAt: at, notified: false })).toBe(false);
    expect(completeIconTimer).toHaveBeenCalledWith("ic1", at, true, undefined, undefined);
    expect(readStoreState().contracts.find((c) => c.id === "ic1")?.status).toBe("active");
  });
  it("passes the stored iconDay", () => {
    testamentTimer.start("ic1", 60, "Basketball", "2026-10-06");
    const at = Date.now();
    applyNativeTimerCompletion({ activityId: "ic1", completedAt: at, notified: true });
    expect(completeIconTimer).toHaveBeenCalledWith("ic1", at, false, undefined, "2026-10-06");
    expect(testamentTimer.get()).toBeNull();
  });
  it("syncNativeTimerState keeps iconDay for the same contract", async () => {
    testamentTimer.start("ic1", 60, "Basketball", "2026-10-06");
    vi.spyOn(bridge, "hasNativeBridge").mockReturnValue(true);
    vi.spyOn(bridge, "getNativeTimerState").mockResolvedValue({ active: true, activityId: "ic1", endsAt: Date.now() + 50_000 } as never);
    await syncNativeTimerState(["ic1"]);
    expect(testamentTimer.get()?.iconDay).toBe("2026-10-06");
    vi.restoreAllMocks();
    testamentTimer.clear();
  });
  it("an ordinary contract is still honoured", () => {
    expect(applyNativeTimerCompletion({ activityId: "c1", completedAt: Date.now(), notified: true })).toBe(true);
    expect(completeIconTimer).not.toHaveBeenCalled();
    expect(readStoreState().contracts.find((c) => c.id === "c1")?.status).toBe("honoured");
  });
});
