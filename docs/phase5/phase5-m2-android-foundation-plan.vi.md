# Phase 5 M2 — Android foundation, native session và web parity: Implementation plan

Ngày lập: 04/11/2026  
Estimate: **44 giờ** = A (15) + B (18) + G (11) trong `phase5-assessment-estimate-plan.vi.md` §4.2.2 và §4.3.  
Exit gate theo plan: đã chốt baseline (frozen), phiên native an toàn, có demo parity trên máy Android thật.

Nguồn đã đối chiếu khi lập plan:

- Code Android hiện tại (`android/`, commit `d04e72c`).
- Cách làm trên iOS: `ios/Honoured/Auth/AuthSessionStore.swift`, `Auth/Core/SessionRefresh.swift`, `Bridge/NativeBridge.swift` (dòng 349–449), `Bridge/NativeBridge+SessionRefresh.swift`, `Bridge/NativeEventStore.swift`.
- Hợp đồng bridge `docs/phase1/bridge.md`: auth session, Google Sign-In, Session refresh, event queue.
- Web head Lovable `df0dc04d` (= production 04/11): `src/lib/native-bridge.ts`, `native-auth.ts`, `native-session-refresh.ts`, `health-settings.ts`, `AuthGate.tsx`.
- Dữ liệu production (chỉ SELECT): 11 user email, 2 Apple, 1 Google. `supabase_migrations` dừng ở `20260904095949`; các SQL sau đó (icon scoring v2–v4, revisions, weekday targets) được chạy tay.

---

## 1. Tóm tắt

Kết thúc M2, app Android:

1. Giữ một bản sao phiên Supabase **đã mã hoá** của người đang đăng nhập.
2. Là nơi **duy nhất** refresh token trong app, giống iOS. Nhờ vậy M3/M4 có credential để sync nền mà không lặp lại lỗi "refresh token reuse" làm văng đăng nhập (iOS 2–6/10).
3. Chỉ nhận token qua kênh `HonouredAuth`, kênh chỉ nhận từ đúng domain của web app. Kênh cũ `HonouredNative` từ chối mọi message mang token.
4. Có nền tảng cho các milestone sau:
   - hàng đợi sự kiện bền, deep link khi app mở nguội (cold start);
   - chịu được renderer crash và process death;
   - một chỗ quản lý quyền và khả năng của app (capability);
   - build release có ký, có version.
5. Có bảng parity với baseline iOS/web đã chốt, và chạy đủ luồng Contract / Icon / Journal / History / Settings / đăng nhập trên một máy Android thật.

Không thuộc M2: Health Connect, đếm bước, notification, FCM, foreground service, Play submission (M3–M5).

## 2. Hiện trạng đã kiểm (04/11/2026)

