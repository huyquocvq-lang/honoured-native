"""Builds docs/phase2/Honoured-V1.2-M2-Test-Cases.xlsx and the evidence SQL file."""
import math
import re
import sys

from openpyxl import Workbook
from openpyxl.formatting.rule import FormulaRule
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
from openpyxl.utils import get_column_letter
from openpyxl.worksheet.datavalidation import DataValidation
from openpyxl.worksheet.table import Table, TableStyleInfo

sys.path.insert(0, sys.argv[1])
from m2_tests_data import CASES  # noqa: E402
from m2_tests_extra import (  # noqa: E402
    ACCOUNTS, AUTOMATED, BUILDS, DEFECTS, ICONS, RUN_PLAN, SESSION_COUNTS, TASKS, TRACE, WORDING,
)
from m2_tests_queries import QUERIES  # noqa: E402

OUT = sys.argv[2]
SQL_OUT = sys.argv[3]

NAVY, INK, GREY, CREAM = "1F3A5F", "1F2937", "667085", "F6EEDC"
FONT = "Carlito"
f_title = Font(name=FONT, size=14, bold=True, color=NAVY)
f_sub = Font(name=FONT, size=11, color=GREY)
f_head = Font(name=FONT, size=11, bold=True, color="FFFFFF")
f_body = Font(name=FONT, size=11, color=INK)
f_bold = Font(name=FONT, size=11, bold=True, color=INK)
f_band = Font(name=FONT, size=11, bold=True, color=NAVY)
f_mono = Font(name="Courier New", size=10, color=INK)
fill_head = PatternFill("solid", fgColor=NAVY)
fill_band = PatternFill("solid", fgColor=CREAM)
thin = Side(style="thin", color="D0D5DD")
border = Border(left=thin, right=thin, top=thin, bottom=thin)
top_wrap = Alignment(wrap_text=True, vertical="top")
center = Alignment(wrap_text=True, vertical="center")

STATUSES = ["Not run", "Pass", "Fail", "Blocked", "N/A"]


def lines_needed(text, width):
    if text is None:
        return 1
    chars = max(8, int(width * 1.15))
    return sum(max(1, math.ceil(len(part) / chars)) for part in str(text).split("\n"))


def fit_row(ws, row, widths, cols, base=15.0, cap=409):
    n = max(lines_needed(ws.cell(row, c).value, widths[c - 1]) for c in cols)
    ws.row_dimensions[row].height = min(cap, max(base, 14.5 * n + 4))


def header(ws, row, names, widths):
    for i, (name, w) in enumerate(zip(names, widths), start=1):
        c = ws.cell(row, i, name)
        c.font, c.fill, c.alignment, c.border = f_head, fill_head, center, border
        ws.column_dimensions[get_column_letter(i)].width = w
    ws.row_dimensions[row].height = 32


def title(ws, text, sub):
    ws["A1"] = text
    ws["A1"].font = f_title
    ws["A2"] = sub
    ws["A2"].font = f_sub
    ws.sheet_view.showGridLines = False


def body_cell(ws, row, col, value, font=f_body, align=top_wrap):
    c = ws.cell(row, col, value)
    c.font, c.alignment, c.border = font, align, border
    return c


def add_table(ws, name, ref):
    t = Table(displayName=name, ref=ref)
    t.tableStyleInfo = TableStyleInfo(name="TableStyleMedium2", showRowStripes=True, showColumnStripes=False)
    ws.add_table(t)


def band(ws, row, text, ncols):
    for c in range(1, ncols + 1):
        cell = ws.cell(row, c)
        cell.fill = fill_band
        cell.border = border
    ws.cell(row, 1, text).font = f_band


wb = Workbook()

# ---------------------------------------------------------------- Overview
ov = wb.active
ov.title = "Overview"
title(ov, "Honoured V1.2 — Milestone 2 (Icon) Test Cases",
      "Prepared Oct 4, 2026 from scope v6, the client's decisions (Sep 28, Oct 1, Oct 3, Oct 4), the tracker and the current code.")
