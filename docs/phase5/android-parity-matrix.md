# Phase 5 M2 — A1: Baseline đóng băng và Android parity matrix

Ngày lập: 05/11/2026  
Task: A1 trong `phase5-m2-android-foundation-plan.vi.md` §5 (2 giờ). Branch `feat/android-m2` (HEAD `830de93`).  
Trạng thái: **DRAFT**. Baseline còn chờ D1 (Jimmy PASS bản iOS). D6, D8 đã chốt 04/11. D7 còn mở. Có một đề xuất mới là D9 (§8).

Nguồn đã đối chiếu (chỉ đọc):

- Web: code Lovable head `df0dc04d` (= production 04/11): `src/components/screens/*`, `src/components/*`, `src/lib/*`. Số dòng ghi trong file này lấy từ bản code đó.
- iOS: `ios/Honoured/{Auth,Billing,Bridge,Health,LiveActivities,MotionProbe,Notifications,Timer,WebView,WordTracker}`, `ios/project.yml`.
- Android: `android/app/src/main` (`MainActivity.kt`, `bridge/NativeBridge.kt`, `auth/AuthBridge.kt`, `billing/SubscriptionService.kt`, `AndroidManifest.xml`).
- `docs/phase1/bridge.md`, `phase5-assessment-estimate-plan.vi.md` §2–3, `phase5-m2-android-foundation-plan.vi.md` §2–5, `docs/db/*.sql`.

Giới hạn: chưa có máy thật (D2), OAuth Android (D4) và tài khoản test (D5), nên chưa chạy được luồng nào khi đã đăng nhập trên Android. Mọi hành vi Android trong bảng là suy từ code. Chỗ nào phải kiểm trên máy thì ghi "(cần xác nhận)"; các chỗ đó thuộc G3/G4.

---

## 1. Baseline đóng băng

| # | Thành phần | Giá trị | Trạng thái / evidence |
|---|---|---|---|
| 1 | iOS build | chờ Jimmy PASS; 1.0.9 (4) trên TestFlight, `ios/project.yml` đang ở 1.0.9 (5) | `97b6baf build: set version 1.0.9 (4)`. Sau đó `c36ad36` nâng `CURRENT_PROJECT_VERSION` lên 5. Chưa biết bản freeze là (4) hay (5) (D1) |
| 2 | Web (Lovable) | commit `df0dc04d`, deployment `b29e7446-62f3-42e5-8c21-0b64eb39a8a7`, bundle `routes-DmE-ESGB.js` (cùng `index-Au73nRD7.js`, `styles-C_Gp5W95.css`), published 04/11/2026 | `phase5-m1-progress-tracker.md`, mục Release history. Kiểm lại lúc 05/11 17:42: `get_project.latest_commit_sha` = `df0dc04d`, nghĩa là không có edit nào chưa publish. Production `/` vẫn tải đúng 3 asset trên |
| 3 | Supabase | md5 của 50 hàm `public` chính, chụp 05/11/2026: `evidence/m2/supabase-function-md5-2026-11-05.tsv`. Ví dụ `record_icon_measurements` `4363134a…`, `revise_icon_targets` `b7484ec7…`, `self_report_icon_day` `95feb366…`, `handle_new_user` `da81315d…` | `supabase_migrations` dừng ở `20260904095949`. Mọi SQL sau mốc đó được chạy tay từ `docs/db/*.sql`, nên phải chốt bằng md5 của `pg_get_functiondef`, không chốt bằng version. Danh sách hàm và query ở §1.1. `bump_contracts_counter` không có trên production. Khi D1 PASS, chạy lại query; md5 khác thì ghi lại thay đổi |
| 4 | Android parity matrix | File này, bản 05/11/2026 | 106 workflow, mỗi cái có một quyết định (thống kê ở §9) |

### 1.1 Hàm SQL cần ghi md5

Query chỉ đọc, chạy bằng `mcp__lovable__query_database`. Cách tính md5 giống `docs/db/tests/icon_revisions_v1/03_baseline_check.sql`:

```sql
select p.proname,
       pg_get_function_identity_arguments(p.oid) as args,
       md5(pg_get_functiondef(p.oid)) as md5
from pg_proc p
where p.pronamespace = 'public'::regnamespace
  and p.proname = any (array[ /* các tên trong bảng dưới */ ])
order by p.proname, args;
```

Không dùng lại md5 ngày 28/10 trong `03_baseline_check.sql`. Từ đó tới nay đã có SQL mới, ít nhất là `icon_revisions_v1_1.sql` và `icon_weekday_targets_v1.sql` (cùng ngày 01/11).

| Nhóm | Hàm (schema `public`) | File nguồn | Workflow liên quan |
|---|---|---|---|
| Account, opt-in | `handle_new_user`, `profiles_marketing_guard`, `record_signup_marketing_opt_in`, `set_marketing_opt_in` | `email_opt_in_v1.sql` | A01, A11 |
| Access, trial | `get_access_state`, `start_session`, `has_entitlement`, `restore_account`, `set_reset_timezone`, `increment_contracts_signed`, `get_contracts_signed_count`, `bump_contracts_counter` | `supabase/migrations` ≤ `20260904095949` (repo web) | A14, G02, H02, H03 |
| Health | `upsert_health_samples`, `upsert_health_daily` | `healthkit_v1.sql` | K05 |
| Icon (lõi) | `icon_schedule`, `contracts_icon_guard`, `contracts_icon_days`, `icon_reserved_days`, `contracts_icon_reserve` | `icon_v1.sql`, `icon_v1_1_midnight_cutoff.sql`, `icon_exclusivity_v1.sql`, `icon_weekday_targets_v1.sql` | D01–D03 |
| Icon (chấm điểm) | `icon_days_to_measure`, `record_icon_measurements`, `expire_icon_days`, `self_report_icon_day` | `icon_scoring_v1..v4.sql`, `icon_revisions_v1.sql` | D07, D09 |
| Revision | `revise_icon_target`, `revise_icon_targets`, `icon_revisions_immutable` (và trigger `icon_revisions_no_truncate`) | `icon_revisions_v1_1.sql`, `icon_weekday_targets_v1.sql` | D12 |
| Push | `register_push_token`, `unregister_push_tokens`, `icon_push_jobs`, `icon_push_plan`, `icon_push_facts`, `icon_push_tick`, `icon_push_collect`, `icon_push_record`, `icon_push_cleanup`, `icon_push_drop_token`, `icon_push_secret_ok`, `icon_push_classify`, `icon_push_reason`, `icon_push_request_token`, `icon_push_selftest`, `icon_copy_affirmation`, `icon_copy_deadline`, `icon_cut`, `icon_target_split` | `icon_push_v1..v5.sql`, `icon_weekday_targets_v1.sql` | D05, D06, I08 |
| Word Tracker | `record_word_reading`, `contracts_word_guard` | Repo web: `docs/db/word_tracker_v1.sql`, `drizzle/migrations/0001..0003` | D11. Android EXCLUDED, nhưng DB dùng chung nên vẫn phải ghi |
| Diagnostics | `record_goal_diagnostics`, `goal_diagnostics_timeline`, `purge_goal_diagnostics` | `goal_diagnostics_v1.sql` | K07 |
| Chung | `update_updated_at_column` | migrations | — |

