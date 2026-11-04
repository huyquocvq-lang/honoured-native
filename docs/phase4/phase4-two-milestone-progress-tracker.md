# Phase 4 — Two-Milestone Progress Tracker

Updated: 01/11/2026

## Cách dùng tracker

Trạng thái hợp lệ:

- `NOT STARTED`: chưa bắt đầu.
- `IN PROGRESS`: đang làm.
- `BLOCKED`: bị chặn; phải ghi rõ blocker và người cần xử lý.
- `CODE DONE`: code đã xong nhưng chưa đủ verification.
- `READY FOR JIMMY`: automated test/build đã đạt và đã có bản để Jimmy test.
- `JIMMY TESTING`: Jimmy đang test trên iPhone thật.
- `DONE`: đã đạt Definition of Done của task.
- `OUT OF SCOPE`: không nằm trong 64 giờ.

Quy tắc cập nhật:

1. Agent phải cập nhật tracker sau mỗi task hoặc khi trạng thái thay đổi.
2. Không chuyển thẳng từ `IN PROGRESS` sang `DONE` nếu task cần TestFlight hoặc
   device test.
3. Với device test, agent dừng ở `READY FOR JIMMY`, ghi build/TestFlight và test
   steps. Jimmy chuyển sang `JIMMY TESTING`, sau đó ghi `PASS` hoặc `FAIL`.
4. Khi `FAIL`, đưa task liên quan về `IN PROGRESS`, ghi bug/evidence và retest
   bằng build mới.
5. Evidence phải là đường dẫn file, log, screenshot, migration version, URL build
   hoặc TestFlight build number; không chỉ ghi “tested”.

## Tổng quan

| Milestone | Scope | Giờ | Progress | Trạng thái | Điều kiện đóng |
|---|---|---:|---:|---|---|
| M1 — Foundation & Tracking | Item 1, 4, 5, 6 | 34 | 0/9 task DONE, 9/9 READY FOR JIMMY | READY FOR JIMMY | Web production + SQL v4 + TestFlight + Jimmy device PASS |
| M2 — Icon Amendment & Daily Card | Item 2, 3 | 30 | 4/9 task DONE, 5/9 READY FOR JIMMY (TestFlight 1.0.9 (4) 01/11: Dynamic Island M2.8; web + SQL target theo thứ, change request) | READY FOR JIMMY | DB/web production + TestFlight + Jimmy device PASS |
| **Tổng** |  | **64** | **4/18 task DONE, 14/18 READY FOR JIMMY** | **READY FOR JIMMY** | Hai milestone đạt Definition of Done |

## Đối chiếu tài liệu với hiện trạng (28/10/2026)

| # | Tài liệu nói | Hiện trạng thực tế | Evidence | Ảnh hưởng |
|---|---|---|---|---|
| E1 | Web Phase 3 M2 (Lovable tới `e79a9650`) chưa publish | Production đã có web Phase 3 M2: copy Core Motion, nhãn "Automatic", `HEALTH_LIVE_TOTALS`, `TRACK_CONTRACT` | Bundle production `routes-DeW-tHJK.js` và `index-CIbMwYIV.js` (tải từ `honour-your-word.lovable.app` ngày 28/10) chứa các chuỗi này; Lovable edit mới nhất vẫn là `e79a9650` (22/10) | Publish web Phase 4 không còn kéo theo phần Phase 3 M2 chưa publish; điều kiện "Jimmy duyệt gộp publish" không còn cần |
| E2 | Native Phase 3 M2 chưa có TestFlight | Native `main` = `origin/main` = `b3c96c9`; không còn archive local (thư mục Archives 22/10 và 26/10 rỗng); chưa có kết quả device test Phase 3 M2 nào được ghi | `git status -sb`; `~/Library/Developer/Xcode/Archives` | Build number TestFlight kế tiếp phải hỏi Jimmy hoặc lấy từ App Store Connect |
| E3 | DB đang ở icon scoring v3 | Đúng: `icon_days.measured_source` check chỉ cho `healthkit`, `core_motion`; `profiles` chưa có cột consent | `query_database` (chỉ SELECT) ngày 28/10 | M1.2 cần migration `profiles`; M1.7 cần v4 |
| E4 | SQL test chạy bằng Docker Postgres 17 | Docker Desktop trả lỗi 500; khởi động lại chạy được một lúc rồi lỗi lại ("no route to host") | Lệnh `docker info` | `docs/db/tests/pgtest.sh` thêm chế độ local (`PG_BIN`, `PSQL`); test SQL chạy trên Postgres 17.7 local, cùng file test |
| E5 | — | 28/10: ổ đĩa đầy giữa lúc archive Release (thiết bị), archive thất bại ở bước link `RevenueCat`; sau đó DerivedData được dọn | `archive-m1.log` (scratchpad): `** ARCHIVE FAILED **`; `df` còn 9,3 GB | Build lại từ đầu; archive TestFlight làm ở M1.9 sau khi có build number |

## Giả định đang dùng cho câu hỏi mở M1

Các câu hỏi mở bên dưới chưa có câu trả lời của khách. Agent implement theo đề
xuất trong plan; mỗi giả định đổi được với chi phí nhỏ và không đổi estimate:

| Câu hỏi | Giả định đang implement | Nguồn |
|---|---|---|
| Go again có giữ target cũ? | Giữ target cũ (cam kết của chính người dùng); contract mới và prefill từ contract gần nhất bắt đầu trống | Plan 3.1, bản trả lời khách 25/10 |
| Tần suất Philosophy modal | Mỗi lần ký (contract, Icon, Go again); không cần cột DB | Plan 3.5 |
| Opt-in cho Apple/Google sign-up | Có, theo scope M1.2 (5 giờ) | Plan 4.2 bảng M1.2 |
| iPhone không có dữ liệu | Dùng tổng gộp Apple Health, báo `fallback: true` và hiện thông báo | Plan 2.3 |
| Hai iPhone cùng model | Chấp nhận gộp; ghi trong copy/docs | Plan 2.3 |

## Milestone 1 — Foundation & Tracking