| Mục | Kết quả | Evidence |
|---|---|---|
| Build Android | `testDebugUnitTest assembleDebug` pass: 11 unit test (AuthSupport 5, GoogleAuthState 6), APK debug 7.9 MB. JDK Temurin 17; Gradle tự cài Build-Tools 34 | Chạy local 04/11 |
| Chạy thử emulator | AVD API 35, WebView 124: mở được production web (đã có M1), không crash. Không đăng nhập được vì không có tài khoản test và Google Sign-In tắt (`GOOGLE_WEB_CLIENT_ID` trống trong `.env`) | `~/.hermes/cache/scratch/hon/qa/shots/android-launch.png` |
| Kích thước code | Khoảng 1.6k dòng Kotlin + XML: WebView shell, Google Sign-In (Credential Manager), RevenueCat, quyền micro | `find android/app/src` |
| Version / ký | `versionCode 1`, `versionName 1.0.0`; chưa có `signingConfigs`, chưa có guard cho bản release | `android/app/build.gradle.kts` |
| Manifest | Chỉ có INTERNET và RECORD_AUDIO; khoá portrait; `allowBackup=false`, chưa có `dataExtractionRules`; không intent-filter deep link; launchMode mặc định | `AndroidManifest.xml` |
| Lifecycle | `restoreState` khi process bị kill; không xử lý `onRenderProcessGone` (renderer WebView crash sẽ kéo cả app crash); không có `onNewIntent` | `MainActivity.kt` |
| Kênh bridge | `HonouredNative` (addJavascriptInterface, không giới hạn origin) cho billing/platform. `HonouredAuth` (WebMessageListener, đúng origin, chỉ main frame) cho Google | `bridge/NativeBridge.kt`, `auth/AuthBridge.kt` |
| Phiên đăng nhập | Android không xử lý `SET_AUTH_SESSION` / `CLEAR_AUTH_SESSION` / `REFRESH_AUTH_SESSION`; trả `ERROR "Unsupported bridge message"`, không lưu, không log | `NativeBridge.kt` nhánh `else` |
| Web gửi token sang Android | Web gửi `SET_AUTH_SESSION` (access + refresh token) qua `HonouredNative` vì hai type này không nằm trong `TRUSTED_AUTH_TYPES`. Chưa phải lỗ hổng vì native bỏ đi, nhưng phải đổi trước khi Android nhận phiên | `native-bridge.ts` dòng 88–101, 254–281 |
| Web refresh qua native | `native-session-refresh.ts` khoá cứng `nativePlatform() !== "ios"`, nên Android chưa bao giờ giao refresh cho native | dòng 53 |
| Supabase config cho native Android | Chưa có `SUPABASE_URL` / `SUPABASE_ANON_KEY` trong `BuildConfig` (`.env` đã có) | `build.gradle.kts` |
| Edge-to-edge (targetSdk 35) | Chưa xử lý insets. Cần kiểm thanh tab dưới cùng có bị thanh điều hướng che không | Kiểm ở G3 |

## 3. Điều kiện trước và quyết định cần chốt

| ID | Cần gì | Ai | Chặn task nào nếu thiếu | Đề xuất |
|---|---|---|---|---|
| D1 | Jimmy PASS bản iOS chuẩn và luồng target theo thứ. Phase 4 hiện 14/18 task READY FOR JIMMY, M1-D01..D10 chưa test. `ios/project.yml` đã lên 1.0.9 (5): cần biết bản freeze là (4) hay (5) | Jimmy | A1 (chỉ chốt được "pending") và exit gate M2 | Code song song; ghi baseline "chờ PASS" |
| D2 | Máy Android thật (ít nhất 1 trong Pixel / Galaxy A06 5G; M3 cần đủ cả hai). Ai mua, ai giữ, cắm vào máy nào để chạy `adb` | Jimmy/khách | G3, demo exit gate | Emulator trước, máy thật cuối M2 |
| D3 | Package name `com.honoured.app` là vĩnh viễn trên Play, khách xác nhận. Ai sở hữu Play Console. Upload key do ai tạo và giữ (không vào repo). Có bật Play App Signing không | Khách | A2 (ký release), App Links (M5) | Jimmy tạo upload key, lưu ngoài repo; bật Play App Signing |
| D4 | Google Cloud: Android OAuth client cho `com.honoured.app` với SHA-1 debug + upload (+ Play signing sau này); `GOOGLE_WEB_CLIENT_ID` trong `.env` | Jimmy/khách | Kiểm Google Sign-In trên Android | |
| D5 | 2 tài khoản test Honoured (email/password) để kiểm đăng nhập, đổi tài khoản, đăng xuất. Không gửi mật khẩu qua chat; nhập trên máy | Jimmy | B5, G3, G4 | |
| D6 | **Tài khoản Apple trên Android.** Production có 2 user chỉ dùng Apple. Web chỉ hiện "Sign in with Apple" trên iOS, nên họ không vào được trên Android | **Đã chốt 04/11 (Jimmy): EXCLUDED** | Parity matrix | Không làm Sign in with Apple trên Android. Ghi deviation trong parity matrix. Cách để user Apple dùng Android: trên iPhone dùng "Link Google" (`Auth.tsx`, intent `link`) hoặc đặt mật khẩu, rồi đăng nhập Android bằng Google/email. G3 kiểm lại luồng này |
| D7 | Copy iPhone / Apple Health mà Android thấy, cho tới khi M3/M4 có Health Connect. Danh sách đúng (bảng parity §6, 14 dòng): Settings › Notifications và Word Tracker "Available in the iPhone app", thẻ "Connect Apple Health" ở Home, ghi chú Apple Health dưới Icon. `NON_NATIVE_NOTE` và nhãn Home "iPhone app" **không** hiện trên Android | Khách | G2 | Đổi theo capability, ví dụ "Coming to Android". Copy chờ khách duyệt |
| D8 | Icon target revision trên Android. Web chỉ cho revise khi `capabilities.iconRevisions.supported`; lý do là card iOS cũ. Android không có card nên bật được an toàn | **Đã chốt 04/11 (Jimmy): INCLUDED** | G1 | Android báo `iconRevisions { protocolVersion: 1, supported: true }` và trả `ICON_REVISIONS_SYNCED { synced: true }` (không có cache card). Web không cần sửa. G3 kiểm sửa target theo thứ và ký lại trên Android. Khi M5 có notification/card Android: phải dùng target của từng ngày (`icon_days.target_text`) |
| D9 | Testament Timer trên Android: `timer-store.ts:159` thoát khi `hasNativeBridge()` và chờ native gửi `TIMER_COMPLETED`; Android không có timer nên contract dùng timer sẽ BROKEN (lỗi có sẵn trên production Android) | Jimmy | G1 | Đề xuất phương án A: web chỉ giao timer cho native khi platform là iOS, hoặc khi có `capabilities.testamentTimer.supported`. Android M2 không báo capability này nên web tự hoàn thành khi app mở. M4 thay bằng engine nền. Gửi cùng G1 (+1–2 credit) |