ov.column_dimensions["A"].width = 26
ov.column_dimensions["B"].width = 70
ov.column_dimensions["C"].width = 16
ov.column_dimensions["D"].width = 16
r = 4
band(ov, r, "PURPOSE", 4)
r += 1
purpose = [
    ("What this is", "Every feature of Milestone 2 written as test cases with steps, expected results and the evidence to keep, so a pass can be shown to the client."),
    ("Covers", "M2-01 to M2-15: the Icon row and sheet, signing and lock-in, scoring, push tokens and the push schedule, the Icon card and its fallback, recaps, the end of an Icon, Go again, Icon-day exclusivity and device QA."),
    ("Already proven automatically", "Logic, database rules and renders are covered by automated runs (sheet 'Automated Evidence'); the cases here are what still needs a person, an iPhone and real time."),
    ("Language of results", "Expected results quote the app's exact words. Capitalised words such as SET THE ICON, HONOURED or GO AGAIN appear in capitals on screen."),
]
for k, v in purpose:
    body_cell(ov, r, 1, k, f_bold)
    body_cell(ov, r, 2, v)
    ov.merge_cells(start_row=r, start_column=2, end_row=r, end_column=4)
    fit_row(ov, r, [26, 102, 16, 16], [1, 2])
    r += 1

r += 1
band(ov, r, "BUILDS UNDER TEST", 4)
r += 1
for k, v in BUILDS:
    body_cell(ov, r, 1, k, f_bold)
    body_cell(ov, r, 2, v)
    ov.merge_cells(start_row=r, start_column=2, end_row=r, end_column=4)
    fit_row(ov, r, [26, 102, 16, 16], [1, 2])
    r += 1

r += 1
band(ov, r, "HOW TO RECORD", 4)
r += 1
howto = [
    ("Status", "Not run, Pass, Fail, Blocked (cannot run: say why), N/A (does not apply: say why). Every Fail gets a row in 'Defects' and its ID in the test case."),
    ("Evidence folder", "docs/phase2/evidence/m2-qa/<TC-ID>/ — one folder per test case. Automated evidence is in docs/phase2/evidence/m2-qa/automated/."),
    ("File names", "<TC-ID>_<nn>_<what>.<ext>, e.g. M2-07-TC01_01_lockscreen.png, M2-07-TC01_02_Q-04.txt. List the files in the 'Evidence files' column."),
    ("Evidence types", "SCR app screenshot · LS Lock Screen screenshot (side + volume up while locked) · DI Dynamic Island screenshot · REC screen recording (Control Centre) · DB query output (sheet 'Evidence Queries', saved as .txt) · LOG Xcode console extract · WEB desktop browser screenshot."),
    ("Time on screen", "For anything time-based (reminders, cut-offs, 24-hour rule) the clock must be visible in the screenshot, and DB outputs keep their timestamps."),
    ("Database evidence", "Run the queries with the Lovable query_database tool (Supabase MCP cannot see this project). They are read-only or rolled back, and never show token values. The same SQL is in docs/phase2/evidence/m2-qa/m2-evidence-queries.sql."),
    ("Privacy", "Use test accounts only. Do not paste tokens, the installation id or session values into evidence or chat."),
]
for k, v in howto:
    body_cell(ov, r, 1, k, f_bold)
    body_cell(ov, r, 2, v)
    ov.merge_cells(start_row=r, start_column=2, end_row=r, end_column=4)
    fit_row(ov, r, [26, 102, 16, 16], [1, 2])
    r += 1

r += 1
band(ov, r, "KNOWN LIMITS BEFORE TESTING", 4)
r += 1
limits = [
    ("DEF-01 (suspected)", "With a daily contract in force, the Contract tab hides the Active Icons list (End early, self-report). M2-04-TC15 checks it; expected to fail until fixed."),
    ("O-11", "Production App IDs still need Push Notifications and the App Group: the production APNs gateway and the signature on a production build cannot be tested yet (M2-07-TC09)."),
    ("O-05", "Results are final as implemented; the client has not confirmed it yet (M2-05-TC07)."),
    ("O-10", "App build 1.0.4 cannot read Icon days; measured days end BROKEN (no_data). Test with the new build only (M2-14-TC10)."),
    ("Push tokens", "On Oct 4 production had no push tokens; open the app signed in before the first push case (M2-06-TC01)."),
    ("Monthly recap", "First naturally visible on 1–2 Nov 2026 (October). Rules are unit-tested (AE-15)."),
    ("iOS below 17.2", "Needs a second device (M2-09-TC09); otherwise covered by the server plan tests (AE-16)."),
]
for k, v in limits:
    body_cell(ov, r, 1, k, f_bold)
    body_cell(ov, r, 2, v)
    ov.merge_cells(start_row=r, start_column=2, end_row=r, end_column=4)
    fit_row(ov, r, [26, 102, 16, 16], [1, 2])
    r += 1