| ID | Task | Giờ | Phụ thuộc | Trạng thái | Người test | Evidence / Ghi chú |
|---|---|---:|---|---|---|---|
| M1.1 | Zero defaults và validation target | 4 | Quyết định Go again | READY FOR JIMMY | Agent automated + web QA | 28/10: Lovable commit `f33dab54` (`Contract.tsx`, `target-units.ts`, `tests/zero-target-defaults.test.ts`). Contract mới không lấy target từ snapshot/contract gần nhất; đổi activity/unit xoá target; Go again và sửa contract giữ target; `sign()` kiểm target > 0, words ≥ 100 cho slot chính và phụ trước `runStartSession`. Vitest 54 file, 713 pass, 0 fail (+12); `tsgo --noEmit` sạch. Diff đã review. Chưa publish. Copy lỗi mới chờ khách duyệt: "Enter a target above 0.", "Enter at least 100 words.". Production 28/10 (Lovable `2238fb9d`); Jimmy kiểm M1-W01 |
| M1.2 | Email opt-in: DB, email/Apple/Google, Settings | 5 | Chốt social sign-up | READY FOR JIMMY | Agent automated + web QA | 28/10 DB: `docs/db/email_opt_in_v1.sql` + `_rollback.sql`; test `docs/db/tests/email_opt_in_v1/run.sh` 39 check pass (migration, chạy lại, rollback, apply lại) trên Postgres 17.7 local. Deploy Lovable Cloud 28/10 (file md5 `0c0b66ac…`); md5 4 hàm trên production khớp bản test (`handle_new_user` `da81315d…`, `set_marketing_opt_in` `d94a37d8…`, `record_signup_marketing_opt_in` `2ec7552d…`, guard `70c90ee1…`); 13 profile hiện có = chưa opt-in, chưa ghi lựa chọn; anon không gọi được RPC. Web: Lovable commit `0ccde6e5` (`marketing-opt-in.ts`, `Auth.tsx`, `AuthGate.tsx`, `use-auth.ts`, `Settings.tsx`, `types.ts`, `tests/marketing-opt-in.test.ts`); vitest 55 file, 730 pass (+17), `tsgo` sạch. Review diff phát hiện lỗi: `AuthGate` xoá lựa chọn chờ khi mount ở chế độ sign-in, có thể làm mất lựa chọn sau Google redirect trên trình duyệt; đã sửa ở Lovable commit `2175fff4` (chỉ xoá khi bấm Apple/Google ở chế độ sign-in), test cập nhật. Chưa publish. Copy mới chờ khách duyệt: "Email updates", "Couldn't update your email preference. Try again.". Production 28/10 (Lovable `2238fb9d`); Jimmy kiểm M1-W02 |
| M1.3 | Philosophy modal trước `runStartSession` | 7 | Chốt tần suất hiển thị | READY FOR JIMMY | Agent automated + web QA | 28/10: Lovable commit `2175fff4` (`SigningPhilosophyDialog.tsx` mới, `Contract.tsx`, `tests/signing-philosophy.test.ts`). Hiện mỗi lần ký (contract, Icon, Go again), sau toàn bộ validation; contract chỉ được dựng, lưu, upload và `runStartSession` sau khi bấm Continue (continuation dùng một lần, chống bấm đôi); Back/Escape/backdrop giữ form và chữ ký (inline, ngang, carried); modal cũng render ở màn ký ngang. Vitest 56 file, 747 pass; `tsgo` sạch; agent Lovable kiểm trên trình duyệt (Playwright): focus, Back, Escape, backdrop, landscape. Chưa test ký thật có đăng nhập. Nút "Continue"/"Back" là copy mới chờ khách duyệt. Production 28/10 (Lovable `2238fb9d`); Jimmy kiểm M1-W03 |
| M1.4 | Health & Tracking screen | 4 | Copy + bridge contract | READY FOR JIMMY | Agent automated + Jimmy device | 28/10: Lovable commit `e5d27fc0` (`HealthTracking.tsx` mới, `health-tracking.ts` mới, `Settings.tsx`, `native-bridge.ts`, `health-source.ts`, `styles.css`, `tests/health-tracking.test.ts` mới, `tests/health-live-totals.test.ts`). Settings chỉ còn row "Health & Tracking ›" (ẩn khi không có HealthKit; trình duyệt: "Available in the iPhone app", không mở); màn con "‹ Settings", thẻ Apple Health + sheet chi tiết, thẻ Tracking source với segmented Automatic / iPhone / Core Motion (map theo `kind`, không theo id), mô tả đúng câu trong design, sheet (i); bỏ dropdown và dòng "In use"; không có UI Wearables. Lựa chọn không dùng được bị mờ, không ẩn, và không bao giờ gửi preference native không liệt kê. Vitest 57 file, 776 pass (+29); type check sạch; agent Lovable kiểm trên trình duyệt có đăng nhập với bridge iOS giả lập (lưu iPhone, thông báo fallback, hai sheet, nút back, khổ 390×844). Đối chiếu native: `sourceSettingsPayload` liệt kê Core Motion chỉ khi máy đếm bước, luôn có `this_iphone` — khớp contract. Quyết định có chủ đích: native không có `this_iphone` thì cả iPhone và Core Motion đều mờ ("Update Honoured…"), vì chưa bản phát hành nào có Core Motion mà thiếu `this_iphone` (E2). Review diff thấy hai lỗi, đã sửa: (1) khi trạng thái Health chưa tải xong, thẻ hiện thoáng "Unavailable right now" → hiện "…" như row cũ, ẩn Connect (Lovable `fcea8698`, +4 test); (2) Android trả `ERROR` cho `GET_HEALTH_STATUS` nên web coi là "unknown" chứ không phải "unsupported", row Health & Tracking vẫn hiện và mở được trên Android (hành vi này có từ trước Phase 4) → ẩn row và màn con khi đã biết platform mà không phải iOS (`healthTrackingVisible`, Lovable `2238fb9d`, +4 test). Vitest 57 file, 784 pass; type check sạch. Chưa publish. Copy mới chờ khách duyệt: nhãn trạng thái, sheet (i), "Update Honoured to use this option.", "Not available on this device.", thông báo fallback iPhone. TestFlight 1.0.9 (1) upload 28/10 14:43 |
| M1.5 | Nguồn “iPhone này” | 4 | Phase 3 M2 baseline | READY FOR JIMMY | Agent unit/build + Jimmy device | 28/10: native `HealthSourcePreference.swift` (kind/preference `this_iphone`, basis `this_iphone:<model>`, fallback), `HealthKitService.swift` (predicate nguồn Apple + `productType` máy này, cache 5 phút, áp dụng cho `readTotal`, `minuteTotals`, `sourceMetadata`, `health_daily`; mục cố định trong `HEALTH_SOURCES`), `IconVerifier.swift` (`readIconTotal`). Unit test: 272 pass (+9 mới) `evidence/2026-10-28-m1/honouredtests.txt`; build Debug/Release simulator pass; BridgeStub `this-iphone` 10/10, `core-motion` 17/17 (`evidence/2026-10-28-m1/stub-*.log`). Simulator không có bước của iPhone nên chỉ kiểm được nhánh fallback; spike `productType` trên máy thật nằm trong M1-D03/D04. TestFlight 1.0.9 (1) upload 28/10 14:43 |
| M1.6 | Preference persistence, migration, compatibility | 2 | M1.4, M1.5 | READY FOR JIMMY | Agent automated + Jimmy relaunch/account test | 28/10: native giữ đọc được lựa chọn cũ (test `testAPreviouslyChosenIPhoneSourceStaysAnOrdinarySource`). Web Lovable commit `e5d27fc0`: `migrateHealthPreference` trong `health-source.ts` chỉ chạy khi native liệt kê `this_iphone` — iPhone có tên (`kind: "iphone"`) → `this_iphone`; Watch/Garmin/app khác/nguồn không còn → Automatic; Core Motion, `this_iphone`, Automatic giữ nguyên; giá trị đã chuyển được lưu cho account trước khi gửi native. Native cũ: không đổi lựa chọn đã lưu, không gửi id không được liệt kê, vẫn cho chọn Automatic. Lưu theo account (`honoured.healthSource.v1:<userId>`), web thắng khi restore. Test: bảng chuyển đổi, reload, hai account tách riêng, native cũ — nằm trong 776 pass ở M1.4. Relaunch/đổi account trên máy thật: M1-D07/D08. TestFlight 1.0.9 (1) upload 28/10 14:43 |
| M1.7 | Icon/History source parity, SQL v4 + rollback | 2 | M1.5 | READY FOR JIMMY | Agent DB test + Jimmy device | 28/10: `docs/db/icon_scoring_v4.sql` (md5 `55b009fd…`) + `_rollback.sql` (md5 `3a44f1ce…`); thân hàm khác v3 đúng một dòng (`healthkit_iphone`). Test `docs/db/tests/icon_scoring_v4/run.sh`: 145 check pass qua 3 lượt (v4 cần v3; v2/v3 test cũ vẫn pass dưới v4; Automatic ↔ iPhone tăng/giảm, HONOURED không bị hạ, BROKEN lên HONOURED, rollback về đúng md5 v3 `227ced59…` = production trước deploy) `evidence/2026-10-28-m1/sql-icon-scoring-v4-tests.log`. Deploy Lovable Cloud 28/10; md5 production `3e443e4f…` = bản test; dữ liệu cũ không đổi (core_motion 13, healthkit 9, null 88). Native gửi `healthkit_iphone` qua `readIconTotal`. Còn device test M1-D06. TestFlight 1.0.9 (1) upload 28/10 14:43 |
| M1.8 | Apple Health status, fallback copy, bridge docs | 1 | M1.4, M1.5 | READY FOR JIMMY | Agent automated + Jimmy device | 28/10: native `hasRecentData` trong `HEALTH_PERMISSION_STATUS` (tổng gộp 7 ngày steps/distance/active energy; null khi máy khóa) xong, BridgeStub pass. `docs/phase1/bridge.md` đã cập nhật (mục "This iPhone as a source", `hasRecentData`, nhãn Icon `healthkit_iphone`); README thêm kịch bản `this-iphone`. Web Lovable commit `e5d27fc0`: `appleHealthView` — còn metric `notDetermined` → "Not connected" + Connect; đã hỏi hết và `hasRecentData` true → "Connected" (chấm xanh), false → "No data yet" (chấm vàng, kèm hướng dẫn), null/thiếu (native cũ) → "Set up"; còn lại → "Unavailable right now"; không bao giờ suy ra "Connected" chỉ từ quyền. Thông báo fallback iPhone chỉ hiện khi đang chọn `this_iphone` và `fallback: true`. Test đủ các nhánh, nằm trong 776 pass. TestFlight 1.0.9 (1) upload 28/10 14:43 |
| M1.9 | Regression, publish, TestFlight và handoff | 5 | M1.1–M1.8 | READY FOR JIMMY | Agent build/release + Jimmy acceptance | 28/10: gate native chạy lại trên DerivedData sạch (272 test, Debug/Release build, BridgeStub 10/10 + 17/17); web 784 test + type check; smoke Android giả lập (Lovable). Web publish 14:38 (Jimmy duyệt, copy mới chưa qua khách). `ios/project.yml` đổi sang 1.0.9 (1) theo Jimmy (chưa commit); archive Release ký tự động, app + widget 1.0.9 (1), `HonouredWebAppURL` = production, `ITSAppUsesNonExemptEncryption` = false; export `app-store-connect` và upload thành công 14:43, App Store Connect đang xử lý — `evidence/2026-10-28-m1/testflight-1.0.9-1.txt`. Bàn giao: hướng dẫn M1-D01..D10 và M1-W01..W03 trong tracker. Lần archive đầu thất bại do đầy đĩa (E5) |

### M1 automated/build gate — Agent chịu trách nhiệm

