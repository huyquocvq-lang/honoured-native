# Phase 4 — Kế hoạch triển khai hai milestone

Lập ngày 25/10/2026 từ file khách gửi `Honoured_M3_Phase_1_Item_6_No_Wearables.pdf`
(scope gốc ngày 06/10/2026, bản sửa ngày 25/10/2026 chỉ đổi Item 6: bỏ hẳn
phần wearable). File PDF chưa có trong repo; nên lưu vào `docs/phase4/clarify/`.

Khách gọi đây là "M3 milestone scope, Phase 1". Trong repo, các phase trước nằm
ở `docs/phase1` đến `docs/phase3`, nên tài liệu này để ở `docs/phase4`. Đừng
nhầm với M3 của Phase 3 (nghiên cứu Core Motion khi chạy nền, 22 giờ).

Hiện trạng đọc từ code native trên `main` (`b3c96c9`, đã có trên `origin/main`)
và web Lovable tại commit `e79a9650`. DB đối chiếu qua các file mirror trong
`docs/db/`, chưa truy vấn Lovable Cloud. Chưa chạy build hay test nào cho tài
liệu này.

## 1. Tóm tắt

| # | Hạng mục | ET khách | ET đề xuất | Nhận xét |
|---:|---|---:|---:|---|
| 1 | Zero defaults cho mọi measurable | 4 | 3,5–4,5 (4) | Đúng. Phải thêm kiểm tra target > 0 trước khi ký |
| 2 | Icon: sửa target, ký lại, lịch sử thay đổi | 20–25, "cần xác nhận" | 24–29 (28) | Thấp: target đang bị khoá trong DB và được đọc từ contract ở mọi chỗ, nên phải thêm target theo ngày, bảng lịch sử, sửa 4 hàm SQL, web và thẻ Icon |
| 3 | Ngày trên Daily Card | 1 | 2–3 | Hơi thấp: thẻ Icon trên màn khóa là native, cần bản app mới; cộng 1–1,5 giờ nếu làm cả thẻ trên web |
| 4 | Email opt-in: checkbox + toggle | 2–3 | 4–5 (5) | Chỉ đủ nếu riêng đăng ký bằng email; Apple và Google cần thêm |
| 5 | Philosophy modal trước khi ký | 12–16 | 5–8 (7) | Dư; chỉ cần tới mức đó nếu khách muốn animation công phu hoặc lưu theo tài khoản |
| 6 | Health & Tracking: chọn nguồn | 12–19 | 13–18,5 (18) | Tổng đủ, nhưng chia sai: Core Motion đã làm ở Phase 3 M2; phần mới thật sự là lựa chọn "iPhone", màn mới, chuyển lựa chọn cũ, Icon và History theo nguồn |
|  | **Tổng** | **51–68** | **51,5–68 (64)** | Tổng gần như trùng; khác ở cách chia |

Kết luận: tổng giờ của khách dùng được. Nên báo lại khách cách chia theo từng
item: Item 2 tăng, Item 5 giảm, và 3–5 giờ Core Motion của Item 6 chuyển sang
phần "iPhone" vì Core Motion đã làm ở M2. Các con số giả định khách chốt theo
đề xuất trong phần câu hỏi của từng item.

Ngày 25/10/2026 Jimmy đồng ý dùng các con số và đề xuất trong tài liệu này. Bản
gửi khách (tiếng Anh, chưa gửi):
`docs/phase4/phase4-two-milestone-client-reply.en.md`. Số trong
bản gửi khách: 4 / 28 / 2 / 5 / 7 / 18, tổng **64 giờ**. Jimmy nâng từ 61,5 giờ
lên 64 giờ: Item 2 +1, Item 4 +0,5, Item 6 +1, đều còn trong khoảng tính ở dưới. Đi
kèm các điều kiện: Item 2 cộng 2–3 giờ nếu làm Icon Word Tracker và khoảng 2 giờ
nếu cho sửa có hiệu lực ngay trong ngày; Item 3 cộng 1 giờ nếu hiện ngày cả trên
thẻ trong app; Item 4 chỉ 2,5–3 giờ nếu chỉ làm đăng ký bằng email. Theo ý
Jimmy, bản gửi khách chỉ gồm estimate và scope; các câu hỏi ở mục 2.6 và mục 3
để hỏi khách sau, trước khi code Item 2 và Item 6. Chia hai milestone (mục 4):
M1 gồm Item 1, 4, 5, 6 (34 giờ); M2 gồm Item 2 và 3 (30 giờ).

## 2. Item 6 — Health & Tracking: chọn nguồn theo dõi

### 2.1 Khách muốn gì

- Một màn **Health & Tracking** trong Settings, theo design: nút "‹ Settings",
  thẻ **Apple Health** (chấm trạng thái "Connected", câu mô tả, mũi tên), thẻ
  **Tracking source** có nút (i) và segmented control ba lựa chọn, bên dưới là
  tên và mô tả của lựa chọn đang chọn.
- Ba nguồn, không hơn:
  - **Automatic**: tổng gộp Apple Health từ mọi thiết bị và app.
  - **iPhone**: chỉ sample Apple Health do **chính iPhone này** ghi, bỏ bước của
    thiết bị khác.
  - **Core Motion**: pedometer của iPhone (bước chân, quãng đường), không qua
    Apple Health.
- Lưu lựa chọn và áp dụng nhất quán cho các goal đủ điều kiện.
- Có trạng thái kết nối Apple Health và xử lý quyền.
- **Không làm wearable**: ghép đôi, quản lý, API hãng, kết nối đồng hồ trực
  tiếp, cài đặt riêng cho wearable. Thẻ "Wearables" trong design chỉ để tham
  khảo, không được làm.
- Tiêu chí nghiệm thu: đổi nguồn thì số hiển thị đổi theo; không cộng trùng;
  xử lý trạng thái quyền bị từ chối hoặc không có; Core Motion chỉ chạy khi máy
  có dữ liệu motion; lựa chọn còn sau khi khởi động lại. Background delivery
  không được bảo đảm.
- Khách giả định Apple Health đã tích hợp sẵn (đúng); làm HealthKit từ đầu thì
  phải estimate riêng.

### 2.2 Hiện trạng: phần lớn đã có từ V1.2 và Phase 3 M2