## 4. Thiết kế

### 4.1 Kênh bridge và quy tắc tin cậy

| Message | Kênh trên Android | Kênh khác |
|---|---|---|
| `SET_AUTH_SESSION`, `CLEAR_AUTH_SESSION`, `REFRESH_AUTH_SESSION` (mới trên Android) | Chỉ `HonouredAuth` (main frame, origin khớp tuyệt đối) | `HonouredNative` trả `ERROR { code: "insecure_transport" }` và bỏ payload ngay; không lưu, không log, không đưa vào queue |
| `AUTH_SESSION_UPDATED`, `AUTH_SESSION_INVALID` (native → web, mang token) | Gửi qua `JavaScriptReplyProxy` của document hiện tại đã nói chuyện trên `HonouredAuth` | Không bao giờ qua `evaluateJavascript`, không vào queue bền. Chưa có proxy thì giữ trong RAM tối đa 1 bản mới nhất và xoá khi đổi account |
| Google (`SYNC_AUTH_CONTEXT`, …) | Như hiện tại | Như hiện tại |
| Billing, platform, `SYNC_ICON_REVISIONS`, sự kiện không chứa bí mật | `HonouredNative` như hiện tại | — |

`AuthBridge.MESSAGE_TYPES` (danh sách bị kênh cũ từ chối) thêm 3 type phiên. Mọi reply chứa token chỉ đi qua proxy của chính document đã hỏi; document đổi (`onPageStarted`) thì vô hiệu.

### 4.2 Lưu phiên native (`auth/SessionStore`)

- **Model:** `NativeAuthSession(userId, accessToken, refreshToken, expiresAt)`, giống iOS.
- **Mã hoá:**
  - Khoá AES-256-GCM trong Android Keystore, alias `honoured_session_v1`, không xuất được.
  - Ciphertext + IV ghi vào `noBackupFilesDir/session.bin`, ghi atomic (file tạm rồi rename).
  - Không dùng `EncryptedSharedPreferences` (androidx.security-crypto đã deprecated) và không thêm dependency.
- **Backup:** thêm `android:dataExtractionRules` + `fullBackupContent` loại thư mục này. Với targetSdk ≥ 31, `allowBackup=false` không chặn chuyển dữ liệu máy-sang-máy. Khoá Keystore cũng không đi theo máy mới, nên một bản bị copy sang chỉ là rác không giải mã được.
- **Giải mã lỗi** (khoá mất, dữ liệu hỏng): coi như không có phiên, xoá file, báo `AUTH_SESSION_INVALID { reason: "unreadable" }` qua kênh tin cậy. Không crash.
- **Không bao giờ log token**: thêm test kiểm `toString()` của model không in token.
- **Tách khỏi crypto để test JVM:** interface `SessionCipher`; bản thật dùng Keystore (test trên emulator), bản fake dùng trong JUnit.

