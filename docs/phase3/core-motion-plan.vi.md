# Phase 3: xác nhận mục tiêu nhanh bằng Core Motion (iOS)

Lập ngày 16/10/2026, cập nhật 18/10/2026 theo góp ý của khách về M1 và M2.
Trạng thái (19/10/2026): đã code probe của M1 (`ios/Honoured/MotionProbe/`,
hướng dẫn test `docs/phase3/m1-probe-guide.md`, nháp DTS
`docs/phase3/dts-draft.md`). Ngày 19/10 đã chạy 4 bài ngắn (100–180 bước) trên
iPhone 15 Pro Max, iOS 26.5.2, bản Release cài từ Xcode: app mở, khóa máy khi
Honoured đang mở, chỉ đeo Watch, vuốt tắt app. Chưa test khóa máy khi Honoured
ở nền, chưa test qua đêm, chưa lên TestFlight. Report M1 tiếng Việt chưa có số
đo ngày 19/10; bản tiếng Anh đang làm dở.
Cập nhật 21/10/2026: khách giữ M2 như đã chốt (57 giờ). Đã code phần native,
SQL và web của M2; trạng thái chi tiết ở mục 4, "Trạng thái M2".

Đầu vào:

- Tin nhắn của khách và hai file brief đính kèm (ý tưởng Core Motion, và PDF
  "faster activity" trước đó). Hai PDF chưa có trong repo; nên lưu vào
  `docs/phase3/clarify/` rồi đối chiếu lại tài liệu này.
- Đề xuất 4 milestone, 90 giờ, đã gửi khách.
- 16/10/2026: khách thêm Diagnostic Instrumentation vào M2; đã báo lại 45 giờ
  (trước là 35) và khách đã duyệt. Diagnostics phải phân biệt mốc thời gian
  thực sự ghi nhận được với mốc ước tính.
- 18/10/2026: khách viết lại mô tả M1 và M2 (M1 15 giờ; M2 57 giờ = 35 tích hợp
  + 10 diagnostics + 12 cho toggle chọn nguồn). Jimmy đã chốt các điểm ở mục 5
  và đề xuất toggle 15 giờ thay vì 12 (M2 60 giờ).
- 20/10/2026: khách muốn giữ M2 như đã chốt: 57 giờ, toggle 12 giờ. Đề xuất
  15 giờ bỏ.
- Jimmy sẽ tự viết cho Apple Developer Technical Support (DTS), kèm Swift code
  và thông tin chẩn đoán.

## 1. Khách muốn gì

- Dùng Core Motion thay cho hướng "faster activity" cho **bước chân và quãng
  đường**, kèm calo đi bộ/chạy bộ ước tính.
- Vấn đề: người dùng đạt mục tiêu lúc 17:00 nhưng tới 17:30–18:00 mới được
  đóng dấu HONOURED, nên họ cứ đi/chạy tiếp. "People's time is sacred."
- Lý tưởng: khi iPhone xác nhận đã đạt, Honoured báo ngay bằng âm thanh,
  rung hoặc notification, kể cả khi màn hình khóa.
- Mở Honoured thì phải cập nhật Core Motion ngay, nhưng việc ghi nhận mục tiêu
  không được phụ thuộc vào việc mở app. Mở lại app thì tổng của các ngày trước
  phải được đối soát lại.
- Calendar phải hiện tổng cả ngày, không đứng yên ở con số lúc contract được
  đóng dấu HONOURED.
- Người dùng chọn nguồn theo dõi: Core Motion (iPhone) hoặc Apple Health
  (HealthKit). Chỉ nguồn đã chọn quyết định tiến độ và việc hoàn thành; không
  cộng hai nguồn; đổi nguồn không xoá thành tích đã có và không tạo sự kiện hoàn
  thành lặp; lịch sử dùng nguồn đã chọn; nhớ lựa chọn của người dùng.
- Câu hỏi của khách: một thành phần Core Motion nhẹ, độc lập với UI, cùng một
  cơ chế chạy nền được Apple cho phép, có nhận ra mục tiêu bước chân và báo
  người dùng **trong vòng 5 phút khi iPhone đang khóa** được không?

## 2. Hiện trạng trong code

