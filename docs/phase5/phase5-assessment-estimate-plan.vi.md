# Phase 5 - Đánh giá, estimate và implementation plan

Ngày đánh giá: 02/11/2026  
Phạm vi nguồn:

- `Honoured_Android_Developer_Scope_Updated_Nov_2026.pdf`
- `Honoured_History_Icon_Scope_Updated_Visual.pdf`
- Code hiện tại của `honoured-native`, tracker Phase 4 và Android/Google/Samsung documentation hiện hành.

## 1. Kết luận điều hành

### 1.1 Cleanup milestone

Scope rõ, nhỏ và hợp lý. Nên làm cleanup trước rồi lấy web build sau cleanup làm một phần của frozen-iOS reference cho Android. Vì Honoured dùng cùng React/Lovable web UI trên iOS và Android, cleanup này tự xuất hiện trong Android và không được tính lại ở Android parity.

**Estimate đề xuất: 12 giờ.**

### 1.2 Android milestone

Scope Android đúng hướng, đặc biệt ở các điểm:

- tái dùng React/Lovable UI, Supabase schema và business logic;
- freeze theo một iOS build cụ thể;
- prototype tracking trước khi hứa thời gian background;
- không coi iOS Live Activities là thứ có thể port nguyên trạng;
- không hứa app tiếp tục chạy sau Force stop;
- không cộng trùng phone steps và Health Connect records;
- dùng timestamp của evidence để reconcile deadline.

Sau khi audit source thực tế, target 120-140 giờ trong PDF không đủ cho acceptance “production-ready Android”. **Estimate thương mại chốt là 188 giờ Android + 12 giờ cleanup = 200 giờ tổng**. Đây là estimate đã ép gọn bằng cách tái dùng tối đa web/backend và code Android hiện có, giới hạn health scope ở steps, walking distance và approved calories, chỉ test hai dòng máy thật, và không gồm raw accelerometer/full nine-metric parity.

### 1.3 Câu trả lời ngắn về step sensor

Honoured Android **không bắt buộc về mặt kiến trúc phải có `TYPE_STEP_COUNTER`**. Kiến trúc đề xuất là:

1. Health Connect aggregate là nguồn mặc định.
2. Direct Phone dùng Health Connect on-device steps khi khả dụng, hoặc `TYPE_STEP_COUNTER` trực tiếp trong chế độ theo dõi phù hợp.
3. Samsung Health có thể tạo step data từ accelerometer rồi đồng bộ sang Health Connect.
4. Không tự viết raw-accelerometer pedometer trong release đầu tiên.

`TYPE_STEP_COUNTER` vẫn là đường native trực tiếp tốt nhất về pin và locked-screen behavior. Health Connect on-device tracking của Android 14 + Extension 20 cũng dùng sensor này ở dưới. Nhưng Health Connect còn có thể nhận Steps từ Samsung Health hoặc thiết bị/app khác, nên Honoured không cần phụ thuộc duy nhất vào nó.

## 2. Hiện trạng repository và phần được tái sử dụng

### 2.1 Kiến trúc đã xác nhận

- iOS: Swift/SwiftUI shell + `WKWebView` tải React/Lovable web app.
- Android: Kotlin shell + Android `WebView` tải cùng React/Lovable web app.
- Backend/data/business logic: Supabase + Lovable web app dùng chung.
- Android hiện target SDK 35, min SDK 26, JDK 17.

### 2.2 Android đã có

- Android WebView shell, loading/error/retry và lifecycle cơ bản.
- RevenueCat SDK và các flow identify, access check, purchase, restore, logout.
- Native Google Sign-In bằng Credential Manager qua origin-scoped `WebMessageListener`.
- Microphone permission bridge cho voice recording trong web app.
- Deep external-link handoff cơ bản.
- Shared UI cho Home, Contract, Icon, Journal, History và Settings qua Lovable.

### 2.3 Android chưa có

- Health Connect dependency, permissions và data access.
- `ACTIVITY_RECOGNITION`, `READ_STEPS`, background-health permission.
- Phone sensor discovery, `TYPE_STEP_COUNTER` reader hoặc sensor probe.
- Tracking source model, aggregate/deduplication và health sync bridge.
- Foreground health service và persistent notification.
- Goal/reminder/completion notification engine.
- Deadline reconciliation, reboot/timezone/offline recovery.
- Android equivalent cho tracked-contract lifecycle.
- Notification deep links/cold-start queue.
- Android health/privacy Play declarations và device evidence.
- Instrumentation/device test suite đủ cho auth, WebView bridge, purchase và tracking.