### 4.3 Refresh (`auth/SessionRefresher`)

Chép đúng hành vi iOS (`refreshForWeb`, `RefreshCoalescer`, `WebRefreshPolicy`):

1. Native là nơi duy nhất refresh. `REFRESH_AUTH_SESSION { userId }`:
   - không có phiên → `AUTH_REFRESH_DECLINED { reason: "no_session" }`;
   - phiên của người khác → `"other_user"`;
   - đúng người → refresh bản native đang giữ, là bản mới nhất.
2. Mỗi refresh token chỉ refresh một lần: `Mutex` + `Deferred` đang chạy, khoá theo refresh token; người hỏi sau dùng chung kết quả.
3. Sau khi mạng trả về, chỉ lưu nếu phiên trong store vẫn đúng là phiên lúc bắt đầu. Không đúng → `superseded`.
4. HTTP 400/401 → `invalid_session` (decline); lỗi mạng hoặc 5xx → `ERROR { code: "auth_refresh_failed" }`; thiếu config → `not_configured`.
5. `user.id` trong response khác `userId` → `invalid_session`.
6. Gọi `POST {SUPABASE_URL}/auth/v1/token?grant_type=refresh_token` với header `apikey`, qua `HttpURLConnection` trên `Dispatchers.IO` (không thêm OkHttp). `SUPABASE_URL` / `SUPABASE_ANON_KEY` lấy từ `.env` vào `BuildConfig`.
7. Có sẵn `refreshedSessionIfNeeded()` (hết hạn trong ≤ 60 s) cho worker của M4. Nếu native tự refresh khi web không chạy thì broadcast `AUTH_SESSION_UPDATED` theo §4.1. Trong M2 chưa có worker, chỉ có API và test.

### 4.4 Hợp đồng message trên Android

- **Capability** trong `NATIVE_READY` / `PLATFORM_INFO`:
  `sessionRefresh: { protocolVersion: 1, supported, transport: "trusted-auth-v1" }`.
  `supported = WebMessageListener khả dụng && origin HTTPS && Supabase config có`.
  Một capability này nghĩa là đủ cả gói: nhận phiên qua kênh tin cậy **và** là nơi refresh duy nhất. Hai việc này không được tách, vì lưu refresh token mà không giữ quyền refresh chính là nguyên nhân văng đăng nhập.
- **`SET_AUTH_SESSION { requestId, userId, accessToken, refreshToken, expiresAt }`:**
  - kiểm tra như iOS, sai → `ERROR { code: "invalid_auth_session" }`;
  - user khác → dọn account cũ (§4.5) trước khi lưu;
  - lưu xong → `AUTH_SESSION_ACCEPTED { userId }`.
  Các lệnh ghi phiên chạy tuần tự qua một hàng đợi (tương đương `authMutations` của iOS).
- **`CLEAR_AUTH_SESSION`:** xoá store, dọn account → `AUTH_SESSION_CLEARED {}`. Gọi nhiều lần vẫn an toàn (idempotent).
- **`REFRESH_AUTH_SESSION`:** như §4.3; reply `AUTH_SESSION_REFRESHED { session }` là response gốc của Supabase.
- `docs/phase1/bridge.md`: đổi tiêu đề "Session refresh (iOS)" thành "(iOS and Android)", thêm `transport`, ghi rõ Android chỉ nhận qua `HonouredAuth`.

### 4.5 Tách dữ liệu theo account

`AccountScopedRegistry`: mọi store theo account (event queue, pending broadcast, sau này là health/timer/push của M3–M5) đăng ký một hàm `clear()`.

| Sự kiện | Thứ tự xử lý |
|---|---|
| `SET_AUTH_SESSION` của user khác | 1. Gọi `googleAuth.sessionOwnerChanged` và bỏ các broadcast token đang chờ, đồng bộ trước mọi await. 2. `registry.clearAll()`. 3. Lưu phiên. 4. Reply |
| `CLEAR_AUTH_SESSION` | Như trên, nhưng xoá store thay vì lưu |

