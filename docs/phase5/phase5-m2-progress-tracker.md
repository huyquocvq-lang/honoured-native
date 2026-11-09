# Phase 5 M2 — Android foundation, native session và web parity: Progress Tracker

Updated: 09/11/2026

Plan: `phase5-m2-android-foundation-plan.vi.md`. Branch: `feat/android-m2` (chưa push).
Trạng thái dùng như tracker Phase 4: `NOT STARTED`, `IN PROGRESS`, `BLOCKED`, `CODE DONE`, `READY FOR JIMMY`, `JIMMY TESTING`, `DONE`.

## Tổng quan

| Milestone | Giờ | Trạng thái | Điều kiện đóng |
|---|---:|---|---|
| M2 — Android foundation, native session, web parity | 44 | DONE 09/11/2026 | Jimmy xác nhận toàn bộ web changes đã publish, đã test trên máy Android thật và chấp nhận đóng M2 |

## Quyết định

| ID | Nội dung | Trạng thái |
|---|---|---|
| D1 | Jimmy PASS baseline dùng để đóng M2 | CHỐT 09/11: Jimmy chấp nhận đóng M2 |
| D2 | Máy Android thật (Pixel / Galaxy A06 5G) | PASS 09/11: Jimmy xác nhận đã test máy thật; không tự bổ sung model/evidence chưa được cung cấp |
| D3 | Package Android, Play Console, upload key | M2 DONE: local package/signing đã cấu hình; Play submission thuộc M5 |
| D4 | Android OAuth client + `GOOGLE_WEB_CLIENT_ID` | M2 DONE: config đã có và Jimmy xác nhận bản máy thật đã test |
| D5 | 2 tài khoản test | CHỐT 07/11: Jimmy đồng ý ("Làm hết M2"). Tạo bằng chính màn đăng ký trên Android: `huyquoc.vq+honoured-android-1@gmail.com` (user `91834e18…`) và `-2` (`d4e1df92…`); mật khẩu trong Keychain `honoured-android-test-1/2`, không in ra. Marketing opt-in = false. Xoá được sau M5 |
| D6 | Sign in with Apple trên Android | CHỐT 04/11: EXCLUDED (dùng Link Google / đặt mật khẩu trên iPhone) |
| D7 | Copy "iPhone app" trên Android | CLOSED 09/11: dùng nội dung trong bản web đã publish và được Jimmy chấp nhận trên máy thật |
| D8 | Revise target trên Android | CHỐT 04/11: INCLUDED (kéo theo chế độ target theo thứ khi tạo Icon, `Contract.tsx:1139, 1254`) |
| D9 | Testament Timer trên Android (R1): web chờ `TIMER_COMPLETED` mà Android không gửi, nên contract dùng timer sẽ BROKEN | CHỐT 05/11: phương án A (Jimmy đồng ý). Đã nằm trong Lovable `727722d8`: `nativeOwnsTimer()` = iOS hoặc `testamentTimer.supported` |
| W5 | Nút Google trên Android rơi vào OAuth web khi không có capability (R3) | Đã nằm trong Lovable `727722d8`: `showGoogleButton(platform, usable)`, OAuth web chỉ cho trình duyệt thường |
| W6 | Contract / Icon đo bằng Health tạo trên Android chưa xác minh được tới M3/M4 (R2) | CLOSED FOR M2: giới hạn được chấp nhận; phần xác minh Health vẫn thuộc M3/M4 |

## Xác nhận đóng M2

- 09/11/2026: Jimmy xác nhận toàn bộ thay đổi web của M2 đã publish và bản Android đã được test trên máy thật.
- Jimmy yêu cầu đánh dấu milestone `DONE`; xác nhận này đóng exit gate publish và physical-device acceptance.
- Không bổ sung deployment SHA, model máy hoặc evidence chưa được cung cấp. Các dòng evidence chi tiết bên dưới vẫn giữ nguyên lịch sử kiểm tra trước lúc nghiệm thu.

## Task