r += 1
band(ov, r, "SCOPE (TRACKER TASKS)", 4)
r += 1
for i, name in enumerate(["Task", "Title", "Tracker status", "Test cases"], start=1):
    c = ov.cell(r, i, name)
    c.font, c.fill, c.alignment, c.border = f_head, fill_head, center, border
r += 1
for tid, ttitle, tstatus in TASKS:
    body_cell(ov, r, 1, tid, f_bold)
    body_cell(ov, r, 2, ttitle)
    body_cell(ov, r, 3, tstatus)
    body_cell(ov, r, 4, sum(1 for c in CASES if c["task"] == tid), align=Alignment(vertical="top", horizontal="center"))
    r += 1
body_cell(ov, r, 1, "End to end", f_bold)
body_cell(ov, r, 2, "Scenario cases spanning several tasks (M2-E2E-01, M2-E2E-02)")
body_cell(ov, r, 3, "—")
body_cell(ov, r, 4, sum(1 for c in CASES if c["area"] == "End to end"), align=Alignment(vertical="top", horizontal="center"))
r += 2

band(ov, r, "SIGN-OFF", 4)
r += 1
for i, name in enumerate(["Role", "Name", "Date", "Result"], start=1):
    c = ov.cell(r, i, name)
    c.font, c.fill, c.alignment, c.border = f_head, fill_head, center, border
r += 1
for role in ["Tester (developer)", "Reviewer (client)"]:
    body_cell(ov, r, 1, role, f_bold)
    for col in (2, 3, 4):
        body_cell(ov, r, col, None)
    ov.row_dimensions[r].height = 24
    r += 1

# ------------------------------------------------------------- Test Cases
tc_ws = wb.create_sheet("Test Cases")
title(tc_ws, "Test Cases", "One row per case. Fill Status, Date run, Build / device, Evidence files and Actual result. Filter by Task, Priority or Status.")
cols = ["ID", "Task", "Area", "Title", "Priority", "Type", "Platform", "Source / requirement", "Preconditions",
        "Steps", "Expected result", "Evidence to capture", "Plan notes", "Run block", "Status", "Date run",
        "Build / device", "Evidence files", "Actual result", "Defect ID"]
widths = [13, 10, 14, 32, 9, 12, 15, 30, 34, 50, 58, 34, 34, 10, 11, 12, 16, 28, 34, 11]
header(tc_ws, 5, cols, widths)


def expand(text):
    out = set()
    for m in re.finditer(r'(M2-(?:\d\d|E2E))-TC(\d\d)(?:\.\.TC(\d\d)| to TC(\d\d))?', text):
        base, a, b1, b2 = m.group(1), int(m.group(2)), m.group(3), m.group(4)
        for i in range(a, int(b1 or b2 or a) + 1):
            out.add(f"{base}-TC{i:02d}")
    for m in re.finditer(r'M2-E2E-\d\d', text):
        out.add(m.group(0))
    return out


block_of = {}
for rp in RUN_PLAN:
    for t in expand(rp[2] + " " + rp[3] + " " + rp[4]):
        block_of.setdefault(t, rp[0])

row = 6
for c in CASES:
    values = [c["id"], c["task"], c["area"], c["title"], c["priority"], c["type"], c["platform"], c["source"],
              c["pre"], c["steps"], c["expected"], c["evidence"], c["note"] or None, block_of.get(c["id"]),
              "Not run", None, None, None, None, None]
    for i, v in enumerate(values, start=1):
        font = f_bold if i in (1, 4) else f_body
        body_cell(tc_ws, row, i, v, font)
    fit_row(tc_ws, row, widths, [4, 8, 9, 10, 11, 12, 13])
    row += 1
last_tc = row - 1
add_table(tc_ws, "M2TestCases", f"A5:T{last_tc}")
tc_ws.freeze_panes = "E6"
dv = DataValidation(type="list", formula1='"' + ",".join(STATUSES) + '"', allow_blank=True)
dv.add(f"O6:O{last_tc}")
tc_ws.add_data_validation(dv)
pri = DataValidation(type="list", formula1='"P1,P2,P3"', allow_blank=False)
pri.add(f"E6:E{last_tc}")
tc_ws.add_data_validation(pri)
status_styles = {
    "Pass": ("C6EFCE", "006100"), "Fail": ("FFC7CE", "9C0006"),
    "Blocked": ("FFEB9C", "9C6500"), "N/A": ("EDEDED", "4B5563"),
}
for status, (bg, fg) in status_styles.items():
    tc_ws.conditional_formatting.add(
        f"O6:O{last_tc}",
        FormulaRule(formula=[f'$O6="{status}"'], fill=PatternFill("solid", fgColor=bg), font=Font(name=FONT, color=fg, bold=True)),
    )
