// The Testament Timer for Icons Apple Health cannot measure. A finished timer
// stamps today's Icon day HONOURED through the self-report RPC; it never
// honours the Icon contract as a whole.
import { useEffect, useState } from "react";
import { parseTimerTarget } from "@/lib/home-dashboard";
import { playCompletionGong } from "@/lib/gong";
import {
  applyIconDayStatus,
  fetchIconDays,
  parseDay,
  readIconDays,
  reloadIconDays,
  selfReportIconDay,
  selfReportableDays,
  todayIconDay,
  type IconDay,
  type IconDaysByContract,
  type IconDayStatus,
  type SelfReportResult,
} from "@/lib/icon-days";
import { readStoreState, type AppState, type Contract } from "@/lib/store";
import type { TimerState } from "@/lib/timer-store";

function isUnmeasuredIcon(c: Contract | undefined): c is Contract {
  return !!c && !!c.icon && !c.icon.metric;
}

export function iconTimerSeconds(c: Contract): number | null {
  if (c.status !== "active" || !isUnmeasuredIcon(c) || c.primaryType !== "complete") return null;
  const s = parseTimerTarget(c.primaryTarget);
  return s !== null && s > 0 ? s : null;
}

export type IconTimerAvailability =
  | { kind: "none" }
  | { kind: "running" }
  | { kind: "busy" }
  | { kind: "too_late" }
  | { kind: "ready"; seconds: number; day: IconDay };

export function iconTimerAvailability(
  c: Contract,
  days: IconDay[] | undefined,
  nowMs: number,
  timer: TimerState | null,
): IconTimerAvailability {
  const seconds = iconTimerSeconds(c);
  if (seconds === null) return { kind: "none" };
  if (timer?.contractId === c.id) return { kind: "running" };
  const day = todayIconDay(days, nowMs);
  if (!day || day.status !== "pending" || day.deadlineMs < nowMs) return { kind: "none" };
  if (timer) return { kind: "busy" };
  if (nowMs + seconds * 1000 > day.deadlineMs) return { kind: "too_late" };
  return { kind: "ready", seconds, day };
}

/** The Icon day whose window (local start of day … cut-off) contains `atMs`. */
export function iconDayAt(days: readonly IconDay[] | undefined, atMs: number): IconDay | null {
  return (days ?? []).find((d) => parseDay(d.day).getTime() <= atMs && atMs <= d.deadlineMs) ?? null;
}

export type IconTimerOutcome = "honoured" | "failed" | "no_session" | "already_stamped" | "not_icon";

export const ICON_TIMER_NOTICES = {
  honoured: "Timer finished. Today's session is HONOURED.",
  failed: "Couldn't save the timer result. Tap Honoured to record it.",
  no_session: "The timer finished after the cut-off, so it doesn't count. Report the session below.",
} as const;

/* ------------------------------ notice store ----------------------------- */

const notices = new Map<string, string>();
const noticeListeners = new Set<() => void>();
function emitNotices() {
  for (const l of [...noticeListeners]) l();
}
export function setIconTimerNotice(clientId: string, text: string | null) {
  if (text) notices.set(clientId, text);
  else if (!notices.delete(clientId)) return;
  emitNotices();
}
export function readIconTimerNotice(clientId: string): string | null {
  return notices.get(clientId) ?? null;
}
export function useIconTimerNotice(clientId: string): string | null {
  const [n, setN] = useState<string | null>(() => readIconTimerNotice(clientId));
  useEffect(() => {
    const l = () => setN(readIconTimerNotice(clientId));
    l();
    noticeListeners.add(l);
    return () => {
      noticeListeners.delete(l);
    };
  }, [clientId]);
  return n;
}

/* ------------------------------- completion ------------------------------ */

export interface IconTimerDeps {
  readState: () => AppState;
  readDays: () => IconDaysByContract;
  fetchDays: () => Promise<IconDaysByContract>;
  call: (contractUuid: string, day: string, honoured: boolean) => Promise<SelfReportResult>;
  applyLocal: (day: IconDay, status: IconDayStatus) => void;
  reload: () => Promise<unknown> | unknown;
  gong: (enabled: boolean) => unknown;
  notify: (clientId: string, text: string | null) => void;
}

const defaults: IconTimerDeps = {
  readState: readStoreState,
  readDays: readIconDays,
  fetchDays: fetchIconDays,
  call: selfReportIconDay,
  applyLocal: applyIconDayStatus,
  reload: reloadIconDays,
  gong: playCompletionGong,
  notify: setIconTimerNotice,
};

export async function completeIconTimer(
  clientId: string,
  completedAtMs: number,
  celebrate: boolean,
  deps: IconTimerDeps = defaults,
  startedFor?: string,
): Promise<IconTimerOutcome> {
  const c = deps.readState().contracts.find((x) => x.id === clientId);
  if (!isUnmeasuredIcon(c)) return "not_icon";
  let days: IconDay[] | undefined = deps.readDays()[clientId];
  if (!days) {
    try {
      days = (await deps.fetchDays())[clientId];
    } catch {
      days = undefined;
    }
  }
  let outcome: IconTimerOutcome;
  const day = iconDayAt(days, completedAtMs);
  if (!day || (startedFor && day.day !== startedFor)) outcome = "no_session";
  else if (day.status !== "pending") outcome = "already_stamped";
  else {
    let res: SelfReportResult;
    try {
      res = await deps.call(day.contractUuid, day.day, true);
    } catch {
      res = { ok: false, reason: "error" };
    }
    if (res.ok) {
      deps.applyLocal(day, res.status);
      if (celebrate) deps.gong(deps.readState().completionSound);
      outcome = "honoured";
    } else outcome = "failed";
  }
  await deps.reload();
  if (outcome === "honoured" || outcome === "failed") deps.notify(clientId, ICON_TIMER_NOTICES[outcome]);
  else if (outcome === "no_session" && selfReportableDays(c, days, Date.now()).length > 0) {
    deps.notify(clientId, ICON_TIMER_NOTICES.no_session);
  }
  return outcome;
}