| # | Task | Giờ | Trạng thái | Evidence |
|---|---|---:|---|---|
| A1 | Audit baseline + bảng parity | 2 | CODE DONE (draft, chờ D1) | `android-parity-matrix.md`: 106 workflow (INCLUDED 59, ADAPTED 9, EXCLUDED 12, DEFERRED M3/M4/M5 9/10/7), 13 rủi ro R1–R13, 14 dòng copy D7. Baseline: Lovable `df0dc04d`; md5 50 hàm SQL `evidence/m2/supabase-function-md5-2026-11-05.tsv`; iOS chờ D1. Đã kiểm lại R1 (`timer-store.ts:159`) và R3 (`AuthGate.tsx:34, 201`) trong code |
| A2 | Version, ký release, guard config, R8 | 3 | CODE DONE (chờ D3/D4 cho bản store) | `android/version.properties` (1.0.0 / code 2, tracked). `signingConfigs.release` đọc `HONOURED_UPLOAD_*` từ `local.properties` hoặc env; `local.properties.example`; `*.jks` / `*.keystore` vào `.gitignore`. Guard: `bundleRelease` / `assembleRelease` fail kèm danh sách lý do khi thiếu upload key, `REVENUECAT_ENTITLEMENT_ID` khác rỗng, URL không https, thiếu RevenueCat / Google / Supabase. Đã kiểm: trên máy này fail đúng 3 lý do (key, RevenueCat, Google). Với key thử (xoá ngay sau) và config giả tạm: ra AAB, `jarsigner` verified. R8 + shrinkResources cho release; build type `smoke` = release ký debug key (Play từ chối), có thể inspect WebView. APK smoke 2.4 MB (debug 7.9 MB), chạy trên emulator: bridge qua CDP OK (capabilities, kênh cũ từ chối token `insecure_transport`, `HonouredAuth` ACCEPTED rồi CLEARED, `ICON_REVISIONS_SYNCED`), logcat không có token |
| A3 | Deep link + cold start | 3 | CODE DONE | `deeplink/ContractDeepLink.kt`: parser chặt (scheme/host, 1 segment, id ≤ 128 ký tự không ký tự điều khiển, UTF-8 hợp lệ, `day` là ngày thật, chỉ `day`/`occurrence`, không user/port/fragment). Manifest: `singleTask` + intent-filter `honoured://contract`. `CONTRACT_LINK_OPENED` đi hàng đợi bền; không phát lại khi recreate hoặc mở từ Recents. 10 unit test. Instrumentation: cold start giao đúng 1 lần sau khi trang nói chuyện, warm qua `onNewIntent`, link sai bị bỏ. `bridge.md` thêm mục Contract deep link |
| A4 | Lifecycle, renderer crash, process death, edge-to-edge | 4 | CODE DONE | WebView tạo bằng code. `onRenderProcessGone` hủy WebView cũ, dựng lại 2 bridge, load lại; quá 3 lần/60 s thì hiện màn lỗi. Bỏ `restoreState`: luôn load mới. Edge-to-edge: `enableEdgeToEdge` + padding theo system bars / cutout / IME, `adjustResize`. Instrumentation: `chrome://crash` thì app sống, WebView mới chạy; `recreate()` load mới, không phát lại link; insets > 0. Emulator: `am kill` khi ở nền rồi mở lại (COLD) load bình thường; ảnh chụp: status bar đen, nội dung không bị che, bàn phím đẩy form lên |
| A5 | Quyền + capability + test nền tảng | 3 | CODE DONE | `permissions/PermissionGate` + `PermissionCoordinator`: mỗi lần một prompt, trạng thái BLOCKED ("không hỏi lại"), `openAppSettings()`; micro của WebView đi qua đây. `WebViewSupport`: WebView < 111 (build target Chrome 111 của Vite 8) thì hiện màn "Update Android System WebView" + nút mở Play, không load trang. Unit: 66/66 (17 test mới cho A3/A5). Instrumentation 13 test: API 35 (WebView 124) 13/13 pass; AVD riêng `HonouredApi26` (API 26, WebView 58, không Play): Keystore 3/3 + gate 1/1 pass, 9 test cần web hiện đại được skip có chủ đích |
| B1 | Kênh tin cậy cho message phiên | 4 | CODE DONE | `AuthBridge.kt`: 3 type phiên chỉ nhận trên `HonouredAuth`, reply qua proxy của document đã hỏi, bỏ nếu document đổi; `HonouredNative` trả `insecure_transport` (qua `AuthBridge.MESSAGE_TYPES`) |
| B2 | Lưu phiên mã hoá | 4 | CODE DONE | `session/SessionStore.kt`, `KeystoreSessionCipher.kt` (AES-256-GCM, Keystore, `noBackupFilesDir`); `res/xml/data_extraction_rules.xml`, `backup_rules.xml` |
| B3 | Refresh tuần tự, chống dùng lại token | 4 | CODE DONE | `session/SessionRefresher.kt`, `HttpRefreshTransport.kt`; `SUPABASE_URL` / `SUPABASE_ANON_KEY` vào `BuildConfig` |
| B4 | Hàng đợi sự kiện bền | 3 | CODE DONE | `bridge/NativeEventStore.kt`, `BridgeEventQueue.kt`; `NativeBridge` flush sau message đầu tiên của trang |
| B5 | Dọn dữ liệu khi đăng xuất / đổi tài khoản | 2 | CODE DONE | `session/SerialMutationQueue.kt` (`AccountScopedRegistry`), `GoogleAuthState.sessionOwnerChanged` |
| B6 | Test bridge / phiên | 1 | CODE DONE | Unit `testDebugUnitTest` 49/49 pass (38 test mới: store, refresher, handler, event queue, capability, owner change). Instrumentation `connectedDebugAndroidTest` trên emulator API 35 (WebView 124): 6/6 pass. Gồm Keystore thật (round trip, IV ngẫu nhiên, sửa 1 byte bị phát hiện, mất khoá thì quên phiên); production web thật: `HonouredNative` từ chối SET/REFRESH với `insecure_transport` và không lưu gì; `HonouredAuth` nhận SET (ACCEPTED không có token), từ chối refresh cho user khác (`other_user`), refresh bằng token giả tới Supabase thật bị trả về `invalid_session` và giữ nguyên phiên đang lưu, CLEAR xoá phiên. Logcat không chứa token test |
| G1 | Adapter web + gate capability (Lovable) | 3 | PUBLISHED 05/11 | Lovable `727722d8` (8.9 credit), publish 05/11 (Jimmy duyệt), deployment `81a78bcd`, bundle `routes-DmE-ESGB.js` → `routes-Ckka2yNr.js` + `index-7eB0IeUw.js` (có `trusted-auth-v1`, `CONTRACT_LINK_OPENED`, `testamentTimer`). Smoke WebKit: 200, không lỗi console. Gồm W1 (SET/CLEAR/REFRESH chỉ qua `HonouredAuth` khi `androidSessionHandOff()`), W2 (`CONTRACT_LINK_OPENED`), W5, D9. Vitest 898/898 ở UTC; ở Asia/Saigon và Los Angeles chỉ fail P5-B02 (có từ trước). `tsc` sạch. Test cũ chạy trên code mới: 5 fail, cả 5 là test giả lập shell Android dự kiến đổi hành vi (token/timer qua kênh cũ) hoặc mock thiếu export mới. A/B bridge (script `50-ab-bridge.mjs`, mock Supabase): **iOS** cùng tập message, cùng kênh, cùng payload key so với production; thứ tự chỉ lệch ở `GET_TIMER_STATE` thứ hai, lệch cả giữa hai lần chạy production nên là do timing; refresh vẫn qua native. **Android cũ**: không còn SET/CLEAR/timer, trang tự refresh, ẩn Google khi chưa cấu hình. **Android mới**: SET/CLEAR/REFRESH chỉ qua `HonouredAuth`, trang không tự dùng refresh token |
| G2 | Copy / trạng thái Health trên Android | 2 | DONE 09/11 | Lovable `8bf3e879` đã được Jimmy xác nhận publish; trạng thái/copy Android đã được chấp nhận khi test máy thật. Evidence trước publish: Android không có `healthConnect.supported` thì health state = `unsupported`, không gửi health request; hook `window.__honouredBack()` cho nút Back |
| G3 | Kiểm parity trên WebView | 2 | DONE 09/11 | Emulator evidence đã ghi cho Export, micro, Back, Icon composer và Health state. Jimmy xác nhận đã test bản hoàn chỉnh trên máy Android thật và chấp nhận parity để đóng M2; không tự bổ sung model/ảnh/video chưa được cung cấp |
| G4 | Test Lovable / browser / WebView | 4 | DONE (emulator) | E2E 07/11 trên emulator API 35 với production `727722d8` và 2 tài khoản test (script `scratch/hon/emu/*.mjs`, CDP + adb, mật khẩu đọc từ Keychain): **đăng ký** trên Android → `AUTH_SESSION_ACCEPTED`, `session.bin` được tạo; **đăng nhập** bằng mật khẩu → như trên; **refresh** (cho access token hết hạn rồi reload): trang KHÔNG gọi `/auth/v1/token`, native refresh, token xoay, `session.bin` ghi lại; DB: 1 session, chuỗi token 1 revoked + 1 active, không có reuse; **đăng xuất** → `POST /logout`, `session.bin` + `native-events.json` bị xoá; **đổi tài khoản** (1 → 2 → 1): refresh của user mới vẫn qua native, Home không lẫn dữ liệu; **Testament Timer** (D9): contract 1 phút, bấm Start, 60 s sau "Honoured · 09:06", DB `status = honoured`, không có `START_TIMER`; **deep link** `honoured://contract/<client_id>`: warm và cold đều mở Standing Contract, contract đã Honoured hoặc của account khác → Home; **app Android cũ (main, code 1) + web mới**: nút Google ẩn, trang tự refresh (`POST /token`), không có `session.bin`; **nâng cấp cũ → mới khi đang đăng nhập**: web gửi phiên sang native một lần, refresh sau đó qua native, DB: 1 session, 3 token, 1 active. Chưa test được: Google (D4), máy thật (D2), mua gói (M5) |

