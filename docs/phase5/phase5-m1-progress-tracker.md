# Phase 5 M1 — History + Icon cleanup: Progress Tracker

Updated: 04/11/2026

Nguồn scope: `Honoured_History_Icon_Scope_Updated_Visual.pdf`, `phase5-assessment-estimate-plan.vi.md` §4.1, §6 Phase 1, §7 Cleanup.
Lovable project: Honoured V13 (`eec79567-2e9c-4821-aef7-11204b546ea7`), làm qua Lovable MCP. Baseline: Lovable `be4de745` = production 01/11 (bundle `routes-Bv7mcqiI.js`).
Không migration, không xoá history, không publish khi Jimmy chưa duyệt.

Trạng thái dùng như tracker Phase 4: `NOT STARTED`, `IN PROGRESS`, `BLOCKED`, `CODE DONE`, `READY FOR JIMMY`, `JIMMY TESTING`, `DONE`.

## Tổng quan

| Milestone | Giờ | Trạng thái | Điều kiện đóng |
|---|---:|---|---|
| M1 — History + Icon cleanup | 12 | JIMMY TESTING (published 04/11) | Web tests + type check pass ✅, review diff ✅, QA trình duyệt ✅, Jimmy duyệt publish, Jimmy kiểm trên iPhone (WebView) |

## Task

| # | Task | Giờ | Trạng thái | Evidence |
|---|---|---:|---|---|
| M1.1 | History mặc định 7 ngày lịch (hôm nay + 6 ngày trước), chế độ theo ngày khi bấm ngày có màu, "Back to recent history", giữ filter | 3 | CODE DONE | Lovable `dbb945ac`: `history-entries.ts` (`recentWindowStart`, `isRecentEntry`, `historyListEntries`, `historyListEmptyText`), `History.tsx` (mode recent/day, `changeMonth` dùng chung), `tests/history-recent-list.test.ts` 7 test. Vitest 64 file, 861 pass; `tsgo` sạch. Diff đã review |
| M1.2 | Vuốt trái/phải đổi tháng, giữ mũi tên, khoá trục, không cướp cuộn dọc/bấm ngày, chuyển cảnh ~250 ms | 2.5 | CODE DONE | Lovable `b57ed715` + `df0dc04d`: `src/lib/calendar-swipe.ts` (slop 10 px, tỉ lệ 1.2, 48 px hoặc flick ≥ 24 px và ≥ 0.4 px/ms, nuốt click sau mọi cử chỉ ngang), `History.tsx` (touch listeners, slide `history-month-next/prev`, fade khi chọn tháng, không animation khi reduced motion), `HistoryDayCell` thêm `expanded` (aria-expanded theo sheet). `tests/calendar-swipe.test.ts` 10 test |
| M1.3 | Active Icon: thu gọn mặc định, chevron, bấm summary mở/đóng lịch sử revision; Revise target (trái) + End early (phải) cùng hàng, ngoài vùng thu gọn | 2.5 | CODE DONE | Lovable `df0dc04d`: `ActiveIconItemView.tsx` mới (nút toggle `aria-expanded`/`aria-controls`, không lồng button; bấm dòng today/chấm cũng toggle, trừ control), `ActiveIcons.tsx`, `IconRevision.tsx` (tách `useIconRevisionState`, `ReviseTargetAction`, `RevisionConfirmation`; câu xác nhận tự ẩn sau 8 s). `tests/active-icon-item.test.ts` 7 test. Vitest 66 file, 878 pass; `tsgo` sạch |
| M1.4 | Unit/regression + browser/WebView QA | 3 | READY FOR JIMMY | Unit: 878 pass. Browser QA (agent Lovable, preview, 390×844 touch, tài khoản huyquoc.vq@gmail.com, không ghi gì) 04/11: 9/9 PASS. QA local 04/11 (code Lovable `df0dc04d`, mock Supabase, Playwright Chromium + WebKit, iPhone 13 viewport): 117/119 PASS, 2 cái còn lại là assertion sai của script, không phải lỗi app — xem các mục QA dưới. Còn: Jimmy kiểm trên iPhone thật (WKWebView) sau publish |
| M1.5 | Review diff, sửa regression, publish khi Jimmy duyệt | 1 | DONE | Review 3 diff xong, 3 điểm nhỏ đã sửa trong `b57ed715`/`df0dc04d`. Jimmy duyệt 04/11, publish Lovable `df0dc04d` (deployment `b29e7446`). Production bundle `routes-DmE-ESGB.js` có "Back to recent history", "Last 7 days", `icon-info-toggle`, `icon-actions`, `history-month-*` |