RevenueCat vẫn do web điều khiển (`LOGOUT_USER` / `IDENTIFY_USER`); M2 chỉ kiểm thứ tự đúng trong luồng đổi tài khoản.

### 4.6 Hàng đợi sự kiện

- **Trong RAM:** tối đa 50 sự kiện. Flush theo thứ tự ngay sau reply cho message đầu tiên của web sau mỗi lần load trang, giống iOS.
- **Bền** (`noBackupFilesDir/native-events.json`):
  - chỉ các type người dùng sẽ để ý nếu mất: `NOTIFICATION_OPENED`, `CONTRACT_LINK_OPENED` (§4.7), sau này `GOAL_REACHED` / `TIMER_COMPLETED`;
  - không bao giờ chứa token (test chặn bằng danh sách type cho phép);
  - giao đúng một lần, trộn với hàng đợi RAM theo thời gian; xoá khi `CLEAR_AUTH_SESSION` hoặc đổi account.
- M2 có hạ tầng + test; sự kiện thật đầu tiên là deep link (§4.7).

### 4.7 Deep link và cold start

- **Scheme** `honoured://contract/<percent-encoded id>?day=<YYYY-MM-DD>`, cùng dạng với iOS (`HonouredShared/HonouredLiveActivity.swift`).
  - `MainActivity` chuyển sang `launchMode="singleTask"`, xử lý cả `onCreate` lẫn `onNewIntent`.
  - Kiểm tra chặt (id theo regex, `day` đúng định dạng); link sai thì bỏ, không crash.
- **Sự kiện** `CONTRACT_LINK_OPENED { eventId, contractId, healthDay? }`: lưu vào hàng đợi bền rồi giao sau khi trang sẵn sàng. Web xử lý như `LIVE_ACTIVITY_OPENED`: chờ auth/router, dedupe theo `eventId`, contract không tồn tại thì về màn an toàn (W2).
- **App Links https** (verified) cần `assetlinks.json` với SHA-256 của chứng chỉ Play signing, nên để M5. M2 chỉ dựng phần định tuyến dùng chung.

### 4.8 Lifecycle

- **`onRenderProcessGone`:** gỡ và hủy WebView cũ, tạo WebView mới, gắn lại 2 bridge, load lại URL, trả `true` để app không crash. Thêm test bằng `chrome://crash` trên emulator debug.
- **Process death:** không tin `restoreState`. Load lại `WEB_APP_URL` từ đầu (phiên web ở localStorage; phiên native trong store) rồi giao pending deep link sau `NATIVE_READY`.
- **Config change:** giữ `configChanges` như hiện tại.
- **Edge-to-edge (API 35):** áp insets cho root view hoặc truyền safe-area cho web; chọn cách sau khi kiểm G3.

### 4.9 Build, version, ký

- **Version:** `android/version.properties` được track (`VERSION_NAME`, `VERSION_CODE`), đọc trong Gradle. Đề xuất bản Android đầu là `1.0.0 (2)`; bản `1.0.0 (1)` có thể đã dùng thử.
- **Ký release:** `signingConfigs.release` đọc `HONOURED_UPLOAD_STORE_FILE`, `HONOURED_UPLOAD_STORE_PASSWORD`, `HONOURED_UPLOAD_KEY_ALIAS`, `HONOURED_UPLOAD_KEY_PASSWORD` từ `local.properties` hoặc biến môi trường. Thiếu bất kỳ cái nào thì `bundleRelease` fail với thông báo rõ; không bao giờ ra bản release không ký.
- **Guard cho bản release:** `REVENUECAT_ENTITLEMENT_ID` khác rỗng thì fail (hiện chỉ là warning). Cũng fail khi URL không phải `https`, hoặc thiếu RevenueCat / Supabase / Google config.
- **R8:** bật `minifyEnabled` + `shrinkResources` cho release, keep rules cho `@JavascriptInterface`, `WebViewCompat.WebMessageListener`, RevenueCat. Kiểm bằng smoke trên bản release ký debug-key. Nếu rủi ro cao thì tắt và ghi lại lý do.
- **Không thêm `applicationIdSuffix` cho debug**, để giữ một package cho RevenueCat / Google. Đổi lại cần OAuth client SHA-1 debug (D4).