Ngoài hàm, cần ghi thêm: các constraint của bảng push token hiện chỉ nhận token APNs (kind, environment, topic). M5 cần migration cho FCM (`phase5-assessment-estimate-plan.vi.md` §4.2.1).

---

## 2. Tóm tắt deviation

1. **D6 — Sign in with Apple: EXCLUDED** (Jimmy chốt 04/11). User chỉ có Apple vào Android bằng một trong hai cách: Link Google trên iPhone, hoặc đặt mật khẩu qua "Forgot password". Trong app không có nút "Set password" cho account Apple-only (A10, R4).
2. **D7 — copy "iPhone app" / Apple Health trên Android: OPEN.** Danh sách chỗ Android thực sự thấy ở §6. Danh sách này khác M2 plan ở hai điểm:
   - `NON_NATIVE_NOTE` và nhãn "iPhone app" ở Home **không** hiện trên Android.
   - Settings › Notifications, Word Tracker, thẻ "Connect Apple Health" ở Home và ghi chú Apple Health dưới Icon **có** hiện.
3. **D8 — sửa target Icon: INCLUDED.** Bật capability `iconRevisions` còn mở luôn chế độ target theo thứ khi tạo Icon (`Contract.tsx:1139, 1254`). G3 phải kiểm cả hai luồng (D02, D12).
4. **Pad chữ ký ngang: EXCLUDED.** Android khoá dọc. Ký contract và ký revision đều làm trên canvas dọc (C07).
5. **Word Tracker: EXCLUDED** theo scope §3 (C16, D11, I07).
6. **Live Activity và Dynamic Island: EXCLUDED** ở dạng iOS. Thay bằng:
   - ongoing notification cho phiên tracking do người dùng bấm Start (M4);
   - notification FCM cho Icon (M5).
7. **Health:** chỉ steps, walking distance và approved calories, qua Health Connect hoặc phone (M3–M4). Sáu metric còn lại là EXCLUDED. Trước M3/M4, contract và Icon đo bằng Health mà tạo trên Android sẽ không được xác minh trên Android (R2).
8. **Notification, push và âm thanh native:** notification local ở M4, FCM ở M5.
9. **iCloud Passwords (`SAVE_WEB_CREDENTIAL`) và Flash for alerts: EXCLUDED.** Cả hai chỉ có trên iOS. Riêng iCloud Passwords là đề xuất, cần khách xác nhận.
10. **Testament Timer — lệch mới, M2 plan chưa có:** trên Android, timer không bao giờ tự đóng dấu Honoured (R1). Đề xuất D9 (§8).

---

## 3. Quy ước

| Quyết định | Nghĩa |
|---|---|
| INCLUDED | Android chạy như iOS qua web dùng chung, hoặc native Android đã có hay sẽ có trong M2 |
| ADAPTED | Có trên Android sau M2 nhưng chạy khác iOS (native khác, transport khác, hoặc copy/gate web khác) |
| EXCLUDED | Không làm trên Android: đã chốt, hoặc đề xuất (có ghi rõ) |
| DEFERRED-M3 / M4 / M5 | Thuộc scope Android nhưng làm ở milestone đó. Sau M2 vẫn chưa có |

Cột "Kiểm ở đâu":

- G3: máy Android thật.
- G4: emulator / E2E.
- A*/B*: unit hoặc instrumentation test của task đó trong M2.
- W4: vitest phía web.
- M3/M4/M5: nghiệm thu ở milestone đó.

---

## 4. Web đang phân nhánh theo nền tảng ở đâu

Shell Android có `window.HonouredNative`, nên `hasNativeBridge()` = `true` và `nativePlatform()` = `"android"` (`native-bridge.ts:217–236`). Android vẫn ở `bridgeVersion: 1` (`AppConfig.kt`).

| Chức năng | Gate hiện tại | File | Hệ quả trên Android |
|---|---|---|---|
| Nút Sign in with Apple | `nativePlatform() === "ios"` | `AuthGate.tsx:26–32`, `native-bridge.ts:1416` | Ẩn (D6) |
| Nút Continue with Google | `(capability \|\| !ios)` | `AuthGate.tsx:34` | **Luôn hiện.** Không có capability thì rơi vào OAuth trong WebView (`AuthGate.tsx:201`). R3 |
| Google sign-in / link | Platform ios hoặc android **và** capability `googleSignIn` | `native-bridge.ts:1861` | Theo capability |
| Lưu mật khẩu | `ios && webCredentials.supported` | `native-bridge.ts:2022` | Không có |
| Refresh phiên qua native | `ios && sessionRefresh.supported`; fetch wrapper khoá cứng iOS | `native-bridge.ts:2068`, `native-session-refresh.ts:53` | Đổi ở W1b |
| `SET/CLEAR_AUTH_SESSION` | Gửi cho mọi shell; không nằm trong `TRUSTED_AUTH_TYPES` | `native-bridge.ts:88–101, 254–281` | Đi qua kênh cũ; đổi ở W1a |
| Live Activities | `ios && liveActivities.supported` | `native-bridge.ts:1707` | Không gửi |
| Word Tracker | `ios && wordTracker.supported` | `native-bridge.ts:2160` | Không có |
| Icon revision + target theo thứ khi tạo | **Chỉ capability**, không xét platform | `native-bridge.ts:2339`, `IconRevision.tsx:161` | Bật khi Android báo capability (D8); web không phải sửa |
| Landscape | `ios` | `native-bridge.ts:1069` | Không gửi |
| Notification status / permission / settings | `ios` | `native-bridge.ts:1362–1379`, `Settings.tsx:534, 638` | Hiện "Available in the iPhone app" |
| Mục Health & Tracking, bước Health ở onboarding | `platform === "ios"` | `health-settings.ts:38, 51` | Ẩn |
| Trạng thái Health ở Home / Contract | `hasNativeBridge()` | `health-connection.ts`, `Home.tsx:436–438` | Native trả `ERROR` → state `unknown` → thẻ "Connect Apple Health" (R5) |
| Ai giữ đồng hồ Testament Timer | `hasNativeBridge()` | `timer-store.ts:104, 121, 132, 141, 159, 204` | Web chờ `TIMER_COMPLETED`, nhưng Android không bao giờ gửi (R1) |
| Dòng tiến độ đo bằng Health | `hasNativeBridge()` | `Contract.tsx:591, 884` | Hiện "… · no Health data yet" |
| Ghi chú `NON_NATIVE_NOTE` dưới Icon | `!hasNativeBridge()` | `ActiveIcons.tsx:136` | Không hiện |
| Nút mua gói | `hasNativeBridge()` | `PlanSurface.tsx:549` | Bật |
| Link quản lý gói | User agent | `PlanSurface.tsx:593` | Google Play |

---

## 5. Parity matrix

### A. Tài khoản và đăng nhập