| Check | Trạng thái | Evidence |
|---|---|---|
| Web tests pass | DONE (28/10, sandbox Lovable) | Commit `2238fb9d`: vitest 57 file, 784 pass, 0 fail; `tsgo --noEmit` sạch. Agent review từng diff (`f33dab54`, `0ccde6e5`, `2175fff4`, `e5d27fc0`, `fcea8698`, `2238fb9d`) |
| Web production build pass | DONE (28/10) | Sandbox Lovable không cho chạy `bun run build` thủ công; production build chạy lúc publish (deployment `b5879848-64e0-4af2-abb2-2835ad2bb594`) và thành công: bundle mới `routes-CN1BttPw.js`, `index-BB79vf9c.js`; type check tự động sạch ở commit `2238fb9d` |
| Native unit tests pass | DONE (28/10, chạy lại sau khi code native M1 xong, DerivedData sạch) | `HonouredTests` 272 test, 0 fail — `evidence/2026-10-28-m1/honouredtests-gate.txt` (lần đầu: `honouredtests.txt`) |
| Debug/Release simulator build pass | DONE (28/10, chạy lại trên DerivedData sạch) | Debug (ký ad-hoc) và Release `-sdk iphonesimulator` BUILD SUCCEEDED — `evidence/2026-10-28-m1/gate-builds.txt` |
| BridgeStub source scenarios pass | DONE (28/10, chạy lại trên bản Debug của gate) | `this-iphone` 10/10, `core-motion` 17/17, 0 FAIL — `evidence/2026-10-28-m1/gate-stub-this-iphone.log`, `gate-stub-core-motion.log` |
| SQL v4 migration tests pass | DONE (28/10) | `docs/db/tests/icon_scoring_v4/run.sh`, Postgres 17.7 local (`PG_BIN`), 145 check — `evidence/2026-10-28-m1/sql-icon-scoring-v4-tests.log`. Thêm `email_opt_in_v1` 39 check — `sql-email-opt-in-v1-tests.log` |
| SQL v4 rollback tests pass | DONE (28/10) | Như trên, lượt 3 |
| SQL v4 deployed và smoke query pass | DONE (28/10) | md5 `record_icon_measurements` production `3e443e4f5a8ae4c80be38ce30c33e73a` = bản test; constraint 3 nhãn; anon không execute |
| Web published, tương thích app cũ | DONE (28/10, 14:38 +07; Jimmy duyệt publish trước khi khách duyệt copy) | `https://honour-your-word.lovable.app` = Lovable commit `2238fb9d`. Bundle production chứa đủ chuỗi M1 ("Enter a target above 0.", "Choose a promise you can honour", "Email updates", RPC opt-in, "Health & Tracking", `this_iphone`, `hasRecentData`, "Update Honoured to use this option."); mở trang production không có lỗi/cảnh báo console. Tương thích: native cũ không có `this_iphone` → iPhone/Core Motion mờ, không gửi preference lạ (unit test); Android giả lập (Lovable, có đăng nhập): target trống, 0 bị chặn, không có row Health & Tracking, có Email updates, 0 lỗi console — bước philosophy modal trên Android giả lập không chạy được vì tài khoản test có Icon đang chạy |
| TestFlight build sẵn sàng | DONE (upload 28/10 14:43; Jimmy xác nhận build hiện trong TestFlight sau khi Apple xử lý xong) | Build: 1.0.9 (1), `com.jimmy.upwork.honoured`, team `2N7M8MK5JN` — `evidence/2026-10-28-m1/testflight-1.0.9-1.txt` |
| Device test steps và expected result đã bàn giao | DONE (28/10) | Mục "Hướng dẫn test M1 trên iPhone thật" (M1-D01..D10) và "Kiểm tra web M1 trên production" (M1-W01..W03) |

### M1 device acceptance — Jimmy test

| Test ID | Test trên iPhone thật | Expected result | Build | Kết quả | Evidence / Bug |
|---|---|---|---|---|---|
| M1-D01 | Mở Health & Tracking | Chỉ có Automatic, iPhone, Core Motion; không có Wearables | 1.0.9 (1) | NOT TESTED | |
| M1-D02 | Automatic với iPhone + Watch | Tổng gần với Apple Health và không cộng trùng hai thiết bị | 1.0.9 (1) | NOT TESTED | |
| M1-D03 | Chọn iPhone, đi bằng iPhone | Steps/distance tăng từ dữ liệu iPhone này | 1.0.9 (1) | NOT TESTED | |
| M1-D04 | Để iPhone trên bàn, đi bằng Watch | Automatic tăng; iPhone và Core Motion không tăng sai | 1.0.9 (1) | NOT TESTED | |
| M1-D05 | Chọn Core Motion | Dùng pedometer iPhone, không cộng thêm HealthKit | 1.0.9 (1) | NOT TESTED | |
| M1-D06 | Đổi Automatic ↔ iPhone ↔ Core Motion | Home, contract, Live Activity, Icon và History dùng đúng source | 1.0.9 (1) | NOT TESTED | |
| M1-D07 | Force-quit và mở lại | Preference vẫn còn | 1.0.9 (1) | NOT TESTED | |
| M1-D08 | Đổi tài khoản | Mỗi account có preference riêng | 1.0.9 (1) | NOT TESTED | |
| M1-D09 | Tắt/deny Motion hoặc Health không có data | UI hiện đúng denied/no-data/fallback, không crash | 1.0.9 (1) | NOT TESTED | |
| M1-D10 | Đổi source sau khi goal đã đạt | Không phát `GOAL_REACHED` lần hai; ngày HONOURED không bị hạ | 1.0.9 (1) | NOT TESTED | |

M1 device result: `NOT TESTED`

#### Hướng dẫn test M1 trên iPhone thật (Jimmy)

Chuẩn bị: cài bản TestFlight ghi ở dòng "TestFlight build sẵn sàng" (1.0.9 (3) có đủ M1 và M2, dùng chung cho M1 và M2 được); đăng nhập
tài khoản dev `huyrambo2k@gmail.com`; iPhone có ghép Apple Watch; Apple Health
đã cấp quyền cho Honoured. Mỗi bài đi ngắn 100–150 bước, target 100. Ghi lại
ảnh màn hình Health & Tracking, Home và app Health (Steps › Show All Data) sau
mỗi bài, lưu vào `docs/phase4/evidence/<ngày>-m1-device/`.

| Test | Bước | Honoured lúc test | Kết quả mong đợi |
|---|---|---|---|
| M1-D01 | Settings › Health & Tracking | Mở | Thẻ Apple Health có trạng thái; Tracking source chỉ có Automatic / iPhone / Core Motion; không có thẻ Wearables; mỗi lựa chọn hiện đúng câu mô tả trong design |
| M1-D02 | Chọn Automatic. Đeo Watch, mang iPhone, đi ~150 bước. Khóa máy 5 phút, mở Honoured | Mở rồi nền | Steps trên Home bằng (±vài bước) số Steps hôm nay trong app Health, không phải tổng Watch + iPhone |
| M1-D03 | Chọn iPhone. Tháo Watch (hoặc để Watch ở nhà), mang iPhone đi ~150 bước, chờ 5–10 phút cho Health ghi | Mở | Steps tăng khoảng 150; dòng nguồn trên Home ghi "iPhone"; số khớp nguồn iPhone trong Health › Steps › Show All Data › Data Sources |
| M1-D04 | Để iPhone trên bàn, đeo Watch đi ~150 bước. Xem lần lượt Automatic, iPhone, Core Motion | Mở | Automatic tăng; iPhone và Core Motion gần như không tăng |
| M1-D05 | Chọn Core Motion (cấp quyền Motion & Fitness khi được hỏi), mang iPhone đi ~150 bước | Mở | Số tăng live trong lúc đi; dòng nguồn ghi "Core Motion"; không cộng thêm số của Health |
| M1-D06 | Có một contract bước chân và một Icon bước chân hôm nay. Đổi Automatic → iPhone → Core Motion → Automatic, mỗi lần chờ ~1 phút | Mở | Home, thẻ contract, Live Activity, History và ngày Icon đổi theo nguồn đang chọn (ngày Icon hiện số của nguồn mới, kể cả thấp hơn) |
| M1-D07 | Chọn iPhone, vuốt tắt Honoured, mở lại; khởi động lại máy, mở lại | Tắt rồi mở | Vẫn là iPhone |
| M1-D08 | Account A chọn Core Motion; đăng xuất; đăng nhập account B, chọn Automatic; quay lại A | Mở | A vẫn Core Motion, B vẫn Automatic |
| M1-D09 | (a) Settings › Privacy & Security › Motion & Fitness: tắt Honoured, quay lại app chọn Core Motion. (b) Tắt Fitness Tracking, chọn iPhone. (c) Health › Data Access › Honoured: tắt hết | Mở | (a) thông báo Motion tắt + nút Open Settings, dùng Apple Health; (b) thông báo iPhone chưa ghi bước, dùng tổng gộp; (c) Apple Health "No data yet"; không crash |
| M1-D10 | Goal bước chân target 100, đi tới khi có thông báo đạt. Sau đó đổi nguồn 2 lần | Nền khi đi, mở khi đổi | Chỉ một thông báo/celebration; ngày vẫn HONOURED sau khi đổi nguồn, kể cả khi số mới thấp hơn 100 |