### 4.10 Quyền và capability

- **`PermissionCoordinator`:** mỗi lần chỉ một yêu cầu quyền (ví dụ micro, sau này notification / activity / Health Connect). Có trạng thái "không hỏi lại", và mở Settings của app khi người dùng chủ động bấm.
- **`CapabilityRegistry`** dựng `capabilities`:
  - `googleSignIn` (như hiện tại);
  - `sessionRefresh` (§4.4);
  - `iconRevisions { protocolVersion: 1, supported: true }` (D8 đã chốt INCLUDED);
  - `healthConnect` / `phoneSteps` / `backgroundTracking` / `notifications` = `{ protocolVersion: 1, supported: false }` cho tới M3–M5, để web gate theo capability thay vì theo platform.
- **`SYNC_ICON_REVISIONS`** trên Android: trả `ICON_REVISIONS_SYNCED { synced: true }` (không có cache card).

### 4.11 Thay đổi web (Lovable)

Gửi **một** `send_message` sau khi phía native đã chạy được trên emulator (ước tính 4–6 credit). Không đổi gì với iOS, browser và app Android đang có (chưa báo capability mới), nên publish lúc nào cũng an toàn.

| ID | Thay đổi | Gate |
|---|---|---|
| W1a | Trên Android, `sendAuthSession` / `clearAuthSession` chỉ gửi qua `HonouredAuth`, và chỉ khi `sessionRefresh.supported && transport === "trusted-auth-v1"`; nếu không thì không gửi gì. Capability chưa biết thì chờ `waitForNativeCapabilities` (4 s). Khi `NATIVE_READY` tới với capability, gửi phiên hiện tại một lần. iOS giữ nguyên đường `webkit.messageHandlers` | Platform + capability |
| W1b | `native-session-refresh.ts`: đổi `nativePlatform() !== "ios"` thành iOS, hoặc Android có capability như W1a. Refresh vẫn chờ capability trước khi dùng token của trang | Như W1a |
| W2 | Nhận `CONTRACT_LINK_OPENED`, dùng chung đường xử lý với `LIVE_ACTIVITY_OPENED` | Chỉ khi có event |
| W3 | Copy Android cho các chỗ "iPhone app" theo D7; gate theo capability `healthConnect` thay vì `nativePlatform() === "ios"` (`health-settings.ts`, `icon-days.ts` `NON_NATIVE_NOTE`, Home, Settings) | Theo quyết định D7 |
| W5 | `AuthGate.tsx:34`: chỉ dùng OAuth web cho nút Google khi `nativePlatform() === null`; shell không có capability Google thì ẩn nút | Platform + capability |
| W6 | (chờ khách) Contract / Icon đo bằng Health tạo trên Android: cảnh báo, chặn hay chỉ ghi chú, cho tới M3/M4 (bảng parity R2) | Capability `healthConnect` |
| W7 | (nếu D9 = A) `timer-store.ts`: thay `hasNativeBridge()` bằng helper "native giữ timer" (iOS hoặc `testamentTimer.supported`) | Platform + capability |
| W4 | Test: iOS gửi đúng như trước (snapshot); Android không capability → không gửi token; Android có capability → qua `HonouredAuth`; refresh trên Android đi native; app Android cũ; browser | — |

## 5. Task và giờ