## Nhật ký

- 04/11: tạo branch, commit plan (`830de93`). Code phiên native B1–B5 + capability + `SYNC_ICON_REVISIONS` (D8). Unit test `testDebugUnitTest`: 49 pass, 0 fail.
- 04/11: `.env` trên máy này để trống `SUPABASE_URL` / `SUPABASE_ANON_KEY`, làm capability tắt. Đã điền vào `android/local.properties` (gitignored) bằng giá trị công khai của Lovable, không in ra. Mac mini có thể đã có giá trị trong `.env`.
- 04/11: `bridge.md` mục "Session refresh (iOS and Android)" thêm quy tắc Android; `.env.example` ghi chú Supabase cho Android.
- Ghi chú thiết kế so với plan:
  - Không dùng cờ build để tắt `sessionRefresh`. Capability bật cũng an toàn với web hiện tại: web cũ gửi token qua `HonouredNative` (bị từ chối) và tự refresh như trước, nên native không bao giờ giữ refresh token khi web chưa giao việc refresh.
  - Phiên không đọc được (mất khoá) thì coi như không có phiên, không broadcast `AUTH_SESSION_INVALID`. Web nhận `no_session` thì tự refresh rồi gửi phiên mới.
  - `AUTH_SESSION_UPDATED` (native tự refresh khi web không chạy, khôi phục phiên cho trang) để M4, khi có worker.