Ghi kết quả từng dòng vào bảng "M1 device acceptance" ở trên (PASS/FAIL, build,
đường dẫn ảnh). Bài nào FAIL thì ghi mô tả và ảnh vào "Bugs và blockers".

#### Kiểm tra web M1 trên production (Jimmy)

Item 1, 4, 5 đã lên web production ngày 28/10 nên chạy được trong bản App Store
hiện tại hoặc bản TestFlight. Không cần đi bộ.

| Test | Bước | Kết quả mong đợi | Kết quả | Evidence / Bug |
|---|---|---|---|---|
| M1-W01 | Tạo contract bước chân mới; nhập 0 rồi ký. Đổi sang contract chữ, nhập 50 words rồi ký. Mở một contract cũ, Go again | Target bắt đầu trống; 0 → "Enter a target above 0."; 50 words → "Enter at least 100 words."; Go again giữ target cũ | NOT TESTED | |
| M1-W02 | Đăng ký tài khoản email mới có tick opt-in; một tài khoản Apple hoặc Google mới không tick. Đăng xuất, đăng nhập lại. Đổi toggle Settings › Account › Email updates, mở lại app | Toggle hiện đúng lựa chọn lúc đăng ký; đăng nhập lại không đổi; toggle giữ sau khi mở lại. Agent đối chiếu `profiles.marketing_opt_in`, `_at`, `_source` khi Jimmy báo email tài khoản test | NOT TESTED | |
| M1-W03 | Ký một contract (dọc), một contract ký ngang, một Icon. Ở dialog bấm Back một lần rồi ký lại và Continue | Dialog hiện sau validation, trước khi contract bắt đầu; Back giữ form và chữ ký, không trừ free session; Continue bắt đầu contract đúng một lần | NOT TESTED | |

M1 blocker/open questions:

- [ ] Go again có giữ target cũ không?
- [ ] Philosophy modal hiện mọi lần hay một lần; theo máy hay account?
- [ ] Opt-in có áp dụng cho Apple/Google sign-up không?
- [ ] iPhone không có data thì fallback Automatic hay hiện no data?
- [ ] Chấp nhận giới hạn hai iPhone cùng model có thể bị gộp?

## Milestone 2 — Icon Amendment & Daily Card