| # | Workflow | iOS hiện tại | Android sau M2 | Quyết định | Lý do / ghi chú | Kiểm ở đâu |
|---|---|---|---|---|---|---|
| A01 | Đăng ký email + mật khẩu (tick Terms) | `SignUp` (`Auth.tsx`) → `supabase.auth.signUp`; trigger `handle_new_user` tạo `profiles`; xong thì gửi `SAVE_WEB_CREDENTIAL` | Web như iOS, không có lời mời lưu mật khẩu. Phiên được giao cho native qua `HonouredAuth` (W1a) | INCLUDED | Web dùng chung; lưu mật khẩu xem A03 | G3 (D5), G4 |
| A02 | Đăng nhập email + mật khẩu | `SignIn` → `signInWithPassword`; Passwords tự điền (`webcredentials:` associated domain) | Web như iOS. Android Autofill có thể tự điền (cần xác nhận) | INCLUDED | | G3, G4 |
| A03 | Lưu mật khẩu vào iCloud Passwords | `SAVE_WEB_CREDENTIAL` (`WebCredentialSaver.swift`), capability `webCredentials` | Web không gửi; native không có | EXCLUDED | Chỉ iOS (Associated Domains). Không có trong danh sách Excluded §3 của scope, nên là đề xuất, cần khách xác nhận | — |
| A04 | Quên / đặt lại mật khẩu | `ForgotPassword` → `resetPasswordForEmail({ redirectTo: <origin>/reset })` (`Auth.tsx:361`); link trong email mở trình duyệt | Như iOS: link mở trình duyệt | INCLUDED | Cả hai nền tảng đều không có universal link / App Link cho `/reset` | G3 |
| A05 | Đổi mật khẩu khi đã đăng nhập | `ChangePassword` xác thực lại rồi `updateUser`; chỉ hiện khi có identity `email` (`Auth.tsx:54, 77`) | Như iOS | INCLUDED | | G3 (tuỳ chọn) |
| A06 | Continue with Google | `SYNC_AUTH_CONTEXT` + `SIGN_IN_WITH_GOOGLE` (GIDSignIn) → `signInWithIdToken` | Đã có Credential Manager qua `HonouredAuth` (`AuthBridge.kt`); capability `googleSignIn` có intents `sign_in`, `link`. Cần D4: OAuth client SHA-1; `GOOGLE_WEB_CLIENT_ID` đang trống | INCLUDED | R3: thiếu capability hợp lệ thì web vẫn hiện nút và chuyển OAuth trong WebView | Unit `GoogleAuthCoreTest` (11 test), G3 sau D4 |
| A07 | Sign in with Apple | `SIGN_IN_WITH_APPLE` (`AppleSignInCoordinator.swift`); nút chỉ hiện trên iOS | Không có nút, không có message | EXCLUDED | D6. Production có 2 user chỉ dùng Apple → xem A10 | G3 (qua A10) |
| A08 | Xử lý khi Apple thu hồi credential | `APPLE_CREDENTIAL_REVOKED` lúc launch và khi đang chạy | Không áp dụng | EXCLUDED | Theo D6 | — |
| A09 | Link Google (Settings › Account) | `GoogleRow` → `SIGN_IN_WITH_GOOGLE { intent: "link" }` → `linkIdentity` | Như iOS; capability Android đã có `link` | INCLUDED | Đây cũng là đường chính của D6, nhưng làm trên iPhone | G3 |
| A10 | User chỉ có Apple chuyển sang Android | — | Đăng nhập bằng Google hoặc email sau khi làm một việc trên iPhone: (a) Link Google; hoặc (b) đăng xuất, "Forgot password" với email của account (thường là email relay Apple) để đặt mật khẩu | ADAPTED | Không có "Set password" cho account Apple-only. (b) cần xác nhận Supabase cho phép. Đăng nhập Google khi chưa link có thể tạo account mới trống (cần xác nhận). R4 | G3 |
| A11 | Email updates (opt-in marketing) | Checkbox lúc sign-up, không tick sẵn → `record_signup_marketing_opt_in` (Google/Apple qua pending opt-in); Settings › Account › Email updates → `set_marketing_opt_in` | Như iOS | INCLUDED | Thuần web + server | G3 smoke |
| A12 | Đăng xuất | `performSignOut` (`sign-out.ts`): huỷ Google flow, `LOGOUT_USER`, `signOut({ scope: "local" })`, `SYNC_AUTH_CONTEXT(null)` + `CLEAR_GOOGLE_SIGN_IN`, `CLEAR_AUTH_SESSION` (xoá Keychain, queue, anchors, push token, card) | Web như iOS. Native: `CLEAR_AUTH_SESSION` chỉ qua `HonouredAuth`; xoá `SessionStore`, event queue và broadcast đang chờ (B1, B5); RevenueCat logout như hiện tại | INCLUDED | Phần dọn health/push sẽ đăng ký vào `AccountScopedRegistry` ở M4/M5 | Unit B5, G4 E2E |
| A13 | Xoá tài khoản | `deleteAccount` (server, xoá mềm 30 ngày; chặn khi subscription còn chạy; revoke Apple phía server); `CLEAR_WORD_SOURCES` nếu có | Như iOS (không có Word Tracker) | INCLUDED | | G4, chỉ trên account test riêng |
| A14 | Khôi phục tài khoản trong 30 ngày | `AccountDeletionNotice` → `restore_account` | Như iOS | INCLUDED | | G4 (tuỳ chọn) |
| A15 | Đổi tài khoản trên cùng máy | Store web theo user (`stateKeyForUser`). `SET_AUTH_SESSION` của user khác dọn queue, anchors, goals, card, push token. RevenueCat `IDENTIFY_USER` | Web như iOS. Native gọi `sessionOwnerChanged` + `AccountScopedRegistry.clearAll()` trước khi lưu phiên (B5) | INCLUDED | | Unit B5/B6, G4 E2E 2 tài khoản (D5) |
| A16 | Phiên native, native là nơi duy nhất refresh | `SET/CLEAR_AUTH_SESSION`, `REFRESH_AUTH_SESSION`, capability `sessionRefresh` (`AuthSessionStore.swift`, `SessionRefresh.swift`) | `SessionStore` (Keystore AES-GCM), `SessionRefresher`, capability `sessionRefresh { transport: "trusted-auth-v1" }`; web W1a/W1b | ADAPTED | Cùng protocol; khác transport (`HonouredAuth`) và nơi giữ khoá. Là nền cho sync M4 | Unit B1–B3/B6, W4, G4 (≥ 2 vòng hết hạn token) |
| A17 | Onboarding (giới thiệu + bước Health) | `Onboarding.tsx`; bước "Let Apple Health keep the record" khi `healthSetupOffer` = `offer` | Chỉ có phần giới thiệu; bước Health bị bỏ (`health-settings.ts:51`) | INCLUDED | Bước Health Connect làm ở M3 | G3 |

### B. Home

