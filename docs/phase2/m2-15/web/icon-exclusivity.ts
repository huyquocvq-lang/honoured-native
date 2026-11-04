// Icon day exclusivity (V1.2 M2-15): on a day an active Icon holds, only that
// Icon. Same rules as the database trigger contracts_icon_reserve, checked
// before signing so the person keeps their draft and signature:
//   - every scheduled day of an active Icon is held, the whole local calendar
//     day, stamped or not; an Icon that ended early releases its days;
//   - a contract cannot be signed if the time from signing to its deadline
//     touches a held day (a legacy Standing contract runs on with no end);
//   - an Icon cannot be signed if one of its days is held by another active
//     Icon, nor while an active ordinary contract covers one of its days (an
//     active Standing contract covers every day).
import { iconSchedule, type IconTerms } from "@/lib/icon";
import type { Contract } from "@/lib/store";

export const ICON_DAY_TAKEN = "Icon already set for this day. Finish your Icon first.";
export const CONTRACT_DAY_TAKEN = "Contract already set for this day. Finish your contract first.";

export type DayConflict = "icon" | "contract";

/** What signing would claim. */
export interface SigningCandidate {
  createdAt: number;
  deadline: number;
  standing: boolean;
  icon?: IconTerms;
}

type Range = readonly [start: number, end: number];

/** Each scheduled day of an Icon as the whole local calendar day, [00:00, 24:00). */
export function iconDayRanges(icon: IconTerms, signedAt: number): Range[] {
  return iconSchedule(icon, signedAt).map((d) => {
    const [y, m, day] = d.day.split("-").map(Number);
    return [new Date(y, m - 1, day).getTime(), new Date(y, m - 1, day + 1).getTime()] as const;
  });
}

function overlaps(a: Range, b: Range): boolean {
  return a[0] < b[1] && a[1] > b[0];
}

/** Null when signing is allowed; otherwise the rule that refuses it. */
export function dayConflict(candidate: SigningCandidate, contracts: readonly Contract[]): DayConflict | null {
  const active = contracts.filter((c) => c.status === "active");
  const held = active.flatMap((c) => (c.icon ? iconDayRanges(c.icon, c.createdAt) : []));
  if (!candidate.icon) {
    const span: Range = [candidate.createdAt, candidate.standing ? Infinity : candidate.deadline];
    return held.some((r) => overlaps(span, r)) ? "icon" : null;
  }
  const days = iconDayRanges(candidate.icon, candidate.createdAt);
  if (days.some((d) => held.some((r) => overlaps(d, r)))) return "icon";
  const covered = active.some(
    (c) => !c.icon && (c.standing || days.some((d) => overlaps(d, [c.createdAt, c.deadline]))),
  );
  return covered ? "contract" : null;
}

export function dayConflictMessage(conflict: DayConflict): string {
  return conflict === "icon" ? ICON_DAY_TAKEN : CONTRACT_DAY_TAKEN;
}

/** The database's refusal of a new contract row, read from the error's DETAIL. */
export function dayReservedRefusal(error: { details?: string | null } | null | undefined): DayConflict | null {
  if (error?.details === "icon_day_reserved") return "icon";
  if (error?.details === "contract_day_reserved") return "contract";
  return null;
}

type UpsertError = { message: string; details?: string | null };

/**
 * Upserts contract rows. When the database refuses some of them for Icon day
 * exclusivity, the rows are sent again one at a time, so one refusal never
 * holds back the others. Returns the refused client ids, and the first error
 * of any other kind.
 */
export async function upsertContractRows<R extends { client_id: string }>(
  upsert: (rows: R[]) => PromiseLike<{ error: UpsertError | null }>,
  rows: R[],
): Promise<{ error: UpsertError | null; refused: { clientId: string; conflict: DayConflict }[] }> {
  const batch = await upsert(rows);
  if (!batch.error) return { error: null, refused: [] };
  if (!dayReservedRefusal(batch.error)) return { error: batch.error, refused: [] };
  const refused: { clientId: string; conflict: DayConflict }[] = [];
  let error: UpsertError | null = null;
  for (const row of rows) {
    const single = await upsert([row]);
    const conflict = dayReservedRefusal(single.error);
    if (conflict) refused.push({ clientId: row.client_id, conflict });
    else if (single.error && !error) error = single.error;
  }
  return { error, refused };
}