| Phần | Chỗ | Đang làm gì |
|---|---|---|
| Phát hiện đạt goal | `Health/GoalMonitor.swift` | So tổng hôm nay với goal từ `SET_GOALS`; app không active thì đặt local notification; phát `GOAL_REACHED` (lưu bền); mỗi activity chỉ báo một lần mỗi health day (marker trong `UserDefaults`). `notified: true` nghĩa là đã **đặt lịch** notification thành công, chưa phải đã giao; Timer thì đã kiểm tra giao thật qua `NotificationCoordinator.wasDelivered`. |
| Tổng số liệu | `Health/HealthKitService.swift` (`readTotal`) | `HKStatisticsQuery` khử trùng nguồn. Với `steps` và `distance_walking_running`, áp dụng nguồn đã chọn. Từ bản sửa ngày 16/10 (chưa lên TestFlight), `automatic` dùng tổng gộp như app Health; chỉ lọc khi người dùng chọn một thiết bị. Khi cách đọc đổi, `health_daily` của hai metric này được tính lại một lần (tối đa 90 ngày). |
| Chọn nguồn (V1.2) | Web: Settings › Health; native: `GET_HEALTH_SOURCES`, `SET_HEALTH_SOURCE_PREFERENCE` | Ô chọn "Let Honoured decide" hoặc một nguồn HealthKit cụ thể, lưu theo tài khoản (localStorage của web và `UserDefaults` của native). Toggle Core Motion sẽ gộp vào ô này (mục 4, M2-C). |
| Đánh thức nền | `Health/HealthBackgroundObserver.swift`, `HealthBackgroundRefresh.swift` | `HKObserverQuery` + `enableBackgroundDelivery(.immediate)` cho mọi metric; `BGAppRefreshTask` sớm nhất 60 phút. `UIBackgroundModes` chỉ có `fetch`. |
| Icon (The Oath) | `Health/IconVerifier.swift`, `docs/db/icon_scoring_v1.sql`, `docs/db/icon_scoring_v2.sql` | Đọc HealthKit rồi gọi `record_icon_measurements`; server đóng HONOURED ngay khi `value >= target`. v2 (khách duyệt, deploy ngày 21/10): ngày đã chấm tiếp tục được đo 30 ngày, số chỉ tăng, BROKEN lên HONOURED khi tổng đến muộn đạt target. v3 (deploy ngày 21/10) lưu nguồn của số đo. |
| Live Activity | `LiveActivities/` | Thẻ cập nhật từ cùng tổng HealthKit; khi máy khóa và dữ liệu Health bị mã hoá thì giữ số cũ (`docs/phase1/bridge.md`, mục Timing and limits). |
| Push | `docs/phase2/icon-push.md` | pg_cron `icon-push` chạy mỗi phút, gửi APNs qua pg_net; lần gửi ghi trong `icon_push_sends`; app đã đăng ký device token. |
| Core Motion | `Health/MotionService.swift`, `MotionModels.swift`, `MotionLiveUpdates.swift` | Có từ M2 (21/10): nguồn bước chân và quãng đường chọn được; xem "Trạng thái M2". `NSMotionUsageDescription` đã có. |

Android không nằm trong phase này.

## 3. Đánh giá

### 3.1 Vì sao trễ 30–60 phút (giả thuyết, M1 phải đo để xác nhận)

1. **HealthKit không đánh thức app ngay cho bước chân.** `frequency` chỉ là
   mức tối đa; theo tài liệu và diễn đàn Apple, một số loại như step count chỉ
   được giao khoảng một lần mỗi giờ dù xin `.immediate`. Điều này khớp với độ
   trễ khách thấy.
2. **Máy khóa thì không đọc được HealthKit.** Kho Health bị mã hoá khi khóa;
   lần đọc trả `protectedDataUnavailable`, app phải chờ người dùng mở khóa.
3. **Dữ liệu từ Apple Watch hoặc app đồng hồ khác (Garmin Connect) tới iPhone
   có độ trễ**, và tổng gộp chờ dữ liệu đó.
4. **Icon chỉ được chấm sau lần upload health hoặc khi mở app.**

Core Motion có thể giải quyết (2) nếu `CMPedometer` đọc được khi khóa, và (3)
vì nó là cảm biến của chính iPhone. Nó **không** giải quyết (1): Core Motion
không có cơ chế nào đánh thức app khi số bước vượt ngưỡng. Mục tiêu 5 phút khi
khóa máy vì thế phụ thuộc hoàn toàn vào kết quả M3.

### 3.2 Quy tắc đã chốt (18/10/2026)

- **Chỉ nguồn đã chọn được tính.** Không có chế độ lai "nhanh nhất trong hai
  nguồn": chọn Apple Health thì độ trễ vẫn như HealthKit hiện tại; muốn nhanh thì
  chọn Core Motion. Không bao giờ cộng Core Motion với HealthKit.
- **Khi chọn Core Motion, Core Motion quyết định cả HONOURED lẫn BROKEN.**
  Bước đi khi không mang iPhone sẽ không được tính; câu chữ trong UI phải nói
  rõ điều này (chờ duyệt câu chữ).
- **Gộp vào ô chọn nguồn hiện có**, áp dụng cho bước chân và quãng đường như ô
  hiện tại. Mặc định giữ "Let Honoured decide" (tổng gộp Apple Health), nên người
  dùng hiện tại không bị đổi hành vi.
- **Lịch sử theo nguồn đã chọn, giới hạn 7 ngày với Core Motion.** Core Motion
  chỉ giữ khoảng 7 ngày lịch sử; ngày cũ hơn giữ số của nguồn trước. Jimmy đã
  chấp nhận; cần báo khách giới hạn này.
- **Calo:** chỉ là ước tính từ bước chân, quãng đường và thời gian (Core Motion
  không có API calo), ghi rõ là ước tính. Contract calo vẫn dùng Active Energy
  của Apple Health; số ước tính không dùng để đóng dấu.