| # | Workflow | iOS hiện tại | Android sau M2 | Quyết định | Lý do / ghi chú | Kiểm ở đâu |
|---|---|---|---|---|---|---|
| B01 | "Your contracts": card contract đang chạy, mở chi tiết, "Sign a contract", "View history" | `Home.tsx` (`ActiveContractCard`, `ExistingContractView`); mở card thì gửi `TRACK_CONTRACT` | Web như iOS; không gửi `TRACK_CONTRACT` | INCLUDED | | G3 |
| B02 | Hàng Icon ở Home | `HomeIconsRow` (chỉ xem, bấm mở tab Contract) | Như iOS | INCLUDED | | G3 |
| B03 | "At a glance": ô Health, "Health · Updated…", "See all" | `health_daily` (`useHealthOverview`) + `QUERY_HEALTH_METRICS`, `HEALTH_LIVE_TOTALS`, `HEALTH_DATA_UPDATED` | `QUERY_HEALTH_METRICS` → `ERROR`. Chỉ thấy `health_daily` khi iPhone cùng account đã sync; còn lại để trống | DEFERRED-M3 | Đọc Health Connect ở M3, sync nền ở M4 | M3 |
| B04 | Thẻ "Connect Apple Health" + nút Set up | Hiện khi chưa có số liệu; Set up → `REQUEST_HEALTH_PERMISSION` | `GET_HEALTH_STATUS` → `ERROR` → state `unknown`, nên hiện "Connect Apple Health" với nút Set up bấm không có tác dụng (`Home.tsx:436–438, 512–533`) (cần xác nhận) | DEFERRED-M3 | Thẻ Health Connect làm ở M3. Trong M2 nên ẩn hoặc đổi copy qua W3 (D7). R5 | G2/W3, G3 |
| B05 | Dòng nguồn ("Steps & distance · …") và ước tính kcal từ Core Motion | `GET_HEALTH_SOURCES`, `estimates.walking_running_energy` | Không hiện | DEFERRED-M3 | Nhãn nguồn Health Connect làm ở M3. Không dùng ước tính kcal (scope §5.6) | M3 |
| B06 | Kéo xuống để refresh | `PullToRefresh` (web) | Như iOS | INCLUDED | | G3 |

### C. Contract

| # | Workflow | iOS hiện tại | Android sau M2 | Quyết định | Lý do / ghi chú | Kiểm ở đâu |
|---|---|---|---|---|---|---|
| C01 | Một hoạt động (danh sách, Custom…, dùng gần đây) | `Contract.tsx` | Như iOS | INCLUDED | | G3 |
| C02 | Hai hoạt động ("Also —") | Slot `secondary` | Như iOS | INCLUDED | Icon không có slot thứ hai | G3 |
| C03 | Target, đơn vị, mặc định 0, kiểm khi ký | `UNIT_RULES` (`target-units.ts`), `targetSignError`: mọi slot đo được phải có target do người dùng nhập | Như iOS | INCLUDED | Logic web, đã có vitest | Vitest, G3 |
| C04 | Because… (bắt buộc) | "Because… must be filled." | Như iOS | INCLUDED | | G3 |
| C05 | Deadline | `defaultDeadline(dayResetHour)`; chặn deadline đã qua | Như iOS | INCLUDED | | G3 |
| C06 | Ký trên màn dọc | `SignatureCanvas` → bucket `signatures` | Như iOS (touch trong WebView) | INCLUDED | M2 plan G3: "Chữ ký (dọc)" | G3 máy thật |
| C07 | Pad chữ ký ngang toàn màn | `SET_LANDSCAPE_ALLOWED` khi mở Contract; xoay máy thì hiện `LandscapeSignaturePad` hoặc `IconRevisionFlow landscape` | Manifest `screenOrientation="portrait"`; `sendLandscapeAllowed` chỉ gửi trên iOS (`native-bridge.ts:1069`) | EXCLUDED | Deviation đã nêu trong M2 plan. Ký dọc vẫn đủ cho cả contract lẫn revision | G3 (xoay máy không có gì thay đổi) |
| C08 | Hộp "Signing philosophy" trước khi ký | `SigningPhilosophyDialog` | Như iOS | INCLUDED | | G3 |
| C09 | Standing contract (lặp mỗi ngày, huỷ) | `rollStandingContracts`; huỷ thì thành broken | Như iOS | INCLUDED | | G3 |
| C10 | Go again (Icon đã xong → soạn lại) | Điền sẵn điều khoản, không mang theo chữ ký | Như iOS | INCLUDED | | G3 |
| C11 | Testament Timer: bắt đầu, pause/resume, tự xong thì Honoured | `START_TIMER`, `CANCEL_TIMER`, `GET_TIMER_STATE`, `TIMER_COMPLETED`; native giữ đồng hồ (`TestamentTimer.swift`) | Hiện tại: Android trả `ERROR`. Web vẫn đếm ngược, nhưng `resolveFinishedTimer` thoát sớm khi có bridge (`timer-store.ts:159`), nên timer **không bao giờ** đóng dấu Honoured (cần xác nhận). Sau M2: tuỳ D9 | ADAPTED | Đề xuất D9 (§8): trong M2, web tự hoàn thành timer khi app đang mở, gate theo capability. Engine nền + notification làm ở M4 (E). R1 | G4, G3, M4 |
| C12 | Pill đếm giờ ở đầu màn (Settings › "Challenge Timer") | `DynamicIsland.tsx`: phần web mô phỏng, bật/tắt bằng `state.dynamicIsland` | Như iOS: pill nằm trong web, không phải Dynamic Island hệ thống | INCLUDED | Kiểm vị trí so với status bar (L03) | G3 |
| C13 | Dòng tiến độ Health trên contract | `useMeasuredContract`, `QUERY_HEALTH_METRICS`, `HEALTH_LIVE_TOTALS` | Hiện "… · no Health data yet" (`Contract.tsx:591`, `health-display.ts:42`) | DEFERRED-M3 | | M3 |
| C14 | Contract Health tự Honoured khi mọi slot đạt | `SET_GOALS` → `GOAL_REACHED` (`GoalMonitor.swift`) | Không có `GOAL_REACHED`. Contract Health tạo trên Android sẽ BROKEN ở deadline, trừ khi iPhone cùng account chấm (cần xác nhận) | DEFERRED-M4 | E: đánh giá goal + hoàn thành idempotent. R2 | M4 |
| C15 | Mời kết nối Health trong composer / contract | `HealthConnectNudge` ("Apple Health can measure this"); nút "Connect Apple Health" khi state là `connect` | Không hiện vì state là `unknown` | DEFERRED-M3 | | M3 |
| C16 | Contract Writing đếm bằng số từ (Word Tracker) | `SELECT_WORD_SOURCE` …; capability `wordTracker`, chỉ iOS | Chọn đơn vị "words" thì thấy "Available in the iPhone app" và không ký được | EXCLUDED | Scope §3 Excluded. Copy thuộc D7 | G3 |
| C17 | Màn hoàn thành + tiếng gong | `CompletionMoment`; gong bằng Web Audio (`gong.ts`) | Như iOS | INCLUDED | | G3 |
| C18 | Locked commitment / màn Restriction (cũ) | `RestrictionScreen` + "Did you honour it?" | Như iOS | INCLUDED | Composer không còn bật `locked` (không có lệnh `setLocked`), nên chỉ gặp ở contract cũ. Lưới app dùng tên app iOS | — |