## Review code (OCR, 07–08/11)

Open Code Review (delegate mode), 4 batch: 34 file Android + 23 file web (diff G1 + G2). Kết quả: 1 high, 8 medium, 34 low, 0 critical. Đã tự đọc lại code cho high và 8 medium: cả 9 là lỗi thật.

| ID | Mức | Chỗ | Lỗi | Sửa |
|---|---|---|---|---|
| R-H1 | High | web `native-session-refresh.ts` (có trên production từ G1) | `NATIVE_READY` đến sau 4 s thì trang Android tự refresh bằng token native cũng đang giữ → có thể dùng lại token | Lovable `8bf3e879`: trên Android (`window.HonouredAuth` có mặt) chờ capability tới 30 s, hỏi native, không bao giờ fallback mạng; hết hạn trả 503. iOS / browser giữ nguyên. A/B với `NATIVE_READY` trễ 7 s: bản cũ `tokenCalls=["page"]`, bản mới `["native"]` |
| R-M1 | Medium | `SessionRefresher.kt` | Gộp refresh không nguyên tử: caller thứ hai nhận `superseded` hoặc refresh lần hai | Spend + store chạy trong task dùng chung; giữ kết quả cuối theo token đã dùng; `forget()` khi clear/đổi tài khoản. Test mới chạy 8 caller trên thread thật × 20 vòng: code cũ FAIL, code mới pass |
| R-M2 | Medium | `SessionMessageHandler.kt` | SET cũ của cùng user ghi đè phiên mới hơn native vừa refresh | `SessionFreshness.keepStored`: cùng user, khác refresh token, `expiresAt` lưu muộn hơn → giữ phiên đang lưu, vẫn trả ACCEPTED |
| R-M3 | Medium | `MainActivity.onDestroy` | Hộp xin micro đang mở → `deny()` hai lần → crash | Trả lời mỗi request đúng một lần, `runCatching` |
| R-M4 | Medium | `MainActivity` micro | Bấm Record hai lần khi prompt đang mở → hiện sai "Microphone is off" | `PermissionGate.Outcome` (GRANTED / DENIED / BUSY); BUSY không bao giờ hiện dialog; chỉ một dialog. Unit test `PermissionGateTest` (BUSY ≠ DENIED) |
| R-M5 | Medium | `build.gradle.kts` | Guard release bị lách qua `signReleaseBundle` / `packageReleaseBundle`; chặn cả Generate Signed Bundle của Android Studio | Danh sách task artifact cụ thể (gồm universal APK); chấp nhận key do Android Studio inject. `signReleaseBundle` giờ fail đúng lý do; `testReleaseUnitTest` không bị chặn |
| R-M6 | Medium | web `Settings.tsx:666` | Hook gọi sau `return` sớm → Settings có thể crash trên iOS | `8bf3e879`: eslint `rules-of-hooks` có lỗi ở `082c1f8e`, sạch ở `8bf3e879`; Playwright shell iOS mở Settings 2 lần, không lỗi |
| R-M7 | Medium | web Subscription | Change plan / màn kết quả mua chưa đăng ký Back → về Home, mất kết quả | `8bf3e879`: lớp Back cho Change plan và overlay kết quả; không đóng khi đang restore |
| R-M8 | Medium | web Contract / Journal | Back khi không có gì mở → về Home, mất bản nháp | `8bf3e879`: draft đã chạm hoặc Journal chưa lưu → `__honouredBack()` trả `false`, shell cho app xuống nền, giữ nguyên. Playwright: Contract có draft → `false`, composer còn nguyên |