### 2.4 Những phần không được tính lại

- Viết lại sáu màn hình chính bằng native Android.
- Viết lại contract/Icon/history/journal business rules đã chạy trong Lovable/Supabase.
- Viết lại signature capture web.
- Viết lại weekday Icon targets, revision storage và immutable history.
- Viết lại Supabase authentication/session logic.
- Tích hợp RevenueCat từ đầu.

## 3. Scope freeze đề xuất

Feature-freeze reference nên được ghi bằng bốn giá trị, không chỉ bằng screenshot:

1. iOS TestFlight build được Jimmy PASS.
2. Lovable production deployment/commit tương ứng.
3. Supabase migration version/hash tương ứng.
4. Android parity checklist có từng workflow INCLUDED, ADAPTED hoặc EXCLUDED.

Tình trạng hiện tại:

- weekday-specific Icon targets và signed prospective amendments đã được implement ở web/backend ngày 01/11/2026;
- iOS TestFlight 1.0.9 (4) chứa native support cần thiết;
- phần này vẫn phải được Jimmy test/accept trước khi gọi là frozen approved baseline;
- cleanup 12 giờ nên hoàn thành trước khi chốt web commit freeze.

### Included

- Home, Contract, Icon, Journal, History, Settings bằng shared web UI.
- Existing account/data continuity.
- Google sign-in hiện có và các auth flow web hiện hành.
- Contract/Single activity, Because, target, deadline, signature, progress, status.
- Icon recurrence, weekday targets, revision/re-signature cho future occurrences.
- History/calendar sau cleanup.
- Voice recording hiện có nếu Android WebView/device pass acceptance.
- Free/premium rules hiện có.
- RevenueCat/Google Play purchase, restore và entitlement.
- Steps tracking, approved source selection, notification và deadline reconciliation.

### Adapted for Android

- iOS Live Activity -> Android ongoing notification/foreground-service progress khi một active tracking session cần realtime behavior.
- Apple Health/Core Motion -> Health Connect/direct phone step capability.
- iOS background callbacks -> Android foreground service, WorkManager, app-resume reconciliation và notification scheduling theo giới hạn nền tảng.

### Excluded

- Raw accelerometer step algorithm riêng của Honoured.
- Garmin/Samsung proprietary SDK integration.
- Wear OS companion app.
- Guaranteed delivery dưới 5 phút trên mọi thiết bị/trạng thái.
- Tracking sau khi người dùng Force stop app.
- Android Word Tracker app/file integrations mới.
- Tablet redesign.
- Marketing và maintenance vô thời hạn.

## 4. Estimate

### 4.1 Cleanup milestone - 12 giờ

| Hạng mục | Giờ | Deliverable |
|---|---:|---|
| Seven-day History default | 3.0 | Mặc định today + 6 ngày trước; chọn ngày màu xem toàn bộ records; Back to recent history; giữ filter và xử lý timezone/day boundary |
| Swipe calendar month | 2.5 | Swipe trái/phải, gesture threshold/axis lock, giữ arrow và date tap, transition phù hợp |
| Active Icon collapse + action row | 2.5 | Collapsed mặc định; chevron; history đầy đủ; actions độc lập và cùng hàng |
| Unit/regression/browser QA | 3.0 | Nhiều record/ngày, tháng biên, touch/scroll, revision/signature, desktop/mobile và WebView |
| Integration/review buffer | 1.0 | Review diff, sửa regression nhỏ và xác nhận production-ready trước handoff |
| **Tổng** | **12.0** | Một Lovable milestone, không migration |

### 4.2 Android milestone - 188 giờ