| # | Task | Giờ | Phụ thuộc | Deliverable / DoD |
|---|---|---:|---|---|
| A1 | Audit baseline + bảng parity Android | 2 | D1 (để chốt) | `docs/phase5/android-parity-matrix.md`: mỗi workflow INCLUDED / ADAPTED / EXCLUDED kèm lý do. Baseline ghi 4 giá trị: build iOS, Lovable `df0dc04d` / deployment `b29e7446`, md5 các hàm SQL chính (query chỉ đọc), danh sách deviation (D6, D7, D8, landscape signature, Word Tracker, Live Activity) |
| A2 | Version, ký release, guard config, R8 | 3 | D3 | §4.9; `bundleRelease` ra AAB ký bằng upload key thử; smoke bản release trên emulator |
| A3 | Deep link + định tuyến khi cold start | 3 | B4 | §4.7; unit test parser; instrumentation: `adb shell am start -d honoured://contract/...` khi app tắt hẳn và khi đang chạy |
| A4 | Lifecycle, renderer crash, process death, edge-to-edge | 4 | — | §4.8; test `chrome://crash`; `adb shell am kill` rồi mở lại; ảnh chụp insets |
| A5 | Quyền + capability + test nền tảng | 3 | — | §4.10; thêm `androidTest` (androidx.test); emulator API 26/28 cho minSdk (tải system image) |
| B1 | Kênh tin cậy cho message phiên | 4 | — | §4.1, §4.4; `HonouredNative` từ chối, `HonouredAuth` nhận; reply chỉ về proxy của document hiện tại |
| B2 | Lưu phiên mã hoá | 4 | — | §4.2; test JVM (cipher giả) + instrumentation (Keystore thật, hỏng file, mất khoá) |
| B3 | Refresh tuần tự, chống dùng lại token | 4 | B2 | §4.3; test: 5 người hỏi cùng lúc → 1 request; superseded; 400/401; mạng lỗi; user khác |
| B4 | Hàng đợi sự kiện bền | 3 | — | §4.6; test: giới hạn 50, giao đúng một lần, không có token, xoá khi đổi account |
| B5 | Dọn dữ liệu khi đăng xuất / đổi tài khoản | 2 | B2, B4 | §4.5; test thứ tự; E2E 2 tài khoản trên emulator |
| B6 | Test bridge / phiên | 1 | B1–B5 | requestId, reload giữa chừng, document cũ, race token, tách account |
| G1 | Adapter web + gate capability | 3 | B1–B3 | W1a, W1b, W2 qua Lovable; review diff; vitest + type check |
| G2 | Copy / trạng thái Health trên Android | 2 | D7 | W3. Giao diện chọn nguồn Health Connect làm ở M3, khi đã có hợp đồng dữ liệu |
| G3 | Kiểm parity luồng chung trên WebView | 2 | D2, D5 | Chữ ký (dọc), revise target theo thứ + ký lại (D8), History mới (vuốt, 7 ngày), Journal voice (quyền micro, từ chối rồi bật lại), Link Google cho user Apple (D6), edge-to-edge; sửa lỗi nhỏ |
| G4 | Test Lovable / browser / WebView | 4 | G1 | W4; QA local bằng mock Supabase (`scripts/local-qa`) với bridge Android giả; emulator + máy thật: đăng nhập, refresh, đổi tài khoản, app Android cũ + web mới |
| | **Tổng** | **44** | | |

## 6. Thứ tự làm và mốc

Làm trên branch `feat/android-m2` (repo `honoured-native`). Commit từng phần; chỉ push / merge khi Jimmy bảo.

1. **Ngày 1:** A1 (bảng parity, baseline "chờ PASS"); B2 + B1 khung.
2. **Ngày 2:** B3, B4, B5, B6. Capability `sessionRefresh` vẫn **tắt** trong build.
3. **Ngày 3:** gửi Lovable W1/W2 (+W3 nếu D7 đã chốt). Review, publish khi Jimmy duyệt (không ảnh hưởng app nào đang chạy). Bật capability trên branch, E2E trên emulator với tài khoản test (D5): đăng nhập, để access token hết hạn (≈ 1 giờ hoặc ép), refresh qua native, đăng xuất, đổi tài khoản.
4. **Ngày 4:** A4, A5, A3.
5. **Ngày 5:** A2 (cần D3), G3 / G4 trên emulator, rồi máy thật (D2).
6. **Ngày 6:** demo trên máy thật, evidence, tracker, bàn giao. Nếu D1 xong thì chốt baseline.

Tracker: `docs/phase5/phase5-m2-progress-tracker.md`, cùng format tracker M1. Evidence lưu trong `docs/phase5/evidence/m2/`.

