# Plan Google Sign-In — iOS + Android

Ngày lập: 24/09/2026. Trạng thái 24/09: **native iOS + Android và web (Lovable, chưa publish) đã implement và qua kiểm tra tự động/simulator; chưa E2E với Google/Supabase thật** — xem [mục 12](#12-tiến-độ-triển-khai--2409).

Tài liệu mở rộng N-28 trong [plan V1.1](v1.1-plan.vi.md). Estimate 8h cũ chỉ là baseline tích hợp iOS; không bao gồm toàn bộ phạm vi dưới đây và không phải cam kết thương mại mới.

## 1. Kết quả cần đạt và phạm vi

Người dùng bấm “Continue with Google” trong app iOS hoặc Android, chọn tài khoản bằng giao diện Google của nền tảng, rồi vào Honoured bằng session Supabase hợp lệ.

Phạm vi đề xuất:

- Đăng nhập/đăng ký bằng Google khi chưa có session Honoured.
- Liên kết Google từ Settings vào tài khoản Honoured đang đăng nhập; giữ nguyên Supabase `userId` và dữ liệu của tài khoản đó.
- Hỗ trợ liên kết anonymous account **nếu web đã có session anonymous**; không tự chuyển sản phẩm sang anonymous-by-default.
- Cùng một tài khoản Google trên hai nền tảng phải vào cùng một Supabase account trong cùng môi trường.
- Đồng bộ đúng account với RevenueCat và các tính năng native hiện có. Không coi Google profile/email là định danh sở hữu dữ liệu.
- Giữ nguyên Apple Sign-In, billing, timer, HealthKit và Live Activities; không làm tính năng three-blink trong gói này.

Ngoài phạm vi: gộp dữ liệu hai account, chuyển subscription giữa account, unlink/revoke Google, Google Drive/Gmail permissions, Firebase Auth, viết lại hệ thống đăng nhập, hoặc thêm Google OAuth cho trình duyệt thông thường. Không có migration DB/Edge Function mới theo kiến trúc đề xuất; nếu audit web phát hiện cần, phải bổ sung phạm vi trước.

## 2. Hiện trạng đã kiểm tra trong checkout

| Thành phần | Hiện trạng | Hệ quả cho plan |
|---|---|---|
| iOS | Bridge v2; Apple native trả credential về web; Supabase session lưu Keychain | Google đi theo ranh giới native lấy credential, web xác thực; không thêm Supabase SDK native |
| iOS dependencies | `ios/project.yml` có RevenueCat, chưa có Google | Thêm GoogleSignIn qua SPM vào app target, không vào widget |
| iOS URL | `.onOpenURL` đang phục vụ `honoured://contract/...` | Thêm router Google callback nhưng giữ nguyên deep link Live Activity |
| Android | Bridge v1, billing; chưa có provider auth hoặc native Supabase session store | Thêm Credential Manager và capability Google riêng; không giả lập toàn bộ bridge v2 |
| Android toolchain | JDK 17, minSDK 26, compile/targetSDK 35, AGP 8.7.3, Kotlin 2.0.21 | Chọn dependency stable tương thích; không tự nâng toàn bộ toolchain |
| Web | Source Lovable nằm ngoài checkout này | Phải kiểm tra source/lockfile/deployed version hiện tại trước khi code; ghi chú cũ không chứng minh production hiện tại |
| Native bridge | Chưa có bảo vệ đầy đủ origin/main frame và callback Google theo document/account | Bổ sung trước khi truyền Google token; không dùng `requestId` đơn lẻ để xác định chủ callback |
| Test | Suite iOS hiện có tập trung Live Activity core; Android chưa có auth tests | Thêm auth test harness riêng; không tính suite cũ là bằng chứng Google hoạt động |

Các điểm account isolation phải xử lý trong phần tích hợp: iOS `SET_AUTH_SESSION`/clear/refresh có các bước async; kết quả cũ không được ghi đè session mới. Android `LOGOUT_USER` hiện chỉ logout RevenueCat, không phải logout Google/Supabase. Các broadcast auth cũ không được phát sang account mới.

Code cần đọc lại lúc bắt đầu: `ios/Honoured/Auth/`, `Bridge/NativeBridge.swift`, `WebView/HonouredWebView.swift`, `App/HonouredApp.swift`, `LiveActivities/NativeBridge+LiveActivities.swift`; Android `MainActivity.kt`, `bridge/NativeBridge.kt`, `AppConfig.kt`; cùng [bridge contract](bridge.md).

## 3. Kiến trúc và quy tắc tài khoản

```text
Web: nút Google + intent + snapshot tài khoản
  → Native: kiểm tra origin/context → Google SDK / Credential Manager
  → Web: credential dùng một lần, chỉ cho request/document còn hiệu lực
  → Supabase Auth: kiểm chứng ID token → sign in hoặc link identity
  → Web: chấp nhận session cuối cùng, cập nhật UI/data
  → Native: đồng bộ auth context; iOS SET_AUTH_SESSION; RevenueCat IDENTIFY_USER
```

Native thành công mới chỉ nghĩa là **lấy được Google credential**, chưa phải Honoured đăng nhập thành công. Supabase là nơi kiểm chứng credential và cấp session. Không tự giải mã JWT rồi dùng claim để cấp quyền. [Google: xác thực với backend](https://developers.google.com/identity/sign-in/ios/backend-auth).

### 3.1 Hai intent tách biệt

| Tình huống | Intent/API phía web | Kết quả mong đợi |
|---|---|---|
| Chưa có session | `sign_in` → `signInWithIdToken` | Vào account Google đã tồn tại hoặc tạo account theo chính sách Supabase |
| Đã đăng nhập, muốn thêm Google | `link` → `linkIdentity` | `user.id` trước và sau giống nhau |
| Đang dùng anonymous account, muốn lưu account này | `link` nếu sản phẩm đã hỗ trợ anonymous | Giữ UUID và contract/dữ liệu của anonymous account |
| Google identity đã thuộc account khác khi đang link | Báo xung đột, giữ nguyên session hiện tại | Không fallback sang sign-in, không merge/unlink tự động |
| Muốn chuyển sang account Google khác | Logout rõ ràng rồi `sign_in` | Không âm thầm chuyển account từ nút “Link Google” |

Supabase hiện có tài liệu `linkIdentity` bằng native ID token; manual linking cần được bật. Auto-link theo verified email là hành vi của Supabase, không thay thế intent/link flow của app. Không tự ghép account bằng email, đặc biệt với Apple private relay. [Supabase Identity Linking](https://supabase.com/docs/guides/auth/auth-identity-linking).

**Gate SDK web:** kiểm tra phiên bản `@supabase/supabase-js`/`auth-js` thực tế và typecheck overload ID-token `linkIdentity`. Nếu chưa hỗ trợ, nâng phiên bản có kiểm thử trong web repo; không cast `any` để che API sai. [Overload trong auth-js](https://github.com/supabase/auth-js/blob/master/src/GoTrueClient.ts).

### 3.2 Ranh giới session và billing

- Payload credential/nonce do app và bridge quản lý chỉ ở bộ nhớ trong lần đăng nhập; không ghi vào log, localStorage của bridge, `NativeEventStore`, hàng đợi offline hoặc crash breadcrumbs. Google SDK iOS có secure credential cache riêng; dùng SDK `signOut` khi logout, không hứa SDK hoàn toàn không persist và không bổ sung kho Google token riêng. [GIDSignIn cache/sign-out](https://developers.google.com/identity/sign-in/ios/reference/Classes/GIDSignIn).
- Session ứng dụng vẫn do Supabase quản lý. iOS dùng cơ chế Keychain hiện có; Android không cần thêm kho Supabase refresh token chỉ để làm Google Sign-In.
- Sau khi web chấp nhận session: đồng bộ context; trên iOS gửi `SET_AUTH_SESSION` với `expiresAt` **Unix seconds**; billing dùng `IDENTIFY_USER { userId: supabaseUser.id }`.
- Serialize/coalesce native `IDENTIFY_USER`/`LOGOUT_USER` theo auth generation đã chấp nhận. Callback bị drop chưa đủ nếu SDK billing đã đổi identity; phải bảo đảm operation cũ kết thúc trước binding mới và fence cả event `ACCESS_STATUS` theo ownership.
- Link giữ cùng UUID không được clear Health/timer/Live Activity hoặc tạo RevenueCat identity khác. Explicit logout/account switch phải clear đúng ownership hiện có.
- Google sign-out, Supabase sign-out và RevenueCat logout là ba bước riêng. Lỗi cleanup SDK/billing không được làm app giữ lại session đã logout hoặc tự đăng nhập lại. Serialize provider cleanup với presentation mới để cleanup A không chạy muộn sau sign-in B.
- Việc có cùng Supabase UUID không tự chứng minh entitlement cross-platform; kiểm thử RevenueCat theo cấu hình hiện hành, không thêm transfer/restore tự động.

## 4. Google Console, Supabase và cấu hình build

### 4.1 Checklist trước khi nghiệm thu E2E

| Cấu hình | Ai cung cấp/thực hiện khi triển khai | Yêu cầu |
|---|---|---|
| Google Cloud/Auth Platform project | Owner của khách + dev | Xác nhận project đúng môi trường, quyền quản trị, consent branding/support email/privacy URL, audience/test users/publishing status |
| Web/server OAuth client | Owner + dev | Dùng làm server audience chung cho ID token iOS/Android trong cùng môi trường |
| iOS OAuth client | Owner + dev | Bundle ID của app được ký thực tế; reversed client ID URL scheme |
| Android OAuth clients | Owner + dev | Package `com.honoured.app` hoặc package build thực tế + SHA-1 của từng chứng thư ký |
| Android signing | Owner release | Debug key, release key nếu sideload, **Play App Signing app-signing certificate**; không nhầm chỉ đăng ký upload key |
| Supabase Google provider | Owner backend/Lovable Cloud + dev | Bật provider, danh sách client IDs/audiences đúng môi trường; secret chỉ nhập phía server/provider configuration |
| Supabase manual linking | Owner backend | Bật nếu nghiệm thu link flow; nếu chưa có thì báo rõ dependency, không biến link thành sign-in |
| Web source và deploy | Owner web | Có quyền sửa/test repo; xác định commit/build đang chạy trong app |
| Thiết bị và distribution | Dev + owner store | iPhone, Android Google Play-capable; TestFlight và Play internal test cho bản release |

Không thay đổi Console, provider settings hoặc phát hành bản build trong bước lập plan này.

### 4.2 Mapping public config dự kiến

| Key dự kiến | Nơi dùng | Ý nghĩa |
|---|---|---|
| `GOOGLE_WEB_CLIENT_ID` | iOS `GIDServerClientID`, Android `serverClientId` | Web/server OAuth client ID, không phải Android/iOS client ID |
| `GOOGLE_IOS_CLIENT_ID` | iOS `GIDClientID` | Native iOS OAuth client ID |
| `GOOGLE_IOS_REVERSED_CLIENT_ID` | iOS `CFBundleURLSchemes` | Scheme callback Google riêng; không thay scheme `honoured` |
| Trusted web origin | Hai platform, từ config URL hiện có | Exact HTTPS scheme + host + normalized port; không wildcard |

Tên key chốt ở G-00 sau khi đối chiếu convention repo. Cập nhật `.env.example`, `ios/Config.xcconfig.example`, `scripts/sync-env.sh`, `AppConfig`/Info.plist/BuildConfig. Client IDs là public config; OAuth client secret và service-role key **không** được đưa vào app/web bundle. Không đọc/ghi đè `.env` có sẵn để lập plan.

Chỉ xin các scope định danh cơ bản `openid`, `email`, `profile`; không xin Health, Drive/Gmail hoặc offline Google API access cho tính năng đăng nhập này.

iOS phải cấu hình riêng client và server client, đăng ký reversed URL scheme. Android chọn Credential Manager cho Google ID token; không thêm Firebase, Google Services plugin hoặc `google-services.json` theo mặc định. [Google iOS setup](https://developers.google.com/identity/sign-in/ios/start-integrating), [Android Sign in with Google](https://developer.android.com/identity/sign-in/credential-manager-siwg).

Provider Supabase cần chấp nhận đúng client IDs; khi cấu hình nhiều ID, kiểm tra thứ tự web client theo hướng dẫn. Redirect URL của Supabase OAuth browser flow không thay cho iOS SDK callback và không mặc nhiên yêu cầu custom scheme Android trong native ID-token flow. [Supabase Google provider](https://supabase.com/docs/guides/auth/social-login/auth-google).

### 4.3 Nonce — kiểm chứng trước khi tích hợp toàn luồng

Thiết kế đề xuất: mỗi attempt sinh `rawNonce` bằng CSPRNG (ít nhất 32 bytes), lấy SHA-256 hex gửi làm Google nonce, trả raw nonce cùng ID token cho web. Web đưa raw nonce vào Supabase. Không tái sử dụng nonce khi retry.

Tài liệu Supabase mô tả cặp hashed/raw nonce, nhưng phần ví dụ iOS vẫn hướng dẫn skip nonce check. Không áp dụng việc tắt kiểm tra trên toàn provider theo ví dụ cũ. [Supabase nonce guidance](https://supabase.com/docs/guides/auth/social-login/auth-google).

SDK iOS release **10.0.0** có overload nhận custom nonce; đây là candidate để kiểm tra với toolchain hiện tại, không suy từ nhánh main và không tự nâng Xcode. Pin bản stable có nonce sau compile spike; nếu phải chọn bản khác, xác minh public API ngay trên tag đó. [Header release 10.0.0](https://github.com/google/GoogleSignIn-iOS/blob/10.0.0/GoogleSignIn/Sources/Public/GoogleSignIn/GIDSignIn.h), [release notes](https://github.com/google/GoogleSignIn-iOS/releases/tag/10.0.0).

Gate bắt buộc: token thật trên từng nền tảng phải exchange thành công khi bật nonce validation; wrong/missing nonce phải bị từ chối. Nếu SDK/config không đạt, dừng để điều chỉnh phương án, không âm thầm bật `Skip nonce check`. Debug chỉ ghi pass/fail/claim-presence, không ghi token hoặc nonce.

## 5. Bridge contract đề xuất

Tên message và shape sau đây là **contract cần implement**, chưa phải API đang có. Chốt chung với web trước khi làm hai platform.

### 5.1 Capability độc lập với bridge version

Thêm cùng shape vào mọi đường `NATIVE_READY` và `PLATFORM_INFO`, giữ nguyên các field/capability hiện có:

```json
{
  "capabilities": {
    "googleSignIn": {
      "protocolVersion": 1,
      "supported": true,
      "configured": true,
      "transport": "trusted-auth-v1",
      "intents": ["sign_in", "link"]
    }
  }
}
```

`supported` phản ánh native/transport có hỗ trợ; `configured` phản ánh public config hợp lệ, **không** chứng nhận Supabase/Console hoạt động. Link còn phụ thuộc web/provider gate. Không nâng Android từ bridge v1 lên v2 chỉ để hiện nút Google, vì v2 hiện gắn với nhiều tính năng iOS khác.

Web chỉ bật nút khi feature flag, capability, transport và provider readiness phù hợp. Old native không có capability tiếp tục chạy bình thường. Không mở OAuth trong embedded WebView làm fallback.

### 5.2 Context và message

Google phải dùng được khi signed out; không tái sử dụng nguyên admission của Live Activity vốn cần bound account.

| Request | Payload thêm ngoài `requestId` | Reply / quy tắc |
|---|---|---|
| `SYNC_AUTH_CONTEXT` | `userId: string \| null` | `AUTH_CONTEXT_SYNCED { authContextId, userId }`; context native cấp, memory-only; gửi sau ready và mỗi lần đổi user/logout |
| `SIGN_IN_WITH_GOOGLE` | `intent`, `authContextId` | `GOOGLE_SIGN_IN_SUCCESS` hoặc `GOOGLE_SIGN_IN_FAILED`; `sign_in` yêu cầu context signed out, `link` yêu cầu có user |
| `CANCEL_GOOGLE_SIGN_IN` | `authContextId`, `targetRequestId` | `GOOGLE_SIGN_IN_CANCEL_ACCEPTED`; vô hiệu attempt cụ thể, không revoke tài khoản Google |
| `CLEAR_GOOGLE_SIGN_IN` | `authContextId` | `GOOGLE_SIGN_IN_CLEARED { authContextId, providerCleared, warningCode? }`; trả context mới, invalidation đồng bộ trước cleanup SDK async; logout idempotent |

`SYNC_AUTH_CONTEXT` chỉ là hint ownership để chống callback cũ, không cấp quyền DB. Idempotent khi user/document không đổi; context mới khi user thay đổi, explicit logout, hoặc document thay thế. Native context không chứa Supabase token. iOS `SET_AUTH_SESSION` chỉ làm mất hiệu lực attempt khi đổi ownership; token refresh cùng UUID giữ context, không hủy sheet link hợp lệ. Explicit clear/logout luôn invalidation.

Logout: invalidation web intent ngay → sync context signed out/clear native account ownership → gọi provider cleanup với context hiện tại. Kết quả cleanup trả context mới phải được web nhận trước lần Google tiếp theo. Không mở presentation mới khi cleanup cũ chưa kết thúc; cleanup retry cũng phải có generation guard, không chạy muộn lên owner mới.

Ví dụ request sau khi đã sync context:

```json
{
  "type": "SIGN_IN_WITH_GOOGLE",
  "payload": {
    "requestId": "gsi-request-uuid",
    "intent": "sign_in",
    "authContextId": "native-issued-context"
  }
}
```

Ví dụ reply trực tiếp, không phải broadcast:

```json
{
  "type": "GOOGLE_SIGN_IN_SUCCESS",
  "payload": {
    "requestId": "gsi-request-uuid",
    "intent": "sign_in",
    "authContextId": "native-issued-context",
    "idToken": "<transient-google-id-token>",
    "rawNonce": "<transient-raw-nonce>"
  }
}
```

`accessToken` là field optional: iOS có thể trả nếu cần cho kiểm tra `at_hash`; Android Google ID credential không mặc định cấp Google API access token. Không thêm scope/API authorization chỉ để ép hai platform trả cùng fields. Web map field có mặt thành `access_token`, không gửi chuỗi rỗng. Kiểm tra yêu cầu theo token thực tế và SDK Supabase. [Supabase ID-token credential type](https://github.com/supabase/auth-js/blob/master/src/lib/types.ts).

Lỗi chuẩn trong `GOOGLE_SIGN_IN_FAILED`: `code`, `message` an toàn, `requestId`, `authContextId`; taxonomy dự kiến `cancelled`, `in_progress`, `not_configured`, `unsupported`, `invalid_payload`, `stale_context`, `no_credential`, `network_error`, `provider_error`, `timeout`. Không trả nguyên exception có dữ liệu nhạy cảm. Context/origin đã mất tin cậy thì drop callback, không cố gửi lỗi/token sang document mới.

### 5.3 Trust boundary và lifecycle

- iOS: kiểm tra `WKScriptMessage.frameInfo.isMainFrame`, security origin và URL document theo allowlist; kiểm tra lại trước trả credential. Không cho external redirect chạy trong WebView vẫn có auth bridge.
- Android: thêm AndroidX WebKit `addWebMessageListener`, exact allowed origin + `isMainFrame`; runtime gate bằng `WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER)`. Dùng endpoint auth riêng, thí dụ `HonouredAuth`, để bảo toàn bridge billing cũ. **Reject nhóm auth mới trên `addJavascriptInterface` cũ**. Reply về đúng requesting frame; adapter web chuẩn hóa về dispatcher hiện có, giữ `requestId`/`honoured:native` compatibility.
- Không dùng `webView.url` đơn lẻ để xác thực sender Android; không dùng `*` allowed origin. Nếu WebView không hỗ trợ secure transport thì Google unavailable, không hạ xuống endpoint kém an toàn. [Android bridge security](https://developer.android.com/privacy-and-security/risks/insecure-webview-native-bridges), [origin-scoped messaging](https://developer.android.com/develop/ui/views/layout/webapps/native-api-access-jsbridge).
- Mỗi attempt chụp document generation, auth context, intent, requestId. Navigation bắt đầu/reload, account change/logout, destroy hoặc timeout đều invalidation; khi quay lại ready phải handshake lại.
- Tối đa một provider presentation; iOS lock chung Apple/Google. Double tap trả `in_progress`. Một request chỉ có tối đa một kết quả; duplicate không phát lại token đã tiêu thụ.
- Timeout UX đề xuất 120 giây, không dùng timeout RPC ngắn cho sheet đăng nhập. Timeout/cancel vô hiệu result; nếu SDK chưa đóng UI thì chưa mở sheet thứ hai cho đến khi presentation cũ kết thúc.
- Token không được queue/replay khi `NATIVE_READY` tới lại. Không persist request/nonce qua process death. Background ngắn để Google UI chạy không tự coi là logout; document/owner thay đổi mới mất hiệu lực.
- Auth event đang chờ và iOS async session save/refresh phải gắn account/session generation. Sau mỗi `await`, trước persist/dispatch phải xác nhận ownership còn đúng; refresh cũ không được hồi sinh session đã logout.
- Debug stub/loggers phải redact Google ID/access token, nonce và mọi authorization code. Không đưa auth payload vào analytics.

## 6. Công việc theo nền tảng

### 6.1 iOS

1. Thêm GoogleSignIn SPM trong `ios/project.yml`; link **app target only**. Compile spike SDK stable hỗ trợ nonce với iOS 16/toolchain hiện tại, pin version; không sửa generated `.xcodeproj` bằng tay.
2. Thêm config/client validation. Missing/unresolved config → capability `configured:false`, không crash app. Giữ các URL scheme có sẵn trong Info.plist.
3. Tạo `Auth/GoogleSignInCoordinator.swift`: MainActor presentation, nonce, SDK outcome normalization, sign-out, không tự đăng nhập Honoured khi restore Google cache.
4. Thêm auth attempt/state coordinator testable; lock Apple/Google, generation/one-shot/cancel. Chỉ sửa luồng Apple ở phần dùng chung cần thiết, có regression test.
5. Tạo `App/AppURLRouter.swift` hoặc tương đương: nhận Google scheme đã cấu hình → `GIDSignIn.handle`; URL contract → LiveActivity router hiện tại. Không forward URL tùy ý sang Google handler.
6. Tích hợp secure admission, message allowlist, response và capability builder; tách/đặt helper chung hợp lý thay vì để Google phụ thuộc feature Live Activities.
7. Fence session writes/refresh và account-scoped events như mục 5.3. Cập nhật debug stub với credential giả; không in credential thật.
8. Tạo unit tests cho auth state, integration harness cho SDK adapter/URL routing và bridge; cấu hình test sources/target rõ ràng. Không đặt auth core vào `LiveActivities/Core` chỉ để tận dụng test target.

### 6.2 Android

1. Thêm phiên bản **stable** tương thích của `androidx.credentials:credentials`, `credentials-play-services-auth`, `googleid`, AndroidX WebKit và lifecycle/coroutine dependencies cần thiết. Không copy alpha version từ ví dụ docs mà chưa đánh giá.
2. Tạo `auth/GoogleSignInCoordinator.kt` và auth state testable; Activity/lifecycle ownership rõ ràng, không giữ Activity đã destroy.
3. Dùng explicit button flow `GetSignInWithGoogleOption` với **web/server client ID** và nonce. V1 không auto-select/auto-login khi mở app. Validate credential type và parse bằng `GoogleIdTokenCredential`; chuẩn hóa cancellation/no credential/provider errors. [Credential Manager implementation](https://developer.android.com/identity/sign-in/credential-manager-siwg-implementation).
4. Lắp origin-scoped auth transport trước load web, giữ billing bridge tương thích. Centralize ready/platform info để cả ba đường hiện tại trả capability giống nhau.
5. Xử lý Activity recreation/rotation: request gắn document cũ bị invalidation, hủy coroutine/presentation khi API cho phép, web mới retry bằng thao tác mới; không lưu token vào saved state.
6. Logout gọi `clearCredentialState` qua cleanup path độc lập RevenueCat. Đây không phải thu hồi Google consent. [Credential Manager sign-out](https://developer.android.com/identity/sign-in/credential-manager-siwg-implementation).
7. Thêm unit tests và WebView instrumentation cho frame/origin/callback ownership. Kiểm tra manifest theo SDK chọn; native ID-token flow không tự thêm OAuth custom scheme.
8. Xác minh bản release với SHA-1 Play App Signing và package thực tế, không lấy debug pass làm bằng chứng release pass.

### 6.3 Web/Lovable — bắt buộc để feature hoàn chỉnh

1. Audit Auth screen, Settings, auth store, `native-bridge.ts`, lifecycle/logout, SDK lockfile và deployment hiện tại. Xác nhận anonymous behavior thực tế; không áp dụng giả định từ L-11 cũ.
2. Thêm type/parser/transport adapter, capability gating, context handshake, timeout/cancel và credential reply không đi qua persistent event buffer.
3. Thêm nút Google đúng branding, loading/disabled và UX cancel/retry; iOS vẫn giữ Apple. Settings hiện “Link Google” hoặc trạng thái đã linked theo identities từ Supabase, không theo cache Google SDK.
4. Native response được chấp nhận chỉ khi request/document/context/intent và snapshot current user còn khớp; token dùng một lần.
5. Với `sign_in`, gọi `supabase.auth.signInWithIdToken({ provider: 'google', token: idToken, nonce: rawNonce, ...optionalAccessToken })`.
6. Với `link`, gọi `supabase.auth.linkIdentity` với cùng credential fields trong session hiện hữu; xác nhận UUID không đổi. Xử lý manual-linking-disabled, conflict và expired session; không fallback sang sign-in.
7. Serialize các thao tác **mutate auth session** của web: sign-in/link/logout/account switch. Logout trong lúc đang exchange phải invalidation intent ngay; nếu SDK ghi session khi response muộn thì transaction coordinator dọn session của attempt bị hủy trước khi cho attempt mới chạy. Không chỉ ignore promise result trong khi SDK đã persist session. Cleanup attempt cũ dùng local-session semantics phù hợp (ví dụ `signOut({ scope: 'local' })`), không mặc định global sign-out làm logout các thiết bị khác, và tuyệt đối không clear session mới đã được chấp nhận. Nếu link đã commit phía server trước cancel/logout thì không tự unlink để “rollback”; app chỉ hủy việc tiếp tục flow local và phản ánh identities thật ở lần tải sau. [Supabase sign-out scopes](https://supabase.com/docs/reference/javascript/auth-signout).
8. Gate side effects của `onAuthStateChange` trong transaction trên: chỉ session được chấp nhận mới hydrate data, gọi native session sync và RevenueCat identify. Logout mới luôn thắng pending sign-in cũ; test rõ thứ tự callback/event.
9. Khi Supabase thành công nhưng native session/billing sync lỗi: giữ UI trạng thái cần retry phần sync, không đăng nhập lại hoặc tạo thêm account. Không cho Health/account-owned native work tiếp tục dưới user cũ; block capability đó đến khi ownership được đồng bộ.
10. Link cùng UUID giữ data/subscription state. Account switch/logout clear query caches/store/subscriptions theo ownership hiện có. Sau ready/relaunch resync từ Supabase session, không dùng Google cached user làm nguồn sự thật.
11. Web trong browser/old native không có capability không gọi native Google và không rơi vào redirect loop. Browser OAuth là scope riêng nếu khách cần.

## 7. Gói việc, dependency và estimate

Estimate dev + kiểm thử, **42–60 giờ công**; không gồm thời gian chờ quyền Console, quyết định sản phẩm, thiết bị, store processing/review hoặc sửa lỗi backend ngoài phạm vi. Đây là estimate đề xuất sau audit native, còn phải xác nhận qua G-00; không tự đổi ngân sách/deadline M3.

| ID | Deliverable | Phụ thuộc | Estimate |
|---|---|---|---|
| G-00 | Audit web hiện tại, chốt UX intents, contract, version/nonce spike và config inventory | Quyền đọc web; hai native checkout | 4–6h |
| G-01 | Google/Supabase setup checklist + public build config | Owner access; G-00 | 3–4h |
| G-02 | Shared auth protocol, trusted transport, attempt/session generation; account-race safeguards | G-00 | 5–7h |
| G-03 | iOS Google coordinator, SPM, URL router, bridge integration | G-01/G-02 contract | 6–8h |
| G-04 | Android Credential Manager, lifecycle, bridge integration | G-01/G-02 contract | 7–10h |
| G-05 | Web UI, sign-in/link, auth transaction, logout/session/billing sync | G-00/G-02; có thể dùng fake native | 6–8h |
| G-06 | Automated auth/bridge tests, regression/build checks hai platform + web | G-03/G-04/G-05 | 4–6h |
| G-07 | E2E máy thật, TestFlight + Play internal, cross-platform/account tests | Provider/config, build ký, G-06 | 6–9h |
| G-08 | Bridge/setup docs, release checklist và bằng chứng nghiệm thu | Các bước trên | 1–2h |
| | **Tổng** | | **42–60h** |

Thứ tự triển khai: G-00 → chốt contract; G-01 và G-02 có thể song song; iOS/Android/web chạy song song sau khi contract ổn định; hội tụ ở G-06/G-07. Thời gian lịch không bằng tổng giờ chia máy móc cho số người vì cùng phụ thuộc cấu hình và QA.

Nếu SDK hoặc web auth store cần thay đổi lớn, cập nhật estimate trước khi mở rộng; không âm thầm bỏ link/account isolation/QA để giữ baseline 8h.

## 8. File dự kiến thay đổi

| Khu vực | File/nhóm file |
|---|---|
| Config/docs | `.env.example`, `scripts/sync-env.sh`, `ios/Config.xcconfig.example`, `README.md`, `docs/bridge.md`, setup guide Google mới nếu cần |
| iOS | `ios/project.yml`, `Honoured/Info.plist`, `App/AppConfig.swift`, `App/HonouredApp.swift`, URL router mới; `Auth/GoogleSignInCoordinator.swift`, auth state mới; `AuthSessionStore.swift`, shared Apple presentation guard; `Bridge/NativeBridge.swift`, `WebView/HonouredWebView.swift`, capability helper, `Debug/BridgeStub.swift`, auth tests |
| Android | `app/build.gradle.kts`, `AppConfig.kt`, `MainActivity.kt`, `bridge/NativeBridge.kt`, `auth/*` mới, `src/test/*`, `src/androidTest/*`; manifest chỉ khi SDK/config yêu cầu |
| Web ngoài repo | `native-bridge.ts`, auth store/hooks, Auth/Settings UI, Supabase integration, tests/lockfile; tên/path xác nhận G-00 |

Repo đang có refactor folder, Live Activities và docs/XLSX chưa commit. Bảo toàn toàn bộ thay đổi có sẵn; không sửa tracker, reset worktree, commit/push hoặc deploy khi chỉ được yêu cầu lập plan.

## 9. Test matrix và tiêu chí nghiệm thu

### 9.1 Account và dữ liệu

- [ ] User mới Google → Supabase session hợp lệ; existing Google → đúng UUID cũ.
- [ ] Google A trên iOS rồi Android → cùng UUID, thấy cùng dữ liệu account; không tạo duplicate profile do bootstrap chạy hai lần.
- [ ] Link account đang đăng nhập → giữ UUID/contracts/progress; anonymous-link chỉ test nếu web hỗ trợ anonymous.
- [ ] Google đã thuộc account B khi link từ A → thông báo xung đột, A không bị logout/mất dữ liệu.
- [ ] Apple/email account và Google cùng verified email được kiểm theo Supabase behavior thực tế; Apple relay email không bị app tự merge.
- [ ] Link cùng UUID không reset RevenueCat/Health/timer/Live Activity. Switch/logout đúng cleanup, không nhìn thấy dữ liệu account cũ. A identify đang pending → logout → B sign-in: RevenueCat cuối cùng bind B, không phát `ACCESS_STATUS` của A sang B.
- [ ] Supabase exchange thất bại → không gọi RevenueCat identify/native SET_AUTH_SESSION cho Google profile chưa xác thực.

### 9.2 Security, concurrency và lỗi

- [ ] Cả hai platform: nonce đúng pass, nonce sai/thiếu fail; sai audience/token hết hạn/provider disabled fail an toàn.
- [ ] Origin khác, iframe dù cùng origin, scheme/port sai → không mở provider và không nhận credential. Google auth bị reject trên Android legacy bridge.
- [ ] Reload/navigation/logout/account switch/timeout giữa sheet hoặc exchange → không nhận token hoặc hồi sinh session cũ.
- [ ] iOS session refresh/save cũ hoàn tất sau logout/new login → không ghi đè session mới; broadcast auth cũ không cross-account.
- [ ] Token refresh cùng UUID trong khi link không hủy flow. Rapid logout → sign-in chờ provider cleanup cũ; cleanup/cancel local không logout thiết bị khác hoặc clear session mới.
- [ ] Double tap, replay requestId, callback hai lần, Apple+Google đồng thời → một presentation, tối đa một credential delivery.
- [ ] Cancel/back, offline, missing client ID, sai SHA-1, không có Google account, Play Services/provider unavailable → UX rõ ràng, retry được.
- [ ] Google cache/sign-out lỗi không tự login lại; Supabase logout thắng pending auth và cleanup billing lỗi.
- [ ] Token/nonce không xuất hiện trong log, stub output, crash analytics, persistent bridge queue hoặc saved state.

### 9.3 Platform và regression

- [ ] iOS: app vẫn chạy trên deployment target hiện có; simulator build/tests pass; iPhone Google→Supabase E2E pass; TestFlight callback đúng config.
- [ ] Google URL router không phá `honoured://contract/...`; widget không link Google SDK.
- [ ] Android: API 26-compatible dependencies; emulator có Play Services + máy thật; rotate/background/recreate/process death an toàn.
- [ ] Android WebView không hỗ trợ secure auth transport → capability `supported:false`, không mở Google UI, legacy billing vẫn hoạt động.
- [ ] Android debug và Play internal release đều đăng nhập được với đúng signing certificate.
- [ ] Old native/new web, new native/old web vẫn chạy billing/auth hiện có; Google chỉ bật với handshake tương thích.
- [ ] Sign in with Apple, RevenueCat identify/logout/purchases, Health session sync và Live Activity cleanup không regression.

### 9.4 Các lệnh/check sẽ chạy khi implement

- iOS: XcodeGen → simulator build; auth unit/integration tests mới + Live Activity regression tests. DerivedData đặt ngoài repo. Dùng signing phù hợp nếu chạy Health runtime; unsigned compile không chứng minh runtime.
- Android từ `android/`: `./gradlew assembleDebug testDebugUnitTest lintDebug`; thêm `connectedDebugAndroidTest` khi emulator/device phù hợp; release build theo signing của owner.
- Web: typecheck, auth/bridge tests, production build; ghi commit/build URL thực sự được deploy trong E2E.
- Kết quả chia riêng: compile/unit tests, provider E2E, release signing/distribution, cross-platform data/billing. Không đánh dấu Done chỉ vì Google sheet trả token.

## 10. Rollout và Definition of Done

1. Chốt G-00/config với owner, giữ feature flag OFF khi chưa đủ provider/web readiness.
2. Native và web mới tương thích cộng thêm, thử trên internal builds và test accounts. Không tự tạo anonymous users để bật Google.
3. Sau khi native release sẵn sàng và web integration đã deploy đúng version, bật flag cho nhóm test rồi mở rộng; old app không có capability không thấy flow không được hỗ trợ.
4. Khi có lỗi: tắt Google entry points bằng web flag; giữ Apple/email và session Supabase đang hợp lệ. Không rollback bằng xóa identities, revoke toàn bộ user hoặc đổi account ownership.
5. Nghiệm thu khi cả hai platform đạt matrix bắt buộc, link giữ UUID, không có cross-account token/session race, config/release evidence và hướng dẫn setup được bàn giao.

Các điều kiện còn thiếu phải ghi `Blocked/Pending` với owner cụ thể; plan, native SDK integration, web integration và release E2E là những trạng thái riêng.

## 11. Ghi chú kiểm chứng tài liệu

Đã đối chiếu code native hiện tại, tài liệu chính thức Google/Android/Supabase và nguồn SDK ngày 24/09/2026. Skill Supabase được dùng để rà changelog và phân biệt `signInWithIdToken` với native-token `linkIdentity`; vì vậy plan giữ hai intent riêng và thêm gate kiểm tra SDK web thực tế. Các link nguồn đặt ngay cạnh quyết định liên quan.

Chưa đọc source web hiện tại, chưa xác minh provider/Console đang cấu hình đúng, chưa chạy build hoặc Google E2E trong bước lập plan. Ghi chú Apple/Lovable cũ trong plan V1.1 là lịch sử, không dùng làm bằng chứng triển khai Google.

## 12. Tiến độ triển khai — 24/09

Đã làm G-00 → G-06 và G-08 ở mức code, test tự động và simulator. G-01 (cấu hình Console/Supabase) và G-07 (E2E máy thật, TestFlight, Play internal) chưa làm vì thiếu quyền và cấu hình. Chưa commit, push, publish hay deploy. Hợp đồng message chốt trong [bridge.md](bridge.md), mục *Google Sign-In*.

### 12.1 Audit (G-00)

| Điểm | Kết quả |
|---|---|
| Web source | Project Lovable *Honoured V13*, HEAD `4e6cceb` trước khi sửa. Auth hiện có: email/password + Apple; **không** anonymous-by-default. |
| Supabase SDK web | `@supabase/supabase-js` / `@supabase/auth-js` **2.110.7** (lockfile + node_modules). Có overload `linkIdentity(SignInWithIdTokenCredentials)`, không cần nâng. |
| GoogleSignIn-iOS | **10.0.0** là tag đầu tiên có `signIn(withPresenting:hint:additionalScopes:nonce:)`, iOS 15+. Pin `exactVersion: 10.0.0`, chỉ link app target. |
| Android | Toolchain giữ nguyên (AGP 8.7.3, compileSdk 35, Kotlin 2.0.21). Kiểm AAR metadata: credentials 1.6.0 cần AGP 8.6+/compileSdk 35 nhưng đã chọn **1.5.0** (minCompileSdk 35); `googleid` **1.1.1** có `GetSignInWithGoogleOption.setNonce`; `webkit` **1.12.1**; lifecycle 2.8.7; coroutines 1.9.0. |

### 12.2 Điều chỉnh so với plan và lý do

- **Android vẫn bridge v1**; capability `googleSignIn` độc lập với `bridgeVersion`.
- **Transport Android** tên `HonouredAuth` (WebMessageListener, rule đúng origin cấu hình). Legacy `HonouredNative` trả `ERROR { code: "insecure_transport" }` cho 4 message auth.
- **iOS dùng chung handler `honouredNative`** nhưng lọc main frame + origin chính xác trước mọi xử lý; message không tin cậy bị drop, không reply. Reply auth chỉ dispatch nếu page generation và origin vẫn khớp.
- **Stub Debug** giờ nạp trang dưới origin web app đã cấu hình (`loadHTMLString(baseURL:)`) để kiểm origin như thật; thêm `-HonouredFakeGoogle` (token giả chứa nonce đã hash để kiểm vòng nonce).
- **Serialize** `SET_AUTH_SESSION`/`CLEAR_AUTH_SESSION` (iOS) và RevenueCat identify/logout (cả hai nền tảng); `ACCESS_STATUS` chỉ phát khi RevenueCat còn bind đúng user. Refresh token nền không ghi đè session đã đổi (compare-and-swap), broadcast `AUTH_SESSION_UPDATED/INVALID` của account cũ bị bỏ khi đổi account.
- **Web:** sign-out tăng generation trước, huỷ attempt Google đang mở, rồi `SYNC_AUTH_CONTEXT(null)` + `CLEAR_GOOGLE_SIGN_IN` không chặn sign-out; sign-in Google sau đó đợi cleanup xong.

### 12.3 File chính

| Khu vực | File |
|---|---|
| iOS | `Auth/Core/GoogleAuthState.swift`, `Auth/Core/AuthSupport.swift`, `Auth/GoogleSignInCoordinator.swift` (kèm `AppURLRouter`), `Bridge/NativeBridge+GoogleSignIn.swift`, `Bridge/NativeBridge.swift`, `Auth/AppleSignInCoordinator.swift`, `Auth/AuthSessionStore.swift`, `Billing/SubscriptionService.swift`, `Health/HealthSyncCoordinator.swift`, `App/AppConfig.swift`, `App/HonouredApp.swift`, `LiveActivities/NativeBridge+LiveActivities.swift`, `Debug/BridgeStub.swift`, `Info.plist`, `ios/project.yml`, `HonouredTests/GoogleAuthCoreTests.swift` |
| Android | `auth/GoogleAuthState.kt`, `auth/AuthSupport.kt`, `auth/GoogleSignInCoordinator.kt`, `auth/AuthBridge.kt`, `bridge/NativeBridge.kt`, `billing/SubscriptionService.kt`, `MainActivity.kt`, `AppConfig.kt`, `app/build.gradle.kts`, `src/test/.../GoogleAuthCoreTest.kt` |
| Config/docs | `.env.example`, `ios/Config.xcconfig.example`, `scripts/sync-env.sh`, `README.md`, `docs/bridge.md` |
| Web (Lovable) | `src/lib/native-bridge.ts`, `src/lib/google-auth.ts` (mới), `src/hooks/use-auth.ts`, `src/lib/sign-out.ts`, `src/components/screens/AuthGate.tsx`, `src/components/screens/Auth.tsx`, `tests/google-auth.test.ts` — commit `4b4b345` + `3f045b1` (sửa: `CANCEL_GOOGLE_SIGN_IN` thiếu `authContextId`, phát hiện khi review) |

### 12.4 Kiểm chứng đã chạy (24/09)

| Loại | Kết quả |
|---|---|
| iOS build | `xcodegen generate`; simulator Debug + Release `BUILD SUCCEEDED`, không warning mới (5 warning `[weak self]` cũ của billing). Release không còn chuỗi stub/fake Google; widget không link Google SDK. |
| iOS unit test | `HonouredTests` **94/94** (81 cũ + 13 auth mới: context/attempt/stale/cancel/one-shot, khoá presentation, nonce, config, định tuyến URL, origin, hàng đợi tuần tự). |
| iOS simulator (iPhone 17, iOS 26.5, stub + fake Google) | `google` **21/21** (capability, stale context, intent, in_progress, khoá Apple/Google, nonce SHA-256 khớp, requestId dùng lại, cancel, refresh cùng user giữ link, đổi owner drop kết quả, clear, iframe cùng origin không được reply); `google-reload` **2/2**. Log stub không có token/nonce. |
| iOS hồi quy | `live-activities-multiple` 20/20, `live-activities-account` 8/8, `live-activities-deeplink` 4/4 (router URL mới giữ `honoured://contract`), `live-activities-timer` 21/21, `timer-foreground` 17/17, `timer-cancel-background` 3/3, `goals` 13/13 (với `-HonouredFakeHealthTotals steps=9000,active_energy=250`), `sound` 5/5. |
| Android | `./gradlew assembleDebug testDebugUnitTest lintDebug` pass; unit test **11/11**. Lint còn 1 cảnh báo `CredentialManagerSignInWithGoogle` (báo nhầm: code so sánh trực tiếp hai `TYPE_*`), còn lại là cảnh báo cũ hoặc gợi ý bản mới hơn (cố ý pin). |
| Web (bản sao ở máy, commit `3f045b1`) | typecheck pass; **292/292** test (27 file, 21 test Google mới); build pass. Lỗi type `tests/native-auth.test.ts:43` có từ trước. Review diff: sau `4b4b345` lệnh huỷ khi sign-out thiếu `authContextId` nên native không huỷ; đã sửa ở `3f045b1` kèm test. |

### 12.5 Chưa kiểm chứng / còn lại

- **Cấu hình (G-01), owner:** Google Cloud Web client + iOS client (bundle id thật) + Android client (`com.honoured.app`, SHA-1 debug và Play App Signing); Supabase Google provider nhận Web + iOS client ID, giữ nonce check, bật **Manual linking**. Điền `GOOGLE_WEB_CLIENT_ID`, `GOOGLE_IOS_CLIENT_ID` trong `.env`.
- **E2E thật (G-07):** Google → Supabase trên iPhone và Android; nonce sai/thiếu bị từ chối; cùng Google account hai nền tảng → cùng UUID; link giữ UUID; conflict; TestFlight và Play internal.
- **Android instrumentation:** máy chưa có emulator/AVD/thiết bị; chưa viết/chạy test WebView frame/origin trên thiết bị.
- **Info.plist khi thiếu client ID:** entry URL scheme Google rỗng; cần kiểm App Store validation trước khi archive (hoặc bảo đảm đã điền config).
- **Web chưa publish;** preview Lovable dùng được để E2E với build native trỏ `HONOURED_WEB_APP_URL` vào URL preview.