| Package | Giờ | Ghi chú |
|---|---:|---|
| A. Foundation, release và lifecycle | 15 | Không dựng shell từ đầu; harden build/release, deep links, lifecycle, process death, permissions/capabilities |
| B. Secure bridge + native auth session | 18 | Health bridge, encrypted Supabase session, refresh serialization, persisted native event queue và account isolation |
| C. Health Connect + direct phone tracking | 42 | Bao gồm 10 giờ prototype; permissions, approved metrics, aggregate/source attribution, `TYPE_STEP_COUNTER`, source choice và tests |
| D. Health sync + backend data integrity | 22 | Offline queue, authenticated native upload, daily ledger, late/deleted records, dedupe/idempotency và schema compatibility |
| E. Contract/timer/background/notification engine | 29 | Tracked-contract state, timer, foreground service, goals, completion/reminders, Doze/reboot/timezone recovery |
| F. FCM + backend push parity | 15 | Android token lifecycle, backend provider routing, scheduled Icon reminders/results và notification deep links |
| G. Lovable/WebView parity | 11 | Android capability adapter, Health & Tracking UI, signatures/Icon/History/voice verification và web tests |
| H. Accounts + Google Play/RevenueCat | 6 | Production config, account switching, products/offering, purchase/restore/entitlement E2E |
| I. QA, compliance và Play launch | 30 | Risk-based automation, Pixel + Samsung, API emulators, privacy/accessibility, Play release/submission và 5 giờ defect window |
| **Tổng Android** | **188** | Cleanup 12 giờ tính riêng; tổng thương mại 200 giờ |

Prototype không được cộng ngoài 188 giờ. Nếu feasibility gate bác bỏ một timing behavior, thời gian còn lại dùng để productionize fallback đã định nghĩa, không tự mở rộng scope.

### 4.2.1 Bằng chứng source khiến estimate tăng

- Android hiện có khoảng 1.5k dòng Kotlin production/test, chủ yếu WebView shell, Google auth và RevenueCat; iOS production có riêng Health 2.9k dòng, Bridge 1.4k, Notifications 656 dòng và Live Activity/tracking core 3.8k dòng. Không port line-by-line, nhưng Android phải có native replacement cho hành vi thuộc acceptance.
- Android chỉ có 11 `@Test`, đều tập trung Google auth/support. iOS test target có 288 test methods cho health/tracking/live-activity core và các model liên quan.
- Android hiện không có dependency hoặc implementation marker cho `HealthConnectClient`, `SensorManager`, foreground health service, Firebase Messaging, WorkManager, encrypted native session storage, Room/offline queue, `POST_NOTIFICATIONS`, `ACTIVITY_RECOGNITION`, `READ_STEPS` hoặc boot recovery.
- Android bridge chưa handle `SET_AUTH_SESSION`, `CLEAR_AUTH_SESSION`, health status/source/query, goals, timer, notification settings hoặc Icon revision sync.
- Backend push schema hiện APNs-specific: token kind/environment/topic constraints, APNs provider token, APNs headers/status/reason. FCM không phải chỉ thêm dependency Android; phải mở rộng token schema và server sender/routing có test/rollback.
- Background health upload cần native Supabase session và refresh token. Android hiện để supabase-js tự quản session trong WebView, nên foreground UI hoạt động nhưng native worker/service không có credential để sync khi WebView không chạy.

### 4.2.2 WBS chi tiết cho 188 giờ Android

#### A. Foundation, release và lifecycle - 15 giờ

| Task | Giờ | Vì sao cần |
|---|---:|---|
| Audit frozen baseline + Android parity/capability matrix | 2 | Chốt chính xác web/iOS/backend version và Android deviations |
| Build flavors, versioning, signing và production config | 3 | Hiện app là 1.0.0/code 1, chưa có release hardening và local build còn test entitlement |
| App Links/deep links + cold-start intent routing | 3 | Notification/auth link phải mở đúng activity khi process/WebView chưa tồn tại |
| Lifecycle, configuration và process-death restore | 4 | Restore đúng account, source, timer/tracking state và pending intent |
| Permission/capability coordinator + foundation tests | 3 | API/device-specific permissions và versioned capabilities |
| **Tổng A** | **15** | |

#### B. Secure bridge + native auth session - 18 giờ

| Task | Giờ | Vì sao cần |
|---|---:|---|
| Origin-scoped bridge cho health/tracking commands | 4 | Không đưa sensitive commands vào generic legacy JS interface |
| Encrypted native Supabase session store | 4 | Worker/service cần access/refresh token khi WebView không chạy |
| Serialized refresh + expiry/rotation handling | 4 | Tránh native và supabase-js dùng cùng refresh token rồi revoke session |
| Persisted bounded native event queue | 3 | Goal/timer/notification event phải sống qua cold start và deliver exactly once |
| Account switch/logout cleanup | 2 | Xóa queue, tracking data, worker và push registration của account cũ |
| Bridge/session unit tests | 1 | RequestId, reload, stale generation, token race và account isolation |
| **Tổng B** | **18** | |

#### C. Health Connect + direct phone tracking - 42 giờ