| ID | Task | Giờ | Phụ thuộc | Trạng thái | Người test | Evidence / Ghi chú |
|---|---|---:|---|---|---|---|
| M2.1 | `icon_amendments`, RLS, audit constraints | 3 | M1 SQL v4 | DONE | Agent DB test | 28/10: `docs/db/icon_revisions_v1.sql` (md5 `1c2973ae…`) + `_rollback.sql` (md5 `fb36e8e1…`). Bảng tên `icon_revisions` thay vì `icon_amendments` như plan nháp: status `amended` đang nghĩa là kết thúc sớm, và scope khóa dùng "Revision". Mỗi revision một dòng: target cũ/mới (chữ + giá trị Health), `effective_day`, `signature_path` riêng, `request_id`, thời điểm; unique (contract, revision), (contract, request_id), signature_path; RLS chỉ cho chủ đọc; authenticated không insert/update/delete; trigger chặn sửa/xoá kể cả service_role, chỉ xoá theo contract/tài khoản (cascade). Test local: baseline = thân hàm production nguyên văn (19 hàm khớp md5 production) — `evidence/2026-10-28-m2/sql-icon-revisions-v1-tests.log`. Deploy Lovable Cloud 28/10, md5 hàm production = bản test, smoke pass — `evidence/2026-10-28-m2/deploy-icon-revisions-v1.txt` |
| M2.2 | Target snapshot theo ngày, backfill, rollback | 3 | M2.1 | DONE | Agent DB test | 28/10: `icon_days.target_text`, `target_value`, `target_revision` (0 = lúc ký); backfill từ contract, không đổi `updated_at`; `contracts_icon_days()` ghi target cho ngày mới (thân production + 2 dòng). Rollback trả md5 production `ba8878e4…`, xoá cột; từ chối khi đã có revision trừ khi `set honoured.discard_icon_revisions = 'yes'` — `evidence/2026-10-28-m2/sql-icon-revisions-v1-tests.log`. Deploy Lovable Cloud 28/10, md5 hàm production = bản test, smoke pass — `evidence/2026-10-28-m2/deploy-icon-revisions-v1.txt` |
| M2.3 | Amendment RPC, idempotency, concurrency | 3 | M2.1, M2.2 | DONE | Agent DB test | 28/10: `revise_icon_target(contract, request_id, target, signature_path)` SECURITY DEFINER: chủ sở hữu, Icon active, không phải Word Tracker; chỉ đổi con số trong "<số> <đơn vị>" theo luật `target-units.ts` (max, số lẻ); Health đổi giá trị theo tỉ lệ lúc ký (km→m); hiệu lực từ ngày Icon pending kế tiếp sau ngày hiện tại theo timezone của Icon; chữ ký phải nằm trong thư mục người gọi, đã upload, khác chữ ký cũ; không đụng contract hay session. Idempotent theo `request_id`; khoá dòng contract nên hai lệnh đồng thời xếp hàng (test hai phiên: retry trả lại cùng revision; lệnh thứ hai thành revision kế tiếp) — `evidence/2026-10-28-m2/sql-icon-revisions-v1-tests.log`. Deploy Lovable Cloud 28/10, md5 hàm production = bản test, smoke pass — `evidence/2026-10-28-m2/deploy-icon-revisions-v1.txt` |
| M2.4 | Server readers dùng target snapshot | 3 | M2.2 | DONE | Agent DB/integration test | 28/10: `icon_days_to_measure()`, `record_icon_measurements()` (v4) và `icon_push_jobs()` đọc target của ngày (fallback contract); mỗi hàm = thân production đổi đúng dòng target. Test: hôm nay chấm theo target cũ, ngày đã sửa chấm theo target của nó (BROKEN → HONOURED), thẻ push sáng mai mang target mới (facts "8,000 STEPS"). Không đổi `record_word_reading()`: Icon Word Tracker không được sửa (ngoài scope), RPC từ chối, nên target ngày luôn = `word_target` — `evidence/2026-10-28-m2/sql-icon-revisions-v1-tests.log`. Deploy Lovable Cloud 28/10, md5 hàm production = bản test, smoke pass — `evidence/2026-10-28-m2/deploy-icon-revisions-v1.txt` |
| M2.5 | Amend/re-sign UI và signature storage | 5 | M2.3 | READY FOR JIMMY | Agent automated + Jimmy device | 28/10: Lovable commit `1059ffd6` (`src/lib/icon-revision.ts`, `src/components/IconRevision.tsx` mới, `Contract.tsx`, `ActiveIcons.tsx`, `native-bridge.ts`, `types.ts`, `tests/icon-revision.test.ts` 24 test): "Revise target" chỉ hiện khi `capabilities.iconRevisions.supported` (bản App Store/TestFlight 1.0.9 (1), Android, trình duyệt không thấy), Icon active, không phải Word Tracker, còn ngày pending sau hôm nay; một ô số cùng đơn vị theo `target-units.ts`; ký lại dọc/ngang (xoay không mất số và chữ ký); philosophy dialog trước khi lưu, Back không lưu gì; upload `<uid>/<client_id>/revisions/<request_id>.png` `upsert: false`; giữ request id khi lỗi mạng, bỏ file và dùng id mới khi server từ chối; `SYNC_ICON_REVISIONS` sau khi thành công; không gọi `START_SESSION`. Vitest 58 file, 808 pass; type check sạch. Review diff thấy 6 điểm, đã gửi Lovable sửa: làm tròn km/mi về 1 số lẻ trước khi gửi; câu lỗi phạm vi sai ("from 500"); Cancel sau lỗi mạng phải kiểm `icon_revisions` theo request id trước khi xoá file; Reset everything chưa xoá chữ ký revision trong thư mục con (kiểm cả purge khi xoá tài khoản); select `icon_days` phải fallback khi rollback SQL; thẻ History của Icon đã kết thúc dùng target mới nhất. Copy mới chờ khách duyệt: "Revise target", "Enter a different target.", câu preview/xác nhận, "Sign revision", "Sign to confirm your revision.", "This Icon has no days left to revise.", "This Icon has ended.", "Couldn't save your revision. Try again." Đã sửa ở Lovable `58400096`: làm tròn theo đơn vị (7.55 km → 7.6) trước kiểm tra/preview/`p_target`; câu lỗi "Enter a target up to <max> <unit>."; Cancel sau lỗi mạng tra `icon_revisions` theo request id (có → giữ file, hiện xác nhận; tra lỗi → giữ file); Reset everything và purge xoá tài khoản (`account-purge.ts`, trước đây chỉ xoá tầng trên cùng của bucket) xoá đệ quy cả chữ ký revision (`storage-tree.ts`); select `icon_days` thử lại không có cột target khi cột thiếu. Vitest 60 file, 817 pass; type check sạch. Đang chạy smoke trình duyệt (Android/iOS cũ/iOS mới giả lập). Web production 28/10 15:49 (Lovable `58400096`); TestFlight 1.0.9 (2) |
| M2.6 | Revision history và display parity | 4 | M2.3, M2.5 | READY FOR JIMMY | Agent web QA + Jimmy device | 28/10: Lovable commit `1059ffd6`: mục "Revision history" trong Icon (Original promise với target, giờ ký, chữ ký gốc; rồi Revision n: target cũ → mới, "Revised <ngày giờ>", "From <ngày>", chữ ký của revision); `icon_days.target_*` được đọc và dùng cho kết quả từng ngày (History, Today, timer Icon tự báo cáo), tiêu đề Icon dùng target đang có hiệu lực hôm nay, Go again lấy target mới nhất (`icon-recap.ts`). Đang chờ bản sửa ở M2.5 (thẻ History của Icon đã kết thúc) Thẻ History của Icon kết thúc sớm dùng target mới nhất (Lovable `58400096`); dòng từng ngày giữ target của ngày. 817 pass. Web production 28/10 15:49 (Lovable `58400096`); TestFlight 1.0.9 (2) |
| M2.7 | Native target/signature theo Icon day | 3 | M2.2, M2.4 | READY FOR JIMMY | Agent unit/build + Jimmy device | 28/10: thẻ app tự mở lấy `target_text` của ngày (`IconCardPlan.swift`; query `icon_days` dùng `*` nên vẫn chạy nếu rollback SQL); cache chữ ký theo revision (`HonouredShared/IconSignatureCache.swift`: revision 0 giữ tên file cũ, file `-r<n>`, danh sách revision + ngày hiệu lực; widget chọn revision đang có hiệu lực ở ngày của thẻ, thiếu ảnh thì không hiện chữ ký chứ không hiện chữ ký cũ); `IconSignatureSync` tải chữ ký từng revision từ `icon_revisions` (lỗi mạng không xoá danh sách đã có; 404 = chưa có bảng). Bridge: `capabilities.iconRevisions {protocolVersion 1, supported}` và `SYNC_ICON_REVISIONS` → `ICON_REVISIONS_SYNCED {synced}` (web gửi sau khi sửa target; đang sync thì chạy lại một lần). Thẻ push dùng target của ngày từ server (M2.4). Unit test 278 pass (+6) — `evidence/2026-10-28-m2/honouredtests.txt`; BridgeStub `icon-revisions` 2/2, `icon-card` 6/6, `icon-card-end` 1/1, `this-iphone` 10/10, `core-motion` 17/17 — `evidence/2026-10-28-m2/stub-*.log`. `docs/phase1/bridge.md` mục mới "Icon target revisions", README thêm kịch bản. Web production 28/10 15:49 (Lovable `58400096`); TestFlight 1.0.9 (2) |
| M2.8 | Ngày trên Lock Screen/Dynamic Island card | 2 | M2.7 | READY FOR JIMMY | Agent render + Jimmy device | 01/11 (khách yêu cầu, ảnh Dynamic Island trên 1.0.9 (3): header bị cắt thành `SUN 01.11.26 · 31 OF…`): Dynamic Island mở rộng làm giống Lock Screen — góc trên phải chỉ còn `31 OF 92`; ngày xuống hàng cuối, ngay trên "Due midnight", cả hai căn phải (đo pixel: lệch ≤ 0.5pt). Ngày không đứng cùng hàng target để `12,382 / 10,000 STEPS · Walking` giữ đủ chỗ. Bỏ `headerLabel`/`headerAccessibilityLabel` (không còn chỗ dùng). `HonouredTests` 288 pass, build simulator pass, render — `evidence/2026-11-01-m2/`. TestFlight 1.0.9 (4) (upload 01/11 18:47) có layout này — `evidence/2026-11-01-weekday-targets/testflight-1.0.9-4.txt`. 31/10: layout này có trong TestFlight 1.0.9 (3) (upload 19:43); Dynamic Island mở rộng giới hạn cỡ chữ tới xxLarge (audit B06). 31/10 (khách yêu cầu, ảnh thẻ trên 1.0.9 (2)): Lock Screen tách header — `30 OF 92` giữ góc trên phải (`IconCardFacts.countLabel`); `SAT 31.10.26` xuống góc dưới phải, ngay trên "Due midnight" (`dayLabel`, cùng hàng với dòng Because); cả hai căn phải, bù 1.2pt tracking ở chữ cuối (đo pixel: lệch ≤ 0.5pt). Dòng Because nhường chỗ cho ngày; không có Because thì ngày vẫn đứng riêng ngay trên cut-off. VoiceOver đọc riêng "30 of 92" và "Saturday 31 October 2026". Dynamic Island mở rộng giữ `SAT 31.10.26 · 30 OF 92` (khách chưa nói tới). `HonouredTests` 278 pass, build simulator pass, render — `evidence/2026-10-31-m2/`. Chưa có TestFlight chứa layout này. 28/10: header thẻ Lock Screen và Dynamic Island mở rộng = `TUE 06.10.26 · 5 OF 17` (`IconCardFacts.headerLabel`, ngày lấy từ `iconDay`, DD.MM.YY cố định mọi locale; không lấy ngày của cut-off) — đúng câu khách "Card header shows contract date: TUE 06.10.26 / Due midnight"; "Due midnight" giữ ở dòng cuối như cũ; VoiceOver đọc "Tuesday 29 September 2026, 5 of 17"; chữ co tới 75% trước khi cắt. Không cần đổi server: thẻ push đã mang `iconDay`. Giả định: giữ "5 OF 17" (plan 3.3 còn hỏi). Render: thường, chữ lớn, nội dung dài — `evidence/2026-10-28-m2/render/`. Web production 28/10 15:49 (Lovable `58400096`); TestFlight 1.0.9 (2) |
| M2.9 | Regression, rollout, feature gate, TestFlight | 4 | M2.1–M2.8 | READY FOR JIMMY | Agent release + Jimmy acceptance | 28/10: regression: SQL 119 check, native 278 test + Debug/Release build + BridgeStub (`icon-revisions`, `icon-card`, `icon-card-end`, `this-iphone`, `core-motion`), web 817 test + type check; smoke trình duyệt (Lovable, lưu giả lập, tài khoản test `huyquoc.vq@gmail.com` không bị ghi gì): Android giả lập không có "Revise target", History mở được, 0 lỗi console; iOS không có `iconRevisions` (bản App Store) không có nút; iOS có `iconRevisions`: sheet, lỗi phạm vi, preview, upload `revisions/<request_id>.png` `upsert: false`, lỗi mạng rồi Cancel (không có revision → xoá file; có → giữ, hiện xác nhận), thành công → xác nhận + lịch sử + một `SYNC_ICON_REVISIONS`. Web publish 28/10 (Jimmy duyệt, copy mới chưa qua khách): deployment `22e83bee-c0b2-4388-a957-325b889f43c8`, bundle `routes-DTH58poV.js`/`index-DMF8Y0N5.js` có chuỗi M2 và M1, 0 lỗi console. Feature gate: nút chỉ hiện khi native có `capabilities.iconRevisions` (chỉ từ 1.0.9 (2)). `ios/project.yml` 1.0.9 (2) (chưa commit); archive app + widget 1.0.9 (2), binary có `SYNC_ICON_REVISIONS`; upload 15:49 thành công, Apple đang xử lý — `evidence/2026-10-28-m2/testflight-1.0.9-2.txt`. Hướng dẫn M2-D01..D11 trong tracker |

### M2 automated/build gate — Agent chịu trách nhiệm