| Phần | Đã có | Còn thiếu so với Item 6 |
|---|---|---|
| UI chọn nguồn | Web `Settings.tsx` › section "Health": dropdown "Steps & distance source" gồm Automatic, Core Motion và **mọi** nguồn HealthKit (iPhone, Apple Watch, Garmin Connect…) | Màn con mới, segmented ba lựa chọn cố định, bỏ nguồn wearable khỏi UI |
| Automatic | Tổng gộp Apple Health, khử trùng bằng `HKStatisticsQuery` (bản sửa 16/10) | Không |
| Core Motion | Native đọc pedometer, quyền Motion, fallback, số live, giới hạn 7 ngày, Icon v3 (Phase 3 M2) | Chỉ cần nối vào control mới |
| iPhone | Chỉ chọn được một nguồn HealthKit theo tên, ví dụ "Michael's iPhone"; `HealthSourceDescriptor.make` đoán loại theo tên có chữ "iphone" | Chưa có lựa chọn "iPhone này" tự nhận diện máy |
| Lưu lựa chọn | Theo tài khoản: `localStorage` của web (`honoured.healthSource.v1:<userId>`) và `UserDefaults` của native; khi restore, bản của web thắng | Giá trị mới và chuyển các lựa chọn cũ |
| Áp dụng | Một điểm đọc chung `HealthKitService.readTotal` cho goal, Live Activity, Icon, `HEALTH_METRICS`, `health_daily`; đổi cách đọc thì tính lại `health_daily` tối đa 90 ngày | Icon: Automatic và iPhone cùng nhãn `healthkit` (xem 2.3) |
| Trạng thái Apple Health | Row "Apple Health": Connect / Set up / Unavailable. iOS không cho biết quyền đọc được cấp hay bị từ chối | Thẻ có "Connected" và mũi tên: phải định nghĩa lại cho đúng sự thật |

Điều kiện trước: Item 6 xây trên code Phase 3 M2. Native M2 đã lên
`origin/main` nhưng chưa test trên iPhone thật và chưa có bản TestFlight; web M2
(Lovable, tới `e79a9650`) theo ghi chú ngày 22/10 chưa publish, cần kiểm lại.
Lỗi tìm thấy khi test M2 tính vào M2, không tính vào Item 6.

### 2.3 Thiết kế đề xuất

**Nơi làm UI.** Web (Lovable), như phần Settings hiện có, không làm SwiftUI.
Section "Health" trong Settings đổi thành một row "Health & Tracking ›" mở màn
con; BottomNav giữ tab Settings.

**Dạng dữ liệu trên bridge** (giữ tương thích v1/v2):

| Lựa chọn | Preference | Ghi chú |
|---|---|---|
| Automatic | `{ mode: "automatic" }` | Như hiện tại |
| iPhone | `{ mode: "source", sourceId: "this_iphone" }` | Mục cố định mới trong `HEALTH_SOURCES.sources`: `{ id: "this_iphone", name: "iPhone", kind: "this_iphone" }`, cùng cách đã làm cho Core Motion, nên bản web cũ vẫn liệt kê và lưu được |
| Core Motion | `{ mode: "source", sourceId: "core_motion" }` | Như hiện tại |

Native vẫn nhận nguồn HealthKit cụ thể (Watch, Garmin…) để bản web cũ không bị
hỏng; web mới không hiện chúng.

**Nhận diện "iPhone này".** Lọc sample của nguồn Apple (`bundleIdentifier` bắt
đầu bằng `com.apple.health.`) có `sourceRevision.productType` trùng model máy
đang chạy (ví dụ `iPhone16,2`), bằng
`HKQuery.predicateForObjects(from: Set<HKSourceRevision>)` với
`HKSourceRevisionAnyVersion` và `HKSourceRevisionAnyOperatingSystem`. Không cần
tên máy (từ iOS 16, app không đọc được tên máy nếu không có entitlement riêng).

- Giới hạn: hai iPhone cùng model trên cùng Apple ID sẽ bị gộp. Cần khách chấp
  nhận.
- Làm spike trên máy thật trước (đã tính trong giờ): xem `productType` của
  sample bước chân do iPhone ghi, khi có ghép Apple Watch. Nếu không dùng được,
  phương án dự phòng là lọc theo `HKDevice` (model `iPhone` và `hardwareVersion`
  của máy này), thêm 1–2 giờ.

**Metric áp dụng.** Chỉ `steps` và `distance_walking_running`, như hiện tại.
Năng lượng, nhịp tim, phút tập và giấc ngủ luôn dùng tổng gộp Apple Health.

**Không có dữ liệu từ iPhone này** (tắt Fitness Tracking, hoặc chưa cấp quyền
đọc): đề xuất dùng tổng gộp, báo `fallback: true` và web hiện thông báo, giống
quy tắc hiện có khi nguồn đã chọn biến mất. Chờ khách chốt.

**Không cộng trùng.** Automatic dùng tổng khử trùng của HealthKit; iPhone chỉ
đọc một thiết bị; Core Motion thay chỗ HealthKit, không bao giờ cộng thêm.

**`health_daily`.** Thêm daily basis `this_iphone:<productType>`; đổi nguồn thì
bước chân và quãng đường được tính lại tối đa 90 ngày bằng cơ chế có sẵn. Đổi
sang iPhone mới (model khác) cũng tính lại.

**Icon.** `icon_scoring_v3.sql` coi mọi nguồn HealthKit là `healthkit`: số mới
từ cùng nhãn chỉ được tăng. Vì vậy đổi Automatic → iPhone (số thấp hơn) sẽ không
thay số của các ngày Icon, và History hiện số lớn hơn của hai nguồn, trái với
tiêu chí "đổi nguồn thì số hiển thị đổi theo". Đề xuất:

- Native gửi `source: "healthkit_iphone"` (tên đề xuất) cho lần đo Icon đọc từ
  nguồn iPhone.
- `icon_scoring_v4.sql` chấp nhận giá trị này trong check constraint
  `measured_source` và trong `record_icon_measurements`. Các quy tắc v3 giữ
  nguyên: không bao giờ hạ một ngày HONOURED; ngày BROKEN lên HONOURED nếu số của
  nguồn mới đạt target trong cửa sổ đo.
- Test trên Postgres cục bộ. Deploy lên Lovable Cloud là bước riêng, sau khi
  khách duyệt, như v2 và v3.

**Trạng thái Apple Health (thẻ "Connected").** iOS không cho biết quyền đọc được
cấp hay bị từ chối, nên không được hiện "Connected" chỉ vì đã hỏi quyền. Đề
xuất:

| Trạng thái | Khi nào | Hiển thị |
|---|---|---|
| Not connected | Còn metric chưa hỏi quyền | Nút Connect (mở sheet quyền của iOS) |
| Connected | Đã hỏi hết và đọc được dữ liệu Apple Health trong 7 ngày gần nhất | Chấm xanh, như design |
| No data yet | Đã hỏi nhưng không đọc được gì | Hướng dẫn Settings › Health › Data Access & Devices › Honoured |
| Không có HealthKit | iPad, Android, trình duyệt | Ẩn màn, hoặc "Available in the iPhone app" |

Native thêm `hasRecentData` (đọc tổng gộp, không theo nguồn đã chọn) vào
`HEALTH_PERMISSION_STATUS`. Chạm vào thẻ (mũi tên) mở sheet chi tiết: Honoured
đọc gì, trạng thái, nút Connect, đường dẫn trong Settings. iOS không có link mở
thẳng trang quyền Health của Honoured.

**Chuyển lựa chọn cũ** (người dùng đã chọn một nguồn trong dropdown hiện tại):
Core Motion giữ nguyên; nguồn có `kind: "iphone"` → iPhone; Apple Watch, Garmin
và app khác → Automatic. Làm trong web lúc restore (web thắng); native vẫn đọc
được lựa chọn cũ.

**Bản App Store hiện tại** (chưa có Core Motion và iPhone): web chỉ bật lựa
chọn mà native liệt kê; lựa chọn còn lại mờ, kèm câu kiểu "Update Honoured to use
this option" (chờ duyệt). Publish web vì vậy vẫn an toàn với bản cũ.

**Câu chữ.** Dùng nguyên câu trong design của khách (sửa lỗi "smantwatch" thành
"smartwatch"). Câu trong sheet (i), nhãn trạng thái Apple Health và các thông
báo mới thì soạn rồi gửi khách duyệt.

### 2.4 Workstream và estimate

| # | Việc | Nơi làm | Giờ |
|---:|---|---|---:|
| 1 | Màn Health & Tracking: row trong Settings, màn con "‹ Settings", thẻ Apple Health và sheet chi tiết, thẻ Tracking source (segmented ba nút, mô tả theo lựa chọn, sheet (i)), trạng thái loading/saving/lỗi/fallback/quyền Motion, không có thẻ Wearables | Web | 3–4,5 |
| 2 | Lựa chọn "iPhone": mục cố định, parse và payload, predicate "iPhone này" áp dụng cho `readTotal`, `minuteTotals`, `sourceMetadata`, fallback, daily basis, unit test trong `HealthSourcePreferenceTests`; spike trên máy thật | iOS | 3–4 |
| 3 | Icon theo nguồn iPhone: nhãn nguồn mới, `icon_scoring_v4.sql`, test Postgres cục bộ (deploy là bước riêng) | iOS + SQL | 1–1,5 |
| 4 | Lưu lựa chọn, chuyển lựa chọn cũ, tương thích native cũ, cập nhật test web | Web | 1–1,5 |
| 5 | Trạng thái Apple Health: `hasRecentData` trên native, map trạng thái trên web | iOS + Web | 0,5–1 |
| 6 | Core Motion: nối vào control mới, regression (phần tích hợp đã làm ở Phase 3 M2) | Web + iOS | 0,5 |
| 7 | Test: simulator (build Debug/Release, `HonouredTests`, kịch bản BridgeStub mới cho iPhone và kịch bản `core-motion` cũ) và iPhone thật (mục 2.5) | Tất cả | 3,5–4,5 |
| 8 | Cập nhật `docs/phase1/bridge.md`, soạn câu chữ gửi khách duyệt | Docs | 0,5–1 |
|  | **Tổng** |  | **13–18,5** |

So với cách chia của khách:

| Dòng của khách | ET khách | Thực tế | Lý do |
|---|---:|---:|---|
| Giao diện và ba control | 2–4 | 3–4,5 | Thêm thẻ Apple Health có sheet, trạng thái lỗi, tương thích bản cũ |
| Lưu lựa chọn và routing | 4–6 | 5,5–8 | Thêm "iPhone này", Icon v4, chuyển lựa chọn cũ, trạng thái Apple Health |
| Tích hợp Core Motion | 3–5 | 0,5 | Đã làm ở Phase 3 M2 (35 giờ tích hợp, khách đã trả) |
| Test và edge case | 3–4 | 3,5–4,5 | Cần iPhone thật có ghép Watch |
| **Tổng** | **12–19** | **13–18,5** | |

Kết luận: tổng 12–19 giờ của khách là đủ, nhưng nên nói rõ với khách rằng 3–5
giờ Core Motion được chuyển sang phần nhận diện iPhone và Icon/History theo
nguồn, vì Core Motion đã bàn giao ở M2. Đề xuất chốt **18 giờ**, hoặc giữ khoảng
12–19 giờ và tính theo giờ thực tế. Rủi ro làm vượt: cách nhận diện iPhone không
chạy trên máy thật (+1–2 giờ), và số vòng sửa UI với agent Lovable để khớp
design.

### 2.5 Test theo tiêu chí nghiệm thu

Mỗi bài đi ngắn 100–150 bước, target 100.

| Tiêu chí của khách | Cách kiểm |
|---|---|
| Đổi nguồn thì số hiển thị đổi theo | Đổi Automatic ↔ iPhone ↔ Core Motion; xem Home, thẻ contract, Live Activity, History (`health_daily` và ngày Icon) |
| Không cộng trùng | Đeo Watch, để iPhone trên bàn, đi ~150 bước: Automatic tăng, iPhone và Core Motion đứng yên. Mang cả hai: Automatic xấp xỉ số app Health hiện, không bằng tổng hai thiết bị. So iPhone với dữ liệu của nguồn iPhone trong app Health |
| Quyền bị từ chối hoặc không có | Motion bị tắt hoặc restricted; Health chưa hỏi (cài mới); Health bị từ chối (No data yet); iPhone tắt Fitness Tracking |
| Core Motion chỉ chạy khi có dữ liệu motion | Simulator (không có pedometer): Core Motion mờ hoặc fallback |
| Lựa chọn còn sau khi khởi động lại | Force-quit rồi mở lại; khởi động lại máy; đổi tài khoản (mỗi tài khoản một lựa chọn) |
| Không lặp sự kiện (quy tắc đã có) | Đổi nguồn sau khi đã đạt goal: không có `GOAL_REACHED` hay notification lặp, ngày HONOURED không bị hạ |
| Tương thích | Web mới trên bản App Store cũ: lựa chọn chưa hỗ trợ bị mờ, không lỗi |