| Task | Giờ | Vì sao cần |
|---|---:|---|
| Pixel + Samsung feasibility/profiling probe | 10 | Đo sensor inventory, HC extension, screen lock, background, Doze, reboot, latency và battery |
| Health Connect SDK/availability/permission/disclosure | 5 | Android 9-13 APK path, Android 14+ framework, foreground/background permission variants |
| Approved metric mapping | 5 | Steps, walking distance và approved calories; canonical units, null/unavailable/zero semantics |
| Aggregate/source attribution/deduplication | 6 | HC aggregate, DataOrigin/SPN, Samsung Health/watch overlap và source priority |
| Direct `TYPE_STEP_COUNTER` pipeline | 5 | Capability, cumulative baseline, reboot/process death, sensor batching và timestamps |
| Automatic/Phone preference + fallback | 4 | Persisted account-scoped choice, revoke/disappearance và honest UI status |
| Day/reset/timezone queries + estimates | 3 | Custom reset hour, midnight/DST và labelled distance/calorie estimates |
| Tracking tests | 4 | Capability, ranges, source switch, reboot, fallback, duplicate/late data |
| **Tổng C** | **42** | Prototype 10 giờ nằm trong tổng |

#### D. Health sync + backend data integrity - 22 giờ

| Task | Giờ | Vì sao cần |
|---|---:|---|
| Durable offline queue + retry/split/drop policy | 5 | Mạng chậm không được mất evidence hoặc block collection tiếp theo |
| Authenticated native Supabase client | 5 | Upload samples/daily totals bằng native session, xử lý invalid/rotated session |
| Daily ledger + history recomputation | 4 | Recompute khi source đổi, late records và history window mà không mix reading methods |
| Android UUID/source/idempotency contract + SQL compatibility | 4 | Health Connect record IDs không giống HealthKit sample UUID; cần collision-safe contract |
| Late/deleted records, retry và account cleanup | 3 | Corrective data không được cộng mãi hoặc rò giữa account |
| Sync/backend tests | 1 | Queue, batching, retry, idempotency và RLS payload |
| **Tổng D** | **22** | |

#### E. Contract/timer/background/notification engine - 29 giờ

| Task | Giờ | Vì sao cần |
|---|---:|---|
| Android tracked-contract state engine | 6 | Focus, definition/version, exactly-once mutations, account/session isolation và restored state |
| Testament timer engine | 5 | Start/cancel/restore/complete, replacement ordering và process death |
| Health foreground service + ongoing lock-screen progress | 5 | User-started active mode, persistent notification, actions và lifecycle |
| Notification channels/status/settings/local delivery | 3 | Android 13 permission, denied recovery, goal/timer/reminder channels |
| Goal evaluation + idempotent completion | 3 | Không notify/complete lặp qua sensor, worker, push và resume |
| Doze/reboot/timezone/offline/deadline reconciliation | 3 | Late pre-deadline evidence, ambiguous PENDING và rescheduling |
| Engine/background tests | 4 | State transitions, timer races, process death, midnight và stale account |
| **Tổng E** | **29** | Android-appropriate replacement, không port ActivityKit UI |

#### F. FCM + backend push parity - 15 giờ

| Task | Giờ | Vì sao cần |
|---|---:|---|
| Firebase Messaging client + token lifecycle | 4 | Register/rotate/unregister token theo installation/account |
| Backend token schema/provider migration + rollback | 3 | Schema hiện chỉ nhận APNs hex token/kind/environment/topic |
| Server FCM sender/routing/error classification | 4 | Icon morning/evening/result/end phải route APNs hoặc FCM và drop/retry đúng provider |
| Android payload/deep-link handling | 2 | Notification data, contract/day target và cold-start navigation |
| Push integration tests | 3 | Token takeover, sign-out, duplicate slot, invalid token và provider failure |
| **Tổng F** | **15** | |

#### G. Lovable/WebView parity - 11 giờ

| Task | Giờ | Vì sao cần |
|---|---:|---|
| Android native adapter/capability gates | 3 | Web hiện ẩn Health & Tracking trên Android; cần feature-detect theo capability |
| Health & Tracking source/status/permission UX | 2 | Automatic/Phone, unavailable/fallback, disclosure và settings recovery |
| Shared workflow WebView parity fixes | 2 | Signature, weekday revisions, History gestures và Journal voice |
| Lovable/browser/WebView tests | 4 | Old Android shell compatibility, request/event mapping và mobile touch behavior |
| **Tổng G** | **11** | Hosted web source không nằm trong checkout; effort phải xác nhận lại khi freeze |