- **Phần web và DB.** Kết nối với contract, deadline và giao diện kéo theo thay
  đổi ở web app Lovable và DB (Lovable Cloud), không nằm trong repo này. Sửa SQL
  trong `docs/db/` chưa phải là đã deploy.
- **Quyền Motion & Fitness** là một quyền riêng, có thể bị từ chối; web cần
  biết trạng thái này.

## 4. Milestone

| # | Milestone | Giờ |
|---:|---|---:|
| 1 | Kiểm chứng Core Motion + report | 15 |
| 2 | Tích hợp Core Motion, Diagnostics và chọn nguồn theo dõi | 57 |
| 3 | Nghiên cứu Core Motion khi chạy nền | 22 |
| 4 | Hoàn thiện production + bàn giao (có điều kiện) | 18 |
|  | **Tổng** | **112** |

### M1 — Kiểm chứng Core Motion + report (15 giờ)

Phạm vi theo mô tả của khách ngày 18/10: test `CMPedometer` thụ động; test hành
vi nền khi iPhone khóa; đánh giá tần suất làm mới Live Activity và Dynamic
Island; đo độ trễ nhận ra mục tiêu; tìm hiểu giới hạn chạy nền của iOS; đánh giá
mức hao pin; ghi kết quả và đề xuất cách triển khai. Giữ thêm từ đề xuất đã gửi:
so sánh với HealthKit, ước tính calo, câu hỏi cho Apple DTS.

Việc cụ thể:

1. **Probe** ghi log có thời gian cho `CMPedometer` (bước, quãng đường) và
   HealthKit (nguồn đã chọn và tổng gộp) ở mỗi lần app được chạy: mở app,
   HealthKit background delivery, `BGAppRefreshTask`, protected data available.
   Khác bản trước: probe phải có trong bản TestFlight để khách tự chạy, nên
   không đặt trong `ios/Honoured/Debug/` (chỉ biên dịch ở Debug). Đặt sau một
   công tắc ẩn, mặc định tắt, chỉ mở được ở bản Debug, bản Release cài từ Xcode
   hoặc Ad Hoc, và bản TestFlight (bản App Store bỏ qua); log nằm trên máy,
   người dùng tự xuất (share sheet) khi gửi cho Jimmy. Không chứa token hay email.
2. **Dựng lại mốc thời gian** sau khi test: truy vấn lại `CMPedometer` theo từng
   khoảng nhỏ (Core Motion giữ khoảng 7 ngày lịch sử) và `endDate` của sample
   HealthKit để biết **phút nào iPhone thực sự vượt ngưỡng**, rồi so với lúc app
   biết và lúc notification hiện.
3. **Ma trận test** (mỗi kịch bản đi bộ tới một ngưỡng thấp, ví dụ 1.000 bước).
   Ở T1–T5 ghi thêm lúc Live Activity và Dynamic Island đổi số.

   | # | Tình huống | Ghi nhận |
   |---|---|---|
   | T1 | Honoured đang mở | Core Motion cập nhật live; lệch so với HealthKit |
   | T2 | Vừa về Home, máy chưa khóa | App còn chạy bao lâu, có đọc được không |
   | T3 | Khóa máy, iPhone trong túi | Có lần đánh thức nào không; Core Motion và HealthKit có đọc được khi khóa không |
   | T4 | Khóa máy lâu (suspended) | Như T3 |
   | T5 | Force-quit rồi đi bộ | App có được đánh thức lại không |
   | T6 | Reboot, chưa mở khóa lần đầu | Đọc được gì |
   | T7 | Đeo Watch, iPhone để trên bàn | Core Motion đứng yên trong khi Watch tăng |
   | T8 | Đeo Watch và mang iPhone | Độ lệch Watch và iPhone |
   | T9 | Low Power Mode | Ảnh hưởng tới đánh thức nền |

   Câu hỏi quan trọng nhất: trong một lần đánh thức nền khi máy đang khóa, có
   gọi được `queryPedometerData` không.
4. **Live Activity và Dynamic Island:** đo khoảng cách giữa lúc số bước đổi và
   lúc thẻ đổi số, khi app mở và khi máy khóa; ghi rõ thẻ chỉ đổi khi iOS cho app
   chạy hoặc khi có push.
5. **Pin:** so mức pin tụt trong vài giờ có và không có probe, kèm báo cáo năng
   lượng của iOS nếu có. Trong 15 giờ chỉ là số tham khảo (lần chạy ngắn); đo đầy
   đủ ở M3.
6. **Calo:** xem có ước tính được từ bước, quãng đường và thời gian không; so với
   Active Energy của Health; ghi rõ đây là ước tính.
7. Soạn câu hỏi DTS (mục 6) và gói chẩn đoán (log, đoạn Swift tối giản) để
   Jimmy gửi.

Bàn giao: bản TestFlight có probe để khách tự chạy, cùng report tiếng Anh kèm
số liệu, log và video quay màn hình. Bằng chứng lưu ở `docs/phase3/evidence/`.

Điều kiện qua M2: khách đã chốt M2 57 giờ (20/10/2026).