Credit Lovable đã dùng: 3.6 + 3.4 + 5.4 + 5.8 (QA) = 18.2.

## QA trình duyệt 04/11 (agent Lovable, preview Lovable `df0dc04d`)

| # | Kiểm | Kết quả |
|---|---|---|
| 1 | Mặc định "Last 7 days", chỉ card 29/10–3/11 (6 card); ngày có màu 2–28/10 không còn trong danh sách | PASS |
| 2 | Bấm 14/10: sheet ngày mở; danh sách "14 October 2026" + "Back to recent history"; đóng sheet vẫn giữ; Back về 7 ngày | PASS |
| 3 | Filter Honoured giữ qua hai chế độ; câu trống "No honoured results on this day." / "No broken results in the last 7 days." | PASS |
| 4 | Vuốt trái → tháng sau (trượt từ phải), vuốt phải → tháng trước; kéo ngang ngắn không mở ngày; kéo dọc vẫn cuộn; bấm ngày vẫn mở; mũi tên chạy; đổi tháng đóng sheet, giữ danh sách | PASS (sheet đang mở che mũi tên — hành vi cũ) |
| 5 | Kéo xuống từ đỉnh vẫn refresh | PASS |
| 6 | Active Icon (Steps, 1 revision): thu gọn mặc định, chevron xuống; bấm mở Original promise + Revision 1, chevron lên; bấm lại đóng; bấm dòng Today cũng toggle | PASS (Icon này không có nút timer/Yes-No để thử) |
| 7 | Revise target trái, End early phải cùng hàng, cả hai trạng thái; mở sheet revise rồi Cancel; mở xác nhận End early rồi Cancel; không toggle lịch sử | PASS |
| 8 | Trình duyệt thường và Android giả lập: chỉ End early, căn phải | PASS |
| 9 | Console History/Contract: không lỗi | PASS (Home có 2 lỗi "JWT not yet valid" một lần do lệch giờ máy test, hết sau reload) |

## QA local 04/11 (tải codebase Lovable `df0dc04d` = head, chạy `vite dev` trỏ vào mock Supabase, không đụng dữ liệu thật)

Dữ liệu mock: hôm nay Wed 4/11/2026 12:00 +07; 11 contract thường 2/9–4/11 (hai kết quả cùng 1/11 và 14/10, một cái 28/10 23:00 ngay ngoài cửa sổ) + 2 Icon đang chạy (Steps T2–T6 có 1 revision; Walking T7–CN không revision).

- Unit: `vitest` 66 file / 878 test pass, `tsc --noEmit` sạch (TZ=UTC như Lovable). 6 file test liên quan M1 (93 test) pass ở 8 múi giờ (UTC, Saigon, London, New York, LA, Sydney, Kiritimati +14, Pago Pago −11).
- History, Chromium touch thật qua CDP: 32/32 PASS. Gồm: mặc định "Last 7 days" đúng 11 card 29/10–4/11; chạm 14/10 mở sheet đủ 2 kết quả, đóng sheet vẫn giữ ngày, `aria-expanded` của ô về false; filter Honoured giữ qua hai chế độ; câu trống "No amended results on this day."; vuốt trái/phải đổi tháng có class slide; kéo ngang ngắn chậm không đổi tháng, không mở ngày; flick 32 px nhanh đổi tháng; kéo dọc trên lịch cuộn trang (scrollTop 0→212); chéo chủ yếu dọc không đổi tháng; chạm sau khi vuốt vẫn mở ngày; mũi tên đóng sheet và giữ chế độ danh sách; chọn tháng dùng fade; bấm card tháng khác không chạy slide; kéo xuống từ đỉnh vẫn refresh; reduced motion không animation.
- History, WebKit (không có touch trên desktop, chỉ kiểm layout + click): 16/16 PASS.
- Vuốt, trường hợp biên (Chromium): 9/9 PASS. Gồm: vuốt ngang lệch xuống ở đỉnh trang đổi tháng và không refresh; vuốt bắt đầu trên ô có màu không mở ngày; vuốt chạy ra ngoài mép lưới; hai cú vuốt nhanh = hai tháng; vuốt khi trang đang cuộn giữa chừng không làm cuộn; vuốt ngang trên danh sách card không đổi tháng.
- Active Icon, WebKit và Chromium: mỗi engine 31/32 PASS. Assertion còn lại là lỗi của script (tìm chữ "Deep work"), UI vẫn đúng, có ảnh chụp. Gồm: thu gọn mặc định, chevron xuống/lên, `aria-expanded`/`aria-controls`, không lồng button; mở ra có Original promise + Revision 1 kèm cả hai chữ ký; Revise target trái + End early phải cùng hàng, cao 44 px, nằm dưới phần lịch sử; chạm dòng Today/chữ dưới chấm cũng toggle; Revise target mở sheet revise rồi đóng không ký, End early mở "End this Icon early?" rồi Cancel, cả hai không toggle; Icon không revision thì không chevron, không `aria-expanded`; Enter/Space toggle; rời tab rồi quay lại thì thu gọn; Home không đổi; trình duyệt thường không có Revise target, End early căn phải, lịch sử vẫn xem được; màn hợp đồng đang chạy (chỗ render thứ hai) cũng đúng. Console: không lỗi, không warning.
- Ảnh chụp và script: `~/.hermes/cache/scratch/hon/qa/` (không commit).