tc_ws.conditional_formatting.add(
    f"E6:E{last_tc}", FormulaRule(formula=['$E6="P1"'], font=Font(name=FONT, color="9C0006", bold=True)))

# ---------------------------------------------------------------- Run Plan
rp_ws = wb.create_sheet("Run Plan")
title(rp_ws, "Run Plan", "A suggested order. Reminders and cut-offs happen at fixed times, and an Icon holds its days, so the order matters. Start Day 1 on a Friday.")
rp_cols = ["Block", "When", "Setup", "Test cases", "Notes"]
rp_w = [8, 26, 52, 70, 46]
header(rp_ws, 5, rp_cols, rp_w)
row = 6
for item in RUN_PLAN:
    for i, v in enumerate(item, start=1):
        body_cell(rp_ws, row, i, v or None, f_bold if i == 1 else f_body)
    fit_row(rp_ws, row, rp_w, [2, 3, 4, 5])
    row += 1
add_table(rp_ws, "M2RunPlan", f"A5:E{row - 1}")
rp_ws.freeze_panes = "B6"

# --------------------------------------------------------------- Test Data
td = wb.create_sheet("Test Data")
title(td, "Test Data", "Accounts, devices, the Icons to create, expected session counts and the approved wording.")
td_w = [18, 52, 70, 26, 14, 14, 14]
for i, w in enumerate(td_w, start=1):
    td.column_dimensions[get_column_letter(i)].width = w
r = 4
band(td, r, "ACCOUNTS AND DEVICES", 4)
r += 1
for i, name in enumerate(["ID", "What", "Used for"], start=1):
    c = td.cell(r, i, name)
    c.font, c.fill, c.alignment, c.border = f_head, fill_head, center, border
r += 1
for a in ACCOUNTS:
    for i, v in enumerate(a, start=1):
        body_cell(td, r, i, v, f_bold if i == 1 else f_body)
    fit_row(td, r, td_w, [2, 3])
    r += 1
r += 1
band(td, r, "ICONS TO CREATE", 4)
r += 1
for i, name in enumerate(["ID", "Activity · target", "Terms", "Used by"], start=1):
    c = td.cell(r, i, name)
    c.font, c.fill, c.alignment, c.border = f_head, fill_head, center, border
r += 1
for a in ICONS:
    for i, v in enumerate(a, start=1):
        body_cell(td, r, i, v, f_bold if i == 1 else f_body)
    fit_row(td, r, td_w, [2, 3, 4])
    r += 1
r += 1
band(td, r, "EXPECTED SESSION COUNT IN THE SHEET (by signing date)", 7)
r += 1
sc_head = ["Date", "Weekday", "Tue·Thu·Sat·Sun | 1 Month", "Every day | 1 Week", "Mon·Wed·Fri | 3 Months",
           "Every day | Custom 2 days", "Sat·Sun | 1 Year"]
for i, name in enumerate(sc_head, start=1):
    c = td.cell(r, i, name)
    c.font, c.fill, c.alignment, c.border = f_head, fill_head, center, border
td.row_dimensions[r].height = 32
r += 1
for a in SESSION_COUNTS:
    for i, v in enumerate(a, start=1):
        body_cell(td, r, i, v, f_bold if i == 1 else f_body, Alignment(vertical="top", horizontal="center" if i > 2 else "left"))
    r += 1
body_cell(td, r, 1, "Rule", f_bold)
body_cell(td, r, 2, "Selected weekdays from the signing day (inclusive) to the same date one period later (exclusive). Custom maximum: 365 days for a start in Oct 2026 (366 when the year ahead contains 29 Feb).")
td.merge_cells(start_row=r, start_column=2, end_row=r, end_column=7)
fit_row(td, r, [18, 180, 1, 1, 1, 1, 1], [2])
r += 2
band(td, r, "APPROVED WORDING (check character by character in M2-13-TC01)", 4)
r += 1
for i, name in enumerate(["Where", "Text", "Source"], start=1):
    c = td.cell(r, i, name)
    c.font, c.fill, c.alignment, c.border = f_head, fill_head, center, border