| Check | Trạng thái | Evidence |
|---|---|---|
| Migration/backfill tests pass | DONE (28/10) | `docs/db/tests/icon_revisions_v1/run.sh`, Postgres 17.7 local: 119 check, ALL STEPS PASSED; baseline = 19 hàm production nguyên văn (md5 khớp) — `evidence/2026-10-28-m2/sql-icon-revisions-v1-tests.log` |
| Rollback tests pass | DONE (28/10) | Như trên, lượt 1: rollback từ chối khi còn revision, chạy với `honoured.discard_icon_revisions`; 4 hàm về đúng md5 production; bảng/cột/hàm mới bị xoá; áp lại được |
| RPC ownership/validation tests pass | DONE (28/10) | Như trên: anon, không đăng nhập, Icon người khác, Word Tracker, kết thúc sớm, ngày cuối, 0/âm/quá max/số lẻ/NaN/Infinity, chữ ký sai thư mục/cũ/chưa upload |
| RPC retry/idempotency/concurrency tests pass | DONE (28/10) | Như trên: retry cùng `request_id` trả cùng revision (cả khi chạy đồng thời hai phiên); hai revision đồng thời xếp hàng, revision sau ghi revision trước làm target cũ |
| Web tests và production build pass | DONE (28/10) | Vitest 60 file, 817 pass, type check sạch (Lovable `58400096`); production build khi publish thành công (deployment `22e83bee…`) |
| Native unit/card render tests pass | DONE (28/10) | `HonouredTests` 278 test, 0 fail — `evidence/2026-10-28-m2/honouredtests.txt`; render thẻ (thường, chữ lớn, dài) — `evidence/2026-10-28-m2/render/`; build Debug/Release simulator — `evidence/2026-10-28-m2/builds.txt` |
| App-start và push-to-start fixtures pass | DONE (28/10) | App-start: `IconCardPlanTests.testTheDaysOwnTargetWinsOverTheSignedOne` (target của ngày, header ngày); push: SQL `icon_push_jobs`/`icon_push_facts` mang target revision ("8,000 STEPS") và `IconLiveActivityTests` giải mã payload push + header từ `iconDay`; BridgeStub `icon-card` 6/6, `icon-revisions` 2/2 |
| Android web smoke pass | DONE (28/10) | Lovable, trình duyệt có đăng nhập, Android giả lập: không có "Revise target" ở Contract và Icon; History mở được; 0 lỗi console |
| Production migration deployed và smoke pass | DONE (28/10) | `icon_revisions_v1.sql` (md5 `1c2973ae…`); md5 6 hàm production = bản test; 110 ngày backfill, 0 lệch, `updated_at` giữ nguyên — `evidence/2026-10-28-m2/deploy-icon-revisions-v1.txt` |
| Web published với feature gate mặc định off | DONE (28/10 15:49, Jimmy duyệt) | Gate = `capabilities.iconRevisions.supported` từ native; App Store và TestFlight 1.0.9 (1) không có capability nên không thấy nút (smoke iOS cũ). Bundle production có chuỗi M2; 0 lỗi console |
| TestFlight build sẵn sàng | DONE (1.0.9 (2) upload 28/10 15:49, Jimmy xác nhận; 1.0.9 (3) upload 31/10 19:43, Apple đang xử lý) | Build cho device test: 1.0.9 (3) (M1 + M2 + bố cục Lock Screen 31/10 + sửa lỗi audit) — `evidence/2026-10-31-m2-audit/testflight-1.0.9-3.txt`; trước đó 1.0.9 (2) — `evidence/2026-10-28-m2/testflight-1.0.9-2.txt` |
| Device test steps và expected result đã bàn giao | DONE (28/10) | Mục "Hướng dẫn test M2 trên iPhone thật" (M2-D01..D11) |

### M2 device acceptance — Jimmy test

| Test ID | Test trên iPhone thật | Expected result | Build | Kết quả | Evidence / Bug |
|---|---|---|---|---|---|
| M2-D01 | Tăng target và ký lại | Tạo một revision; ngày hiện tại giữ target cũ; ngày kế tiếp dùng target mới | 1.0.9 (3) | NOT TESTED | |
| M2-D02 | Giảm target và ký lại | Cùng quy tắc effective day; không thay đổi ngày đã đóng | 1.0.9 (3) | NOT TESTED | |
| M2-D03 | Cancel ở amend/re-sign | Không revision, không signature rác nhìn thấy, không mất session | 1.0.9 (3) | NOT TESTED | |
| M2-D04 | Tạo nhiều revision | History đủ thứ tự, target, effective day, time và signature | 1.0.9 (3) | NOT TESTED | |
| M2-D05 | Mở card ngày kế tiếp từ app | Card dùng target và chữ ký mới | 1.0.9 (3) | NOT TESTED | |
| M2-D06 | Mở card ngày kế tiếp bằng push | Card dùng target và chữ ký mới | 1.0.9 (3) | NOT TESTED | |
| M2-D07 | Xem card/ngày cũ | Target, chữ ký và kết quả cũ không đổi | 1.0.9 (3) | NOT TESTED | |
| M2-D08 | Qua midnight/timezone boundary | Revision có hiệu lực đúng Icon day | 1.0.9 (3) | NOT TESTED | |
| M2-D09 | Lock Screen header | `n OF m` góc trên phải; ngày Icon dạng đã chốt ngay trên “Due midnight” ở góc dưới phải, cả hai căn phải | 1.0.9 (3) | NOT TESTED | 01/11: khách báo "I saw the date on the activity card, it looks good" (chưa rõ Lock Screen hay Dynamic Island, chưa có ảnh); Jimmy vẫn cần đánh PASS. 31/10: ảnh khách trên 1.0.9 (2) hiện đúng ngày `SAT 31.10.26 · 30 OF 92`; khách yêu cầu đổi layout |
| M2-D10 | Dynamic Island expanded | `n OF m` góc trên phải; ngày ngay trên “Due midnight”, cả hai căn phải; target đúng, layout không vỡ | 1.0.9 (4) | NOT TESTED | 01/11: ảnh khách trên 1.0.9 (3) — header bị cắt `31 OF…`; khách yêu cầu chuyển ngày xuống |
| M2-D11 | App version cũ hoặc capability thiếu | Không thấy/không dùng được amendment CTA | App Store hoặc 1.0.9 (1) | NOT TESTED | |

M2 device result: `NOT TESTED`

#### Hướng dẫn test M2 trên iPhone thật (Jimmy)

Chuẩn bị: cài bản TestFlight ghi ở dòng "TestFlight build sẵn sàng" của M2 (bản có
`capabilities.iconRevisions`); web production có M2.5/M2.6; tài khoản dev
`huyrambo2k@gmail.com`; bật Live Activities và thông báo. Ký một Icon bước chân
mới, mỗi ngày, target 100 steps, nhắc sáng và tối, kéo dài ít nhất một tuần. Mỗi
bài đi ngắn 100–150 bước. Một số bài cần sang ngày hôm sau. Lưu ảnh màn hình vào
`docs/phase4/evidence/<ngày>-m2-device/`.

| Test | Bước | Honoured lúc test | Kết quả mong đợi |
|---|---|---|---|
| M2-D01 | Icon detail › Revise target, nhập 150, ký, qua philosophy dialog bấm Continue | Mở | Thông báo "Revised. From <ngày mai> …"; Revision history có Revision 1 (100 → 150, giờ sửa, From <ngày mai>, chữ ký mới); hôm nay vẫn 100 |
| M2-D02 | Revise lần nữa xuống 120 | Mở | Revision 2 (150 → 120, From <ngày mai>); hôm nay vẫn 100; ngày đã qua không đổi |
| M2-D03 | Mở Revise target rồi huỷ: (a) ở sheet, (b) bấm Back ở philosophy dialog, (c) xoay ngang ký rồi huỷ | Mở | Không có revision mới; không mất free session; không thấy chữ ký lạ trong lịch sử |
| M2-D04 | Xem Revision history sau D01–D02 | Mở | Original promise + Revision 1 + Revision 2 đúng thứ tự, target, giờ sửa, ngày hiệu lực, chữ ký |
| M2-D05 | Hôm sau, mở app sau giờ nhắc sáng | Mở | Thẻ Icon do app mở: target 120, chữ ký của Revision 2, header ngày hôm đó |
| M2-D06 | Hôm sau nữa, không mở app tới giờ nhắc sáng (iOS 17.2+) | Tắt | Thẻ do server mở bằng push: target 120, chữ ký Revision 2 |
| M2-D07 | History: xem ngày đầu tiên (trước revision) | Mở | Vẫn 100 và kết quả cũ; thẻ/ngày cũ không đổi |
| M2-D08 | Revise lúc ~23:50, rồi một lần nữa lúc ~00:10 | Mở | Lần 23:50: From ngày mai; lần 00:10: From ngày kế tiếp sau hôm nay (ngày vừa sang giữ target cũ) |
| M2-D09 | Xem thẻ trên Lock Screen | Khoá | Góc trên phải `n OF m`; góc dưới phải `TUE 06.10.26` (ngày của Icon) ngay trên "Due midnight", hai dòng thẳng mép phải |
| M2-D10 | Nhấn giữ Dynamic Island (iPhone có Dynamic Island) | Khoá/nền | Góc trên phải `n OF m`; ngày ngay trên "Due midnight", thẳng mép phải; target đúng; không vỡ layout |
| M2-D11 | Trên bản App Store hoặc TestFlight 1.0.9 (1) | Mở | Không có "Revise target" |

Giả định đang dùng cho M2 (đổi được với chi phí nhỏ):