## 7. Kế hoạch test

| Tầng | Nội dung | Công cụ |
|---|---|---|
| Unit JVM | Store (cipher giả), refresher (HTTP giả), policy decline, coalescing, event queue, deep link parser, capability JSON, guard trong Gradle | JUnit4 + kotlinx-coroutines-test |
| Instrumentation | Keystore thật; `HonouredAuth` chỉ nhận từ đúng origin (trang test origin khác bị bỏ); legacy từ chối token; renderer crash; deep link khi app tắt hẳn | androidx.test trên emulator API 35 (+ API 28 smoke) |
| Web | W4 trong vitest; type check; QA local mock | Lovable + `scripts/local-qa` |
| E2E emulator | Tài khoản test thật: đăng nhập email, refresh do native, đăng xuất, đổi tài khoản; app chạy nền 1 giờ rồi mở lại không bị văng; web mới + app Android cũ | Emulator API 35 |
| Máy thật | Bảng parity G3 + demo exit gate | Pixel hoặc A06 5G |

**Test bắt buộc chống văng đăng nhập:** chạy hai lượt refresh song song (web + native API) với cùng một token → chỉ một request tới Supabase. Sau đó vẫn đăng nhập, và lần refresh tiếp theo vẫn thành công.

## 8. Checklist nghiệm thu M2

- [ ] Android chỉ nhận `SET` / `CLEAR` / `REFRESH_AUTH_SESSION` qua `HonouredAuth`; `HonouredNative` trả `insecure_transport` và không giữ gì.
- [ ] Phiên được lưu mã hoá (Keystore), không có trong backup / device transfer, không có trong log (grep logcat khi chạy E2E).
- [ ] Mỗi refresh token chỉ được refresh một lần; không văng đăng nhập sau ≥ 2 vòng hết hạn token trên emulator và trên máy thật.
- [ ] Đăng xuất và đổi tài khoản xoá phiên, hàng đợi, broadcast đang chờ của account cũ.
- [ ] Deep link `honoured://contract/...` mở đúng contract khi app tắt hẳn và khi đang chạy; link sai không crash.
- [ ] Renderer crash và process death không làm app crash, mở lại đúng trạng thái.
- [ ] `bundleRelease` ra AAB ký; bản release fail khi thiếu config hoặc khi đang dùng entitlement test.
- [ ] Web mới: iOS không đổi (test snapshot); app Android cũ không nhận token; app Android mới refresh qua native.
- [ ] Bảng parity đủ mọi workflow, có quyết định D6–D8; luồng chung chạy trên máy Android thật (ảnh / video).
- [ ] Unit + instrumentation + vitest pass; `bridge.md` cập nhật.

**Definition of Done:** checklist trên đạt; Jimmy xem demo trên máy thật; baseline đã chốt (hoặc ghi rõ còn chờ D1).

## 9. Rủi ro

| Rủi ro | Xử lý |
|---|---|
| Văng đăng nhập do hai nơi cùng refresh | Một capability cho cả gói; web chờ capability; test song song (§7) |
| WebView cũ không có `WEB_MESSAGE_LISTENER` | `sessionRefresh.supported=false`: web tự refresh như hiện tại, native không giữ phiên |
| Keystore lỗi trên một số máy (đặc biệt Samsung đời cũ) | Lỗi → coi như không có phiên, web tự refresh; ghi vào parity matrix |
| R8 phá bridge | Keep rules + smoke bản release; tắt nếu cần |
| Chưa có máy thật / D1 chưa PASS | Làm hết trên emulator; exit gate để mở, ghi blocker trong tracker |
| Tài khoản Apple không đăng nhập được trên Android (D6, đã chốt EXCLUDED) | Ghi deviation; hướng dẫn link Google hoặc đặt mật khẩu trên iPhone; G3 kiểm luồng này |

## 10. Ngoài scope M2

Health Connect, `TYPE_STEP_COUNTER`, chọn nguồn (M3); sync nền, timer, foreground service, đối soát deadline (M4); FCM, notification, App Links có xác minh, Google Play Billing E2E, submission (M5); Sign in with Apple trên Android (D6, đã loại khỏi scope).