### D. Icon

| # | Workflow | iOS hiện tại | Android sau M2 | Quyết định | Lý do / ghi chú | Kiểm ở đâu |
|---|---|---|---|---|---|---|
| D01 | Tạo Icon: chọn thứ, giờ chốt, nhắc sáng/tối | Composer Icon; `contracts_icon_days` / `icon_schedule` sinh các dòng `icon_days` | Như iOS | INCLUDED | | G3 |
| D02 | Target khác nhau theo thứ khi tạo Icon | Lựa chọn "different days" chỉ có khi `iconRevisionsSupported()` (`Contract.tsx:1139, 1254`) → `contracts.icon_day_targets` | Hiện tại không có. Sau M2 có, vì Android báo `iconRevisions.supported: true` (D8) | INCLUDED | Hệ quả của D8, plan chưa ghi. Card/notification Android sau này phải dùng `icon_days.target_text` | A5 unit (JSON capability), G3 |
| D03 | Chặn trùng ngày giữa Icon và contract | `dayConflict` + trigger `contracts_icon_reserve` | Như iOS | INCLUDED | | G3 |
| D04 | Sửa giờ nhắc Icon (Settings › Icon reminders) | `IconReminderEditor` → `setIconReminders` | Như iOS: lưu được, nhưng chưa có push | INCLUDED | Việc gửi nhắc nằm ở D05 | G3 |
| D05 | Push nhắc sáng/tối, kết quả, kết thúc Icon | Server `icon_push_*` gửi qua APNs; app gọi `register_push_token` | Không có | DEFERRED-M5 | F: FCM + mở rộng schema token, hiện chỉ nhận APNs | M5 |
| D06 | Card Icon trên màn khoá (Live Activity do push mở) | `IconCardCoordinator.swift`, push-to-start, cache chữ ký `SYNC_ICON_REVISIONS` | Không có | DEFERRED-M5 | Chuyển thành notification FCM, không có card. Dùng target của từng ngày (D8) | M5 |
| D07 | Xác minh ngày Icon bằng HealthKit | `IconVerifier.swift`: `icon_days_to_measure` → đọc HealthKit → `record_icon_measurements`; broadcast `ICON_DAYS_UPDATED` | Không có. Icon Health tạo trên Android chỉ được chấm khi iPhone cùng account đọc; không thì sau 24 h thành BROKEN `no_data` | DEFERRED-M4 | Cần: đọc Health Connect (M3), phiên native (M2), và giá trị `source` mới cho `record_icon_measurements` (hiện nhận `healthkit`, `core_motion`, `healthkit_iphone`) — phần D: SQL compatibility. R2 | M4 |
| D08 | Ghi chú dưới Icon đo bằng Health | `measuredNotes` (`icon-days.ts:274–290`): "Waiting for Apple Health data…", "No Apple Health data was recorded…"; `NON_NATIVE_NOTE` khi không có bridge | Hai câu Apple Health có hiện; `NON_NATIVE_NOTE` không hiện (`ActiveIcons.tsx:136`) | ADAPTED | Đổi copy theo capability (W3, D7) | G2, W4 |
| D09 | Tự báo cáo ngày Icon (Yes/No) | `self_report_icon_day`, tới 24 h sau giờ chốt | Như iOS | INCLUDED | | G3 |
| D10 | Timer cho ngày Icon tính bằng phút | Như C11; `completeIconTimer` sau `TIMER_COMPLETED` | Cùng lỗi C11. Thêm: timer còn nằm trong store thì prompt tự báo cáo hôm nay bị ẩn (`ActiveIcons.tsx:151`) | ADAPTED | Theo D9. R1 | G4, G3, M4 |
| D11 | Icon Word Tracker (Check now / Reconnect, nhắc trước giờ chốt) | `READ_WORD_SOURCE`, `record_word_reading`, `SET_WORD_REMINDERS` | Icon tạo trên iPhone: xem được tiến độ từ `icon_days`, kèm "Available in the iPhone app". Không tạo mới được | EXCLUDED | Scope §3 | G3 |
| D12 | Sửa target (theo thứ) + ký lại | `revise_icon_target` / `revise_icon_targets`, chữ ký `<uid>/<client_id>/revisions/`, sau đó `SYNC_ICON_REVISIONS` | Có "Revise target". `SYNC_ICON_REVISIONS` → `ICON_REVISIONS_SYNCED { synced: true }` | INCLUDED | D8. Web chỉ gate theo capability (`native-bridge.ts:2339`), không phải sửa | A5 unit, G3 (ký dọc) |
| D13 | Active Icon thu gọn, lịch sử revision, dòng Today, chấm ngày (M1) | `ActiveIconItemView.tsx`, `IconRevision.tsx` | Như iOS. Trước M2 Android chỉ có End early | INCLUDED | | G3 |
| D14 | End early | `endIconEarly` + hộp xác nhận; iOS dừng cả card | Như iOS, không có card | INCLUDED | | G3 |
| D15 | Recap / Icon moment | `IconMoment.tsx`, `icon-recap.ts` | Như iOS | INCLUDED | | G3 |

### E. Journal

| # | Workflow | iOS hiện tại | Android sau M2 | Quyết định | Lý do / ghi chú | Kiểm ở đâu |
|---|---|---|---|---|---|---|
| E01 | Ghi chép chữ: viết, sửa, đổi tên, xoá, đồng bộ | `Journal.tsx`, bảng `journal_entries` | Như iOS | INCLUDED | | G3 |
| E02 | Gợi ý viết theo contract | `POST_PROMPTS` | Như iOS | INCLUDED | | G3 |
| E03 | Ghi âm Voice of Change (và ghi lại) | `getUserMedia` + `MediaRecorder` trong WKWebView | `onPermissionRequest` → xin `RECORD_AUDIO` (`MainActivity.kt:101–123`), chỉ cho origin của web app. Nếu người dùng từ chối hẳn, web chỉ hiện lỗi thô, không có đường mở Settings | INCLUDED | M2 plan G3: từ chối rồi bật lại. R8 | G3 |
| E04 | Phát lại ghi âm, kể cả bản ghi từ máy khác | Bucket `voice-memos`, thẻ `<audio>` | Android ghi `audio/webm` (Opus); iOS ghi theo `rec.mimeType` (thường là `audio/mp4`) | INCLUDED | Phát chéo nền tảng chưa kiểm (R7) | G3 |

### F. History