| Câu hỏi | Giả định đang implement | Nguồn |
|---|---|---|
| Tên bảng lịch sử | `icon_revisions` (plan nháp: `icon_amendments`), vì `amended` đang nghĩa là kết thúc sớm | Scope khóa: dùng Revision |
| Định dạng ngày trên thẻ | `TUE 06.10.26`, DD.MM.YY cố định mọi locale | PDF khách, Item 3 |
| "5 OF 17" trên thẻ | Lock Screen và Dynamic Island mở rộng: `5 OF 17` góc trên phải, ngày ngay trên "Due midnight", căn phải | Khách 31/10 (Lock Screen), 01/11 (Dynamic Island) |
| Philosophy modal khi ký lại revision | Có, như mọi lần ký (giả định M1) | Tracker M1 |
| Chữ ký trên thẻ sau revision | Chữ ký của revision đang có hiệu lực ở ngày đó | Plan 3.2 câu 8 |

M2 scope đã khóa:

- [x] Target mới có hiệu lực từ ngày Icon kế tiếp.
- [x] Chỉ sửa con số; không đổi activity/metric/unit/schedule/deadline.
- [x] Không tiêu thêm free session.
- [x] Dùng Revised/Revision; không tái sử dụng AMENDED.
- [x] Không gồm Word Tracker Icon.
- [x] Không gồm ngày trên web/app card.
- [x] Không gồm same-day amendment.
- [x] Không gồm App Store submission/review.

## Release history

| Ngày | Milestone | Environment | Version/build | Thay đổi | Trạng thái | Evidence |
|---|---|---|---|---|---|---|
| 28/10/2026 | M1 | Lovable Cloud (Postgres 17.6) | `email_opt_in_v1.sql` (md5 `0c0b66aca53056dbca32fe58324b3c50`) | Cột consent trên `profiles`, guard, `handle_new_user` mới, RPC `record_signup_marketing_opt_in`, `set_marketing_opt_in` | Deployed, smoke pass | md5 hàm khớp bản test local; rollback: `docs/db/email_opt_in_v1_rollback.sql` (trả `handle_new_user` về md5 production cũ `1842a362…`, đã test) |
| 28/10/2026 | M1 | Lovable Cloud (Postgres 17.6) | `icon_scoring_v4.sql` (md5 `55b009fdbeaf6e429b5f2f6cd20ef14e`) | Nhãn `healthkit_iphone` trong `icon_days.measured_source` và `record_icon_measurements` | Deployed, smoke pass | md5 hàm production `3e443e4f…` = bản test; rollback `icon_scoring_v4_rollback.sql` (md5 `3a44f1ce…`) trả về md5 v3 `227ced59…`, đã test |
| 28/10/2026 | M1 | Web production `honour-your-word.lovable.app` | Lovable commit `2238fb9d`, deployment `b5879848-64e0-4af2-abb2-2835ad2bb594` | M1.1 zero defaults, M1.2 email opt-in (sign-up + Settings), M1.3 philosophy modal, M1.4/M1.6/M1.8 Health & Tracking | Published 14:38 +07 | Bundle `routes-CN1BttPw.js`, `index-BB79vf9c.js` chứa chuỗi M1; trước đó `routes-DeW-tHJK.js`, `index-CIbMwYIV.js`. Rollback: publish lại commit `e79a9650` trong Lovable (bản production trước, xem E1) |
| 28/10/2026 | M1 | TestFlight (App Store Connect, team `2N7M8MK5JN`) | Honoured 1.0.9 (1), `com.jimmy.upwork.honoured` | Item 6 native: nguồn iPhone này, `hasRecentData`, nhãn Icon `healthkit_iphone` (trên nền native Phase 3 M2 `b3c96c9`) | Uploaded 14:43 +07, Apple đang xử lý | `evidence/2026-10-28-m1/testflight-1.0.9-1.txt`; code native chưa commit (theo yêu cầu) |
| 28/10/2026 | M2 | Lovable Cloud (Postgres 17.6) | `icon_revisions_v1.sql` (md5 `1c2973aeeff64a548ed4e2b2b6c8a64d`) | Cột target theo ngày trên `icon_days` (backfill), bảng `icon_revisions`, RPC `revise_icon_target`, `contracts_icon_days`/`icon_days_to_measure`/`record_icon_measurements`/`icon_push_jobs` đọc target theo ngày | Deployed, smoke pass | md5 hàm khớp bản test; rollback `icon_revisions_v1_rollback.sql` (md5 `fb36e8e1…`) trả 4 hàm về md5 production cũ, đã test |
| 28/10/2026 | M2 | Web production `honour-your-word.lovable.app` | Lovable commit `58400096`, deployment `22e83bee-c0b2-4388-a957-325b889f43c8` | M2.5 sửa target + ký lại, M2.6 lịch sử revision và target theo ngày; xoá đệ quy chữ ký khi Reset/purge tài khoản | Published 15:49 +07, gate theo `capabilities.iconRevisions` | Bundle `routes-DTH58poV.js`, `index-DMF8Y0N5.js`; rollback: publish lại `2238fb9d` (M1) |
| 28/10/2026 | M2 | TestFlight (team `2N7M8MK5JN`) | Honoured 1.0.9 (2), `com.jimmy.upwork.honoured` | M1 + thẻ Icon theo target/chữ ký từng ngày, header ngày, `capabilities.iconRevisions`, `SYNC_ICON_REVISIONS` | Uploaded 15:49 +07, Apple đang xử lý | `evidence/2026-10-28-m2/testflight-1.0.9-2.txt`; code native chưa commit |
| 29/10/2026 | M1 (yêu cầu khách) | Web production `honour-your-word.lovable.app` | Lovable commit `bb71f319`, deployment `e6386a3c-ee15-47f4-b874-794be87d0a22` | Settings: dòng Health & Tracking dùng kiểu tiêu đề như các mục khác (chữ 10px in hoa, giãn chữ, màu muted, bỏ viền trên/dưới); chỉ đổi `HealthSection` trong `Settings.tsx` | Published 14:01 +07 (Jimmy duyệt) | Vitest 60 file, 817 pass, type check sạch (Lovable); bundle `routes-BbjUpSzY.js` có class mới; chưa xem trên máy thật. Rollback: publish lại `58400096` |
| 31/10/2026 | M2 (audit) | Web production `honour-your-word.lovable.app` | Lovable commit `d8a64d12` (gồm `9c43f998`), deployment `7109cd4f-4145-4e05-92d0-c6a24509a73b` | Sửa lỗi audit B01, B04, B05 (khung ký kẹt sau khi ký ngang, khoá ô nhập/chữ ký khi chưa rõ kết quả, preview target hôm nay, các lỗi nhỏ) | Published 31/10, kiểm trên production 19:40 +07 (Jimmy duyệt) | Vitest 61 file, 827 pass hai lần, type check sạch (Lovable); bundle `routes-CCJQQ5Pg.js` có code mới; trang production 0 lỗi/cảnh báo console; chưa xem trên máy thật. Rollback: publish lại `bb71f319` |
| 31/10/2026 | M2 (audit + khách) | TestFlight (team `2N7M8MK5JN`) | Honoured 1.0.9 (3), `com.jimmy.upwork.honoured` | Sửa lỗi audit B02, B03, B06 (cache chữ ký theo revision, `synced`, đổi tài khoản lúc sync) + bố cục Lock Screen khách yêu cầu 31/10 (M2.8) + toàn bộ 1.0.9 (2) | Uploaded 19:43 +07, Apple đang xử lý | `evidence/2026-10-31-m2-audit/testflight-1.0.9-3.txt`; 288 test, build Debug/Release, BridgeStub; code native chưa commit |
| 01/11/2026 | Change request (target theo thứ) | Lovable Cloud SQL | `icon_revisions_v1_1.sql`, `icon_weekday_targets_v1.sql` | Gia cố revision (B07); `contracts.icon_day_targets`, `revise_icon_targets`, `icon_revisions.changes`, push facts `targetRevision` | Deployed ~18:30 +07 (Jimmy duyệt), md5 = bản test, smoke rollback pass | `evidence/2026-11-01-weekday-targets/deploy-icon-weekday-targets-v1.txt`; rollback: `icon_weekday_targets_v1_rollback.sql` rồi `icon_revisions_v1_1_rollback.sql` |
| 01/11/2026 | Change request (target theo thứ) | Web production `honour-your-word.lovable.app` | Lovable commit `be4de745`, deployment `0ccece9a-6191-4cf3-9dab-e8e3f2ac0aa4` | Ký Icon với target theo thứ; tờ "Revise Icon Target" theo mockup (sửa nhiều thứ, ký một lần); lịch sử theo thứ; Go again giữ target theo thứ | Published (Jimmy duyệt) | Bundle `routes-Bv7mcqiI.js`, `index-DLIug4a3.js`; rollback: publish lại `d8a64d12` |
| 01/11/2026 | M2 + change request | TestFlight (team `2N7M8MK5JN`) | Honoured 1.0.9 (4), `com.jimmy.upwork.honoured` | 1.0.9 (3) + Dynamic Island mở rộng giống Lock Screen (M2.8, 01/11); target theo thứ không cần sửa native (dùng `targetRevision` có từ 1.0.9 (3)) | Uploaded 18:47 +07 (Jimmy duyệt), Apple đang xử lý | `evidence/2026-11-01-weekday-targets/testflight-1.0.9-4.txt`; HonouredTests 288 pass; code native và `project.yml` (build 4) chưa commit |