### M2 — Tích hợp Core Motion, Diagnostics và chọn nguồn theo dõi (57 giờ)

Gồm 35 giờ tích hợp (A), 10 giờ diagnostics (B) và 12 giờ cho chọn nguồn (C),
như khách chốt ngày 20/10/2026.

#### A. Tích hợp Core Motion (35 giờ)

1. **Module.** `ios/Honoured/Health/` (ví dụ `MotionService.swift`): bọc
   `CMPedometer` cho bước chân và quãng đường, truy vấn từ đầu health day (theo
   `SET_DAY_RESET_HOUR`) tới hiện tại, theo dõi live khi app active, trả "không
   khả dụng" tách biệt với 0 (giống `HealthTotalRead`). Calo ước tính tính từ cùng
   số liệu.
2. **Quyền.** Thêm `NSMotionUsageDescription` vào `ios/Honoured/Info.plist`;
   đọc `CMPedometer.authorizationStatus()` (khác HealthKit, trạng thái từ chối
   đọc được).
3. **Nối vào mọi chỗ đang đọc số:** `GoalMonitor`, Live Activity, `IconVerifier`,
   `HEALTH_METRICS` và notification hoàn thành đọc qua một điểm chung, trả số của
   nguồn đã chọn (C). Giữ nguyên marker một lần mỗi activity mỗi ngày, nên không
   có notification lặp.
4. **Khi mở app.** Cập nhật Core Motion ngay khi app active và khi WebView sẵn
   sàng; cập nhật Live Activity và kiểm tra goal từ cùng số đó.
5. **Đối soát lịch sử khi mở lại app.** Với nguồn Core Motion, đọc lại
   `CMPedometer` cho các ngày bị lỡ, tối đa 7 ngày, rồi cập nhật tổng ngày và số
   của các ngày Icon. Với HealthKit, việc này đã có (anchored sync và
   `icon_scoring_v2.sql`).
6. **Calendar hiện tổng cả ngày.** Với HealthKit đã làm trong bản sửa ngày
   16/10 (`icon_scoring_v2.sql` và native), nằm ngoài giờ của M2. M2 chỉ áp dụng
   cùng cách cho ngày dùng nguồn Core Motion (trong giới hạn 7 ngày).
7. **Bridge** (bổ sung, giữ tương thích v1; chốt chi tiết khi làm và cập nhật
   `docs/phase1/bridge.md`):
   - `GOAL_REACHED` thêm `source: "healthkit" | "core_motion"`.
   - Trạng thái quyền Motion trong `HEALTH_PERMISSION_STATUS`, và cách xin quyền
     (message mới hoặc gộp vào `REQUEST_HEALTH_PERMISSION`).
   - Số Core Motion trong `HEALTH_METRICS` cho bước chân, quãng đường và calo
     ước tính, với `source` để web ghi rõ nguồn của con số.
8. **Icon / deadline.** `IconVerifier` gửi kèm nguồn số đo. SQL mới
   `docs/db/icon_scoring_v3.sql` (v2 đã dùng cho bản sửa calendar): lưu nguồn
   của số đo; trong cùng một nguồn số chỉ tăng; quy tắc khi đổi nguồn ở C.
   Deploy lên Lovable Cloud là một bước riêng.
9. **Web (Lovable).** Xử lý `source` trong `GOAL_REACHED`, hiển thị nguồn và nhãn
   "ước tính" cho calo, xử lý khi chưa cấp hoặc bị từ chối quyền Motion.

#### B. Diagnostic Instrumentation (10 giờ)

Có trong bản production (TestFlight). Yêu cầu của khách: tách rõ mốc **ghi nhận
thật** với mốc **ước tính**; chỗ iOS không cho biết đúng thời điểm thì không
được ghi ước tính như sự thật. Mục đích: Jimmy thấy độ trễ nằm ở đâu và đo được
mức cải thiện.

Mỗi mốc mang một nhãn:

- `recorded`: app hoặc iOS ghi được đúng lúc việc đó xảy ra.
- `estimated`: suy ra sau, luôn kèm khoảng `[windowStart, windowEnd]` và cách
  suy ra (`method`). Không bao giờ ghi một mốc ước tính thành `recorded`.
- `unknown`: không có bằng chứng. Để trống, không lấy mốc khác điền vào.