r += 1
for a in WORDING:
    body_cell(td, r, 1, a[0], f_bold)
    body_cell(td, r, 2, a[1])
    td.merge_cells(start_row=r, start_column=2, end_row=r, end_column=3)
    body_cell(td, r, 4, a[2])
    fit_row(td, r, [18, 122, 1, 26], [2, 4])
    r += 1

# --------------------------------------------------------- Evidence Queries
eq = wb.create_sheet("Evidence Queries")
title(eq, "Evidence Queries", "Run with the Lovable query_database tool. Replace the <PLACEHOLDERS>. Read-only or rolled back; token values are never selected. Checked against production on Oct 4.")
eq_cols = ["ID", "Title", "Purpose", "SQL", "Expected / how to read"]
eq_w = [8, 22, 34, 90, 40]
header(eq, 5, eq_cols, eq_w)
row = 6
for qid, qtitle, purpose, sql, expect in QUERIES:
    body_cell(eq, row, 1, qid, f_bold)
    body_cell(eq, row, 2, qtitle, f_bold)
    body_cell(eq, row, 3, purpose)
    body_cell(eq, row, 4, sql, f_mono)
    body_cell(eq, row, 5, expect)
    n = max(sql.count("\n") + 1, lines_needed(purpose, 34), lines_needed(expect, 40))
    eq.row_dimensions[row].height = min(409, 14.5 * n + 6)
    row += 1
add_table(eq, "M2EvidenceQueries", f"A5:E{row - 1}")
eq.freeze_panes = "C6"

# ------------------------------------------------------- Automated Evidence
ae = wb.create_sheet("Automated Evidence")
title(ae, "Automated Evidence", "Checks already run by machine. Re-run the native suite before sign-off (README › Tests) and add a row with the new result.")
ae_cols = ["ID", "Task(s)", "What was checked", "Result", "Date", "Source / evidence", "Tracker"]
ae_w = [8, 14, 46, 52, 11, 46, 12]
header(ae, 5, ae_cols, ae_w)
row = 6
for item in AUTOMATED:
    for i, v in enumerate(item, start=1):
        body_cell(ae, row, i, v, f_bold if i == 1 else f_body)
    fit_row(ae, row, ae_w, [3, 4, 6])
    row += 1
add_table(ae, "M2AutomatedEvidence", f"A5:G{row - 1}")
ae.freeze_panes = "C6"

# ------------------------------------------------------------ Traceability
tr = wb.create_sheet("Traceability")
title(tr, "Traceability", "Every requirement and client decision mapped to test cases and automated evidence.")
tr_cols = ["Req", "Requirement", "Source", "Test cases", "Automated evidence", "Cases", "Passed"]
tr_w = [7, 52, 34, 46, 18, 8, 8]
header(tr, 5, tr_cols, tr_w)
row = 6
case_ids = [c["id"] for c in CASES]
id_row = {cid: 6 + i for i, cid in enumerate(case_ids)}
for item in TRACE:
    for i, v in enumerate(item, start=1):
        body_cell(tr, row, i, v, f_bold if i == 1 else f_body)
    linked = sorted(expand(item[3]), key=case_ids.index)
    missing = [x for x in linked if x not in id_row]
    if missing:
        raise SystemExit(f"Traceability {item[0]} names unknown cases {missing}")
    body_cell(tr, row, 6, len(linked), align=Alignment(vertical="top", horizontal="center"))
    passed = "+".join(f"--(INDEX('Test Cases'!$O:$O,{id_row[x]})=\"Pass\")" for x in linked) or "0"
    body_cell(tr, row, 7, f"={passed}", align=Alignment(vertical="top", horizontal="center"))
    fit_row(tr, row, tr_w, [2, 3, 4])
    row += 1
add_table(tr, "M2Traceability", f"A5:G{row - 1}")
tr.freeze_panes = "C6"

# ---------------------------------------------------------------- Defects
de = wb.create_sheet("Defects")
title(de, "Defects", "One row per failure found in testing. Link it from the test case's Defect ID column.")
de_cols = ["Defect ID", "Test case", "Severity", "Status note", "Summary", "Status", "Evidence", "Fixed in"]
de_w = [10, 13, 10, 30, 80, 10, 30, 14]
header(de, 5, de_cols, de_w)
row = 6
for d in DEFECTS:
    for i, v in enumerate(d, start=1):
        body_cell(de, row, i, v, f_bold if i == 1 else f_body)
    body_cell(de, row, 7, None)
    body_cell(de, row, 8, None)
    fit_row(de, row, de_w, [4, 5])
    row += 1
