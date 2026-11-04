import { useMemo, useState } from "react";
import { useStore } from "@/lib/store";
import { iconMeasuredText, useIconDays } from "@/lib/icon-days";
import {
  historyEntries,
  monthTotals,
  statusByDay,
  type HistoryEntry,
  type HistoryStatus,
} from "@/lib/history-entries";
import { refreshTopics } from "@/lib/screen-refresh";
import { PullToRefresh } from "@/components/PullToRefresh";

type Filter = "all" | "honoured" | "broken" | "amended";
type DayStatus = HistoryStatus;

const MONTHS = [
  "January", "February", "March", "April", "May", "June",
  "July", "August", "September", "October", "November", "December",
];
const DOW = ["M", "T", "W", "T", "F", "S", "S"];

/** What decided an Icon day: the Health reading, or how it was stamped. */
function iconDayResult(e: HistoryEntry): string {
  const d = e.iconDay;
  if (!d) return "—";
  if (d.measuredValue !== null && e.contract.icon?.metric) return iconMeasuredText(e.contract, d.measuredValue);
  if (d.resolution === "self_reported") return "Self-reported";
  if (d.resolution === "no_data") return "No Health data";
  return "—";
}

export function HistoryScreen() {
  const [state] = useStore();
  const iconDays = useIconDays();
  // Resolved contracts and every stamped Icon day, newest first.
  const entries = useMemo(() => historyEntries(state.contracts, iconDays), [state.contracts, iconDays]);
  const [filter, setFilter] = useState<Filter>("all");
  const [selectedDay, setSelectedDay] = useState<string | null>(null);
  const [selectedEntryId, setSelectedEntryId] = useState<string | null>(null);
  const [monthPickerOpen, setMonthPickerOpen] = useState(false);
  const selectedEntry = entries.find((e) => e.id === selectedEntryId) ?? null;
  const selectedEntryDayKey = selectedEntry?.dayKey ?? null;
  const activeDayKey = selectedEntryDayKey ?? selectedDay;
  const selectedStatus: DayStatus | null = selectedEntry?.status ?? null;
  const [cursor, setCursor] = useState(() => {
    const d = new Date();
    d.setDate(1);
    d.setHours(0, 0, 0, 0);
    return d;
  });

  // Map of yyyy-m-d → the colour of that date's newest entry.
  const byDay = statusByDay(entries);

  const year = cursor.getFullYear();
  const month = cursor.getMonth();
  const first = new Date(year, month, 1);
  // Monday = 0 … Sunday = 6
  const startOffset = (first.getDay() + 6) % 7;
  const daysInMonth = new Date(year, month + 1, 0).getDate();

  const cells: { date?: Date; status?: DayStatus }[] = [];
  for (let i = 0; i < startOffset; i++) cells.push({});
  for (let d = 1; d <= daysInMonth; d++) {
    const date = new Date(year, month, d);
    const key = `${year}-${month}-${d}`;
    cells.push({ date, status: byDay.get(key) });
  }
  while (cells.length % 7 !== 0) cells.push({});

  const totals = monthTotals(entries, year, month);
  const monthIsEmpty = totals.total === 0;

  const showStatus = (s?: DayStatus) => {
    if (!s) return undefined;
    if (filter === "all") return s;
    return s === filter ? s : undefined;
  };

  const resolvedList = entries
    .filter((e) => (filter === "all" ? true : e.status === filter))
    .filter((e) => !activeDayKey || e.dayKey === activeDayKey);

  const prevMonth = () => { setSelectedDay(null); setSelectedEntryId(null); setMonthPickerOpen(false); setCursor(new Date(year, month - 1, 1)); };
  const nextMonth = () => { setSelectedDay(null); setSelectedEntryId(null); setMonthPickerOpen(false); setCursor(new Date(year, month + 1, 1)); };
  const pickMonth = (m: number) => { setSelectedDay(null); setSelectedEntryId(null); setMonthPickerOpen(false); setCursor(new Date(year, m, 1)); };

  return (
    <PullToRefresh className="flex-1 overflow-y-auto px-6 py-6 pb-24 bg-black text-neutral-100" onRefresh={() => refreshTopics(["contracts"])} label="Refresh History">
      <h2 className="serif text-3xl">History</h2>
      <p className="text-xs text-neutral-400 mt-1">
        Your record. Your truth.
      </p>

      <div className="mt-4 flex gap-1.5">
        {(["all", "honoured", "broken", "amended"] as Filter[]).map((f) => (
          <button
            key={f}
            onClick={() => setFilter(f)}
            className={
              "px-3 py-1.5 rounded-full text-[11px] tracking-widest uppercase border " +
              (filter === f
                ? "border-neutral-100 bg-neutral-100 text-black"
                : "border-neutral-700 text-neutral-300")
            }
          >
            {f}
          </button>
        ))}
      </div>

      <div className="mt-6 flex items-center justify-between">
        <button
          onClick={prevMonth}
          className="text-neutral-400 text-lg px-2"
          aria-label="Previous month"
        >
          ‹
        </button>
        <button
          onClick={() => setMonthPickerOpen((o) => !o)}
          className="serif text-lg underline decoration-neutral-700 underline-offset-4"
          aria-haspopup="true"
          aria-expanded={monthPickerOpen}
        >
          {MONTHS[month]} {year}
        </button>
        <button
          onClick={nextMonth}
          className="text-neutral-400 text-lg px-2"
          aria-label="Next month"
        >
          ›
        </button>
      </div>

      {monthPickerOpen && (
        <div className="mt-3 grid grid-cols-3 gap-1.5 rounded-lg border border-neutral-800 bg-neutral-900 p-2">
          {MONTHS.map((m, i) => (
            <button
              key={m}
              onClick={() => pickMonth(i)}
              className={
                "py-2 rounded-md text-[11px] tracking-widest uppercase border " +
                (i === month
                  ? "border-neutral-100 bg-neutral-100 text-black"
                  : "border-neutral-800 text-neutral-300")
              }
            >
              {m.slice(0, 3)}
            </button>
          ))}
        </div>
      )}


      <div className="mt-3 grid grid-cols-7 gap-1.5 text-center">
        {DOW.map((d, i) => (
          <div key={i} className="text-[10px] tracking-widest text-neutral-500">
            {d}
          </div>
        ))}
        {cells.map((cell, idx) => {
          const s = showStatus(cell.status);
          const base =
            "aspect-square rounded-md flex items-center justify-center text-[11px] ";
          if (!cell.date) return <div key={idx} className={base} />;
          const key = `${year}-${month}-${cell.date.getDate()}`;
          const isSelected = activeDayKey === key;
          const cls =
            s === "honoured"
              ? "bg-emerald-500/90 text-black font-medium"
              : s === "broken"
                ? "bg-red-500/90 text-white font-medium"
                : s === "amended"
                  ? "bg-amber-400/90 text-black font-medium"
                  : "bg-neutral-900 text-neutral-500 border border-neutral-800";
          const ringStatus: DayStatus | undefined =
            isSelected && selectedEntryDayKey === key && selectedStatus
              ? selectedStatus
              : cell.status;
          const ringColor =
            ringStatus === "honoured"
              ? "ring-emerald-400"
              : ringStatus === "broken"
                ? "ring-red-400"
                : ringStatus === "amended"
                  ? "ring-amber-300"
                  : "ring-neutral-100";
          const ring = isSelected ? ` ring-2 ring-offset-2 ring-offset-black ${ringColor}` : "";
          return (
            <button
              key={idx}
              onClick={() => {
                setSelectedEntryId(null);
                setSelectedDay(selectedDay === key ? null : key);
              }}
              className={base + cls + ring}
            >
              {cell.date.getDate()}
            </button>
          );
        })}
      </div>

      <div className="mt-5 flex items-center justify-center gap-5 text-[10px] tracking-widest uppercase text-neutral-400">
        <span className="flex items-center gap-1.5">
          <span className="w-2 h-2 rounded-full bg-emerald-500" /> Honoured
        </span>
        <span className="flex items-center gap-1.5">
          <span className="w-2 h-2 rounded-full bg-red-500" /> Broken
        </span>
        <span className="flex items-center gap-1.5">
          <span className="w-2 h-2 rounded-full bg-amber-400" /> Amended
        </span>
      </div>

      <p className="mt-4 text-center serif text-lg">
        {monthIsEmpty
          ? "Nothing recorded this month."
          : `${totals.honoured} honoured. ${totals.broken} broken. ${totals.amended} amended.`}
      </p>

      {activeDayKey && (() => {
        const dayEntry = selectedEntry ?? entries.find((e) => e.dayKey === activeDayKey);
        const dayContract = dayEntry?.contract;
        const [y, m, dd] = activeDayKey.split("-").map(Number);
        const dayLabel = new Date(y, m, dd).toLocaleDateString();
        const status = (dayEntry?.status ?? byDay.get(activeDayKey)) as DayStatus | undefined;
        const fmt = (secs: number) => {
          const h = Math.floor(secs / 3600);
          const min = Math.round((secs % 3600) / 60);
          return h > 0 ? `${h}h ${min}m` : `${min}m`;
        };
        const taken =
          dayContract?.resolvedAt && dayContract.createdAt
            ? fmt(Math.max(0, Math.round((dayContract.resolvedAt - dayContract.createdAt) / 1000)))
            : "—";
        const badge =
          status === "honoured"
            ? "bg-emerald-500/20 text-emerald-300"
            : status === "amended"
              ? "bg-amber-400/20 text-amber-300"
              : "bg-red-500/20 text-red-300";
        const closeDetail = () => { setSelectedDay(null); setSelectedEntryId(null); };
        return (
          <>
          <div
            className="fixed inset-0 z-30"
            onClick={closeDetail}
            aria-hidden
          />
          <div
            className="mt-4 rounded-lg border border-neutral-800 bg-neutral-900 p-4 relative z-40 cursor-pointer"
            onClick={closeDetail}
          >
            <button
              onClick={(e) => { e.stopPropagation(); closeDetail(); }}
              aria-label="Close details"
              className="absolute top-2 right-3 text-neutral-500 text-sm"
            >
              ×
            </button>

            <p className="text-[10px] tracking-widest uppercase text-neutral-500">{dayLabel}</p>
            {dayEntry && dayContract ? (
              <>
                <p className="serif text-lg mt-0.5">{dayContract.primaryActivity}</p>
                <div className="mt-2 grid grid-cols-2 gap-2 text-xs">
                  <div>
                    <p className="text-[10px] tracking-widest uppercase text-neutral-500">Target</p>
                    <p className="text-neutral-200">{dayContract.primaryTarget || "—"}</p>
                  </div>
                  {dayEntry.iconDay ? (
                    <div>
                      <p className="text-[10px] tracking-widest uppercase text-neutral-500">Session</p>
                      <p className="text-neutral-200">
                        {dayEntry.iconDay.session} of {dayEntry.iconDay.total}
                      </p>
                    </div>
                  ) : dayContract.icon ? (
                    <div>
                      <p className="text-[10px] tracking-widest uppercase text-neutral-500">Sessions</p>
                      <p className="text-neutral-200">{dayEntry.sessions ?? "—"}</p>
                    </div>
                  ) : (
                    <div>
                      <p className="text-[10px] tracking-widest uppercase text-neutral-500">Time taken</p>
                      <p className="text-neutral-200">{taken}</p>
                    </div>
                  )}
                </div>
                {dayEntry.iconDay && (
                  <div className="mt-2 text-xs">
                    <p className="text-[10px] tracking-widest uppercase text-neutral-500">Result</p>
                    <p className="text-neutral-200">{iconDayResult(dayEntry)}</p>
                  </div>
                )}
                {dayContract.because && (
                  <p className="text-xs italic text-neutral-400 mt-2">{dayContract.because}</p>
                )}
              </>
            ) : (
              <p className="serif text-base mt-0.5 text-neutral-400">
                {status ? "No contract details recorded." : "Nothing recorded on this day."}
              </p>
            )}
            {status && (
              <span className={"inline-block mt-3 text-[10px] tracking-widest px-2 py-1 rounded-full " + badge}>
                {status.toUpperCase()}
              </span>
            )}
          </div>
          </>
        );

      })()}


      <div className="mt-6 space-y-2">
        {resolvedList.map((entry) => {
          const c = entry.contract;
          const d = entry.date;
          const isSelected = selectedEntryId === entry.id;
          const sameMonth = d.getFullYear() === year && d.getMonth() === month;
          return (
            <button
              key={entry.id}
              onClick={() => {
                if (isSelected) {
                  setSelectedEntryId(null);
                  return;
                }
                if (!sameMonth) {
                  setCursor(new Date(d.getFullYear(), d.getMonth(), 1));
                }
                setSelectedDay(entry.dayKey);
                setSelectedEntryId(entry.id);
              }}
              className={
                "w-full text-left rounded-lg border bg-neutral-900 p-3 flex items-center justify-between transition-colors " +
                (isSelected
                  ? "border-neutral-100"
                  : "border-neutral-800")
              }
            >
              <div>
                <p className="text-[10px] tracking-widest uppercase text-neutral-500">
                  {d.toLocaleDateString()}
                </p>
                <p className="serif text-base">{c.primaryActivity}</p>
                {entry.iconDay && (
                  <p className="text-[10px] tracking-widest uppercase" style={{ color: "var(--color-gold)" }}>
                    Icon · Session {entry.iconDay.session} of {entry.iconDay.total}
                  </p>
                )}
                {c.because && (
                  <p className="text-xs italic text-neutral-400 mt-0.5">{c.because}</p>
                )}
                {c.voiceOfChangeId && (
                  <p className="text-[10px] text-neutral-500">🎙 Voice of Change attached</p>
                )}
              </div>
              <span
                className={
                  "text-[10px] tracking-widest px-2 py-1 rounded-full " +
                  (entry.status === "honoured"
                    ? "bg-emerald-500/20 text-emerald-300"
                    : entry.status === "amended"
                      ? "bg-amber-400/20 text-amber-300"
                      : "bg-red-500/20 text-red-300")
                }
              >
                {entry.status.toUpperCase()}
              </span>
            </button>
          );
        })}
      </div>
    </PullToRefresh>
  );
}