| Mốc | Nhãn | Lấy từ đâu |
|---|---|---|
| Vượt mục tiêu (`goal_crossed`) | Luôn `estimated` | Không API nào cho biết đúng lúc bước thứ N xảy ra. Khoảng = lần đọc cuối còn dưới ngưỡng tới lần đọc đầu đã đạt. `method`: `motion_live` (giữa hai cập nhật live khi app đang chạy, khoảng hẹp), `motion_query` (truy vấn lại `CMPedometer` theo khoảng nhỏ; độ phân giải đo ở M1), `healthkit_sample` (start/end của sample). |
| Dữ liệu có mặt (`data_available`) | `estimated` hoặc `unknown` | iOS không cho biết lúc sample HealthKit vào kho hay lúc Core Motion có số mới. Chỉ ghi khoảng giữa lần đọc trước (chưa có) và lần đọc sau (đã có). |
| Vòng đời app (`app_lifecycle`) | `recorded` | Launch, vào foreground, vào background, background task sắp hết giờ, protected data sắp khóa hoặc đã mở. Lúc app bị suspend hoặc bị kill thì iOS không báo, nên không ghi như sự thật. |
| App được chạy (`app_ran`) | `recorded` | Lúc handler bắt đầu, kèm lý do (HealthKit delivery, BG refresh, push, mở app, protected data available), máy có đang khóa không (`isProtectedDataAvailable`), Low Power Mode. |
| Lần đọc số (`reading`) | `recorded` | Lúc đọc, nguồn (Core Motion hoặc HealthKit), giá trị hoặc kết quả: có số, không có dữ liệu, bị khóa, lỗi, bị từ chối quyền. |
| App xác nhận đạt (`goal_detected`) | `recorded` | Lúc app thấy số ≥ mục tiêu, kèm nguồn. |
| Đặt notification (`notification_requested`) | `recorded` | Lúc `UNUserNotificationCenter.add` thành công; hoặc lý do không gửi (app đang mở, chưa có quyền, lỗi). |
| Notification được giao (`notification_delivered`) | `recorded` chỉ khi iOS xác nhận, còn lại `unknown` | `UNNotification.date` của notification còn trong Notification Center, đọc ở lần app chạy sau; hoặc `willPresent` khi app đang mở. Người dùng đã xoá, Focus chặn hoặc tắt quyền thì là `unknown`. Không lấy giờ đặt lịch thay cho giờ giao. Đối chiếu `UNNotification.date` với quay màn hình trên máy thật. |
| Gửi cập nhật Live Activity (`live_activity_update`) | `recorded` | Lúc app gọi cập nhật ActivityKit, kèm số và nguồn; với push của server thì lúc gửi APNs trong `icon_push_sends`. Lúc thẻ thực sự đổi trên màn hình khóa thì iOS không báo, ghi `unknown`. |
| Người dùng mở notification (`notification_opened`) | `recorded` | Lúc chạm (`didReceive`). |
| Icon được đóng dấu (`icon_stamped`) | `recorded` (đồng hồ server) | `scored_at` trong `icon_days`. |

Không đo được và không ghi: người dùng có thực sự nhìn thấy notification hay
không.

Quy tắc khi báo cáo độ trễ:

- Độ trễ giữa hai mốc `recorded` là số đo thật, ví dụ từ `goal_detected` tới
  `notification_delivered`.
- Độ trễ có dính mốc `estimated` thì ghi thành khoảng, ví dụ "giao sau khi vượt
  mục tiêu 3–7 phút", kèm `method`.
- Mỗi dòng có giờ thiết bị và giờ server nhận, để phát hiện đồng hồ máy bị lệch.

Lưu trữ:

- Sự kiện ghi vào bộ đệm trên máy, rồi đẩy lên một bảng Supabase riêng, dùng
  lại cách làm của hàng đợi offline. SQL mới trong `docs/db/` có RLS: người
  dùng chỉ ghi và đọc dòng của chính mình. Deploy lên Lovable Cloud là một bước
  riêng.
- Không có token, email hay nội dung nào ngoài số đo và mốc thời gian. Xoá bộ
  đệm trên máy khi đăng xuất hoặc đổi tài khoản.
- Thời gian lưu giữ trên server: chốt khi làm.
- Một truy vấn SQL dựng dòng thời gian cho từng goal mỗi ngày, dùng cho report
  và cho M3.

#### C. Chọn nguồn theo dõi: HealthKit hoặc Core Motion (12 giờ)

Gộp vào ô chọn nguồn hiện có trong Settings › Health, không thêm màn mới:

1. **Lựa chọn:** "Let Honoured decide" (tổng gộp Apple Health, mặc định), từng
   nguồn HealthKit như hiện tại, và thêm một mục Core Motion của iPhone. Áp dụng
   cho bước chân và quãng đường. Tên mục và câu giải thích là chữ hiển thị cho
   người dùng, chờ duyệt.
2. **Chỉ nguồn đã chọn quyết định** tiến độ contract, goal, Icon, Live Activity
   và notification. Không cộng hai nguồn. Core Motion được chọn thì quyết định cả
   BROKEN.
3. **Giữ thành tích:** marker của `GoalMonitor` theo activity và ngày, không theo
   nguồn, nên đổi nguồn không phát lại `GOAL_REACHED` hay notification. Server
   không bao giờ hạ một ngày HONOURED.
4. **Lịch sử theo nguồn đã chọn:** đổi nguồn thì đo lại các ngày Icon còn trong
   cửa sổ đo (Core Motion tối đa 7 ngày, HealthKit 30 ngày). Khi nguồn đổi,
   `measured_value` được thay bằng số của nguồn mới, kể cả khi thấp hơn; trạng
   thái HONOURED giữ nguyên, kể cả khi số mới thấp hơn mục tiêu. Ngày BROKEN lên
   HONOURED nếu số của nguồn mới đạt mục tiêu (`icon_scoring_v3.sql`; cả hai
   điểm đã xác nhận ngày 21/10/2026).