for _ in range(15):
    for i in range(1, 9):
        body_cell(de, row, i, None)
    row += 1
add_table(de, "M2Defects", f"A5:H{row - 1}")
dsev = DataValidation(type="list", formula1='"Critical,High,Medium,Low"', allow_blank=True)
dsev.add(f"C6:C{row - 1}")
de.add_data_validation(dsev)
dst = DataValidation(type="list", formula1='"Open,Fixed,Verified,Won\'t fix"', allow_blank=True)
dst.add(f"F6:F{row - 1}")
de.add_data_validation(dst)

# ---------------------------------------------------------------- Summary
su = wb.create_sheet("Summary", 1)
title(su, "Summary", "Counts update from the Status column of 'Test Cases'.")
su_cols = ["Task", "Title", "Cases", "P1", "Pass", "Fail", "Blocked", "N/A", "Not run", "Done %"]
su_w = [14, 58, 8, 8, 8, 8, 9, 8, 9, 9]
header(su, 5, su_cols, su_w)
row = 6
task_rows = [(t[0], t[1]) for t in TASKS]
extra_tasks = sorted({c["task"] for c in CASES} - {t[0] for t in TASKS})
task_rows += [(t, "End-to-end scenario") for t in extra_tasks]
rng = f"'Test Cases'!$B$6:$B${last_tc}"
srng = f"'Test Cases'!$O$6:$O${last_tc}"
prng = f"'Test Cases'!$E$6:$E${last_tc}"
for tid, ttitle in task_rows:
    body_cell(su, row, 1, tid, f_bold)
    body_cell(su, row, 2, ttitle)
    body_cell(su, row, 3, sum(1 for c in CASES if c["task"] == tid))
    body_cell(su, row, 4, sum(1 for c in CASES if c["task"] == tid and c["priority"] == "P1"))
    for col, st in zip(range(5, 10), ["Pass", "Fail", "Blocked", "N/A", "Not run"]):
        body_cell(su, row, col, f"=COUNTIFS({rng},A{row},{srng},\"{st}\")")
    body_cell(su, row, 10, f"=IF(C{row}=0,0,(E{row}+H{row})/C{row})")
    su.cell(row, 10).number_format = "0%"
    row += 1
body_cell(su, row, 1, "Total", f_bold)
body_cell(su, row, 2, None)
for col in range(3, 10):
    L = get_column_letter(col)
    body_cell(su, row, col, f"=SUM({L}6:{L}{row - 1})", f_bold)
body_cell(su, row, 10, f"=IF(C{row}=0,0,(E{row}+H{row})/C{row})", f_bold)
su.cell(row, 10).number_format = "0%"
total_row = row
row += 2
body_cell(su, row, 1, "P1 passed", f_bold)
body_cell(su, row, 2, f"=COUNTIFS({prng},\"P1\",{srng},\"Pass\")&\" of \"&COUNTIF({prng},\"P1\")")
row += 1
body_cell(su, row, 1, "Open defects", f_bold)
body_cell(su, row, 2, "=COUNTIF(Defects!$F$6:$F$200,\"Open\")")
row += 1
body_cell(su, row, 1, "Ready for sign-off when", f_bold)
body_cell(su, row, 2, "Every P1 case is Pass, no Critical/High defect is open, and each Blocked or N/A case has its reason in Actual result.")
su.row_dimensions[row].height = 32
su.freeze_panes = "C6"

wb.calculation.fullCalcOnLoad = True
wb.save(OUT)

with open(SQL_OUT, "w") as f:
    f.write("-- Honoured V1.2 M2 test plan: evidence queries.\n"
            "-- Run with the Lovable query_database tool. Replace the <PLACEHOLDERS>.\n"
            "-- Read-only or rolled back. Token values are never selected.\n\n")
    for qid, qtitle, purpose, sql, expect in QUERIES:
        f.write(f"-- {qid} {qtitle}\n-- {purpose}\n-- Expect: {expect}\n{sql}\n\n")

print(f"{len(CASES)} cases; last row {last_tc}; summary total row {total_row}")