Low đã sửa ở shell: account switch lỗi lưu không còn để lại phiên cũ; store không đọc được thì dọn account state trước; `SessionStore.clear()` xoá file trước; `toString` kết quả refresh không in token; danh sách key bí mật thêm `id_token` / `provider_token` (mọi cách viết, cả trong mảng); event bền đi qua hàng đợi khi flush (không mất nếu trang đổi); timeout HTTP refresh 10 + 15 s (< 30 s trang chờ); Back có fallback 1.5 s khi script treo; chỉ crash thật tính vào giới hạn renderer; Export lỗi không để file 0 byte, decode ngoài main thread; deep link giữ ký tự ngoài BMP (emoji), từ chối surrogate lẻ; 2 test instrumentation sửa assert vô nghĩa / sleep cố định. Low web (`8bf3e879`): copy health kiểu iPhone ẩn trên Android, google-auth, native-auth.

Kiểm: Android unit 78/78; instrumentation API 35 15/15; web `8bf3e879` vitest 927/927 (UTC), `tsc` sạch, không lỗi `rules-of-hooks`; A/B bridge iOS cùng tập message so với production (chỉ lệch thứ tự `GET_TIMER_STATE` do timing, như trước). Commit Android `87dacda`. Low còn để lại (không ảnh hưởng hành vi): đọc event store trên main thread lúc khởi động (file nhỏ), vài comment.

## Bugs và blockers

| ID | Task | Mô tả | Severity | Trạng thái |
|---|---|---|---|---|
| P5-M2-B01 | G1 / D9 | R1: Testament Timer trên Android không bao giờ hoàn thành, nên contract BROKEN. Lỗi có từ trước trên production Android | High | DONE: fixed, published 05/11 (`727722d8`), Jimmy xác nhận test máy thật 09/11 |
| P5-M2-B02 | G1 / W5 | R3: thiếu Google config thì nút Google trên Android mở OAuth web, ra trình duyệt ngoài, app không đăng nhập | Medium | DONE: fixed, published 05/11 (`727722d8`), Jimmy xác nhận test máy thật 09/11 |
| P5-M2-B03 | G2 / D7 | R5: Home Android hiện "Connect Apple Health" với nút Set up không có tác dụng | Medium | DONE: fix trong web `8bf3e879`, Jimmy xác nhận đã publish và test máy thật 09/11 |
| P5-M2-B04 | A5 | WebView cũ (API 26 không Play, WebView 58): web production lỗi cú pháp (`Unexpected token ?`), app chỉ hiện màn đen. Có từ trước | Medium | FIXED trong shell: gate WebView ≥ 111. Copy "Update Android System WebView" / nút "Update" chờ khách duyệt (cùng D7) |
| P5-M2-B05 | G3 / R6 | Export my history trên Android báo "Export saved." nhưng không có file. Có từ trước | Medium | FIXED ở shell (`DownloadSaver`), đã test emulator + instrumentation |
| P5-M2-B06 | G3 / R9 | Nút Back trên Android thoát và huỷ activity: mất bản nháp contract / dialog. Có từ trước | Medium | FIXED ở shell (không `finish()`); phần đóng sheet/dialog chờ web `__honouredBack` (G2) |
| P5-M2-B07 | G3 / R8 | Micro bị từ chối hẳn thì không có đường mở lại trong app | Low | FIXED ở shell: dialog "Microphone is off" → Open Settings. Copy chờ D7 |
| P5-M2-B08 | Review / R-H1 | Trang Android tự refresh khi `NATIVE_READY` đến sau 4 s (có trên production từ G1) | High | DONE: fixed trong Lovable `8bf3e879`, Jimmy xác nhận đã publish và test máy thật 09/11 |
| P5-M2-B09 | Review / R-M6 | Settings gọi hook sau `return` sớm (G2, chưa từng publish) | Medium | DONE: fixed trong `8bf3e879`, Jimmy xác nhận đã publish 09/11 |