#### H. Accounts + Google Play/RevenueCat - 6 giờ

| Task | Giờ | Vì sao cần |
|---|---:|---|
| Production Google/Supabase/RevenueCat config audit | 1 | Code có sẵn nhưng chưa chứng minh production/store mapping |
| Account switch/logout isolation E2E | 1 | Native session, tracking, push và RevenueCat phải đổi cùng account |
| Play products/base plans/offering mapping | 1 | Product/package/entitlement khớp Google Play + RevenueCat |
| Purchase/cancel/pending/restore/entitlement E2E | 2 | Bao gồm subscriber hiện có và offline/cache |
| Regression tests | 1 | Identity race và error mapping |
| **Tổng H** | **6** | |

#### I. QA, compliance và Play launch - 30 giờ

| Task | Giờ | Vì sao cần |
|---|---:|---|
| Test plan/parity matrix/evidence + risk-based automation | 6 | Tập trung state/sync/bridge critical paths thay vì port toàn bộ iOS tests |
| Real Pixel reliability matrix | 4 | Lock, Doze, Saver, swipe-away, reboot, revoke, latency/battery |
| Real Galaxy A06 5G reliability matrix | 4 | One UI, Samsung Health, HC sync và sensor inventory |
| Android API compatibility regression | 3 | API 28/29, API 33 notification, API 34/35 Health Connect/FGS |
| Privacy + accessibility basics | 2 | Disclosure, data minimization và accessibility smoke cơ bản |
| Play declarations/assets/signed AAB/internal test | 4 | Data safety, Health apps, HC permissions và release artifact |
| Submission + one in-scope review response | 2 | Không tính thời gian chờ Google/client |
| Included defect-fix allowance | 5 | Lỗi tái hiện so với frozen scope trong 7 ngày sau RC/submission |
| **Tổng I** | **30** | |

#### Kiểm tra tổng

`15 + 18 + 42 + 22 + 29 + 15 + 11 + 6 + 30 = 188 giờ Android`.

Trong đó:

- **33 giờ** foundation + secure bridge/native session;
- **64 giờ** Health Connect/direct sensor + durable sync/backend integrity;
- **44 giờ** contract/timer/background notification + FCM/backend push;
- **17 giờ** web parity + billing/account hardening;
- **30 giờ** QA/compliance/release.

Để giữ tổng 200 giờ, scope phải freeze đúng steps, walking distance và approved calories; không raw accelerometer, Wear OS, proprietary wearable SDK hoặc full nine-metric parity. QA dùng risk-based coverage, real-device tracking tập trung Pixel + A06 5G, các API khác chủ yếu bằng emulator; defect allowance còn 5 giờ. Hosted Lovable/backend source phải được bàn giao đúng baseline; thay đổi sau freeze là change request.

### 4.3 Milestone billing/delivery grouping

| Milestone | Giờ | Exit gate |
|---|---:|---|
| M1 - Cleanup | 12 | History/Icon cleanup và regression QA |
| M2 - Foundation/session/web parity | 44 | Android A/B/G; frozen baseline, secure native session và physical Android parity demo |
| M3 - Tracking feasibility + core | 42 | C; device report, Health Connect/direct Phone và source model |
| M4 - Durable sync + background engine | 51 | D/E; production data pipeline, timer/contract state, lock-screen behavior và deadline reconciliation |
| M5 - FCM, Billing, QA và Play release | 51 | F/H/I; push provider, purchase/restore, risk-based QA, signed AAB, internal test và submission |
| **Tổng** | **200** | 12h cleanup + 188h Android |

## 5. Tracking architecture

### 5.1 Source model

#### Automatic

- Đọc Health Connect aggregate cho khoảng thời gian cần thiết.
- Dùng aggregate API, không cộng thủ công từng record/source.
- Không filter cứng package `android`: từ Health Connect update tháng 06/2026, on-device steps có device-specific Synthetic Package Name.
- Có thể bao gồm phone, Samsung Health, watch và provider khác theo ưu tiên của Health Connect.

#### Phone

Ưu tiên theo runtime capability:

1. Health Connect on-device steps nếu Android >= 14 và Extension >= 20.
2. Direct `TYPE_STEP_COUNTER` nếu sensor tồn tại và permission được cấp.
3. Nếu cả hai không có, Phone source là unavailable; không giả `0` và không tự chuyển sang raw accelerometer.