Background delivery không phải tiêu chí đạt/không đạt; chỉ ghi nhận.

### 2.6 Câu hỏi cần khách chốt (Item 6)

1. "iPhone" là iPhone đang dùng, nhận diện theo nguồn Apple và model máy; hai
   iPhone cùng model trên cùng Apple ID sẽ được tính chung. Đồng ý?
2. Chỉ áp dụng cho bước chân và quãng đường đi bộ/chạy; các chỉ số khác luôn
   dùng tổng gộp Apple Health. Đồng ý?
3. Người dùng đã chọn Apple Watch, Garmin hoặc app khác trong dropdown cũ sẽ được
   chuyển sang Automatic (đã chọn một iPhone thì sang iPhone). Đồng ý?
4. Nhãn trạng thái Apple Health: Connected / Not connected / No data yet như
   bảng trên, vì iOS không cho biết quyền đọc có được cấp hay không.
5. Mũi tên trên thẻ Apple Health mở sheet chi tiết (không mở thẳng được trang
   quyền Health của Honoured).
6. Nội dung sheet (i) của Tracking source: Jimmy soạn, khách duyệt.
7. Chọn iPhone mà không có dữ liệu từ iPhone này: dùng tổng gộp kèm thông báo
   (đề xuất), hay hiện "không có dữ liệu"?
8. Đổi Automatic ↔ iPhone sẽ thay số của các ngày Icon trong cửa sổ đo (30 ngày),
   như khi đổi sang Core Motion; cần deploy `icon_scoring_v4.sql`. Đồng ý?
9. Chỉ làm cho iPhone (Android không có HealthKit). Đồng ý?

## 3. Item 1–5

Dòng tham chiếu web lấy từ commit `e79a9650`; chỉ số dòng của `Contract.tsx` là
chính xác, file khác ghi theo tên hàm.

### 3.1 Item 1 — Zero defaults (khách 4 giờ, đề xuất 4 giờ)

**Khách muốn:** mọi measurable mặc định là 0, người dùng tự nhập cam kết,
không gợi ý sẵn. "We don't decide what your promise should be. You do."

**Hiện trạng (web, `Contract.tsx`):**

- Không có target mặc định cứng. Ô trống đã hiện là 0; tối thiểu là 0, riêng
  words là 100.
- Số vẫn được điền sẵn từ: contract đang có, "Go again" (`goAgainPrefill`),
  contract gần nhất (`honoured.lastContract.v1`, ghi ở dòng 1471–1484), và số
  mang sang khi đổi activity hoặc đơn vị (dòng 1170–1209; ví dụ 10.000 bước đổi
  sang km thành 50 km, mức tối đa).
- `sign()` (dòng 1358–1436) không kiểm target. Target trống hoặc 0 thì Icon vẫn
  ký được và thành Icon tự báo cáo, không có metric (đọc code, chưa chạy thử).
  Có zero defaults thì trường hợp này sẽ hay xảy ra, nên bắt buộc thêm kiểm tra
  target > 0 (words ≥ 100) cho cả target chính lẫn target phụ.
- Không có default nào ở native hay DB.

| Việc (chỉ web) | Giờ |
|---|---:|
| Target bắt đầu trống (hiện 0), xoá số khi đổi activity hoặc đơn vị | 1,5 |
| Kiểm tra target > 0 trước khi ký, câu báo lỗi | 1 |
| Go again và contract gần nhất, theo quyết định của khách | 0,5 |
| Test web | 1 |
| **Tổng** | **4** |

**Câu hỏi:** Go again có giữ target cũ không (đó là cam kết của chính người
dùng)? Có giữ việc điền sẵn activity, câu Because và deadline từ contract trước
không?

### 3.2 Item 2 — Icon: sửa target, ký lại, lịch sử (khách 20–25 giờ, đề xuất 28 giờ)

**Khách muốn:** Icon đang chạy được sửa target giữa chừng và phải ký lại. Giữ
bản cam kết gốc, target gốc, target mới, thời điểm sửa, thời điểm có hiệu lực
và chữ ký mới trong một lịch sử thay đổi nhìn thấy được. Không ghi đè bản gốc,
không sửa ngày đã xong hoặc đã hết hạn; chỉ áp dụng cho các ngày sau.

**Hiện trạng:**

- Icon nằm trong một dòng `contracts` (các cột `icon_*`, `primary_target`, một
  `signature_path`). Mỗi ngày là một dòng `icon_days`, **không có cột target**.
- Trigger `contracts_icon_guard` (`icon_v1.sql`) khoá target sau khi ký: mọi
  UPDATE bị trả về giá trị cũ. Hiện chỉ sửa được giờ nhắc.
- Target được đọc từ contract ở nhiều chỗ:
  - SQL: `icon_days_to_measure`, `record_icon_measurements` (chấm lại các ngày
    đã đóng dấu trong 30 ngày, nên đổi `icon_target` sẽ đổi kết quả ngày cũ),
    `record_word_reading`, job push (`icon_push_v5.sql` đọc `primary_target`
    cho thẻ và thông báo).
  - Native: thẻ Icon đọc `contracts.primary_target` (`IconCardCoordinator.swift`,
    `IconCardPlan.swift`). Target nằm trong attributes của Live Activity
    (`IconActivityAttributes`), không đổi được trên thẻ đang chạy.
  - Web: ActiveIcons, `icon-days.ts`, History, tổng kết Icon, Go again.
- Chữ ký được upload với `upsert: true` vào `signatures/<uid>/<client_id>.png`,
  nên ký lại sẽ ghi đè chữ ký gốc. Native cache chữ ký với giả định "không bao
  giờ đổi sau khi ký" (`IconSignatureSync.swift`).
- Trùng tên: trạng thái `amended` đã có và đang có nghĩa là "kết thúc sớm".

**Thiết kế đề xuất:**

- Không sửa target trên `contracts`; giữ nguyên làm bản gốc. Thêm bảng
  `icon_amendments` chỉ cho insert (target cũ, target mới, lúc sửa, ngày có hiệu
  lực, đường dẫn chữ ký mới), ghi qua một RPC `SECURITY DEFINER`.
- `icon_days` thêm target theo ngày (số và chữ), backfill từ contract. RPC cập
  nhật target cho các ngày `pending` kể từ ngày có hiệu lực.
- Các hàm SQL đọc target theo ngày, trong một bản SQL mới làm trên nền
  `icon_scoring_v4.sql` của Item 6 (M1).