| # | Workflow | iOS hiện tại | Android sau M2 | Quyết định | Lý do / ghi chú | Kiểm ở đâu |
|---|---|---|---|---|---|---|
| F01 | Danh sách mặc định 7 ngày ("Last 7 days") | `history-entries.ts` (M1) | Như iOS | INCLUDED | M1 dùng chung | G3 |
| F02 | Xem theo ngày + "Back to recent history" | `History.tsx` mode recent/day | Như iOS | INCLUDED | | G3 |
| F03 | Lọc theo trạng thái (giữ qua hai chế độ) | Filter web | Như iOS | INCLUDED | | G3 |
| F04 | Vuốt đổi tháng, mũi tên, chọn tháng | `calendar-swipe.ts` | Như iOS | INCLUDED | M1 mới kiểm Chromium CDP và iPhone; cần kiểm touch thật trên Android WebView | G3 |
| F05 | Sheet ngày (bấm ô có màu) | `HistoryDayCell` (`aria-expanded`) | Như iOS | INCLUDED | | G3 |
| F06 | Kéo để refresh, bấm card mở contract | `PullToRefresh` | Như iOS | INCLUDED | | G3 |

### G. Settings

| # | Workflow | iOS hiện tại | Android sau M2 | Quyết định | Lý do / ghi chú | Kiểm ở đâu |
|---|---|---|---|---|---|---|
| G01 | Tên (Your name) | `saveDisplayName` → `profiles` | Như iOS | INCLUDED | | G3 |
| G02 | Giờ reset hằng ngày | Store + `set_reset_timezone`; gửi `SET_DAY_RESET_HOUR` cho native | Phần web như iOS; native trả `ERROR` (vô hại) | INCLUDED | Native cần giờ này từ M3 (C: truy vấn theo ngày/giờ reset) | G3 |
| G03 | Health & Tracking (Automatic / iPhone / Core Motion) | `HealthTracking.tsx`; `GET_HEALTH_SOURCES`, `SET_HEALTH_SOURCE_PREFERENCE`, `REQUEST_MOTION_PERMISSION` | Mục bị ẩn (`healthTrackingVisible` = `false` khi platform không phải iOS) | DEFERRED-M3 | Chuyển thành Automatic / Phone (Health Connect, `TYPE_STEP_COUNTER`). Web chuyển sang gate theo capability `healthConnect` | M3 |
| G04 | Notifications: trạng thái, xin quyền, mở Settings | `GET_NOTIFICATION_STATUS`, `REQUEST_NOTIFICATION_PERMISSION`, `OPEN_NOTIFICATION_SETTINGS` | Hiện "Available in the iPhone app" (`Settings.tsx:584`) | DEFERRED-M4 | E: channel, quyền API 33, trạng thái. Copy thuộc D7 | M4; G2 (copy) |
| G05 | Flash for alerts | Hướng dẫn mở Settings của iOS | Ẩn | EXCLUDED | Là cài đặt trợ năng của iOS | — |
| G06 | Completion sound | Toggle → `SET_SOUND_ENABLED`; gong trong web + âm thanh notification native | Gong trong app chạy; native trả `ERROR` | INCLUDED | Âm thanh notification ở I05 (M4) | G3 |
| G07 | Export my history | Tạo blob JSON + `a.download` | Shell chưa có `DownloadListener`: có thể không lưu file mà vẫn báo "Export saved." (cần xác nhận; kiểm luôn iOS) | INCLUDED | R6 | G3 |
| G08 | Reset everything | Xoá `contracts`, `journal_entries`, storage và dữ liệu local | Như iOS | INCLUDED | | G4 (account test) |
| G09 | About: Privacy, Terms, Journeys, Website, X, Version | `LegalSheet`; link ngoài mở trình duyệt | Như iOS (`shouldOverrideUrlLoading` → `ACTION_VIEW`). Version là chuỗi web "1.0.0", không phải version app | INCLUDED | Privacy hiện chỉ nói tới Apple Health; phải sửa trước khi nộp Play (M5, R12) | G3 |

Các mục Settings khác có hàng riêng: Subscription (H), Account / Email updates / Delete account (A), Icon reminders (D04), Challenge Timer (C12).

### H. Billing

| # | Workflow | iOS hiện tại | Android sau M2 | Quyết định | Lý do / ghi chú | Kiểm ở đâu |
|---|---|---|---|---|---|---|
| H01 | Gắn RevenueCat với user | `IDENTIFY_USER` / `LOGOUT_USER` | Đã có (`SubscriptionService.kt`) | INCLUDED | | G4 |
| H02 | Kiểm quyền Honoured+ | `CHECK_ACCESS` → `ACCESS_STATUS`; server `get_access_state`; webhook RevenueCat (nhận cả `PLAY_STORE`) | Đã có | INCLUDED | | G4 |
| H03 | 12 phiên miễn phí, chặn khi hết | `start_session`, `SessionBlocked` | Như iOS | INCLUDED | | G3 |
| H04 | Mua Honoured+ (tháng / năm) | `START_PURCHASE` với `$rc_monthly` / `$rc_annual` | Code đã có; chưa có sản phẩm Play và offering production | DEFERRED-M5 | H: mapping sản phẩm + E2E. Giá "$4.99" / "$19" đang viết cứng trong web (R11) | M5 |
| H05 | Khôi phục giao dịch | `RESTORE_PURCHASES` | Code đã có | DEFERRED-M5 | H | M5 |
| H06 | Quản lý gói | Link App Store hoặc Google Play, chọn theo user agent | Link Google Play | INCLUDED | | G3 |
| H07 | Người mua trên iOS đăng nhập Android | RevenueCat app user id = Supabase uid | Tuỳ cấu hình RevenueCat (cần xác nhận) | DEFERRED-M5 | Assessment §6 Phase 7, bước 5 | M5 |

### I. Notifications và âm thanh

| # | Workflow | iOS hiện tại | Android sau M2 | Quyết định | Lý do / ghi chú | Kiểm ở đâu |
|---|---|---|---|---|---|---|
| I01 | Xin quyền notification (lần đầu có timer / goal) | Sau `START_TIMER` / `SET_GOALS` đầu tiên | Không có; chưa khai báo `POST_NOTIFICATIONS` | DEFERRED-M4 | | M4 |
| I02 | Notification khi timer hết giờ | `timer-<activityId>` tại `endsAt` | Không có | DEFERRED-M4 | | M4 |
| I03 | Notification khi đạt goal | `goal-<activityId>-<day>`, khi app không active | Không có | DEFERRED-M4 | | M4 |
| I04 | Bấm notification mở đúng hoạt động | `NOTIFICATION_OPENED` qua hàng đợi bền | M2 đã có hàng đợi bền (B4) và deep link (A3), nhưng chưa có notification nào | DEFERRED-M5 | F: payload + deep link | M5 |
| I05 | Âm thanh notification (gong) | `gong.caf`, `SOUND_STATE.gongBundled`; tôn trọng nút gạt im lặng | Không có | DEFERRED-M4 | Đặt âm thanh theo channel | M4 |
| I06 | Gong trong app | Web Audio (`gong.ts`) | Chạy; trên Android theo âm lượng media, không có khái niệm nút gạt im lặng (cần xác nhận) | INCLUDED | | G3 |
| I07 | Nhắc trước giờ chốt cho Word Tracker | `SET_WORD_REMINDERS` | Không có | EXCLUDED | Theo Word Tracker | — |
| I08 | Đăng ký push token | `register_push_token` / `unregister_push_tokens` (APNs) | Không có | DEFERRED-M5 | Schema token hiện chỉ nhận APNs | M5 |