Direct Phone và Automatic là hai lựa chọn loại trừ nhau trong một evaluation window. Không cộng direct sensor count với Health Connect aggregate.

### 5.2 Vì sao không dùng raw accelerometer

- Android 9+ không giao continuous accelerometer events cho background app.
- Muốn giữ thì phải chạy foreground service với notification thường trực.
- Tốn pin hơn sensor hub/step counter.
- Phải tự chịu trách nhiệm thuật toán, calibration, false positives và device fragmentation.
- Samsung Health có thể dùng accelerometer của hãng, nhưng điều đó không biến accelerometer thành API step count ổn định cho app bên thứ ba.

### 5.3 Samsung Galaxy A06 5G

Đã xác nhận từ thông số Samsung:

- có Accelerometer;
- có Gyro, Geomagnetic, Light và Proximity;
- Samsung không liệt kê rõ `TYPE_STEP_COUNTER` trong public specification.

Kết luận mua máy:

- phù hợp làm máy Samsung budget test cho WebView, One UI battery restrictions, Samsung Health và Health Connect;
- không thể xác nhận `TYPE_STEP_COUNTER` chỉ từ spec công khai;
- nên mua nếu có chính sách đổi trả, hoặc chạy sensor probe trước khi hết hạn đổi trả;
- không đủ làm thiết bị duy nhất: cần thêm một Pixel thật cho Android reference behavior.

Probe ngay khi có máy:

```text
Model/build fingerprint/Android/One UI
All SensorManager sensors
TYPE_STEP_COUNTER present + vendor + wake-up + reporting mode
TYPE_STEP_DETECTOR present
Health Connect SDK/Extension version
READ_STEPS and background-read feature availability
Samsung Health -> Health Connect Steps sync
100-step tests: screen on, screen locked, app background, swipe-away
reboot, Battery Saver, permission revoke, force-stop behavior
```

### 5.4 Background modes

#### Passive daily tracking

- Health Connect/Samsung Health/device records data.
- Honoured reads on app start/resume and permitted scheduled/background opportunities.
- Không hứa target notification ngay lập tức.

#### User-initiated active tracking

- Người dùng chủ động Start.
- Honoured start health foreground service khi use case cần direct sensor/near-realtime goal detection.
- Persistent notification hiển thị trạng thái/progress hợp lệ.
- Service dừng khi session xong, người dùng Stop, permission mất hoặc state không còn hợp lệ.

### 5.5 Deadline reconciliation

Mỗi evidence phải có:

- source/mode;
- interval start/end hoặc sensor timestamp;
- arrival/read timestamp;
- value và unit;
- device/source identity ở mức privacy cho phép;
- evaluation version.

Luật:

- evidence có activity timestamp trước deadline được tính dù đến muộn;
- arrival timestamp không thay thế activity timestamp;
- nếu batched record không đủ xác định thời điểm crossing, trạng thái giữ PENDING thay vì tự đoán HONOURED/BROKEN;
- reconcile khi app resume, background worker chạy, reboot, timezone đổi, source đổi và mạng trở lại;
- idempotency key ngăn upload/evaluation lặp;
- server remains authoritative cho final status khi nhiều thiết bị cùng account.

### 5.6 Distance và calorie

- Ưu tiên record gốc từ Health Connect nếu được scope chấp thuận.
- Giá trị suy từ steps phải ghi rõ Estimated.
- Release đầu không dùng estimated distance/calorie để quyết định hậu quả contract nếu chưa có acceptance riêng về công thức và tolerance.

## 6. Detailed implementation plan

### Phase 0 - Freeze và test contract

1. Jimmy PASS frozen iOS build và weekday target flows.
2. Hoàn thành cleanup và chốt Lovable commit/deployment.
3. Chốt Supabase migration hashes.
4. Lập parity matrix từng screen/workflow.
5. Chốt Android-specific deviations/copy.
6. Chốt device ownership: Galaxy A06 5G và Pixel thật.

### Phase 1 - Cleanup milestone