- Chữ ký mới lưu ở đường dẫn mới, không ghi đè.
- Có hiệu lực từ ngày Icon kế tiếp (đề xuất): không phải khởi động lại thẻ đang
  chạy, và không ai hạ target lúc 23:00 để lấy HONOURED.

| # | Việc | Nơi làm | Giờ |
|---:|---|---|---:|
| 1 | Bảng `icon_amendments`, RLS, RPC sửa target; target theo ngày trên `icon_days` (backfill, trigger tạo ngày) | SQL | 4–5 |
| 2 | Viết lại 4 hàm đọc target (đo, chấm, Word, push); rollback; test Postgres cục bộ. Deploy là bước riêng | SQL | 4–5 |
| 3 | Sheet sửa target (tách ô target và chọn đơn vị ra khỏi `Contract.tsx`); ký lại, kể cả màn ký ngang (khi xoay máy, `DailyContractView` thay cả tab Contract bằng `LandscapeSignaturePad`, sẽ đóng sheet); upload chữ ký mới; gọi RPC | Web | 5–6 |
| 4 | Target theo ngày ở mọi chỗ hiển thị; màn lịch sử thay đổi (bản gốc và từng lần sửa, kèm chữ ký); test web | Web | 6–7 |
| 5 | Thẻ Icon đọc target theo ngày, làm mới cache chữ ký, cập nhật `IconCardPlanTests` | iOS | 2,5–3 |
| 6 | Test trên máy thật: sửa, ký lại, thẻ ngày hôm sau (cả thẻ mở bằng push), History, Icon kết thúc | Tất cả | 2–3 |
|  | **Tổng** |  | **24–29** |

Cộng thêm 2–3 giờ nếu làm cho Icon Word Tracker, và khoảng 2 giờ nếu sửa có
hiệu lực ngay trong ngày (phải kết thúc rồi mở lại thẻ, cả từ app lẫn push).

Phương án rẻ hơn (khoảng 10–12 giờ): kết thúc Icon sớm rồi ký một Icon mới nối
vào. Nhược điểm: số buổi đếm lại từ đầu và các ngày còn lại hiện AMENDED, nên
giống "bỏ cuộc" hơn là "điều chỉnh", trái với ý khách.

**Câu hỏi:**

1. Có hiệu lực từ hôm nay hay từ ngày Icon kế tiếp? Đề xuất: ngày kế tiếp.
2. Chỉ được đổi con số (cùng metric và đơn vị), hay đổi được cả đơn vị hoặc
   activity?
3. Có giới hạn số lần sửa không? Tăng và giảm đều được?
4. Loại Icon nào: đo bằng Health, tự báo cáo, Word Tracker?
5. Sửa target có tốn một free session không?
6. Lịch sử thay đổi hiện ở đâu: trong Icon, trong History, hay cả hai?
7. Đặt tên gì cho lần sửa để không trùng "AMENDED" (đang nghĩa là kết thúc sớm),
   ví dụ "Revised"?
8. Sau khi sửa, thẻ Icon hiện chữ ký nào? Đề xuất: chữ ký mới nhất.

### 3.3 Item 3 — Ngày trên Daily Card (khách 1 giờ, đề xuất 2–3 giờ)

**Khách muốn:** đầu thẻ hiện ngày của contract: "TUE 06.10.26 / Due midnight",
để ngày neo lại thời điểm contract có hiệu lực.

**Hiện trạng:**

- Thẻ Icon trên màn khóa (Live Activity, iOS) đã có đầu thẻ "TUE · 5 OF 17" và
  dòng "Due midnight" (`IconLiveActivity.swift`, `IconLiveActivityViews.swift`).
  Mẫu của khách khớp với thẻ này, nên "Daily Card" nhiều khả năng là thẻ Icon.
- Ngày Icon (`iconDay`) đã có trong dữ liệu thẻ, cả khi app tự mở thẻ lẫn khi
  server mở bằng push, nên không phải sửa server.
- Web: thẻ contract trên Home chưa có ngày hay deadline; màn chi tiết ghi
  "STANDING CONTRACT"; row Icon ghi "Session 5 of 18 · Today".
- Ngày phải lấy theo ngày Icon, không theo deadline: cut-off 00:00 rơi vào ngày
  hôm sau, nên lấy theo deadline thì thẻ thứ Ba sẽ hiện ngày thứ Tư.

**Việc:**

- Native: đổi đầu thẻ (màn khóa và Dynamic Island mở rộng), kiểm chiều cao thẻ,
  cập nhật test và preview: 1,5–2 giờ. Chỉ tới tay người dùng khi có bản app mới.
- Web, nếu khách muốn cả thẻ trong app: 1–1,5 giờ.

**Câu hỏi:** Thẻ nào: thẻ Icon trên màn khóa, thẻ trong app, hay cả hai? Bỏ
hay giữ "5 OF 17"? Contract thường có deadline cách nhiều ngày thì hiện thế nào?
Dùng định dạng DD.MM.YY cố định cho mọi người dùng?

### 3.4 Item 4 — Email opt-in (khách 2–3 giờ, đề xuất 4–5 giờ)

**Khách muốn:** checkbox ở màn đăng ký, mặc định không tích: "Send me Honoured
inspiration, updates and new features." Có toggle trong Settings, dùng control
kiểu app.

**Hiện trạng:**

- `AuthGate.tsx`: nút Apple (chỉ iOS) và Google nằm trên form, hiện ở cả chế độ
  đăng nhập lẫn đăng ký. Ô đồng ý điều khoản đang mặc định tích sẵn
  (`useState(true)`); ô opt-in mới không được làm theo mặc định này.
- Đăng ký bằng email truyền metadata sang `profiles` qua `handle_new_user`.
  Apple (`signInWithIdToken`) không mang metadata được; Google trên web dùng
  redirect nên mất state trong trang.
- `profiles` chưa có cột consent; repo chưa tích hợp công cụ gửi email nào.
- Đã có sẵn switch kiểu iOS (row Notifications trong Settings) và checkbox
  (`AuthCheckboxInput`).

| Việc (web và DB, không có native) | Giờ |
|---|---:|
| Cột opt-in (mặc định false), thời điểm và nguồn; cập nhật `handle_new_user` | 1 |
| Checkbox ở đăng ký bằng email | 0,5 |
| Đăng ký bằng Apple/Google: giữ lựa chọn tạm, chỉ ghi cho tài khoản vừa tạo | 1–1,5 |
| Toggle trong Settings | 1 |
| Test | 0,5–1 |
| **Tổng** | **4–5** |

