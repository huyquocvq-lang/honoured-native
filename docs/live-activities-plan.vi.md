# Honoured — Kế hoạch nhiều Live Activities theo contract

Ngày lập: 23/09/2026. Trạng thái 24/09: **phần native đã triển khai và kiểm trên simulator; phần web (LA-06) đã có code trên Lovable, chưa publish** (xem [mục 14](#14-tiến-độ-triển-khai--2409)); E2E native + web, QA máy thật và signing/TestFlight còn mở.

Tài liệu này thay thế phương án một Live Activity duy nhất đã thảo luận trước đó. Phần Live Activity của M3 trong [kế hoạch V1.1](v1.1-plan.vi.md) dùng phạm vi và tiêu chí dưới đây; Google Sign-In vẫn là công việc riêng. Các message, file và capability ghi là **đề xuất** chưa có trong runtime. Chưa xác nhận signing, bản web đang deploy hoặc hành vi trên máy thật trong lần lập plan này.

## 1. Kết quả cần đạt và phạm vi đã thống nhất

- Mỗi contract đang được người dùng theo dõi có tối đa một Live Activity, hiển thị trên Lock Screen và có thể xuất hiện trên Dynamic Island.
- Contract đủ điều kiện được người dùng **mở chi tiết hoặc Start gần nhất** có độ ưu tiên cao nhất. Mở danh sách, re-render, reload hoặc đồng bộ tự động không được coi là hành động chọn mới.
- Mở contract B không kết thúc thẻ của contract A. A tiếp tục được cập nhật dù không được ưu tiên trên Dynamic Island.
- Timer hiển thị thời gian còn lại; Health hiển thị giá trị/mục tiêu theo từng activity. Một contract có hai slot vẫn chỉ có một thẻ.
- Hoàn thành, hủy hoặc hết hạn contract nào thì xử lý riêng thẻ đó. Đổi tài khoản/logout phải gỡ toàn bộ dữ liệu hiển thị của tài khoản cũ.
- Giữ giới hạn **một Testament Timer chạy đồng thời** hiện tại. Nhiều thẻ Health có thể cùng tồn tại với thẻ của timer đó. Start timer B vẫn thay timer A theo bridge hiện tại; chỉ mở B thì không hủy timer A.
- Mở contract Health có goal hợp lệ có thể tạo thẻ. Mở contract chỉ có timer chưa Start chỉ ghi nhận lựa chọn, không tạo thẻ rỗng. Contract completed/expired hoặc chỉ manual không tự tạo thẻ theo dõi.

### Ví dụ nghiệm thu sản phẩm

| Hành động | Các thẻ còn trên Lock Screen | Contract được Honoured ưu tiên |
|---|---|---|
| Mở Walking có goal 8.000 bước | Walking | Walking |
| Mở Exercise có goal 30 phút | Walking, Exercise | Exercise |
| Start Meditation 10 phút | Walking, Exercise, Meditation | Meditation |
| Mở lại Walking | Giữ cả ba; Meditation vẫn đếm | Walking |
| Exercise đạt đủ điều kiện hoàn thành | Exercise có trạng thái cuối rồi được gỡ theo policy; hai thẻ khác giữ nguyên | Walking |
| Logout | Gỡ tất cả thẻ Honoured của phiên tài khoản đó | Không còn |

Độ ưu tiên là yêu cầu gửi tới iOS, không phải quyền chiếm Dynamic Island bất chấp các app khác. Có nhiều thẻ không có nghĩa mọi thẻ xuất hiện cùng lúc trên Dynamic Island. [Apple: cấu hình relevance score](https://developer.apple.com/documentation/activitykit/activitycontent/relevancescore)

## 2. Hiện trạng đã đối chiếu trong checkout

| Thành phần | Hiện có | Phần cần thêm |
|---|---|---|
| [ios/project.yml](../ios/project.yml) | App iOS 16.0, Swift 5.9, XcodeGen; chưa có widget/test target | Widget Extension, shared models, test target; embed/sign extension |
| [TestamentTimer.swift](../ios/Honoured/Timer/TestamentTimer.swift) | Một timer; lưu `startedAt/endsAt`; notification; reconcile sau relaunch | Liên kết timer với contract occurrence; cập nhật thẻ và chống event cũ |
| [HealthKitService.swift](../ios/Honoured/Health/HealthKitService.swift) | Statistics query khử trùng nguồn; sleep gộp khoảng; `nil` khi không lấy được total | Snapshot tiến độ và phân biệt lỗi đọc/không có dữ liệu để giữ cache đúng |
| [HealthSyncCoordinator.swift](../ios/Honoured/Health/HealthSyncCoordinator.swift) | Collect trước, upload sau; gọi GoalMonitor khi outcome `.queued` | Publish tiến độ local cho mọi contract đang theo dõi, không phụ thuộc upload |
| [GoalMonitor.swift](../ios/Honoured/Health/GoalMonitor.swift) | Chỉ duyệt goal chưa đánh dấu đạt; phát `GOAL_REACHED` một lần/activity/ngày | Tách cập nhật tiến độ khỏi phát hiện đạt goal; tái sử dụng snapshot |
| [HealthSyncSettings.swift](../ios/Honoured/Health/HealthSyncSettings.swift) | Goal list + reset hour; `healthDayStart` | Bind tracked occurrence vào ngày/cửa sổ hiệu lực; không tái sử dụng goal ngày cũ |
| [NativeBridge.swift](../ios/Honoured/Bridge/NativeBridge.swift) | Allowlist, v1/v2, request IDs, queue; cleanup theo auth session | Protocol tracking/focus, trạng thái nhiều thẻ, explicit contract completion |
| [HonouredAppDelegate.swift](../ios/Honoured/App/HonouredAppDelegate.swift) | Launch/foreground/protected-data callbacks | Restore, dọn thẻ mồ côi, kết nối navigation |
| [HonouredApp.swift](../ios/Honoured/App/HonouredApp.swift), Info.plist | Chưa thấy inbound deep-link handler/scheme cho contract | Scheme/URL validation, pending navigation theo tài khoản |
| [BridgeStub.swift](../ios/Honoured/Debug/BridgeStub.swift) | Test bridge + fake totals khi launch | Kịch bản nhiều thẻ, đổi focus, fake totals thay đổi, lỗi/lifecycle |
| Web Lovable | Nằm ngoài checkout này | Phải đọc code hiện tại trước khi triển khai rule completion và tích hợp web |

`docs/bridge.md` quy định contract Health hoàn thành khi mọi **Health-mapped slot** cần thiết đã đạt; slot không map Health không chặn. Không mặc định đổi thành “timer và tất cả Health đều phải xong”. Native `ACTIVITY_COMPLETED` hiện chỉ đánh dấu đã celebration; không phải API hoàn thành/cancel toàn bộ native state.

## 3. Ràng buộc iOS và cách xử lý

### 3.1 Version, số lượng và dữ liệu

Đề xuất bật feature này từ **iOS 16.2**, giữ app chính ở iOS 16.0. SDK đang cài khai báo `ActivityContent` và `relevanceScore` từ 16.2; đây là API cần cho cơ chế đổi ưu tiên. iOS 16.0–16.1 giữ timer, Health và notification hiện có; Live Activity báo unsupported. Không nâng min OS của cả app chỉ vì extension.

Live Activities thông thường chạy tối đa 8 giờ, có thể còn trên Lock Screen thêm tối đa 4 giờ. Dữ liệu attributes + state phải trong 4 KB. Số thẻ đồng thời tùy giới hạn hệ thống. Tạo mới bằng app yêu cầu foreground. [Apple: Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)

Thiết kế của Honoured:

- Không quảng cáo đây là dashboard tồn tại 24 giờ hoặc tự mở lại thẻ để né timeout.
- Lưu `createdAt`, health day và thời hạn contract để reconcile; `staleDate` là dấu dữ liệu cũ, **không phải lệnh tự end**.
- Đo kích thước encoded attributes/state; chỉ gửi metadata hiển thị, tối đa hai slot. Không đưa sample, token hoặc payload dài vào thẻ.
- Nếu hệ thống từ chối tạo thêm: giữ thẻ đang có, trả trạng thái `limit_reached` cho thẻ mới; nghiệp vụ timer/Health vẫn tiếp tục. Không tự xóa thẻ khác và không retry vòng lặp.

### 3.2 Health khi khóa máy

HealthKit có thể không đọc được kho dữ liệu mã hóa khi thiết bị khóa. Observer/BG refresh cũng không bảo đảm một nhịp cập nhật cố định. [Apple: dữ liệu HealthKit được mã hóa](https://developer.apple.com/documentation/healthkit/protecting-user-privacy), [observer query](https://developer.apple.com/documentation/healthkit/executing-observer-queries)

Mặc định triển khai:

- Thẻ giữ snapshot hợp lệ gần nhất và thời điểm cập nhật; không đổi lỗi đọc thành `0`.
- Chưa từng có snapshot thì hiện trạng thái chờ dữ liệu, không khẳng định người dùng từ chối quyền đọc.
- Khi protected data sẵn sàng/foreground/HealthKit có dữ liệu mới, đọc lại và cập nhật tất cả thẻ liên quan.
- Không hứa đếm từng bước, nhịp tim live hoặc goal celebration đúng giây khi máy khóa. Theo dõi workout thời gian thực/Watch là phạm vi khác.
- Đề xuất ngưỡng stale Health 60 phút, cấu hình tập trung và hiệu chỉnh qua QA; đây là lựa chọn UX, không phải cam kết HealthKit cập nhật mỗi giờ.

### 3.3 Timer hết giờ khi app bị suspend

Countdown dùng view thời gian của hệ thống. Khi countdown về 0, không được suy ra app đã được chạy để gọi `Activity.end` hoặc ghi nhận contract hoàn thành. Local notification được hệ thống hiển thị khi app không chạy; callback foreground không được gọi ở nền. [Apple: local notification delivery](https://developer.apple.com/library/archive/documentation/NetworkingInternet/Conceptual/RemoteNotificationsPG/SchedulingandHandlingLocalNotifications.html)

Bản local trong plan này:

- Countdown không chạy âm; UI có thể ở `00:00`/stale trong lúc chờ reconcile.
- Notification hết giờ vẫn hoạt động theo quyền/Focus của người dùng, độc lập với Live Activity.
- Khi app được chạy lại hoặc có background execution hợp lệ, reconcile rồi cập nhật/kết thúc thẻ.
- Không dùng `Task.sleep`, BG refresh hoặc notification như cam kết chạy code đúng deadline ở nền.
- Nếu acceptance bắt buộc remote end/update khi app không chạy, cần hạng mục backend + ActivityKit APNs riêng; push vẫn có thể trễ hoặc mất khi offline. [Apple: ActivityKit push notifications](https://developer.apple.com/documentation/activitykit/starting-and-updating-live-activities-with-activitykit-push-notifications)

### 3.4 Celebration và thời điểm gỡ thẻ

Animation bị giới hạn tối đa 2 giây; Always-On giảm sáng không chạy animation, iOS 16 dùng animation/transition hệ thống. Vì thế không lấy “nhấp nháy đúng 3 lần trên mọi máy” làm điều kiện bắt buộc. [Apple: animations](https://developer.apple.com/documentation/widgetkit/animating-data-updates-in-widgets-and-live-activities)

Đề xuất trạng thái cuối có dấu check và copy rõ, animation bổ trợ trên OS hỗ trợ. Gọi `end` với final content và `.after(now + 30s)` để Lock Screen có thời gian đọc kết quả. Policy này kiểm soát gỡ thẻ **đã end trên Lock Screen**, không lên lịch kết thúc timer hoặc bảo đảm giữ Dynamic Island 30 giây. Không trì hoãn cleanup bằng một task ngủ chờ animation. [Apple: end](https://developer.apple.com/documentation/activitykit/activity/end(_:dismissalpolicy:)), [dismissal policy](https://developer.apple.com/documentation/activitykit/activityuidismissalpolicy/after(_:))

Các mốc 60 phút stale và 30 giây kết quả là default đề xuất trong plan; có thể chỉnh copy/UX khi review.

## 4. Danh tính, state và quyền sở hữu nghiệp vụ

### 4.1 Tách contract khỏi lần thực hiện trong ngày

Khóa local: `(nativeAccountScope, contractId, healthDay)`. Native lấy account scope từ session đã chấp nhận, không tin `userId` truyền tự do trong payload tracking.

- `contractId`: ID nghiệp vụ, không đoán bằng cắt chuỗi `activityId`.
- `healthDay`: ngày theo reset hour của user; native xác minh với `HealthSyncSettings`.
- Mỗi record còn có `windowStart`, `windowEnd`, timezone/reset-hour generation và `expiresAt` để xử lý đổi giờ, DST/timezone và standing contract qua ngày.
- `activityId` + `slot` được map tường minh tới occurrence. Timer legacy dùng contract ID và Health dùng `:primary/:secondary` vẫn nhận được qua mapping, không đổi ID cũ tùy tiện.
- Dữ liệu ngày mới không cập nhật thẻ ngày cũ. Không giả định persisted `SET_GOALS` tự mang ngày hết hạn vì model hiện tại chưa có trường ngày.

### 4.2 Native store đề xuất

`TrackedContractsStore` (actor, persisted versioned record) lưu:

| Field | Ý nghĩa |
|---|---|
| `schemaVersion`, `accountScope`, `accountGeneration` | Version dữ liệu, cách ly tài khoản và invalidation callback |
| `contractId`, `healthDay`, `windowStart/end`, `expiresAt` | Danh tính và hiệu lực occurrence |
| `contractName`, `activities[]`, `completionPolicy` | Metadata do web cung cấp và native validate |
| `definitionGeneration` | Native tăng khi goal/definition thay đổi; chặn query result cũ |
| `lastFocusedSequence` | Thứ tự chọn do native cấp; không dùng wall-clock để phân xử |
| `presentationStatus`, `activityKitId?`, `lastError?` | Trạng thái thẻ độc lập trạng thái nghiệp vụ |
| `lastSnapshot?`, `lastSuccessfulReadAt?` | Cache hiển thị tối thiểu, phân biệt unknown và 0 |
| `dismissed/suppressed`, `terminalReason?` | Không tự tái tạo thẻ người dùng vừa gỡ hoặc occurrence đã kết thúc |

Không lưu health snapshot trong log. Widget chỉ nhận dữ liệu hiển thị qua ActivityKit; không truy cập token, HealthKit hoặc backend.

### 4.3 Model shared cho Widget Extension

`HonouredActivityAttributes` chỉ chứa identity ổn định (`contractId`, `healthDay`, opaque occurrence token). Tên contract, tên activity, target và các nội dung có thể sửa nằm trong `ContentState` để update tại chỗ:

- `contractName`, `status`, `displaySlot`.
- `timer? { activityId, startedAt, endsAt, status }` — timestamp từ `TestamentTimer`.
- `health[] { activityId, slot, name, metric, value?, target, unit, reached, dataStatus, measuredAt? }`.
- `completedAt?`, `updatedAt`, `validUntil`.

Không persist countdown mỗi giây. `relevanceScore`/`staleDate` nằm trong `ActivityContent`, không lẫn vào business state.

### 4.4 Contract completion

Web tiếp tục là nguồn quyết định và lưu trạng thái contract. Native chỉ tạo projection hiển thị từ rule đã được web cung cấp, và giữ các event completion hiện có để web reconcile.

| Policy đề xuất | Native được làm gì |
|---|---|
| `all_health_slots` + danh sách ID bắt buộc | Đánh dấu từng slot; khi đủ tất cả slot đã đạt trong occurrence thì hiện goal completion và end thẻ, kể cả khi WebView chưa chạy |
| `timer_completion` + ID timer | Khi native thực sự xử lý timer completion thì hiện final state/end; event `TIMER_COMPLETED` vẫn giao về web |
| `web_authoritative` | Hiện tiến độ/slot đã đạt; chỉ end như honoured khi có xác nhận cấp contract từ web |

Chỉ bật hai policy native khi đối chiếu đúng business rule trên web thật. Mixed contract chưa đối chiếu dùng `web_authoritative`; không tự đặt thêm điều kiện AND/OR. Việc end thẻ không tự ghi backend, không tự đánh dấu contract honoured thay web và không hủy timer còn chạy ngoài business rule.

`GOAL_REACHED` hoặc `ACTIVITY_COMPLETED` legacy theo slot không được kết thúc toàn contract. Marker “đã celebration” hiện tại có thể đến từ manual/timer, không được coi nó là bằng chứng metric đã đạt. Cần kết quả reached riêng theo occurrence/policy và test parity với web, bao gồm chỉnh target và dữ liệu bị xóa.

## 5. Bridge protocol đề xuất — additive trên v2

Không đổi các message v1/v2 đang hoạt động. Giữ transport `honoured:native`, allowlist, `payload.requestId` và event queue. Khi triển khai mới cập nhật [bridge.md](bridge.md); tài liệu runtime hiện tại không được quảng cáo message kế hoạch như đã hỗ trợ.

### 5.1 Capability và thứ tự lệnh

Thêm vào mọi nguồn phát `NATIVE_READY`/`PLATFORM_INFO` một capability thống nhất:

```json
{
  "bridgeVersion": 2,
  "type": "NATIVE_READY",
  "payload": {
    "platform": "ios",
    "bridgeVersion": 2,
    "capabilities": {
      "liveActivities": {
        "protocolVersion": 1,
        "supported": true,
        "enabled": true,
        "minimumOS": "16.2"
      }
    },
    "liveActivityBridgeSessionId": "native-issued-session-7"
  }
}
```

`enabled` chỉ là snapshot cho phép tại thời điểm trả lời, không phải quyền notification/HealthKit. Capability absent/unsupported trên app cũ hoặc Android thì web không gọi API mới. iOS cũ có protocol nhưng `supported:false` dùng fallback. Nếu gọi nhầm trên Android, trả `not_implemented` với requestId.

Mọi mutation mới có `bridgeSessionId` và `clientSequence` (số nguyên tăng dần trong phiên bridge). Native đổi session token khi main-frame reload/account đổi; trả token mới trong `AUTH_SESSION_ACCEPTED`, `AUTH_SESSION_CLEARED` và `LIVE_ACTIVITY_STATE` ngoài các ready/platform response. Web chỉ gửi mutation khi đã nhận token cho account hiện tại; queue hoặc bỏ thao tác của phiên cũ trong lúc auth đang chuyển. Same-user token refresh không xoay session và không xóa tracking.

Web gán sequence ngay khi hành động xảy ra, serialize outbound mutation, không đợi async fetch xong mới gán thứ tự. Native kiểm tra thứ tự tại điểm nhận lệnh, cấp `lastFocusedSequence` trước các `await`, và re-check generation sau mỗi async result.

Transport retry giữ requestId/sequence và nhận lại kết quả đã cache, không focus hay chạy side effect lần nữa. Khi sửa payload hoặc sync goals sau một rejection, đó là logical attempt mới: dùng requestId/sequence mới. Sequence cũ không ghi đè state mới; query health/update từ account, ngày, definition hoặc phiên timer cũ bị bỏ. `activatedAt` có thể ghi cho diagnostics nhưng **không dùng `Date.now()` để quyết định ai thắng**. Snapshot restore dùng cơ chế sync riêng và tuyệt đối không tăng focus.

### 5.2 Message inventory

| Web → Native | Reply | Quy tắc |
|---|---|---|
| `TRACK_CONTRACT` | `CONTRACT_TRACKING_ACCEPTED` | Upsert một definition rồi focus theo thao tác mở rõ ràng; không xóa thẻ khác |
| `SYNC_TRACKED_CONTRACTS` | `TRACKED_CONTRACTS_SYNCED` | Full snapshot chỉ của danh sách user đang theo dõi, sau hydrate/auth; cập nhật metadata, dọn occurrence đã mất, giữ thứ tự focus và suppression |
| `STOP_TRACKING_CONTRACT` | `CONTRACT_TRACKING_STOPPED` | Gỡ đúng thẻ occurrence; idempotent, không tự cancel timer/Health business |
| `GET_LIVE_ACTIVITY_STATE` | `LIVE_ACTIVITY_STATE` | Đọc capability, focus, danh sách thẻ/trạng thái/lỗi; không tạo/focus thẻ |

Broadcast mới: `LIVE_ACTIVITY_STATE_CHANGED` cho status/focus thay đổi, `LIVE_ACTIVITY_OPENED` cho tap deep link. Progress từng metric không cần broadcast liên tục về web; web giữ đường Health hiện tại.

`STOP_TRACKING_CONTRACT.reason`: `user_stopped`, `contract_cancelled`, `contract_deleted`, `contract_expired`. Client không dùng message này để giả hoàn thành. Snapshot chỉ authoritative sau web load đủ contract và đúng account; empty trong giai đoạn loading không được gửi thành lệnh xóa tất cả.

Các payload còn lại dùng cùng mutation envelope, ngoại trừ GET chỉ cần requestId:

- `SYNC_TRACKED_CONTRACTS`: `contracts: ContractDefinition[]` có cùng schema `contract` bên dưới; không chứa lệnh focus. Web lấy tracked IDs từ `GET_LIVE_ACTIVITY_STATE`, đối chiếu với contract store đã hydrate, hợp nhất các thao tác mới có thứ tự rồi gửi snapshot. Không suy ra tracking từ route hiện tại hoặc toàn bộ danh sách contract. Native giữ dismissal/suppression kể cả khi definition vẫn có trong snapshot.
- `STOP_TRACKING_CONTRACT`: `contractId`, `healthDay`, `reason`; chỉ gỡ occurrence được chỉ định.
- `GET_LIVE_ACTIVITY_STATE`: không có mutation envelope; response trả thêm `liveActivityBridgeSessionId` và danh sách state như mục 5.5.
- `TRACKED_CONTRACTS_SYNCED`: echo requestId và danh sách trạng thái per-occurrence; `CONTRACT_TRACKING_STOPPED`: echo requestId, contractId, healthDay, `stopped:true` kể cả đã stop trước đó.

### 5.3 TRACK_CONTRACT — payload đầy đủ cho Health

```json
{
  "bridgeVersion": 2,
  "type": "TRACK_CONTRACT",
  "payload": {
    "requestId": "track-42",
    "bridgeSessionId": "native-issued-session-7",
    "clientSequence": 42,
    "reason": "opened",
    "contract": {
      "contractId": "contract-walk",
      "contractName": "Morning Walk",
      "healthDay": "2026-09-23",
      "expiresAt": "2026-09-24T00:00:00+07:00",
      "completionPolicy": {
        "kind": "all_health_slots",
        "requiredActivityIds": ["contract-walk:primary"]
      },
      "activities": [
        {
          "activityId": "contract-walk:primary",
          "slot": "primary",
          "name": "Walking",
          "mode": "health",
          "metric": "steps",
          "target": 8000,
          "unit": "count"
        }
      ]
    }
  }
}
```

Ví dụ dùng reset hour 0; native tính/xác minh cửa sổ thực theo setting, không hard-code ngày kết thúc là nửa đêm. Mỗi activity gồm `activityId/slot/name/mode`; `mode=health` bắt buộc metric/target/unit canonical khớp `SET_GOALS`. `mode=timer` dùng mapping ID tới timer native; không tin `startedAt/endsAt` từ web và không tự Start chỉ vì track.

```json
{
  "bridgeVersion": 2,
  "type": "CONTRACT_TRACKING_ACCEPTED",
  "payload": {
    "requestId": "track-42",
    "contractId": "contract-walk",
    "healthDay": "2026-09-23",
    "focused": true,
    "presentationStatus": "active"
  }
}
```

Validation: ID/tên có giới hạn độ dài, 1–2 slot duy nhất, target hữu hạn > 0, unit đúng metric, occurrence chưa hết hạn, policy chỉ trỏ ID trong contract, auth/day/sequence đúng. Với `all_health_slots`, required IDs phải bằng toàn bộ tập Health slot áp dụng đã xác minh ở LA-01, không được là subset tùy ý. Definition lệch goal hiện tại trả `goal_definition_mismatch`; web sync goals rồi gửi logical attempt mới thay vì native tự tạo nguồn target thứ hai.

### 5.4 Tích hợp START_TIMER/CANCEL_TIMER/ACTIVITY_COMPLETED

- Mở contract và Start là hai ý định khác nhau. Web mới thêm `trackingContext` tùy chọn vào `START_TIMER`: mutation envelope (`bridgeSessionId/clientSequence`), full contract definition như trên và timer activity ID. Native validate/dedupe envelope **trước `TestamentTimer.start`**; retry không tạo timer run mới hoặc cancel run khác. Native xử lý thành một thao tác start + register + focus; chỉ focus sau khi start được chấp nhận. Payload cũ vẫn hợp lệ và giữ behavior cũ.
- Live Activity request thất bại không làm timer thất bại. `TIMER_STARTED` vẫn trả endsAt; field tùy chọn `liveActivityStatus` báo kết quả presentation riêng.
- `CANCEL_TIMER` thêm `reason: paused|cancelled` và tracking context cho web mới. Legacy không có reason coi là cancelled. Pause hiện là cancel/resume=start(remaining); không quảng cáo native có `PAUSE_TIMER` hay clock pause mới. V1 tạm gỡ phần timer khi pause; thẻ có Health vẫn giữ, timer-only end. Resume tạo lại nếu foreground và vẫn đúng occurrence.
- `ACTIVITY_COMPLETED` thêm các field tùy chọn `contractId`, `healthDay`, `scope: contract|slot`, `completedAt`, mutation envelope. `scope=contract` mới được coi là xác nhận hoàn thành toàn thẻ; `scope=slot` chỉ update slot. Payload legacy tiếp tục mark celebration như cũ, không suy luận contract completion từ tên ID.
- Completion mới phải validate thời gian/owner/occurrence trước khi gọi logic markCelebrated; receipt sau ngày mới không được đánh dấu nhầm goal của ngày hiện tại. Giữ thông tin occurrence gốc của timer đi qua boundary và ghi nhận completion theo business rule web đã xác minh.
- Update `SET_GOALS`/day reset trong web mới phải serialize trước snapshot tracking; thêm envelope tùy chọn khi cần chặn stale mutation cùng transaction. Mục LA-01 phải chốt danh sách field chính xác trong schema/fixture trước code integration.

### 5.5 State response và errors

`LIVE_ACTIVITY_STATE` gồm `supported`, `enabled`, `focusedOccurrence?`, `tracked[]`. Mỗi entry trả `contractId`, `healthDay`, `presentationStatus`, `focused`, `reason?`, `lastUpdatedAt?`; không đưa token hoặc raw Health sample.

Presentation status: `pending`, `active`, `stale`, `awaiting_timer`, `needs_foreground`, `disabled`, `limit_reached`, `dismissed`, `ended`, `failed`. Stale/disabled không đồng nghĩa contract thất bại. Errors cho payload/sequence/account/day dùng `ERROR` có requestId; ActivityKit refusal hợp lệ được trả thành presentation status để web không retry nghiệp vụ timer.

## 6. Quản lý nhiều thẻ, focus và concurrency

`LiveActivityCoordinator` là đầu mối duy nhất gọi ActivityKit. Lưu map occurrence → ActivityKit ID; dùng adapter/protocol để fake driver trong test. `Activity.activities` là nguồn đối chiếu thực tế sau relaunch, không chỉ tin ID persisted.

Thuật toán focus đề xuất:

1. Lệnh mở/Start hợp lệ được native gán focus sequence tăng dần.
2. Trong các thẻ còn eligible/hiển thị, thẻ focus nhận score 100, các thẻ còn lại xếp giảm dần dưới 100 theo lần chọn gần nhất.
3. Update score của các thẻ bị ảnh hưởng; không end/recreate chỉ để đổi focus.
4. Health update, timer tick, completion thẻ khác, reload và metadata sync không tăng focus.
5. Khi focused thẻ kết thúc/bị dismiss/không tạo được, ưu tiên lại thẻ eligible gần nhất còn tồn tại. Có thể giữ riêng last user selection để khi Start một timer-only contract nó được focus đúng.

Các `Activity.update`/`end` phải đi qua queue tuần tự theo occurrence, kèm desired state version. Actor vẫn có thể re-enter tại `await`; vì vậy re-check generation sau đọc HealthKit, sau request/create và trước apply. Account/occurrence đã invalid thì end ngay Activity vừa tạo trễ, không gắn vào account mới. End là terminal cho generation đó; stale query không được revive thẻ.

Khi iOS/user dismiss, ghi suppression cho occurrence và không tạo lại trong health observer, app reload hoặc snapshot sync. Một thao tác mở/Start rõ ràng sau đó có thể request lại; không tự hồi sinh khi người dùng chưa tương tác.

## 7. Timer và Health integration

### 7.1 Timer

- Reuse `TestamentTimer` làm nguồn thời gian duy nhất; không thêm timer thứ hai trong coordinator/widget.
- Thêm timer instance/generation nội bộ và mapping occurrence để completion của lần chạy cũ không ảnh hưởng lần resume/start mới cùng ID.
- Start timer B: timer A vẫn được cancel theo behavior hiện tại; bỏ phần timer của thẻ A. A còn Health thì giữ, A timer-only thì end. Không kết thúc mọi thẻ khác.
- Mở Health contract B khi timer A đang chạy: chỉ đổi focus, timer A/thẻ A giữ nguyên.
- Cancel/pause không đồng nghĩa contract honoured. Hết giờ chỉ xử lý policy tương ứng ở mục 4.4.
- Notification identifier, `TIMER_COMPLETED` durable event, `notified` và chống completion trùng được giữ và regression test. Hiển thị Live Activity không được dùng làm bằng chứng user đã thấy celebration.
- Timer vượt health-day boundary: hết hiệu lực Health projection của ngày cũ; giữ phần timer nếu nó vẫn chạy và contract chưa thực sự hết hạn. Timer vẫn map occurrence gốc, không tự chuyển sang ngày mới. Contract có expiry đúng boundary thì gỡ thẻ theo expiry nhưng không tự hủy timer nghiệp vụ ngoài rule đã xác minh ở LA-01.

### 7.2 Health progress

Tạo `HealthProgressSnapshotBuilder`, được gọi sau collection local hoàn tất, khi track/update goal, foreground, protected-data recovery và đổi reset hour. Với lần track đầu hoặc reload, phải đọc snapshot dù không có sample mới trong outcome `.noChanges`.

1. Chụp account/day/definition generations và danh sách mọi occurrence đang theo dõi.
2. Gom unique `(metric, windowStart, queryEnd)` để mỗi metric/cửa sổ chỉ query một lần, fan-out cho các contract.
3. Reuse statistics/sleep logic có sẵn; không cộng raw iPhone + Watch samples, không chờ upload thành công.
4. Kết quả đọc phân biệt `value`, `noData`, `protectedDataUnavailable`, `failed`. Giữ API optional cũ cho caller cũ, thêm typed read path bên trong nếu cần; không suy ra quyền đọc bị từ chối.
5. Dữ liệu sửa/xóa có thể làm total giảm; không ép total tăng đơn điệu. Chỉ bỏ ActivityKit update khi **toàn snapshot hiển thị liên quan** không đổi; nil→value/value→noData, target, reached, stale, focus và terminal đều phải xử lý.
6. Re-check generation, update mọi thẻ liên quan rồi cho GoalMonitor consume cùng snapshot khi phù hợp. Giữ completion handler HealthKit được acknowledge đúng cả error path; không chờ web/network/animation.

Progress mỗi slot: `clamp(value / target, 0...1)` nếu có value; `nil` vẫn unknown. Không cộng steps với kcal, không tự lấy trung bình rồi gọi đó là phần trăm hoàn thành contract. V1 ưu tiên hiển thị từng slot và số slot đạt; chỉ dùng overall % khi đã xác minh đúng công thức web.

Metric policy:

| Nhóm | Cách trình bày/đọc |
|---|---|
| Steps, walk/run distance, cycling distance, swimming distance, exercise minutes | Value/target canonical; distance đổi km/mi chỉ ở display |
| Active/basal energy | Giữ metric goal web gửi; không tự cộng basal thành Calories tổng |
| Sleep | Phút ngủ đã ghi nhận, không phải đang đo giấc ngủ trực tiếp; giữ attribution hiện tại |
| Heart rate | Giá trị thống kê theo cửa sổ hiện tại, không phải live sensor; chỉ progress/auto-complete khi web có goal rule tường minh đã kiểm tra |

Danh sách metric đọc được không có nghĩa tự tạo một goal/thẻ cho tất cả metric. Chỉ theo activity đã map hợp lệ trong contract.

## 8. UI và deep link

Widget Extension dùng SwiftUI với Lock Screen, compact leading/trailing, minimal và expanded. Cùng một data model hỗ trợ timer-only, health-only, mixed, unknown/stale, completed.

| Presentation | Nội dung |
|---|---|
| Compact | Icon + countdown nếu contract có timer chạy; nếu Health thì primary chưa đạt, rồi secondary; tên/value ngắn vừa không gian |
| Minimal | Icon hoặc progress ring của slot đang ưu tiên; unknown dùng placeholder |
| Expanded | Tên contract, tối đa hai slot, value/target hoặc countdown, trạng thái dữ liệu |
| Lock Screen | Chi tiết tương tự expanded, timestamp khi stale; không thêm thao tác nghiệp vụ chưa thống nhất |
| Completed | Check + copy kết quả; transition hỗ trợ theo OS, vẫn rõ khi animation tắt |

V1 chỉ tap để mở contract; pause/cancel trực tiếp bằng App Intent chưa nằm trong scope. Thêm accessibility label, Dynamic Type/layout tên dài, đơn vị địa phương, Light/Dark/Always-On và privacy redaction phù hợp nội dung Health.

URL đề xuất `honoured://contract/<encoded-id>?day=<health-day>&occurrence=<opaque-token>`. Đăng ký scheme + `.onOpenURL`; chỉ chấp nhận route/ID hợp lệ, map token vào record của account hiện tại. Không đưa auth/session token vào URL.

Warm/cold start: lưu navigation intent theo account, chờ web hydrate auth + router, rồi gửi `LIVE_ACTIVITY_OPENED { eventId, contractId, healthDay }`. Native queue hiện flush khi inbound message đầu tiên tới, không đồng nghĩa store/router đã hydrate; web phải buffer event và dedupe theo eventId. Tap không tự đổi business state. Contract đã xóa/hết hạn hoặc token thuộc account cũ dẫn về màn hình an toàn, không hiển thị dữ liệu user cũ.

## 9. Restore, ngày mới, account cleanup

Thứ tự restore đề xuất:

1. Đọc auth hiện tại và store versioned; không lấy billing identity làm account owner của Health.
2. Reconcile timer, xác định occurrence/day hiện tại và inventory `Activity.activities`.
3. End orphan/wrong-account/expired/duplicate thẻ; giữ một thẻ hợp lệ mỗi occurrence. Không tạo thẻ mới trong launch nền.
4. Refresh snapshot khi dữ liệu truy cập được, cập nhật score của các thẻ còn sống.
5. Sau web hydrate, `SYNC_TRACKED_CONTRACTS` cung cấp snapshot đúng và không đổi focus. Missing activity do user dismiss/timeout không tự tạo lại; await explicit open/start.

Reset hour/timezone/day change tăng day generation, invalidate query cũ, refresh validity. Health-only thẻ của ngày cũ hết hiệu lực; timer còn chạy được xử lý theo mục 7.1 và expiry thực của contract. Standing contract ngày sau là occurrence khác và cần web definition mới; không dùng goal list persisted của ngày trước để tự khởi tạo ngày sau. Nếu app không chạy đúng boundary, cleanup diễn ra ở lần execution sau; UI có thời hạn/stale và không hứa tự biến mất đúng nửa đêm.

Account cleanup gắn trực tiếp vào `SET_AUTH_SESSION` đổi user và `CLEAR_AUTH_SESSION`. `IDENTIFY_USER`/`LOGOUT_USER` hiện là billing path; phải audit logout flow và bảo đảm cleanup Live Activity được gọi idempotent khi logout thực sự, không nhầm RevenueCat identity với Health account. Đổi account invalidate session token + generation **trước** khi await end các thẻ, xóa snapshot/pending navigation/tombstone của owner cũ. Không để late callback tái tạo thẻ.

## 10. Xcode, file map và dependencies

| File/nhóm đề xuất | Công việc |
|---|---|
| `ios/project.yml` | `HonouredWidgets` target iOS 16.2, embed dependency, schemes, shared source membership, unit test target |
| `ios/Honoured/Info.plist` | `NSSupportsLiveActivities`, URL scheme |
| `ios/HonouredShared/HonouredActivityAttributes.swift` | DTO tương thích app/extension, không import app service |
| `ios/Honoured/TrackedContractsStore.swift` | Persistence, sequence/generation, lifecycle occurrence |
| `ios/Honoured/LiveActivityCoordinator.swift` | ActivityKit driver, map nhiều thẻ, priority, serialized update/end |
| `ios/Honoured/HealthProgressSnapshotBuilder.swift` | Query reuse, typed availability, projection tiến độ |
| `ios/Honoured/ContractDeepLinkCoordinator.swift` | Parse/validate URL, account-bound pending navigation |
| `ios/HonouredWidgets/*` | Widget bundle, ActivityConfiguration, reusable views, previews, Info.plist |
| `ios/HonouredTests/*` | Reducer/store/coordinator với fake clock, fake Health reader, fake ActivityKit driver |
| Bridge/timer/Health/lifecycle files hiện tại | Hooks và regression safeguards như các mục trên |
| `docs/bridge.md`, `README.md` | Chỉ cập nhật protocol/setup khi implementation thực sự có |
| Web repo riêng | Types/parser, theo dõi contract, completion scope, hydration/deep-link buffer và tests |

App/extension ký cùng team, extension bundle ID lấy từ app bundle ID đã resolve + suffix `.widgets`; kiểm tra cả debug override và release. Không sửa tay generated `.xcodeproj`; generate từ `project.yml`. Shared DTO được compile cả hai target; extension không link billing/Health/backend services.

**App Group không bắt buộc cho bản đầu** vì widget render từ ActivityKit content. Chỉ thêm nếu có nhu cầu shared preference/App Intent cụ thể sau này. Không bật Push Notifications/frequent-update capability cho bản local chỉ vì dùng Live Activities.

Web chưa ở checkout: đường dẫn như `native-bridge.ts`, `timer-store.ts`, contract view/router cần xác minh trong repo thật. Không dùng progress note cũ để đánh dấu web đã tích hợp hoặc production đã publish.

## 11. Các giai đoạn triển khai và bàn giao

Trạng thái từng gói ghi ở [mục 14](#14-tiến-độ-triển-khai--2409); bảng dưới giữ nguyên estimate ban đầu. Giờ là ước lượng engineering, không thay đổi thỏa thuận thương mại M3; chưa gồm chờ account/device, App Store review hoặc backend APNs.

| ID | Gói công việc | Kết quả review được | Phụ thuộc | Giờ |
|---|---|---|---|---|
| LA-01 | Đối chiếu web business rule + spike nền | Mapping contract/slot/timer, schema bridge/fixtures, policy completion; demo Health locked + timer suspended; chốt local acceptance | Truy cập web source; thiết bị cho spike | 3–4 |
| LA-02 | Tracking store, bridge và concurrency | Persistence/account/day, sequence/session, capabilities, protocol mới; fake-driver tests | LA-01 | 8–10 |
| LA-03 | Widget target và UI | Build app+extension; preview đủ mode; priority demo bằng stub; payload size check | Schema LA-01; driver LA-02 | 6–8 |
| LA-04 | Timer integration | Start/replace/cancel/pause/resume/completion/restore, notification regression | LA-02/03 | 4–6 |
| LA-05 | Health progress và completion projection | Fan-out mọi thẻ, cache/availability, query dedupe, all-slot parity tests | LA-01/02/03 | 6–8 |
| LA-06 | Web integration | Open/start focus, sync sau hydrate, explicit completion scope, tap navigation và capability fallback | LA-02; web repo | 6–8 |
| LA-07 | Lifecycle/deep links và account cleanup | Cold/warm start, orphan/dismissal, rollover, logout/account race | LA-04/05/06 | 4–6 |
| LA-08 | QA thiết bị + archive/TestFlight validation | Evidence matrix, regression, signing app/extension, danh sách giới hạn đã kiểm chứng | LA-03–07 | 8–12 |
| | **Tổng** | | | **45–62 giờ** |

LA-03 có thể làm song song với phần logic LA-02 khi schema đã khóa; LA-06 dùng stub/fixtures trong lúc native timer/Health tích hợp. Không cần đợi backend upload để làm Live Activity. Hạng mục APNs nếu phát sinh phải có estimate và acceptance riêng.

Các commit dự kiến tách thành: protocol/state; widget/UI; timer; Health; web integration (repo riêng); lifecycle/QA fixes. Mỗi commit có validation tương ứng; không gom scratch outputs, generated project bản sao hoặc secrets.

## 12. Kế hoạch kiểm thử

### 12.1 Unit/logic — cần tạo test target thật

Hiện `testTargets: []`; không coi có unit suite trước khi LA-02 thêm harness. Dùng fake clock/ActivityKit/Health reader để test các hành vi dưới đây, không phụ thuộc simulator chờ nhiều giờ.

| Nhóm | Ca bắt buộc |
|---|---|
| Identity | Hai slot cùng contract → một thẻ; hai contract → hai thẻ; standing contract khác health day không đè nhau |
| Ordering | Mở A→B nhưng async A xong sau; retry cùng request; message phiên reload cũ; đổi clock thiết bị không đảo focus |
| Async lifecycle | Logout giữa request/create/update; end trước query trả về; update đang chờ rồi cancel; timer cũ cùng activityId hoàn thành sau resume |
| Focus | Update Health không giành focus; mở B không hủy A; focused end/dismiss thì fallback thẻ gần nhất; sync không đổi focus |
| Timer | One-timer replacement giữ Health của A; pause/resume bridge mapping; notification không bị duplicate; Live Activity failure không fail timer |
| Health | Cùng metric query một lần; nil khác 0; protected data giữ snapshot; successful noData không giữ số cũ như fresh; sample deletion cho phép total giảm |
| Completion | Primary đạt/secondary chưa → không honoured toàn contract; all required reached; manual/timer celebration marker không giả metric reached; policy mixed/web-authoritative |
| Validity | Reset hour khác 0, timezone/DST, qua ngày, snapshot ngày cũ, definition/target thay đổi giữa query |
| Limits/restore | Disabled/unsupported/limit failure; create bị crash trước persist mapping; orphan/duplicate; user-dismiss không tự hồi sinh; payload vượt giới hạn |
| Protocol | RequestId correlation, missing/unknown/invalid fields, sequence, account, policy reference, units, backward compatibility |

### 12.2 Simulator và web tests

- BridgeStub có kịch bản `live-activities-multiple`, `live-activities-focus-race`, `live-activities-health`, `live-activities-timer`, `live-activities-account`, `live-activities-restore`.
- Thêm debug-only cách đổi fake totals ngay trong session (25%→80%→đạt, nil/error), không chỉ launch args cố định. Không expose debug API trong release.
- Preview/render compact, minimal, expanded, Lock Screen: timer/Health/mixed/unknown/stale/completed; 1–2 slot; text dài; font lớn; dark/light.
- Web tests: capability absent; click A/B nhanh; resume order; hydrate chưa xong; SYNC empty lúc loading bị ngăn; event completion/tap được buffer và dedupe.
- Build app + extension, chạy test target, validate extension được embed đúng. Simulator Health runtime dùng ad-hoc signing như AGENTS.md; compile unsigned chỉ chứng minh compile.

### 12.3 Thiết bị thật

| Kịch bản | Kỳ vọng |
|---|---|
| Hai Health + một timer, mở lần lượt | Ba thẻ riêng; score đổi đúng; timer không dừng khi mở Health |
| Có Live Activity từ app khác | Honoured giữ policy nội bộ, UI đúng compact/minimal; không cam kết chiếm ưu tiên toàn máy |
| Khóa máy khi Health thay đổi | Snapshot không nhảy về 0; ghi nhận latency thực; unlock/protected data cập nhật trở lại |
| Timer hết lúc app foreground/background/suspend/force quit | Countdown đúng; notification theo cài đặt; ghi rõ lúc native có thể reconcile/end |
| Tắt mạng | Local Health/timer còn hoạt động theo dữ liệu đọc được; upload failure không chặn presentation |
| Tắt Live Activities riêng, tắt notifications riêng | Hai quyền độc lập; app/timer không hỏng, không tự lặp request |
| User swipe dismiss một thẻ | Các thẻ khác còn; sync/background không tự mở lại |
| Logout/đổi user khi đang có nhiều thẻ | Gỡ nội dung cũ, late callback/deep link cũ không lộ dữ liệu |
| Tap thẻ warm/cold start | Đến đúng contract/day sau auth/router ready, không navigate trùng |
| Always-On, Reduce Motion, chữ lớn | Nội dung vẫn hiểu được khi animation không chạy |
| iPhone + Apple Watch cùng nguồn dữ liệu | Số liệu thống nhất với native statistics, không cộng đôi |
| Qua ngày/reset hour và hết tuổi thọ thẻ | Không tự tạo vòng lặp thẻ mới; reconcile đúng occurrence |
| iOS 16.0–16.1 và máy không có Dynamic Island | Feature fallback theo OS; máy OS hỗ trợ nhưng không có Island vẫn có Lock Screen |
| Signed release/TestFlight | Extension ký/nhúng đúng, capability đúng; release không có fake-health/debug handlers |

Không đánh dấu các ca thiết bị thật pass bằng simulator hoặc log fake data. Không coi archive thành công là đã publish TestFlight/App Store; report mỗi trạng thái riêng.

## 13. Điều kiện Done và các quyết định cần giữ rõ

- [ ] Một thẻ mỗi tracked occurrence, không duplicate, không đóng thẻ khác chỉ vì đổi focus.
- [ ] Mọi thẻ Health được cập nhật từ source-deduplicated local data; nil/error không giả thành 0.
- [ ] Native/web thống nhất completion policy; partial slot không hoàn thành nhầm contract.
- [ ] Timer và notification hiện có không regression; vẫn chỉ một timer nghiệp vụ.
- [ ] Request/create/update/end, account/day changes không có race làm revive hoặc lộ thẻ cũ.
- [ ] Restore/sync không tự giành focus hoặc hồi sinh thẻ user đã dismiss.
- [ ] Deep link tới đúng occurrence và đúng tài khoản sau hydrate.
- [ ] Các giới hạn khóa máy, timer suspended, thời hạn thẻ và animation được thể hiện trong acceptance/QA.
- [ ] Build/test app + widget, web integration và ca máy thật có bằng chứng riêng.
- [ ] Bridge/setup docs cập nhật theo behavior đã triển khai; rollout và rollback có capability gate.

Gate trước implementation đầy đủ: LA-01 phải xác minh completion rule từ web thật và kiểm chứng spike local. Nếu khách yêu cầu **Health live từng giây khi khóa máy**, **thẻ hoạt động cả ngày**, **animation 3 lần bắt buộc**, hoặc **auto-end đúng giây khi process không chạy**, đó không phải cam kết của bản local trong plan này; cần điều chỉnh thiết kế/scope dựa trên bằng chứng thiết bị.

Kế hoạch rollout: native có capability và fallback trước; web chỉ bật khi protocol có sẵn. Khi rollback web ngừng tạo tracking mới; các thẻ hiện có được cleanup qua reconcile/stop-tracking đã hỗ trợ. Không xóa timer/Health nghiệp vụ chỉ để tắt presentation. Chưa có thao tác publish/deploy nào được thực hiện bởi tài liệu này.

## 14. Tiến độ triển khai — 24/09

Phần native của LA-01 → LA-07 đã có code, unit test và bằng chứng simulator. Phần web LA-06 đã có code trên project Lovable (xem [14.6](#146-la-06--tích-hợp-web-2409)), chưa publish và chưa chạy E2E với build native. Chưa có: QA máy thật và signing/TestFlight (LA-08). Không commit, push, publish hay deploy trong đợt này. Hợp đồng message chính thức nằm ở [bridge.md](bridge.md), mục *v2 — Live Activities*.

### 14.1 LA-01 — đối chiếu web

Phiên này không có Lovable MCP và không có bản checkout source web, nên đã đối chiếu **bundle production đang deploy** (`honour-your-word.lovable.app`, tải 23/09, `routes-Da7O-fFB.js`). Đây là bằng chứng về bản đang chạy, không phải HEAD của repo Lovable; cần kiểm lại trên source trước khi sửa web.

| Điểm | Web đang chạy |
|---|---|
| Hoàn thành | Contract honoured khi (a) **mọi** slot map Health đạt trong cùng health day (`GOAL_REACHED` → `honoured.goalsReached.v1`), (b) Testament Timer kết thúc tự nhiên (`TIMER_COMPLETED` → honour bất kể slot Health), hoặc (c) tự báo "Honoured". Hết `deadline` khi còn active → broken. Standing contract qua reset → honoured nếu `progress ≥ 1` (trung bình các slot), sinh contract mới với **ID mới**. |
| ID | Timer: `activityId = contract.id`, mọi contract active đều Start được. Health slot: `<contractId>:primary/secondary`, chỉ activity map được Health. |
| `SET_GOALS` | Chỉ gửi goal của **contract active đầu tiên** (`En(state)`). |
| Số contract | Màn tạo contract chặn khi đã có contract active: thực tế **một contract active mỗi lúc**. |
| Auth | `CLEAR_AUTH_SESSION` gửi khi `SIGNED_OUT`; `SET_AUTH_SESSION` mỗi lần load trang (INITIAL_SESSION). `LOGOUT_USER` chỉ là billing. |

### 14.2 Điều chỉnh so với plan và lý do

- **Policy thêm `all_health_slots_or_timer`.** Web thật honour contract Health khi timer xong tự nhiên, nên một policy `kind` đơn không tả đúng contract Health có chạy timer. Giữ `all_health_slots`, `timer_completion`, `web_authoritative` như plan.
- **`timerActivityId` ở cấp contract** (ngoài `mode: timer`). Timer của web thuộc contract chứ không thuộc slot; contract Health cũng Start được timer.
- **Nguồn target duy nhất là `SET_GOALS`** như plan, nhưng vì web hiện chỉ gửi goal của contract đầu tiên, web phải gửi goal của **mọi** contract đang theo dõi; nếu không `TRACK_CONTRACT` trả `goal_definition_mismatch`. Ghi vào integration notes của bridge.md.
- **Session gắn account qua `SET_AUTH_SESSION`.** Trang mới chưa bind thì mutation bị từ chối (`auth_session_required`); ID đổi khi reload, sign-out, đổi user, giữ nguyên khi refresh token cùng user.
- **SYNC không tạo thẻ** cho occurrence chưa ai mở (`pending`/`awaiting_open`), chỉ thử lại thẻ đã được yêu cầu mà hỏng vì `needs_foreground`/`disabled`. `limit_reached` không tự thử lại.
- **Thêm lý do `contract_broken`** cho `STOP_TRACKING_CONTRACT` vì web có trạng thái broken.
- **Thẻ hoàn thành** end với `.after(now + 30 s)`; thẻ hết hạn/qua ngày end `.immediate`. Đổi account/logout gỡ ngay cả thẻ đã hoàn thành đang hiển thị kết quả.
- **Broadcast `LIVE_ACTIVITY_STATE_CHANGED` đi trước reply** của cùng lệnh, giống `TIMER_CANCELLED` trước `TIMER_STARTED` (unit test bắt được race khi làm ngược lại).
- **Ngoài phạm vi nhưng sửa kèm:** helper `number()` của bridge coi số JSON `0`/`1` là boolean (`raw is Bool` đúng với NSNumber 0/1), nên `durationSeconds: 1`, `target: 1` bị từ chối. Đổi sang kiểm tra kiểu CFBoolean.
- **Sau review độc lập (agent audit, chỉ đọc code):** không có lỗi Critical/High; 4 lỗi Medium đã sửa và có test: (1) kết quả Health đọc trước `STOP` có thể rơi vào record được track lại cùng key → plan đọc gắn `occurrenceToken` và metric; (2) `TRACK`/`SYNC` thiếu `timerActivityId` làm rơi timer mà `START_TIMER` đã gắn → giữ timer đã biết; (3) `ACTIVITY_COMPLETED` có scope bị từ chối envelope thì không đặt marker celebration → đặt marker trước, độc lập với envelope; (4) JSON `null` ở field tùy chọn bị coi là có giá trị → coi là không có. Kèm các điểm nhỏ: restore khi mở khóa không đảo lại account vừa đổi, session xoay khi trang mới commit (điều hướng lỗi không làm mất session), khởi động lại timer của cùng contract không end/tạo lại thẻ, `CANCEL_TIMER.reason` lạ coi là `cancelled`, bỏ gợi ý trạng thái cũ trong hàng đợi khi đổi account.

Các giá trị kiểm chứng trên SDK iOS 26.5 trong máy: `ActivityContent`, `relevanceScore`, `staleDate` từ iOS 16.2 (đúng như plan); iOS 26 thêm `ActivityState.pending` nên code xử lý state bằng nhánh `default`.

### 14.3 Đã triển khai

| Gói | Nội dung | File chính |
|---|---|---|
| LA-02 | Store theo account có version, file bảo vệ đến lần mở khóa đầu, không ghi đè khi chưa đọc được. Engine một hàng đợi lệnh: thứ tự xử lý = thứ tự message đến, focus sequence do native cấp, generation account/definition/lần đọc, per-card update tuần tự (nội dung mới nhất thắng), end là trạng thái cuối. Bridge session + sequence + cache reply cho retry. Capability trong `NATIVE_READY`/`PLATFORM_INFO`. 4 message mới, trạng thái/lỗi như bridge.md. | `ios/Honoured/LiveActivities/Core/*`, `LiveActivities/NativeBridge+LiveActivities.swift`, `NativeBridge.swift` |
| LA-03 | Target `HonouredWidgets` (iOS 16.2, `<bundle>.widgets`, nhúng vào app), app vẫn iOS 16.0 và weak-link ActivityKit. Lock Screen, compact, minimal, expanded cho timer/Health/mixed/unknown/stale/completed; một countdown mỗi thẻ; giới hạn Dynamic Type `xxLarge` để vừa ~160 pt; accessibility label; giá trị Health `privacySensitive`. Kiểm kích thước payload 4 KB trước khi tạo. | `ios/HonouredWidgets/*`, `ios/HonouredShared/HonouredLiveActivity.swift`, `ios/project.yml`, `Info.plist` |
| LA-04 | `TestamentTimer` có `runId` mỗi lần chạy; hook start/discard/complete sang engine. `START_TIMER` + `trackingContext`: kiểm envelope trước khi đụng timer, timer luôn chạy, focus sau khi start; `liveActivityStatus` riêng. Thay timer A giữ Health của A; pause/resume; hoàn thành chỉ khi native xử lý thật. | `TestamentTimer.swift`, `NativeBridge.swift` |
| LA-05 | Đọc HealthKit có kiểu (`value`/`noData`/`protectedDataUnavailable`/`failed`), mỗi metric/cửa sổ đọc một lần rồi chia cho mọi thẻ, sau mỗi lượt collection (kể cả `.noChanges`), khi track/sync, foreground, protected data. `GoalMonitor` dùng lại cùng số đọc cho ngày hiện tại. Slot đạt giữ nguyên trong occurrence; một slot đạt không hoàn thành contract. | `HealthKitService.swift`, `HealthSyncCoordinator.swift`, `GoalMonitor.swift` |
| LA-07 | Restore khi launch/protected data: nhận lại thẻ theo token, gỡ thẻ mồ côi/tài khoản khác/trùng, thẻ biến mất khi app không chạy → `dismissed`, không tạo mới ở nền; Keychain chưa đọc được thì không đụng gì. Qua ngày/đổi reset hour/múi giờ/hết hạn. Đổi account/logout gỡ mọi thẻ trước khi xử lý tiếp. Deep link `honoured://contract/…` → `LIVE_ACTIVITY_OPENED` bền vững, chỉ với token của account hiện tại. | `LiveActivityEngine.swift`, `LiveActivityCoordinator.swift`, `HonouredAppDelegate.swift`, `HonouredApp.swift`, `AuthSessionStore.swift` |
| Android | 4 message mới trả `ERROR { code: "not_implemented" }` kèm requestId. | `NativeBridge.kt` |

### 14.4 Kiểm chứng đã chạy (24/09)

| Loại | Kết quả |
|---|---|
| Build | `xcodegen generate`; simulator Debug app + widget `BUILD SUCCEEDED` (unsigned và ad-hoc). Không có warning mới (còn 5 warning `[weak self]` cũ của billing). Bundle: `HonouredWidgets.appex` nhúng đúng, min iOS 16.2, cùng version/build với app; app min 16.0, ActivityKit `LC_LOAD_WEAK_DYLIB`; extension chỉ link ActivityKit/WidgetKit/SwiftUI. |
| Unit test | Target mới `HonouredTests` (không host app): **81/81 pass** trên bản cuối; engine + session chạy lặp 25 lần: 1.325 lượt pass, không flaky. Test của lỗi (1) được xác nhận fail khi gỡ bản sửa. Gồm identity, thứ tự/focus, race account/stop/definition với kết quả Health về muộn, timer, Health nil ≠ 0, completion, reset hour/DST/qua ngày, restore/mồ côi/trùng, dismiss, payload, protocol, deep link, render mọi biến thể thẻ. |
| Simulator (iPhone 17, iOS 26.5, ActivityKit thật, qua BridgeStub), chạy lại trên bản cuối | `live-activities-multiple` 20/20 (bảng nghiệm thu mục 1, score đọc lại từ ActivityKit), `focus-race` 16/16, `health` 11/11, `timer` 21/21, `account` 8/8, `deeplink` 4/4 (qua URL scheme thật), `restore-setup` 4/4 + `restore-check` 5/5 (qua exit/relaunch thật), `suspended-timer` 3/3 (app ở nền qua deadline). Hồi quy: `timer-foreground` 17/17, `timer-cancel-background` 3/3, `goals` 13/13, `sound` 5/5. |
| Release | Build simulator Release pass: không còn chuỗi/stub DEBUG trong binary, ActivityKit vẫn weak-link. Android `assembleDebug` pass (JDK 17). |
| Ảnh simulator | Dynamic Island compact: timer dẫn đầu (đồng hồ đếm ngược); mở lại Walking → Walking dẫn đầu (`2k` bước) trong khi timer vẫn chạy; app ở nền qua deadline → thẻ đứng `0:00`, chỉ hoàn thành khi app chạy lại (reconcile, `TIMER_COMPLETED` một lần, `completedAt = endsAt`). |

Lưu ý khi đọc kết quả: lần đầu `START_TIMER` hiện hộp thoại quyền thông báo và app ở `inactive` cho tới khi trả lời, nên timer hết giờ lúc đó hoàn thành khi reconcile chứ không phải in-app (đúng thiết kế cũ). Một lượt chạy `timer` bị gián đoạn vì nút thủ công của trang stub được bấm giữa chừng; chạy lại riêng thì 21/21.

### 14.5 Chưa kiểm chứng / còn lại

- **Web (LA-06):** code đã có (mục 14.6) nhưng **chưa publish** và **chưa chạy E2E** với build native. Cho phép nhiều contract active (điều kiện để có nhiều thẻ cùng lúc) vẫn chờ khách quyết; web hiện vẫn một contract active mỗi lúc.
- **Máy thật (LA-08):** toàn bộ bảng 12.3 — Lock Screen thật, Always-On, khóa máy khi Health đổi, background delivery, banner/Focus, app khác có Live Activity, giới hạn số thẻ thật, 8 giờ, iOS 16.0–16.2, máy không có Dynamic Island. Simulator không chứng minh những điểm này.
- **Signing:** App ID `<bundle>.widgets` và profile cho extension; archive/TestFlight chưa làm.
- **Cần chốt với sản phẩm:** thẻ iOS tự end sau 8 giờ (`system_ended`) hiện có thể được tạo lại khi người dùng **mở rõ ràng** contract (giống thẻ bị vuốt bỏ); native không tự tạo lại. Chưa chạy trên runtime iOS 16.0–16.1 (máy chỉ có iOS 26.5); weak-link đã kiểm bằng `otool`.
- **Chưa chụp được** Lock Screen và expanded trên simulator (không có công cụ khóa máy/nhấn giữ từ CLI); bố cục các presentation này mới kiểm bằng render offscreen trong unit test. `ProgressView(timerInterval:)` không render được offscreen, cần xem trên máy.

### 14.6 LA-06 — tích hợp web (24/09)

Làm qua Lovable MCP trên project **Honoured V13** (`eec79567-2e9c-4821-aef7-11204b546ea7`), chia 3 yêu cầu cộng một vòng sửa sau review. Agent Lovable viết code; mỗi phần được review diff và chạy lại typecheck, test, build trên một bản sao source ở máy (không có `.env` thật). Chưa publish/deploy, không đụng database/Supabase, không sửa repo native.

**Đối chiếu source trước khi sửa.** Trên source (commit `67a8132`) cả 5 điểm ở 14.1 khớp với bundle production: luật hoàn thành, ID timer/slot, `SET_GOALS` chỉ contract đầu tiên, một contract active mỗi lúc, và thời điểm gửi `SET_AUTH_SESSION`/`CLEAR_AUTH_SESSION`.

| Phần | Commit Lovable | Nội dung | Kiểm trên máy |
|---|---|---|---|
| 1 | `00217d3` | Type, parser, capability, hàng đợi mutation (`src/lib/live-activity-queue.ts`) | typecheck pass, 236/236 test, build pass |
| 2 | `ce8eade` | Nối dây vào app (`src/lib/live-activities.ts` và các call site) | typecheck pass, 246/246, build pass |
| 2b | `bbf3de2` | Sửa sau review, thêm test | typecheck pass, 264/264, build pass |
| 3 | `4e6cceb` | Chạm thẻ → mở contract, lưu `LIVE_ACTIVITY_STATE_CHANGED` | typecheck pass, 271/271 (26 file), build pass |

Ba file test Live Activities chạy lặp 5 lần đều pass. Cấu hình typecheck của dự án không gồm `tests/`; khi typecheck cả `tests/` chỉ còn một lỗi có từ trước ở `tests/native-auth.test.ts:43`.

**Hành vi đã triển khai:**

- **Capability gate:** chỉ chạy khi native báo `capabilities.liveActivities.supported === true` trên iOS. Browser preview, Android và shell cũ nhận đúng các message như trước (có test so sánh).
- **Hàng đợi mutation:** gửi từng lệnh một theo thứ tự người dùng thao tác. Timeout thì gửi lại cùng `requestId` và sequence; đổi session thì sequence về 1. Chờ `AUTH_SESSION_ACCEPTED` trên trang và không gửi khi `SET_AUTH_SESSION` đang chờ reply. Không gửi lệnh của tài khoản khác. `stale_bridge_session` và `auth_session_required` chỉ thử lại một lần.
- **Theo dõi:** `TRACK_CONTRACT` chỉ khi người dùng chạm mở contract trên Home. `SYNC_TRACKED_CONTRACTS` sau khi đã tải xong contract từ server; danh sách gồm occurrence native đang theo dõi hôm nay còn active, cộng các contract đã mở trong phiên. Khi có capability, `SET_GOALS` gửi goal của mọi contract active, và TRACK/SYNC/START chờ `GOALS_ACCEPTED`.
- **Timer:** `START_TIMER`/`CANCEL_TIMER` có `trackingContext` và lý do `paused`/`cancelled`. Khi trang chưa bind hoặc gặp lỗi envelope thì gửi lệnh thường, nên timer luôn chạy.
- **Kết thúc:** `ACTIVITY_COMPLETED` với `scope: "contract"` cho timer, tự báo, goal Health, và standing qua ngày mà đã đạt (health day của chu kỳ vừa đóng). `STOP_TRACKING_CONTRACT` với `contract_broken` (tự báo Broken, "Break it", standing qua ngày mà không đạt), `contract_expired` và `contract_deleted` (Settings → "Erase everything", chờ tối đa khoảng 2 s).
- **Lỗi:** `goal_definition_mismatch` và `health_day_mismatch` thử lại một lần; `occurrence_expired` bỏ qua.
- **Chạm thẻ:** `LIVE_ACTIVITY_OPENED` được buffer tới khi đăng nhập và contract tải xong, xử lý một lần, bỏ trùng theo `eventId`. Contract còn active thì mở màn chi tiết, không thì về Home. Đường này không đổi dữ liệu và không gửi message nào. `NOTIFICATION_OPENED` giữ nguyên.

**Làm khác yêu cầu, theo source thực tế:**

- `auth_session_required`: chờ `AUTH_SESSION_ACCEPTED` kế tiếp rồi mới gửi lại một lần, vì gửi ngay thì trang vẫn chưa bind.
- `NOTIFICATION_OPENED` hiện chỉ về tab Home; để chạm thẻ mở đúng contract, state màn chi tiết được đưa lên `routes/index.tsx`.
- Module queue được import trong `use-auth.ts` thay vì `native-auth.ts`, vì đặt ở `native-auth.ts` làm hỏng test có sẵn.
- `displayUnit` km/mi lấy từ đơn vị trong `primaryTarget`, vì goal Health không lưu đơn vị hiển thị.

**Cần khách hoặc sản phẩm quyết:**

- Contract bị khóa (`locked`): chạm thẻ mở thẳng màn chi tiết, không qua màn Restriction. Hiện áp dụng cùng quy tắc với `contractOpen`; muốn giữ màn Restriction thì cần một yêu cầu sửa nhỏ.
- Cho phép nhiều contract active, điều kiện để có nhiều thẻ cùng lúc.

**Rủi ro đã biết:** `ACTIVITY_COMPLETED` phải chờ trang bind mới gửi; nếu trang không bao giờ nhận được `AUTH_SESSION_ACCEPTED` thì lệnh nằm chờ, không có đường dự phòng. Contract có timer vẫn được native tự đóng thẻ khi timer kết thúc.

**Chưa kiểm:** E2E với build native (trỏ `HONOURED_WEB_APP_URL` sang `https://id-preview--eec79567-2e9c-4821-aef7-11204b546ea7.lovable.app`, chạy `./scripts/sync-env.sh`, build lại), các ca web ở 12.2 trên app thật, và điều hướng trong `index.tsx`/`Home.tsx` (dự án không có thư viện test DOM nên phần này mới review bằng mắt).