1. Thêm History view mode: `recent7` và `selectedDate`.
2. Tính theo local calendar day, today + 6 ngày trước; không dùng rolling 168 giờ.
3. Filter status áp dụng nhất quán cho cả recent và selected-date.
4. Date tap tải/hiện mọi activity trong ngày, không chỉ record đầu.
5. Back to recent history reset selection nhưng giữ status filter.
6. Calendar horizontal gesture dùng axis lock + minimum distance/velocity; bỏ gesture nếu vertical intent thắng.
7. Arrow và swipe gọi cùng month-change function.
8. Active Icon summary là semantic button/region với `aria-expanded` và chevron.
9. Revision list collapsed mặc định, nhưng active details/today progress/status dots luôn thấy.
10. `Revise target` và `End early` nằm ngoài toggle; stop propagation; giữ confirmation safeguards.
11. Unit tests, touch/browser smoke và regression signatures/history.

### Phase 2 - Android foundation hardening

1. Bump/version strategy và release signing config không chứa secret trong repo.
2. Add app links/custom deep links cho notification/auth navigation.
3. Cold-start intent queue đến khi WebView/native bridge ready.
4. Permission coordinator: notification, activity recognition, Health Connect.
5. Capability payload có version riêng cho `healthConnect`, `phoneSteps`, `backgroundTracking`, `notifications`.
6. Origin-scoped transport cho health-sensitive commands; legacy bridge không nhận chúng.
7. Lifecycle/process-death restore và account-isolated local state.
8. Add baseline unit/instrumentation harness.

### Phase 3 - Shared parity bridge

1. Map parity matrix sang native capabilities, không fork UI không cần thiết.
2. Android Health & Tracking UI chỉ hiện khi capability đã biết.
3. Implement request/reply correlation và account/document generation guards.
4. Verify signature canvas, upload, weekday targets và revisions trên Android WebView.
5. Verify Journal audio permission/record/playback và revoked-permission recovery.
6. Verify History cleanup/touch gesture trên WebView thật.
7. Define Android notification status/settings bridge.

### Phase 4 - Tracking feasibility gate (nằm trong package C)

1. Viết internal sensor probe, không đưa production UI trước khi gate qua.
2. Inventory sensor + Health Connect capability trên Pixel và A06 5G.
3. Log sensor activity timestamp, callback arrival, evaluation và notification timestamp.
4. Test screen on/locked/background/swipe-away/reboot/Doze/Battery Saver/revoke/force-stop.
5. Chạy tối thiểu nhiều trial cho mỗi state, báo median/P90/worst/miss rate/battery delta.
6. Chốt production mode:
   - Automatic Health Connect aggregate;
   - Phone Health Connect on-device/direct Step Counter;
   - active foreground service có cần thiết hay không.
7. Gate: không hứa sub-five-minute universal; copy/acceptance phản ánh evidence thật.

### Phase 5 - Production tracking

1. Add Health Connect SDK và availability/update flows.
2. Declare/minimize `READ_STEPS`, background read và `ACTIVITY_RECOGNITION` theo capability thực tế.
3. Prominent disclosure trước system permission.
4. Aggregate step ranges theo local day/reset rule.
5. Source preference persistence theo account; automatic fallback có audit reason.
6. Direct Step Counter baseline across reboot và process restarts.
7. Deduplication/idempotent upload.
8. Health status/source/query/goal bridge messages.
9. Diagnostics export không chứa raw sensitive health history ngoài scope.

### Phase 6 - Background, notifications và reconciliation

1. Notification channels: tracking, reminders, completion.
2. Android 13+ notification permission và denied/settings recovery.
3. Health foreground-service type/permissions cho active mode.
4. Ongoing notification action: open/stop; progress chỉ khi evidence đủ mới.
5. Reminder scheduling phù hợp Doze; không xin exact-alarm permission nếu không chứng minh cần thiết.
6. Goal completion notification idempotent.
7. Cold-start deep link về đúng activity.
8. Reconcile app start/resume, WorkManager, reboot/timezone/package update.
9. Handle late records, PENDING và server authority.
10. Document Force stop limitation và Samsung battery settings without coercive prompts.

### Phase 7 - Accounts và billing

1. E2E Google sign-in với production OAuth/Supabase config.
2. Account switch/logout không rò tracking state hoặc RevenueCat identity.
3. Google Play products/base plans khớp RevenueCat offering/entitlement.
4. Test new purchase, cancel, pending, restore, offline/cache, expired entitlement.
5. Existing iOS subscriber signs in Android và nhận đúng cross-platform entitlement theo cấu hình store/RevenueCat được duyệt.

### Phase 8 - QA và Play launch