Nếu chỉ làm cho đăng ký bằng email thì 2,5–3 giờ, khớp ET của khách.

**Câu hỏi:** Đăng ký bằng Apple/Google có cần checkbox không? Đồng bộ sang công
cụ email (Mailchimp, Resend…) không nằm trong estimate. "Native app control"
chỉ có thể là switch trông giống iOS trong web; không đặt được control native
thật vào trang web.

### 3.5 Item 5 — Philosophy modal (khách 12–16 giờ, đề xuất 7 giờ)

**Khách muốn:** ngay trước khi ký, hiện "Choose a promise you can honour" và
"Small daily steps / compound into a life / beyond measure". Giữ vững triết lý;
người dùng tự chọn cam kết.

**Hiện trạng:**

- Chỉ có một đường ký: `DailyContractView.sign()` (`Contract.tsx` dòng 1358),
  sau nút "Sign this contract", dùng chung cho contract thường, Icon và Go again.
  Chữ ký lấy từ canvas, từ màn ký ngang (`LandscapeSignaturePad`, nằm ngoài
  khung app) hoặc từ chữ ký standing cũ.
- `sign()` gọi `runStartSession()`, tức là tiêu một free session trên server.
  Modal phải hiện sau khi kiểm tra hợp lệ và trước lời gọi này, để bấm quay lại
  không mất session.
- Màn "The Philosophy" hiện có chỉ xuất hiện trước khi đăng nhập
  (`Onboarding.tsx`); cờ `philosophyRead` lưu theo máy.

| Việc (chỉ web) | Giờ |
|---|---:|
| Modal, theo mẫu portal của `EndIconDialog` | 2–3 |
| Tách `sign()` thành hai bước, xử lý màn ký ngang | 1,5–2 |
| Logic hiện một lần hay mọi lần, test | 1,5–3 |
| **Tổng** | **5–8** |

12–16 giờ của khách là dư. Chỉ cần tới mức đó nếu khách muốn animation công
phu, âm thanh hoặc lưu "đã xem" theo tài khoản trên server.

**Câu hỏi:** Hiện mọi lần ký hay chỉ một lần (theo máy, hay theo tài khoản; theo
tài khoản thì cần cột trong `profiles`)? Có hiện khi ký lại lúc sửa Icon (Item
2) không? Hiện trước khi vẽ chữ ký hay sau khi bấm Sign? Có những nút gì? Có tóm
tắt lời hứa trong modal không?

## 4. Kế hoạch triển khai đã sửa: chia thành hai milestone

### 4.1 Nguyên tắc chia scope

Chia hai milestone (Jimmy chốt ngày 25/10/2026):

| Milestone | Scope chốt | Giờ | Kết quả khách nghiệm thu |
|---|---|---:|---|
| M1 — Foundation & Tracking | Item 1 Zero defaults; Item 4 Email opt-in; Item 5 Philosophy modal; Item 6 Health & Tracking | **34** | Web production cho Item 1/4/5; SQL v4 đã deploy; TestFlight có Item 6; evidence trên iPhone thật |
| M2 — Icon Amendment & Daily Card | Item 2 sửa target, ký lại, lịch sử; Item 3 ngày trên thẻ Icon | **30** | SQL amendment đã deploy; web production có amendment UI; TestFlight có thẻ Icon mới; regression đầy đủ |
|  | **Tổng** | **64** | App Store submission/review không nằm trong hai mốc này |

Cách chia này đúng về kỹ thuật:

- M1 gom các thay đổi nền và tạo `icon_scoring_v4.sql`, là baseline DB mà M2 sẽ
  xây tiếp.
- M2 gom hai việc cùng chạm thẻ Icon native, nên chỉ cần một vòng sửa, build và
  test TestFlight.
- Không chia Item 2 sang hai milestone: schema target theo ngày, RPC amendment,
  UI ký lại và thẻ native phải phát hành như một vertical slice. Bàn giao một
  nửa sẽ tạo trạng thái DB/UI không tương thích.
- Tổng 64 giờ chỉ đúng với các quyết định scope ở mục 4.2 và 4.3. Các option có
  tính thêm giờ được ghi riêng, không được tự đưa vào milestone.

### 4.2 Milestone 1 — Foundation & Tracking (34 giờ)

#### Scope và phân bổ giờ

| ID | Hạng mục | Đầu việc chi tiết | Nơi làm | Giờ |
|---|---|---|---|---:|
| M1.1 | Zero defaults | Xóa prefill target từ contract gần nhất và khi đổi activity/unit; định nghĩa riêng hành vi Go again; validate target > 0 và words >= 100; thông báo lỗi; test | Web | 4 |
| M1.2 | Email opt-in | Migration consent; mặc định false; lưu value/time/source; checkbox ở sign-up; giữ lựa chọn qua email/Apple/Google sign-up nhưng không đổi consent khi sign-in; toggle Settings; test | Web + SQL | 5 |
| M1.3 | Philosophy modal | Modal theo design; đặt sau validation nhưng trước `runStartSession`; back/cancel không tốn session; xử lý chữ ký portrait/landscape; quy tắc tần suất hiển thị; test | Web | 7 |
| M1.4 | Health & Tracking UI | Row Settings và màn con; Apple Health card/detail sheet; segmented Automatic/iPhone/Core Motion; trạng thái loading/error/fallback/unsupported; không hiện Wearables | Web | 4 |
| M1.5 | Nguồn “iPhone này” | Bridge model; source cố định; HealthKit predicate; spike trên iPhone thật; áp dụng cho steps/distance ở mọi read path; daily basis; fallback; unit tests | iOS | 4 |
| M1.6 | Persistence & migration | Lưu preference theo account; chuyển source cũ sang ba option; native cũ vẫn an toàn; option chưa được native hỗ trợ phải disabled; web tests | Web + iOS | 2 |
| M1.7 | Icon/History source parity | Native gửi source riêng cho iPhone; `icon_scoring_v4.sql` + rollback; constraint/RPC update; local Postgres tests; deploy và smoke query | iOS + SQL | 2 |
| M1.8 | Health status & copy | Thêm `hasRecentData`; map Not connected/Connected/No data yet/Unavailable; nội dung help và sheet (i); cập nhật bridge docs | iOS + Web + Docs | 1 |
| M1.9 | QA và release | Native unit tests; web tests/build; BridgeStub; compatibility với app hiện tại; iPhone thật có Watch; Android web smoke; publish web; TestFlight; evidence | Tất cả | 5 |
|  | **Tổng** |  |  | **34** |