### J. Live Activities

| # | Workflow | iOS hiện tại | Android sau M2 | Quyết định | Lý do / ghi chú | Kiểm ở đâu |
|---|---|---|---|---|---|---|
| J01 | Card Live Activity của contract đang chạy | `TRACK_CONTRACT`, `SYNC_TRACKED_CONTRACTS`, `STOP_TRACKING_CONTRACT`, `GET_LIVE_ACTIVITY_STATE`; capability `liveActivities` | Native trả `not_implemented`. Web không gửi (gate iOS + capability) | DEFERRED-M4 | Chuyển thành ongoing notification / foreground service, chỉ cho phiên tracking người dùng bấm Start (scope §3 Adapted) | M4 |
| J02 | Dynamic Island hệ thống | ActivityKit | Không có tương đương | EXCLUDED | | — |
| J03 | Bấm card để mở contract | `honoured://contract/<id>?day=&occurrence=` → `LIVE_ACTIVITY_OPENED` | `honoured://contract/<id>?day=` → `CONTRACT_LINK_OPENED` (A3, W2). M2 mới có hạ tầng; link thật đầu tiên đến từ notification ở M4/M5 | ADAPTED | | Unit parser, `adb shell am start -d …` (A3) |

### K. Health và đồng bộ nền

| # | Workflow | iOS hiện tại | Android sau M2 | Quyết định | Lý do / ghi chú | Kiểm ở đâu |
|---|---|---|---|---|---|---|
| K01 | Quyền Health + trạng thái | `REQUEST_HEALTH_PERMISSION`, `GET_HEALTH_STATUS` (kèm `hasRecentData`) | Trả `ERROR` | DEFERRED-M3 | Health Connect + disclosure | M3 |
| K02 | Đọc steps, walking distance, calories | HealthKit (`HealthKitService.swift`) | Không có | DEFERRED-M3 | Health Connect aggregate / phone | M3 |
| K03 | Sáu metric còn lại: cycling, swimming, basal energy, heart rate, exercise minutes, sleep | HealthKit | Không có | EXCLUDED | Scope chỉ có 3 metric (assessment §1.2, §4.2.2) | — |
| K04 | Đếm bước trực tiếp từ điện thoại, cập nhật live | Core Motion, `HEALTH_LIVE_TOTALS` | Không có | DEFERRED-M3 | Chuyển thành Health Connect on-device / `TYPE_STEP_COUNTER` | M3 |
| K05 | Sync nền lên `health_samples` / `health_daily` | HealthKit observer, `BGAppRefreshTask`, offline queue, `upsert_health_*`, `HEALTH_DATA_UPDATED` | Không có | DEFERRED-M4 | D: queue bền, client Supabase native (dùng phiên của M2) | M4 |
| K06 | Đối soát deadline khi dữ liệu đến muộn | Server chấm điểm + đọc lại tới 30 ngày | Không có | DEFERRED-M4 | E | M4 |
| K07 | Goal diagnostics | `record_goal_diagnostics` | Không có | EXCLUDED | Công cụ chẩn đoán nội bộ (cần xác nhận) | — |
| K08 | Motion probe (màn ẩn trên TestFlight) | `MotionProbe/*` | Không có | EXCLUDED | M3 có probe riêng cho Pixel / Samsung (C) | — |

### L. Shell Android

| # | Workflow | iOS hiện tại | Android sau M2 | Quyết định | Lý do / ghi chú | Kiểm ở đâu |
|---|---|---|---|---|---|---|
| L01 | Loading, lỗi mạng, Retry, timeout | `WebViewLoadState.swift` | Đã có (`MainActivity.kt`, timeout 30 s) | INCLUDED | | G3 |
| L02 | Nút Back hệ thống | iOS không có | `canGoBack()` thì `goBack()`, không thì `finish()`. App một trang nên Back thường thoát app chứ không đóng sheet (cần xác nhận) | ADAPTED | Quyết định ở G3: giữ nguyên, hay đóng sheet / về Home trước | G3 |
| L03 | Edge-to-edge / safe area (targetSdk 35) | `env(safe-area-inset-*)` trong WKWebView | Chưa xử lý insets | ADAPTED | A4 | Ảnh chụp A4, G3 |
| L04 | Renderer crash, process death, cold start | iOS reload | `onRenderProcessGone`; load lại URL (A4) | ADAPTED | | A4 |
| L05 | Link ra ngoài (website, X, Google Play, mailto) | Mở Safari | `ACTION_VIEW`; bỏ qua nếu máy không có app xử lý | INCLUDED | | G3 |

---

## 6. Copy iPhone / Apple mà Android thấy (D7)

Gom từ code `df0dc04d`. "Android thấy" là đánh giá theo gate ở §4.

| # | Chỗ | Copy | File | Android thấy? | Ghi chú |
|---|---|---|---|---|---|
| 1 | Settings › Notifications | "Available in the iPhone app" | `Settings.tsx:584` (`notification-toggle.ts` trả `web` khi không phải iOS) | **Có** | M2 plan chưa liệt kê. Đổi theo capability `notifications` |
| 2 | Composer, chọn Writing + words → dòng Writing source | "Available in the iPhone app" | `Contract.tsx:1952` (`WORD_IPHONE_ONLY`) | **Có** | Word Tracker EXCLUDED: nên ẩn đơn vị "words" trên Android, hoặc copy "Not available on Android" |
| 3 | Lỗi khi ký Icon tính bằng words | "Available in the iPhone app" | `word-tracker.ts:40` | **Có** | Như #2 |
| 4 | Icon Word Tracker tạo trên iPhone | "Available in the iPhone app" | `ActiveIcons.tsx:242` | **Có** | Chỉ xem |
| 5 | Home, khi chưa có số liệu Health | "Connect Apple Health" / "Steps, heart rate, energy and minutes will show here." + nút Set up không có tác dụng | `Home.tsx:512–533` | **Có** (cần xác nhận) | R5 |
| 6 | Ghi chú dưới Icon Health | "Waiting for Apple Health data — results settle…" / "No Apple Health data was recorded for … Settings › Health › Data Access & Devices › Honoured." | `icon-days.ts:274–279` | **Có** | D08 |
| 7 | Dòng tiến độ contract Health | "… · no Health data yet" | `health-display.ts:42` | **Có** | Copy chung nhưng gây hiểu lầm trên Android (C13) |
| 8 | Privacy Policy | "Health and fitness data (iPhone only…)" | `LegalDocument.tsx:17, 29` | **Có** | Đúng sự thật cho tới M3; sửa trước khi nộp Play (M5) |
| 9 | Màn Restriction (contract locked cũ) | Tên app iOS (Safari, Wallet, Health…) | `Restriction.tsx` | Chỉ với contract cũ | Ưu tiên thấp |
| 10 | `NON_NATIVE_NOTE` | "Results are verified by the Honoured iPhone app." | `icon-days.ts:276` | **Không** (gate `hasNativeBridge()`) | M2 plan D7 ghi là có. Nếu W3 đổi gate thì cần copy riêng cho Android |
| 11 | Nhãn Home | "iPhone app" | `Home.tsx:538` | **Không** (chỉ ở `web_preview`) | Như #10 |
| 12 | Settings › Health & Tracking | "Available in the iPhone app" | `Settings.tsx:754` | **Không** (mục bị ẩn) | Hiện lại ở M3 |
| 13 | `BROWSER_SOURCE_COPY` | "Source choice is available only in the iPhone app." | `health-source.ts:33` | **Không** | |
| 14 | `NOT_NATIVE` ở PlanSurface | "Available in the iPhone and Android app" | `PlanSurface.tsx:30` | **Không** (chỉ trình duyệt) | |