1. Automated unit tests cho source selection, dedupe, date/reset/deadline, reboot, account isolation.
2. Instrumentation tests cho permissions, bridge/origin, notification deep links và process death.
3. Real-device matrix ít nhất:
   - Galaxy A06 5G / current supported One UI;
   - một Pixel thật / current supported Android;
   - API 28/29 compatibility cho foreground use nếu vẫn giữ minSdk 26;
   - API 33 notification permission;
   - API 34/35 Health Connect + FGS behavior.
4. Parity checklist có screenshot và deviation.
5. Accessibility basics: TalkBack labels/order, touch targets, font scaling, contrast, reduced motion.
6. Privacy policy/in-app disclosure/Data safety/Health apps declaration/Health Connect permission declaration.
7. Signed AAB, closed/internal testing, purchase evidence và crash/ANR check.
8. Submission và xử lý lỗi trong scope.
9. Included defect window: 7 calendar days sau khi giao release candidate/submission, tối đa 5 giờ nằm trong milestone cuối; chỉ lỗi tái hiện được so với frozen scope. Policy change, feature mới và account/store waiting time không thuộc defect hours.

## 7. Acceptance matrix trọng yếu

### Cleanup

- Recent History dùng đúng 7 calendar days gồm hôm nay.
- Chọn ngày cũ thấy mọi contract/activity của ngày đó.
- Filter giữ nguyên khi đổi mode.
- Swipe ngang không cướp vertical scroll/date tap.
- Arrow/swipe cho cùng kết quả.
- Icon collapsed mặc định; mở thấy original + mọi revision + đúng signature/date/detail.
- Hai action luôn thấy, cùng hàng, không toggle history.

### Tracking

- Không sensor/data trả `unavailable`, không trả zero giả.
- Automatic và Phone không bị cộng vào nhau.
- Source switch/revoke fallback có hiển thị và audit reason.
- Reboot không làm sai daily count.
- Locked screen/background evidence report có Pixel + Samsung.
- Force stop được mô tả là ngừng Honoured processing cho đến khi user mở lại.
- Late pre-deadline evidence được reconcile; ambiguous crossing giữ PENDING.

### Account/billing

- Một account hiện có thấy cùng contracts/Icon/revisions/signatures/history.
- Logout/account switch xóa state theo account.
- Google Play test purchase/restore/entitlement pass.

## 8. Rủi ro và decision gates

| Rủi ro | Xử lý |
|---|---|
| A06 5G không expose `TYPE_STEP_COUNTER` | Health Connect/Samsung Health path; Phone direct unavailable; không raw-accelerometer fallback trong scope |
| Health Connect/background data đến chậm | Passive mode không hứa realtime; active user-started FGS nếu prototype chứng minh phù hợp |
| Records nhiều nguồn overlap | Aggregate Health Connect; source modes loại trừ nhau; idempotency |
| Batched data không cho biết exact crossing | Dùng evidence interval/timestamp; giữ PENDING nếu ambiguous |
| Samsung battery optimization | Test A06 thật; app-resume reconciliation; hướng dẫn setting có điều kiện |
| Play policy không chấp nhận permission/copy | Permission minimization, prominent disclosure, Health apps declaration và privacy mapping trước submission |
| Feature freeze tiếp tục đổi | Mọi thay đổi sau freeze là change request |

## 9. Tài liệu kỹ thuật chính thức dùng cho quyết định

- Android `TYPE_STEP_COUNTER`: https://developer.android.com/reference/android/hardware/Sensor#TYPE_STEP_COUNTER
- Android motion/step sensors: https://developer.android.com/develop/sensors-and-location/sensors/sensors_motion
- Background sensor limits: https://developer.android.com/develop/sensors-and-location/sensors/sensors_overview
- Health Connect read/mobile steps: https://developer.android.com/health-and-fitness/health-connect/read-data
- Health Connect background access: https://developer.android.com/health-and-fitness/health-connect/get-started
- Foreground service changes/types: https://developer.android.com/develop/background-work/services/fgs/changes
- Play Health apps declaration: https://support.google.com/googleplay/android-developer/answer/14738291
- Play Health policy: https://support.google.com/googleplay/android-developer/answer/18265346
- Galaxy A06 5G official specifications: https://www.samsung.com/in/smartphones/galaxy-a/galaxy-a06-5g-light-gray-128gb-sm-a066bzagins/
- Samsung Health and Health Connect: https://developer.samsung.com/health/health-connect-faq.html
- Samsung Health step method: https://www.samsung.com/us/apps/samsung-health/