#### Thứ tự thực hiện

1. **Chốt behavior trước khi code (không tính là một scope mới).** Khách trả lời
   các câu ở mục 2.6; riêng M1 phải chốt: Go again, tần suất Philosophy modal,
   social sign-up có opt-in, cách fallback khi iPhone không có dữ liệu, và quy
   tắc chuyển source cũ.
2. **Baseline Phase 3 M2.** Test Core Motion hiện tại trên iPhone thật. Lỗi thuộc
   scope Phase 3 M2 được ghi và sửa ở M2 cũ, không trừ vào 34 giờ Phase 4.
3. **Làm nhánh web độc lập M1.1–M1.3.** Các phần này có thể code và test trước,
   nhưng chỉ publish sau compatibility smoke với native đang ở App Store.
4. **Làm native M1.5 và M1.8.** Spike nhận diện “iPhone này” phải đi trước phần
   wiring cuối. Nếu `productType` không phân biệt được, dùng fallback `HKDevice`
   như mục 2.3 và báo rủi ro trước khi vượt estimate.
5. **Làm web M1.4/M1.6 trên bridge mới.** UI chỉ enable option native thực sự
   advertise; browser, Android và iOS cũ không được gửi preference không hỗ trợ.
6. **Tạo và kiểm `icon_scoring_v4.sql`.** Migration phải chạy được trên DB đang ở
   v3, có rollback, có test đổi Automatic ↔ iPhone với số tăng và số giảm, đồng
   thời chứng minh ngày HONOURED không bị hạ.
7. **Release theo thứ tự an toàn:** deploy SQL v4 → publish web tương thích ngược
   → phát TestFlight → test end-to-end trên thiết bị. Không publish web Phase 3
   M2 đang chờ nếu Jimmy chưa duyệt gộp vào lần publish này.

#### Acceptance checklist M1

- Contract mới không được tự điền target từ activity/unit hoặc contract gần
  nhất; target không hợp lệ không thể ký. Hành vi Go again đúng quyết định đã
  chốt.
- Opt-in mặc định tắt. Tài khoản email, Apple và Google mới lưu đúng yes/no,
  timestamp và source; đăng nhập lại không ghi đè lựa chọn; toggle Settings lưu
  bền. Không có gửi email hay đồng bộ Mailchimp/Resend trong scope.
- Philosophy modal xuất hiện đúng thời điểm và tần suất đã chốt; Cancel/Back
  không tiêu free session; ký ngang và dọc đều tiếp tục đúng luồng.
- Health & Tracking chỉ có Automatic, iPhone và Core Motion; không có wearable.
  Preference còn sau force-quit/relaunch và tách riêng theo account.
- Automatic gần với tổng trong Apple Health; iPhone chỉ lấy dữ liệu do iPhone
  hiện tại ghi theo giới hạn đã chấp nhận; Core Motion không cộng thêm vào
  HealthKit; steps/distance đổi theo nguồn ở Home, contract, Live Activity,
  `health_daily`, Icon và History.
- Trạng thái permission/no-data/fallback/unsupported có copy rõ ràng; simulator,
  iOS cũ, browser và Android không crash hay hiện control dùng được sai.
- `icon_scoring_v4.sql` và rollback pass bộ test; migration production được ghi
  lại version/thời gian; không phát lại `GOAL_REACHED`, không hạ ngày HONOURED.
- Agent có trách nhiệm đưa bản tới `READY FOR JIMMY`: web production, log test,
  SQL evidence, TestFlight và test steps rõ ràng. Jimmy thực hiện device test,
  ghi PASS/FAIL và evidence vào
  `docs/phase4/phase4-two-milestone-progress-tracker.md`. “Code complete” hoặc
  “đã upload build” chưa đủ để đóng milestone.

#### Definition of Done M1

M1 chỉ hoàn thành khi Item 1/4/5 chạy trên web production, SQL v4 đã deploy và
smoke test, Item 6 có trên TestFlight và Jimmy đã đánh PASS device acceptance
trong tracker trên một iPhone thật (ưu tiên máy có Apple Watch để kiểm không
cộng trùng). Agent chuẩn bị build, test steps và expected result; Jimmy chịu
trách nhiệm thao tác trên máy thật. App Store submission/review không phải điều
kiện thanh toán M1.

### 4.3 Milestone 2 — Icon Amendment & Daily Card (30 giờ)

#### Scope chốt dùng để giữ 30 giờ

- Chỉ sửa **con số target**, giữ nguyên activity, metric, unit, lịch và deadline.
- Target mới có hiệu lực từ **ngày Icon kế tiếp**; ngày đang chạy và ngày đã đóng
  giữ target cũ.
- Áp dụng cho Icon dùng Health và Icon self-reported. **Word Tracker Icon không
  nằm trong 30 giờ**; nếu thêm thì +2–3 giờ.
- Cho phép tăng hoặc giảm target; không giới hạn số lần, nhưng mỗi lần đều tạo
  bản ghi lịch sử immutable và phải ký lại.
- Không tiêu thêm free session khi amendment; trạng thái “AMENDED” hiện có vẫn
  chỉ nghĩa là kết thúc sớm. UI dùng từ **Revised/Revision** cho thay đổi target.
- Lịch sử hiện ở màn Icon detail và History; thẻ màn khóa dùng target/chữ ký có
  hiệu lực cho ngày đó.
- Item 3 chỉ sửa thẻ Icon native trên Lock Screen và Dynamic Island expanded.
  Thẻ trong web/app không nằm trong 2 giờ; nếu thêm thì +1 giờ.

Nếu khách đổi bất kỳ quyết định nào ở trên thì phải re-estimate trước khi code,
đặc biệt hiệu lực ngay trong ngày (+ khoảng 2 giờ) và Word Tracker (+2–3 giờ).

#### Scope và phân bổ giờ