## Quyết định/giả định (chờ Jimmy/khách xác nhận nếu cần)

1. Cửa sổ 7 ngày tính theo ngày lịch local của máy; entry có ngày sau hôm nay (Icon ở múi giờ đi trước) vẫn tính là gần đây, để không giấu record mới.
2. Bấm ngày: mở day sheet như hiện tại và danh sách card chuyển sang ngày đó; đóng sheet vẫn giữ danh sách theo ngày cho tới khi bấm "Back to recent history".
3. Đổi tháng (mũi tên, chọn tháng, vuốt) chỉ đóng day sheet, không đổi chế độ danh sách.
4. Icon chưa có revision: không có chevron, không có gì để mở.
5. Câu xác nhận sau khi sửa target tự ẩn sau 8 giây (scope: "may remain temporarily visible; avoid permanent clutter").
6. Bấm dòng Today/chấm ngày cũng mở/đóng lịch sử (scope: "tap the main Active Icon information area"); bấm control bên trong (timer, Yes/No, Check now) thì không.
7. Copy mới (chờ khách duyệt): "Back to recent history" (từ scope), "Last 7 days", "No results in the last 7 days." / "No results on this day." (có tên status khi lọc).

## Release history

| Ngày | Environment | Version | Thay đổi | Trạng thái | Evidence |
|---|---|---|---|---|---|
| 04/11/2026 | Production web `honour-your-word.lovable.app` (iOS + Android WebView) | Lovable `df0dc04d` | M1: History 7 ngày + Back to recent history, vuốt đổi tháng, Active Icon thu gọn + hàng Revise target / End early | PUBLISHED, chờ Jimmy/khách kiểm trên máy thật | Deployment `b29e7446-62f3-42e5-8c21-0b64eb39a8a7`; bundle `routes-Bv7mcqiI.js` → `routes-DmE-ESGB.js`, `index-Au73nRD7.js`, `styles-C_Gp5W95.css`; WebKit smoke trang đầu 200, không lỗi console. Không cần build native |

## Bugs và blockers

| ID | Task | Mô tả | Severity | Trạng thái | Evidence |
|---|---|---|---|---|---|
| P5-B01 | M1.3 | QA 04/11: khi mở lịch sử, ô chữ ký "Original promise" của Icon Steps (ký 01/10) trống; chữ ký Revision 1 hiện bình thường. QA local với chữ ký hợp lệ thì cả hai đều hiện. `RevisionHistory`/`useSignatureUrl` không đổi trong M1 (chỉ thêm `id`). DB: contract có `signature_path`, object có trong bucket `signatures` (33.8 KB). Kết luận: lỗi có sẵn từ trước hoặc do file ảnh đó, không phải M1. Cần xem trên iPhone (so với chữ ký ở màn hợp đồng) | Low | OPEN (pre-existing) | Báo cáo QA Lovable 04/11; QA local `c3-expanded-webkit.png` |
| P5-B02 | — | `tests/icon-signed.test.ts` "00:00 means the midnight that ENDS each Icon day" fail khi chạy ở mọi múi giờ khác UTC. Baseline `be4de745` cũng fail y hệt; test giả định máy chạy UTC. Lovable chạy UTC nên không thấy | Low (test-only) | OPEN (pre-existing) | `TZ=Asia/Saigon npx vitest run tests/icon-signed.test.ts` |