---

## 7. Rủi ro phát hiện

| ID | Mức | Rủi ro | Evidence | Đề xuất |
|---|---|---|---|---|
| R1 | Cao | Trên Android, Testament Timer chạy về 0 nhưng contract không bao giờ được đóng dấu Honoured; contract BROKEN ở deadline. Timer cũ còn nằm trong localStorage làm ẩn prompt tự báo cáo hôm nay của Icon | `timer-store.ts:159` (thoát sớm khi `hasNativeBridge()`), `:204` (`GET_TIMER_STATE` → `ERROR` → không dọn); `NativeBridge.kt` nhánh `else`; `ActiveIcons.tsx:151` | D9 (§8). Kiểm trên emulator trước khi demo G3 (cần xác nhận) |
| R2 | Cao | Contract / Icon Health tạo trên Android không được xác minh tới M3/M4: contract BROKEN ở deadline, ngày Icon BROKEN `no_data` sau 24 h. Icon Health không cho tự báo cáo | `selfReportableDays` loại Icon có `metric` (`icon-days.ts`); `record_icon_measurements` chỉ được iOS gọi | Khách quyết (W6): tới M3/M4, trên Android cảnh báo hoặc chặn target đo bằng Health, hoặc chỉ ghi chú. Ghi trong tracker M2 |
| R3 | Trung bình | Android không có capability `googleSignIn` hợp lệ (`GOOGLE_WEB_CLIENT_ID` trống, hoặc WebView thiếu `WEB_MESSAGE_LISTENER`) thì web vẫn hiện nút Google và chạy OAuth trong WebView. Trang Google là host khác nên shell mở trình duyệt ngoài, và app vẫn chưa đăng nhập | `AuthGate.tsx:34, 201`, `MainActivity.kt:249–264` | Guard bản release ở A2 (thiếu Google config thì fail). W5: chỉ dùng OAuth web khi `nativePlatform() === null` |
| R4 | Trung bình | User chỉ có Apple (2 người ở production): không có "Set password" trong app. Đăng nhập Google mà chưa link có thể tạo account mới trống (cần xác nhận cách Supabase tự link theo email) | `Auth.tsx:54, 77` | Copy hỗ trợ / hướng dẫn D6; G3 kiểm cả (a) và (b) ở A10 |
| R5 | Trung bình | Home Android hiện "Connect Apple Health" với nút Set up không có tác dụng | `health-settings.ts` (state `unknown`), `Home.tsx:436–438, 512–533` | W3 / G2: ẩn thẻ khi `healthConnect.supported !== true` |
| R6 | Thấp | Export my history có thể không ra file trên Android (và có thể cả iOS), nhưng vẫn báo "Export saved." | `Settings.tsx:168–191`; shell không có `DownloadListener` | Kiểm G3; nếu hỏng thì sửa nhỏ ở shell (blob → share sheet), hoặc ghi CR |
| R7 | Thấp | Ghi âm từ Android (`audio/webm` Opus) có thể không phát được trên iPhone, và ngược lại (cần xác nhận) | `VoiceOfChange.tsx:112, 121` | G3: ghi trên Android, phát trên iPhone và ngược lại |
| R8 | Thấp | Từ chối micro hẳn thì không quay lại được từ app; lỗi hiện thô ("Permission denied") | `MainActivity.kt:43–50`, `VoiceOfChange.tsx:131` | `PermissionCoordinator` (A5) mở Settings. Web cần một message mới; ghi lại để chốt ở G3 |
| R9 | Thấp | Nút Back thoát app thay vì đóng sheet (cần xác nhận) | `MainActivity.kt:146–150` | G3 (L02) |
| R10 | Thấp | Edge-to-edge (targetSdk 35): tab bar / pill có thể bị thanh hệ thống che | `PhoneFrame.tsx` (`env(safe-area-inset-top)`), M2 plan §2 | A4 |
| R11 | Thấp | Giá viết cứng bằng USD trong PlanSurface, không lấy từ store | `PlanSurface.tsx` | M5 (H) |
| R12 | Thấp | Privacy Policy chưa nói tới Health Connect | `LegalDocument.tsx` | M5 (Play declarations) |
| R13 | Thông tin | D8 mở thêm chế độ target theo thứ khi tạo Icon; mọi card / notification Android sau này phải dùng target của từng ngày | `Contract.tsx:1139, 1254` | G3 kiểm D02 + D12 |

---

## 8. Đề xuất bổ sung cho M2 (cần Jimmy chốt)

1. **D9 — Testament Timer trên Android trong M2** (R1).
   - **Phương án A (đề xuất):** sửa web ngay trong `send_message` G1, ước tính thêm 1–2 credit.
     - Web chỉ để native giữ đồng hồ khi platform là iOS, hoặc khi Android báo `capabilities.testamentTimer.supported === true`. Cách làm: thay `hasNativeBridge()` trong `timer-store.ts` bằng một helper.
     - Android M2 không báo capability này, nên web tự hoàn thành timer khi app đang mở, giống trình duyệt.
     - Giới hạn: process bị kill thì mất timer, vì `SESSION_START` bỏ timer đã hết trước khi app mở lại. M4 thay bằng engine nền.
     - Test: W4 thêm case "Android không capability".
   - **Phương án B:** giữ nguyên tới M4. Khi đó Android không dùng được timer tới M4, và demo G3 sẽ thấy lỗi.
2. **W5 — nút Google** (R3): `showGoogle` chỉ dùng OAuth web khi `nativePlatform() === null`. Gửi cùng G1.
3. **W6 — target đo bằng Health trên Android trước M3/M4** (R2): cần khách chọn giữa cảnh báo, chặn, hoặc chỉ ghi chú. Nên gộp với D7 / W3.
4. **Thêm vào checklist G3:** D02 (target theo thứ khi tạo), C11 / D10 (timer, sau D9), B04 (thẻ Health ở Home), G07 (Export), E04 (phát ghi âm chéo nền tảng), L02 (Back), A10 (cả hai đường của user Apple-only).

---

## 9. Thống kê

| Quyết định | Số workflow |
|---|---:|
| INCLUDED | 59 |
| ADAPTED | 9 |
| EXCLUDED | 12 |
| DEFERRED-M3 | 9 |
| DEFERRED-M4 | 10 |
| DEFERRED-M5 | 7 |
| **Tổng** | **106** |

Theo nhóm: A 17, B 6, C 18, D 15, E 4, F 6, G 9, H 7, I 8, J 3, K 8, L 5.