5. **`health_daily`:** với bước chân và quãng đường, theo nguồn đã chọn, như ô
   chọn nguồn hiện tại. Đổi nguồn thì tính lại bằng cơ chế "daily basis" đã có
   (Core Motion chỉ được 7 ngày, ngày cũ hơn giữ số cũ). `health_samples` vẫn
   chỉ chứa sample HealthKit. Đây là đề xuất kỹ thuật, không cần khách chốt.
6. **Quyền và dữ liệu không có:** chọn Core Motion mà quyền Motion bị từ chối hoặc
   không có cảm biến thì dùng tổng gộp Apple Health và báo `fallback: true`, như
   khi nguồn đã chọn biến mất; web hiện thông báo. HealthKit bị từ chối hoặc không
   có dữ liệu thì xử lý như hiện tại ("không có dữ liệu", không thành 0).
7. **Nhớ lựa chọn:** dùng cách lưu hiện có (theo tài khoản ở web và native).

#### Kiểm tra M2

Build simulator; `HonouredTests`; test trên iPhone thật các kịch bản T1, T2, T7,
T8, đổi tài khoản, đổi giờ reset; đổi nguồn qua lại khi chưa đạt và khi đã đạt
(không mất HONOURED, không có notification lặp); tổng ngày và calendar sau khi
đổi nguồn; quyền Motion bị từ chối; một lần đi bộ khi khóa máy để đối chiếu dòng
thời gian diagnostics với quay màn hình. Checklist từng bài (đi ngắn 100–150
bước) và câu SQL xem diagnostics: `docs/phase3/m2-device-tests.vi.md`.

#### Trạng thái M2 (21/10/2026)

Native đã commit trên `main` ngày 21/10 (chưa push), chưa lên TestFlight:
`ee1ea2f`, `4e2b157`, `2cca603`, `7570f7c`, `6f534f4`. Sau đó thêm `2297c14`
(docs) và `a251fc9` (số live trên Home, `HEALTH_LIVE_TOTALS`). Ngày 22/10 thêm
`acb8919` (tên nguồn "Core Motion") và `b3c96c9` (sửa lỗi ngoài M2: thẻ Icon
không hiện lại sau khi cập nhật app).

- **Native:** đọc Core Motion (`Health/MotionService.swift`,
  `MotionModels.swift`), đếm live khi app mở (`MotionLiveUpdates.swift`), rẽ
  nguồn tại `HealthKitService.readTotal`, `GoalMonitor` chạy từng lượt một,
  diagnostics ở `ios/Honoured/Diagnostics/`.
- **Bridge** (ghi trong `docs/phase1/bridge.md`):
  - Core Motion là một mục trong `HEALTH_SOURCES.sources` (id `core_motion`,
    `kind: "core_motion"`). Preference vẫn là `{ mode: "source" }`, nên bản web
    cũ không bị hỏng.
  - Message mới `REQUEST_MOTION_PERMISSION` → `MOTION_PERMISSION_STATUS`.
  - Thêm `motion` trong `HEALTH_PERMISSION_STATUS` và `HEALTH_SOURCES`,
    `GOAL_REACHED.source`, và `HEALTH_METRICS.estimates.walking_running_energy`.
  - Broadcast mới `HEALTH_LIVE_TOTALS`: khi app đang mở và đang đọc Core
    Motion, native gửi tổng hôm nay mỗi lần pedometer báo. Khi lưu một nguồn
    khác, bản cuối tới trước `HEALTH_SOURCE_PREFERENCE_ACCEPTED`. Trang chưa sẵn
    sàng chỉ nhận bản mới nhất.
- **SQL:**
  - Ngày 21/10 đã deploy lên Lovable Cloud `icon_scoring_v2.sql` rồi
    `icon_scoring_v3.sql`, sau khi khách duyệt. Trước khi deploy, md5 hàm v1
    trên production khớp với file rollback của v2. Sau khi deploy, md5 các hàm
    khớp với v2 + v3 chạy ở Postgres cục bộ, tức trạng thái đã qua test.
  - Cũng ngày 21/10, áp dụng `goal_diagnostics_v1.sql`. Smoke test chạy trong
    transaction đã rollback; bảng đang rỗng.