## Bugs và blockers

| ID | Milestone/task | Mô tả | Severity | Owner | Trạng thái | Build fix | Evidence |
|---|---|---|---|---|---|---|---|
| B01 | M2.5 | Audit 31/10: sau một lần ký ngang, lần "Revise target" sau trên cùng màn bị kẹt khung ký (nét đầu thành ảnh) | Medium | Agent | READY FOR JIMMY | Web production 31/10 (Lovable `d8a64d12`, kiểm trên production 19:40) | `evidence/2026-10-31-m2-audit/README.md` |
| B02 | M2.7 | Audit 31/10: danh sách revision ghi sau khi tải ảnh; sync ngắt/lỗi thì thẻ ngày sau có thể hiện chữ ký gốc cạnh target mới | Medium | Agent | READY FOR JIMMY | TestFlight 1.0.9 (3) (upload 31/10 19:43) | `evidence/2026-10-31-m2-audit/` (288 test, build, BridgeStub) |
| B03 | M2.7 | Audit 31/10: tải ảnh lỗi vẫn `synced: true` và chặn sync 15 phút | Medium | Agent | READY FOR JIMMY | TestFlight 1.0.9 (3) (upload 31/10 19:43) | như B02 |
| B04 | M2.5 | Audit 31/10: sau lỗi mất phản hồi vẫn sửa được số/chữ ký trước khi thử lại (server giữ số cũ hoặc ghép chữ ký cũ) | Low–Medium | Agent | READY FOR JIMMY | Web production 31/10 (Lovable `d8a64d12`, kiểm trên production 19:40) | `evidence/2026-10-31-m2-audit/README.md` |
| B05 | M2.5/M2.6 | Audit 31/10: preview sai target "hôm nay" khi hai revision cùng ngày; các lỗi web nhỏ khác (lưu hai lần, Cancel khi tra lỗi, file rác khi upload lỗi, flow qua đăng xuất, trạng thái ngang, fallback cột, prefix xoá storage) | Low | Agent | READY FOR JIMMY | Web production 31/10 (Lovable `d8a64d12`, kiểm trên production 19:40) | như B04 |
| B06 | M2.7/M2.8 | Audit 31/10: native nhỏ (ảnh cache cũ sau rollback, đổi tài khoản lúc sync, 404 bất kỳ, lỗi đọc revision chặn chữ ký gốc, reply ngoài main actor, Dynamic Island chữ lớn) | Low | Agent | READY FOR JIMMY | TestFlight 1.0.9 (3) (upload 31/10 19:43) | như B02 |
| B07 | M2.1/M2.3 | Audit 31/10: SQL gia cố (TRUNCATE của `service_role`, `clock_timestamp()`, chữ ký phải ở thư mục revisions của chính Icon và do người gọi upload, nested delete, khoá bảng khi rollback v1) | Low | Agent | DONE | `icon_revisions_v1_1.sql` + rollback, test local 243 check; deploy Lovable Cloud 01/11 cùng change request target theo thứ (Jimmy duyệt), md5 = bản test — `evidence/2026-11-01-weekday-targets/deploy-icon-weekday-targets-v1.txt` | `evidence/2026-10-31-m2-audit/sql-icon-revisions-v1-1-tests.log` |
| B08 | M2.9 | Audit 31/10: cùng tài khoản dùng thêm bản app cũ trên máy khác thì thẻ do bản cũ tự mở hiện target đã ký (plan §4.3 bước 6) | Low | — | NOT STARTED | Hết khi bản mới lên App Store | `evidence/2026-10-31-m2-audit/README.md` |
| B09 | M2.1 | Audit 31/10: chủ tài khoản ghi đè/xoá được ảnh chữ ký revision của mình (policy storage) | Low | — | NOT STARTED | Để sau (Jimmy đồng ý 31/10) | `evidence/2026-10-31-m2-audit/README.md` |

### Test trên iPhone — target theo thứ (Jimmy)

Web production 01/11 (`be4de745`); TestFlight 1.0.9 (4) (1.0.9 (3) cũng chạy được), tài khoản dev. Mỗi người chỉ có một Icon chạy mỗi ngày: nếu tài khoản đang có Icon thì dùng nó cho bước W2–W4, hoặc End early trước khi làm W1.

| # | Làm gì | Mong đợi |
|---|---|---|
| W1 | Ký Icon mới (Steps, vài ngày trong tuần), bật "Different target on some days", nhập số khác nhau (vd. hôm nay 100, mai 150) | Ký được; Icon detail có dòng "Mon 100 · Tue 150 … steps"; tiêu đề và thẻ Lock Screen hôm nay hiện target của hôm nay |
| W2 | Revise target: chọn thứ của ngày mai, nhập số mới; chọn thêm một thứ khác, nhập số; ký | Tờ giống mockup; thứ đã sửa có chấm vàng; Effective = ngày đầu tiên của thứ đang chọn; xác nhận liệt kê từng thứ; lịch sử có từng dòng "Thứ: cũ → mới · from …" |
| W3 | Gõ số vào một thứ rồi xoá trắng, chỉ sửa một thứ khác, ký | Không báo lỗi; chỉ thứ kia được ghi |
| W4 | Hôm sau, để Honoured ở nền tới giờ nhắc sáng (thẻ mở bằng push), rồi mở app | Thẻ hiện target mới và chữ ký mới của revision; hôm nay chấm theo target của ngày |
| W5 | Ký Icon với cùng một target mọi ngày, hoặc Word Tracker | Như trước; Word Tracker không có công tắc |

## Change requests ngoài 64 giờ

| Yêu cầu | Estimate thêm | Trạng thái |
|---|---:|---|
| Same-day amendment | Khoảng 2 giờ | OUT OF SCOPE |
| Word Tracker Icon amendment | 2–3 giờ | OUT OF SCOPE |
| Ngày trên web/app card | 1 giờ | OUT OF SCOPE |
| App Store submission/review | Estimate riêng | OUT OF SCOPE |
| Target theo thứ trong tuần (khách 01/11, kèm mockup "Revise Icon Target"): (A) ký Icon với target riêng cho từng thứ; (B) Icon đang chạy sửa target của một hoặc nhiều thứ, ký một lần, mỗi thứ có hiệu lực từ lần kế tiếp của thứ đó | Không tính thêm giờ (Jimmy 01/11) | READY FOR JIMMY — Jimmy chốt thiết kế phiên b9 01/11 (bỏ thiết kế `icon_revisions_v2` của phiên song song). SQL `docs/db/icon_weekday_targets_v1.sql` + rollback: `contracts.icon_day_targets` (guard kiểm và khoá, `contracts_icon_days()` tạo ngày theo target của thứ), `revise_icon_targets(contract, request, {"6": 12000}, signature)`, `icon_revisions.changes`, `icon_push_facts()` thêm `targetRevision`; cần `icon_revisions_v1_1.sql` trước; `icon_revisions_v1_rollback.sql` từ chối khi file này còn. Test local 193 check + bộ revision 243 check pass — `evidence/2026-11-01-weekday-targets/`. Deploy Lovable Cloud 01/11 ~18:30 (Jimmy duyệt): `icon_revisions_v1_1.sql` rồi `icon_weekday_targets_v1.sql`, md5 hàm production = bản test, smoke trong transaction rollback pass (14 ngày đúng target theo thứ, sửa thứ Hai → 2 ngày, push facts `targetRevision` 1, điều khoản khoá) — `evidence/2026-11-01-weekday-targets/deploy-icon-weekday-targets-v1.txt`. Web: Lovable `ab27698f` (tờ sửa theo mockup, ký với target theo thứ, lịch sử, Go again; 857 test), dọn phần sót của thiết kế bị bỏ + sửa ô xoá trắng ở `be4de745` (854 test, type check sạch; diff đã review); web production 01/11 (Jimmy duyệt): deployment `0ccece9a-6191-4cf3-9dab-e8e3f2ac0aa4`, bundle `routes-Bv7mcqiI.js` có "Different target on some days", "Revise Icon Target", `revise_icon_targets`, `icon_day_targets`, không còn `revise_icon_weekdays`/`icon_revision_targets`. Copy mới chờ khách duyệt: "Different target on some days", "Revise Icon Target", "Adjust the daily target. A new signature is required.", "Current target", "Repeat for other days as needed.", "View change history", "Effective", câu xác nhận/lịch sử theo thứ. Native: không cần sửa code (1.0.9 (3) đọc `targetRevision` từ push); TestFlight 1.0.9 (4) upload 01/11 18:47 theo yêu cầu Jimmy. Còn lại: Jimmy test W1–W5 trên iPhone; khách duyệt copy mới |
