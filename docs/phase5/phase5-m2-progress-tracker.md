# Phase 5 M2 — Android foundation, native session và web parity: Progress Tracker

Updated: 04/11/2026

Plan: `phase5-m2-android-foundation-plan.vi.md`. Branch: `feat/android-m2` (chưa push).
Trạng thái dùng như tracker Phase 4: `NOT STARTED`, `IN PROGRESS`, `BLOCKED`, `CODE DONE`, `READY FOR JIMMY`, `JIMMY TESTING`, `DONE`.

## Tổng quan

| Milestone | Giờ | Trạng thái | Điều kiện đóng |
|---|---:|---|---|
| M2 — Android foundation, native session, web parity | 44 | IN PROGRESS | Checklist §8 của plan; demo trên máy Android thật; baseline đã chốt (D1) |

## Quyết định

| ID | Nội dung | Trạng thái |
|---|---|---|
| D1 | Jimmy PASS bản iOS chuẩn (1.0.9 (4) hay (5)) | CHỜ JIMMY |
| D2 | Máy Android thật (Pixel / Galaxy A06 5G) | CHỜ JIMMY/KHÁCH |
| D3 | Package `com.honoured.app`, Play Console, upload key | CHỜ KHÁCH |
| D4 | Android OAuth client + `GOOGLE_WEB_CLIENT_ID` | CHỜ JIMMY/KHÁCH |
| D5 | 2 tài khoản test | CHỜ JIMMY |
| D6 | Sign in with Apple trên Android | CHỐT 04/11: EXCLUDED (dùng Link Google / đặt mật khẩu trên iPhone) |
| D7 | Copy "iPhone app" trên Android | CHỜ KHÁCH |
| D8 | Revise target trên Android | CHỐT 04/11: INCLUDED |

## Task

| # | Task | Giờ | Trạng thái | Evidence |
|---|---|---:|---|---|
| A1 | Audit baseline + bảng parity | 2 | IN PROGRESS | `android-parity-matrix.md` (đang soạn) |
| A2 | Version, ký release, guard config, R8 | 3 | NOT STARTED | Chờ D3 cho upload key |
| A3 | Deep link + cold start | 3 | NOT STARTED | Hạ tầng hàng đợi bền đã có (B4) |
| A4 | Lifecycle, renderer crash, process death, edge-to-edge | 4 | NOT STARTED | |
| A5 | Quyền + capability + test nền tảng | 3 | IN PROGRESS | `bridge/Capabilities.kt` (sessionRefresh, iconRevisions, 4 capability chưa hỗ trợ); `androidTest` harness đã thêm |
| B1 | Kênh tin cậy cho message phiên | 4 | CODE DONE | `AuthBridge.kt`: 3 type phiên chỉ nhận trên `HonouredAuth`, reply qua proxy của document đã hỏi, bỏ nếu document đổi; `HonouredNative` trả `insecure_transport` (qua `AuthBridge.MESSAGE_TYPES`) |
| B2 | Lưu phiên mã hoá | 4 | CODE DONE | `session/SessionStore.kt`, `KeystoreSessionCipher.kt` (AES-256-GCM, Keystore, `noBackupFilesDir`); `res/xml/data_extraction_rules.xml`, `backup_rules.xml` |
| B3 | Refresh tuần tự, chống dùng lại token | 4 | CODE DONE | `session/SessionRefresher.kt`, `HttpRefreshTransport.kt`; `SUPABASE_URL` / `SUPABASE_ANON_KEY` vào `BuildConfig` |
| B4 | Hàng đợi sự kiện bền | 3 | CODE DONE | `bridge/NativeEventStore.kt`, `BridgeEventQueue.kt`; `NativeBridge` flush sau message đầu tiên của trang |
| B5 | Dọn dữ liệu khi đăng xuất / đổi tài khoản | 2 | CODE DONE | `session/SerialMutationQueue.kt` (`AccountScopedRegistry`), `GoogleAuthState.sessionOwnerChanged` |
| B6 | Test bridge / phiên | 1 | CODE DONE | Unit `testDebugUnitTest` 49/49 pass (38 test mới: store, refresher, handler, event queue, capability, owner change). Instrumentation `connectedDebugAndroidTest` trên emulator API 35 (WebView 124): 6/6 pass. Gồm Keystore thật (round trip, IV ngẫu nhiên, sửa 1 byte bị phát hiện, mất khoá thì quên phiên); production web thật: `HonouredNative` từ chối SET/REFRESH với `insecure_transport` và không lưu gì; `HonouredAuth` nhận SET (ACCEPTED không có token), từ chối refresh cho user khác (`other_user`), refresh bằng token giả tới Supabase thật bị trả về `invalid_session` và giữ nguyên phiên đang lưu, CLEAR xoá phiên. Logcat không chứa token test |
| G1 | Adapter web + gate capability (Lovable) | 3 | NOT STARTED | Gửi sau khi native E2E trên emulator |
| G2 | Copy / trạng thái Health trên Android | 2 | BLOCKED | D7 |
| G3 | Kiểm parity trên WebView | 2 | BLOCKED | D2, D5 |
| G4 | Test Lovable / browser / WebView | 4 | NOT STARTED | |

## Nhật ký

- 04/11: tạo branch, commit plan (`830de93`). Code phiên native B1–B5 + capability + `SYNC_ICON_REVISIONS` (D8). Unit test `testDebugUnitTest`: 49 pass, 0 fail.
- 04/11: `.env` trên máy này để trống `SUPABASE_URL` / `SUPABASE_ANON_KEY`, làm capability tắt. Đã điền vào `android/local.properties` (gitignored) bằng giá trị công khai của Lovable, không in ra. Mac mini có thể đã có giá trị trong `.env`.
- 04/11: `bridge.md` mục "Session refresh (iOS and Android)" thêm quy tắc Android; `.env.example` ghi chú Supabase cho Android.
- Ghi chú thiết kế so với plan:
  - Không dùng cờ build để tắt `sessionRefresh`. Capability bật cũng an toàn với web hiện tại: web cũ gửi token qua `HonouredNative` (bị từ chối) và tự refresh như trước, nên native không bao giờ giữ refresh token khi web chưa giao việc refresh.
  - Phiên không đọc được (mất khoá) thì coi như không có phiên, không broadcast `AUTH_SESSION_INVALID`. Web nhận `no_session` thì tự refresh rồi gửi phiên mới.
  - `AUTH_SESSION_UPDATED` (native tự refresh khi web không chạy, khôi phục phiên cho trang) để M4, khi có worker.

## Bugs và blockers

| ID | Task | Mô tả | Severity | Trạng thái |
|---|---|---|---|---|