- **Web (Lovable, commit `e798753`, rồi `a5ceb356`):** parse các trường mới,
  xin quyền Motion trước khi lưu lựa chọn, thông báo khi tắt quyền, dòng calo
  ước tính trên Home. Theo agent Lovable, 680 test web đều qua.
  - Câu giải thích "Let Honoured decide" mới chỉ hiện khi native gửi `motion`
    (bản native mới). Bản App Store hiện tại vẫn thấy câu cũ, đúng với cách nó
    đang chạy, nên publish lúc nào cũng an toàn.
  - Commit này kèm hai cập nhật nền tảng do Lovable tự thêm:
    `@lovable.dev/vite-tanstack-config` 2.26.5 và `previewAuthStorage.ts`.
  - Commit `56cca058`, `bea928ee`, `ea9ca060`, sau khi Jimmy test thấy Home và
    contract cập nhật chậm với Core Motion, và Home không hiện nguồn:
    - Home và thẻ contract hiện số live. Số live chỉ để hiển thị, giữ tối đa 2
      phút, và bị xoá khi lưu nguồn mới hoặc đổi tài khoản.
    - Web nhận `source.mode: "aggregate"` của native. Trước đó web bỏ qua giá
      trị này, nên Home không hiện nguồn.
    - Dòng "Steps & distance · <nguồn>" nằm ngay dưới "Health · Updated…".
    - Theo agent Lovable, 698 test web qua, type check sạch.
  - Commit `c4a0510d` (22/10, theo yêu cầu của khách): đổi nhãn "Let Honoured
    decide" thành "Automatic", và "iPhone motion sensor" thành "Core Motion".
    Tên "Core Motion" do native gửi, nên đổi trong `HealthSourcePreference.swift`
    và chỉ hiện từ build native kế tiếp.
  - Commit `e79a9650` (22/10, sửa lỗi ngoài M2): ký xong một contract là gửi
    `TRACK_CONTRACT` ngay, nên Live Activity hiện mà không cần mở thẻ contract.
    Lỗi có từ đợt làm lại Home ngày 21/9.
  - Chưa publish.

Quyết định kỹ thuật khi làm:

- **Giới hạn 7 ngày:** Core Motion không đọc khoảng bắt đầu sớm hơn 7 ngày trừ
  6 giờ.
- **Không có lịch sử:** số 0 khi pedometer chưa đếm bước nào trong lịch sử của
  nó thì tính là không có dữ liệu (máy mới hoặc vừa restore), không phải 0.
- **Đọc lại mỗi lượt sync:** với nguồn Core Motion, mỗi lượt sync đọc lại các
  ngày Core Motion còn giữ, vì Core Motion không có anchor như HealthKit.
- **Khi mở app:** chọn Core Motion thì mở app là kiểm tra goal và sync ngay.
  Khi app đang mở mà người dùng đang đi: kiểm tra tối đa mỗi 3 giây, sync tối đa
  mỗi phút, vì thẻ contract trên Home đọc `health_daily`. Giữa hai lượt sync,
  Home và thẻ contract lấy số từ `HEALTH_LIVE_TOTALS`.
- **Diagnostics:**
  - Chỉ ghi ở bản Debug, Ad Hoc và TestFlight; bản App Store không ghi.
  - Upload 50 dòng một lần; khi lỗi thì chờ lâu dần, riêng 404 chờ 24 giờ.
  - Xoá khi đăng xuất hoặc đổi tài khoản.
- **Calo ước tính:** giả định 70 kg.

Đã kiểm tra (lần cuối ngày 21/10, sau phần số live):

- 263 unit test.
- Build Debug và Release cho simulator.
- Test SQL của v3 và diagnostics, chạy trên Postgres 17 cục bộ.
- Kịch bản `core-motion` 17/17 trên simulator. Simulator không có pedometer nên
  chỉ kiểm được nhánh fallback, chưa thấy `HEALTH_LIVE_TOTALS` thật.
- Chưa test trên iPhone thật.

Còn lại:

- Test trên iPhone thật (`docs/phase3/m2-device-tests.vi.md`).
- Publish web.
- Build TestFlight.
- Chốt thời gian giữ diagnostics (đề xuất 90 ngày).

### M3 — Nghiên cứu Core Motion khi chạy nền (22 giờ)

Phạm vi đã gửi khách: thử các cơ chế Apple cho phép để tự xác nhận mục tiêu,
gửi notification và cập nhật Live Activity khi màn hình khóa; đo độ trễ, pin và
độ tin cậy; bàn giao report khả thi. Mốc 5 phút là mục tiêu nghiên cứu, không
phải cam kết.

Các ứng viên cần thử:

| Cơ chế | Ghi chú |
|---|---|
| HealthKit background delivery (đang có) + đọc Core Motion trong cùng lần đánh thức | Không tốn thêm quyền. Vẫn bị giới hạn tần suất của HealthKit. |
| Silent push (`content-available`) từ server trong khung giờ có goal bước chân hoặc quãng đường chưa đạt | Dùng lại pg_cron và APNs của Icon push. Cần thêm `remote-notification` vào `UIBackgroundModes`. APNs có thể bóp tần suất; không đánh thức app đã bị force-quit. |
| `BGAppRefreshTask` (đang có) | iOS tự quyết thời điểm; khó đạt 5 phút. |
| `HKWorkoutSession` trên iPhone (iOS 26+) | App chạy suốt phiên nhưng người dùng phải bấm bắt đầu, nên không còn thụ động. Cần xác minh hành vi chạy nền trên iPhone. |
| Significant location change | Đánh thức khi di chuyển, nhưng cần quyền vị trí "Always" và lý do hợp lệ với App Review (2.5.4). Rủi ro bị từ chối cao; chỉ thử nếu khách chấp nhận. |

Không dùng: phát audio im lặng hoặc định vị liên tục chỉ để giữ app sống. App
Review sẽ từ chối.