| ID | Hạng mục | Đầu việc chi tiết | Nơi làm | Giờ |
|---|---|---|---|---:|
| M2.1 | Amendment data model | `icon_amendments` immutable; original/new target; effective day; signature path; actor/time; RLS; index; audit constraints | SQL | 3 |
| M2.2 | Target snapshot theo ngày | Thêm target value/text/unit vào `icon_days`; backfill; trigger tạo ngày mới; không đổi ngày đã tạo sai phạm vi; migration + rollback | SQL | 3 |
| M2.3 | Amendment RPC | Validate owner/status/value/effective day; insert history; update chỉ future pending days; idempotency; không tiêu session; concurrency tests | SQL | 3 |
| M2.4 | Rewrite server readers | Scoring/measurement, Word hook hiện hữu, push job và day queries đọc target snapshot; regression trên nền SQL v4; pgTAP/local tests | SQL | 3 |
| M2.5 | Amend & re-sign UI | CTA/sheet sửa target; validation; re-sign portrait/landscape; upload signature path mới không upsert bản cũ; RPC states; error/retry | Web | 5 |
| M2.6 | History & display parity | Original promise + từng revision; effective date/time/signature; target đúng theo ngày ở Active Icon, History, recap/Go again; web tests | Web | 4 |
| M2.7 | Native Icon update | Query target/signature theo ngày; cache key/version không dùng giả định signature bất biến; card mới đọc đúng target; unit tests | iOS | 3 |
| M2.8 | Date on Daily Card | `TUE 06.10.26` từ `iconDay`; giữ “Due midnight”; Lock Screen + expanded Dynamic Island; accessibility/long locale preview | iOS | 2 |
| M2.9 | QA, rollout và evidence | Migration rehearsal; web/native regression; push-start và app-start card; iPhone thật qua hai ngày; Android web smoke; production deploy/publish; TestFlight | Tất cả | 4 |
|  | **Tổng** |  |  | **30** |

#### Thứ tự thực hiện

1. **Freeze contract của M2.** Khách xác nhận bảy quyết định scope ở trên và format
   ngày `DD.MM.YY`. Chưa xác nhận thì chỉ được chuẩn bị migration/test fixture,
   không code UI dựa trên phỏng đoán.
2. **Thiết kế migration trên baseline M1 v4.** Tạo schema, backfill và RPC trước;
   chạy migration + rollback trên DB local có dữ liệu: Icon đang pending, đã
   HONOURED/BROKEN, đã end early, nhiều timezone và nhiều revision.
3. **Đổi toàn bộ server reader sang target snapshot.** Không deploy schema trống
   mà code production vẫn đọc `contracts.primary_target`; deploy migration theo
   kiểu expand-compatible để app/web cũ tiếp tục đọc target gốc và tính năng
   amendment vẫn bị khóa.
4. **Làm web amendment vertical slice.** Upload signature mới bằng path duy nhất,
   gọi RPC idempotent, hiển thị history và target theo từng ngày. Failure giữa
   upload và RPC phải retry được hoặc dọn orphan có kiểm soát.
5. **Làm native M2.7 và M2.8 cùng một build.** Native lấy target và signature của
   chính `icon_day`; cache không còn khóa theo `contract_id` duy nhất. Thẻ ngày
   đang chạy không đổi; thẻ ngày kế tiếp dùng revision mới.
6. **Release theo feature gate:** deploy DB compatible → publish web nhưng chưa
   bật CTA amendment cho production → phát TestFlight và test end-to-end → bật
   CTA cho build native đủ version. Nếu app cũ vẫn còn ngoài store, server/web
   phải ngăn app cũ tạo thẻ với target sai.

#### Acceptance checklist M2

- Sửa target bắt buộc nhập giá trị hợp lệ và ký lại; Cancel/error không tạo
  revision nửa chừng, không tiêu session và không ghi đè chữ ký cũ.
- Contract gốc không đổi. Mỗi revision lưu target cũ/mới, effective day,
  timestamp và signature riêng; client không thể update/delete history trực
  tiếp; retry không tạo bản ghi trùng.
- Ngày hiện tại và ngày đã HONOURED/BROKEN giữ target cũ. Chỉ ngày pending từ
  effective day dùng target mới; scoring, notification, push card, recap và
  History đều dùng cùng snapshot.
- Test cả tăng và giảm target, nhiều lần revision, hai thao tác đồng thời,
  timezone gần midnight, Icon kết thúc sớm và user không còn sở hữu contract.
- Card mở từ app và card push-to-start của ngày kế tiếp đều hiện target/chữ ký
  mới. Card ngày cũ không bị thay đổi; cache không trả nhầm chữ ký.
- Header thẻ lấy ngày Icon, không lấy `deadline_at`; đúng qua cut-off midnight,
  timezone và DST; Lock Screen/Dynamic Island không vỡ layout.
- Web mới smoke trên Android; phần native Icon chỉ enable trên iOS hỗ trợ. App
  production cũ không được nhìn thấy CTA amendment có thể tạo dữ liệu sai.
- SQL migration/rollback, web tests/build, native unit tests và BridgeStub pass.
  Agent bàn giao TestFlight cùng test steps; Jimmy chạy device test và ghi
  PASS/FAIL, evidence trước/sau revision vào progress tracker.

#### Definition of Done M2

M2 hoàn thành khi migration amendment đã deploy, web production đã bật feature
gate cho native version phù hợp, và Jimmy đã đánh PASS các device test amendment
trên TestFlight trong progress tracker. Agent chịu trách nhiệm đưa bản tới
`READY FOR JIMMY`, sửa các lỗi được báo và bàn giao build retest. App Store
submission, thời gian review và một release M1 riêng lên App Store là mốc ngoài
64 giờ, chỉ làm khi khách yêu cầu.

### 4.4 Ma trận phụ thuộc và release chung

| Phụ thuộc | Chặn việc gì | Cách xử lý |
|---|---|---|
| Khách chưa chốt câu hỏi Item 6 | M1.4–M1.8 | Gửi một batch câu hỏi; vẫn làm M1.1–M1.3 |
| Phase 3 M2 chưa device-test/publish | Item 6 | Test và phân loại bug về Phase 3 trước; chỉ publish chung sau khi Jimmy duyệt |
| SQL v4 của M1 chưa production-ready | Toàn bộ SQL M2 | M2 branch trên v4, không viết migration song song trên v3 |
| Không có iPhone + Health data (+ Watch ưu tiên) | Acceptance Item 6 | Không đóng M1 bằng simulator-only evidence |
| Native M2 chưa phát hành/đủ version | Bật amendment CTA | Gate bằng capability/version, mặc định off |
| Scope same-day hoặc Word Tracker chưa chốt | Estimate M2 | Giữ ngoài 30 giờ và lập change order nếu khách thêm |

Mỗi milestone báo riêng các trạng thái: **code complete → automated tests → SQL
deployed → web published → TestFlight available → device acceptance → App Store
submitted/released**. Không dùng một trạng thái thay cho trạng thái khác.