Đo cho từng cơ chế bằng diagnostics của M2: thời gian từ lúc iPhone vượt ngưỡng
(`estimated`, ghi thành khoảng) tới lúc notification được giao (`recorded` hoặc
`unknown`), phần trăm lần đạt trong 5 phút, mức hao pin, và hành vi khi
force-quit, reboot hoặc Low Power Mode. Lần nào thiếu mốc giao notification thì
không tính vào tỷ lệ "trong 5 phút".

Bàn giao: report khả thi cho khách với khuyến nghị cụ thể, hoặc kết luận không
có cơ chế phù hợp.

### M4 — Hoàn thiện production + bàn giao (18 giờ, có điều kiện)

Chỉ làm nếu M3 tìm được giải pháp phù hợp và khách đồng ý.

- Tích hợp cơ chế nền đã chọn.
- Xử lý gián đoạn: reboot, force-quit, thu hồi quyền Motion hoặc thông báo,
  đổi tài khoản, đổi múi giờ hoặc giờ reset.
- Chống trùng giữa notification local của GoalMonitor, push hoặc Live Activity
  của Icon, và lần báo từ HealthKit đến sau.
- Regression phần Phase 2: health sync, Icon, Live Activity, Word Tracker.
- Build bàn giao (TestFlight) và cập nhật `docs/phase1/bridge.md`, README.

## 5. Điểm đã chốt và còn mở

Jimmy đã chốt ngày 18/10/2026. Điểm 1, 2 và 3 khớp với mô tả mới của khách;
điểm 4 và 7 cần báo khách:

1. Chọn Apple Health thì không có đường nhanh từ Core Motion.
2. Chọn Core Motion thì Core Motion chấm cả BROKEN.
3. Gộp lựa chọn Core Motion vào ô chọn nguồn hiện có.
4. Lịch sử Core Motion chỉ làm mới được 7 ngày.
5. Làm cả quãng đường và calo ước tính (calo không dùng để đóng dấu, mục 3.2).
6. M1 bàn giao cả bản TestFlight có probe lẫn report kèm log và video.
7. M2 57 giờ, toggle 12 giờ, như khách chốt ngày 20/10/2026.
8. Đổi nguồn có thể biến một ngày BROKEN thành HONOURED, khi tổng của nguồn mới
   đạt mục tiêu trong cửa sổ đo (xác nhận ngày 21/10/2026).
9. Sau khi đổi nguồn, ngày HONOURED có thể hiện số thấp hơn mục tiêu; trạng thái
   vẫn giữ HONOURED (chấp nhận ngày 21/10/2026).

10. Khách đã duyệt `icon_scoring_v2.sql` và mọi câu chữ hiển thị của M2
    (21/10/2026). v2 và v3 đã deploy cùng ngày.

Còn mở:

1. **Chấp nhận cơ chế cần người dùng thao tác** (bắt đầu phiên đi bộ) hoặc
   **quyền vị trí "Always"** nếu M3 chỉ ra đó là cách duy nhất đạt gần 5 phút.
2. **Publish web** trên Lovable. Đã an toàn với bản App Store hiện tại (câu
   giải thích đi theo phiên bản native). Có thể trỏ `HONOURED_WEB_APP_URL` vào
   URL preview để test trước.
3. Thời gian lưu giữ dữ liệu diagnostics trên server (`purge_goal_diagnostics`
   có sẵn nhưng chưa được lên lịch chạy). Bản App Store hiện chưa ghi
   diagnostics.

## 6. Câu hỏi gửi Apple DTS (nháp)

Soạn bằng tiếng Anh khi gửi:

1. Is there a supported way to have an iOS app woken while the device is
   locked when the pedometer step count crosses a threshold, without an Apple
   Watch app?
2. What delivery frequency can an app expect from
   `enableBackgroundDelivery(for: stepCount, frequency: .immediate)` on iOS, and
   is there a documented cap for step count?
3. During a HealthKit background delivery, `BGAppRefreshTask` or silent push
   launch while the device is locked, can the app call
   `CMPedometer.queryPedometerData`, and is that data protected until first
   unlock or until every unlock?
4. What approach does Apple recommend for notifying a user within about five
   minutes of reaching a daily step goal while the iPhone is locked?
5. Does `HKWorkoutSession` on iPhone (iOS 26) keep the app running in the
   background, and would App Review accept it for a user-started "walk to my
   goal" session?

## 7. Kiểm thử và bằng chứng

- Cần iPhone thật, bản build có ký với HealthKit; một máy có ghép Apple Watch.
  Simulator không có pedometer.
- Build simulator chỉ kiểm tra biên dịch; không chứng minh hành vi nền, khóa
  máy, pin hay notification.
- Bản TestFlight của M1 có probe sau công tắc ẩn; trước khi lên App Store phải
  bảo đảm công tắc này không bật được.
- Mỗi lần test lưu log và ảnh màn hình vào `docs/phase3/evidence/<ngày>-<mốc>/`.
- Hoàn thành code, test trên máy thật, TestFlight và review của App Store là các
  mốc riêng; không gộp khi báo tiến độ.
