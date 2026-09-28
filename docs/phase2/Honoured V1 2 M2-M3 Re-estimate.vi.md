# HONOURED V1.2 - ESTIMATE LẠI MILESTONE 2 VÀ 3

Lập ngày 28/09/2026 theo hai tài liệu mới trong `clarify/`:

- `Honoured The Oath Feature Scope v6.pdf` (bỏ Wallet pass, thay bằng Oath card dùng Live Activity)
- `Honoured Basic Word Tracker Scope v5.pdf` (ba ứng dụng: Word, TextEdit, Scrivener; giới hạn 30 giờ)

Milestone 1 và 4 giữ nguyên như bản estimate trước (26 giờ và 27 giờ).

## Hiện trạng đã kiểm tra

| Hạng mục | Hiện trạng | Ảnh hưởng tới estimate |
|---|---|---|
| Live Activity cho contract (V1.1) | Đã có: widget extension, `LiveActivityEngine`, cập nhật tiến độ từ HealthKit | Dùng lại kiến trúc và style, nhưng Oath card cần loại Activity mới và layout mới |
| HealthKit background delivery | Đã có `HealthBackgroundObserver`, `GoalMonitor` | Tiến độ buổi tối trên card làm được, nhưng không có lịch chạy chính xác |
| Mirror dữ liệu sức khỏe | Có bảng `health_daily` (tổng theo ngày) trên Lovable Cloud | Server có thể chấm HONOURED/BROKEN từ dữ liệu này |
| `pg_cron`, `pg_net` | Đã cài trên Lovable Cloud | Chạy job hẹn giờ trên server được |
| Push notification / APNs | **Chưa có gì**: không có `aps-environment`, không lưu device token, không có code gửi APNs | Phải xây từ đầu, đây là phần mới lớn nhất |
| Timezone người dùng | `profiles` không có timezone; `contracts` chưa có lịch Oath | Cần thêm schema để server biết giờ nhắc theo giờ địa phương |
| Deployment target | iOS 16.0 | Push-to-start chỉ có từ iOS 17.2, nên bắt buộc có fallback |

## Milestone 2 - The Oath: 62-68 giờ, đề xuất 65 giờ

So với bản trước (86 giờ): bỏ Wallet pass (khoảng -25 giờ), thêm hạ tầng push, job hẹn giờ trên server và Live Activity khởi chạy từ xa, đồng thời thu gọn thời gian test và polish.

### Phân bổ theo workstream

| # | Workstream | Nơi làm | Giờ |
|---:|---|---|---:|
| 1 | Oath row (chưa đặt / đã đặt), status pill `OATH · UNSIGNED`, bỏ Standing Contract, giữ contract Standing cũ chạy tới hết hạn | Web (Lovable) | 4 |
| 2 | Oath sheet: 7 ngày, chọn thời hạn (quick pick + Custom 2 ngày-1 năm), toggle tùy biến, giờ nhắc sáng/tối, đếm số buổi trực tiếp, Remove Oath, vuốt xuống để hủy | Web | 7-8 |
| 3 | Deadline theo từng ngày Oath, khóa sau khi ký, thoát sớm = AMENDED, danh sách Oath đang chạy | Web + Supabase | 4 |
| 4 | Supabase: bảng lịch Oath, kết quả theo ngày, giờ nhắc, timezone, RLS, đồng bộ web | Supabase | 4-5 |
| 5 | Chấm điểm cuối ngày: so `health_daily` với target, trạng thái chờ khi dữ liệu chưa đồng bộ, đối soát lại, xử lý khi chưa cấp quyền HealthKit | Supabase + iOS | 7 |
| 6 | Hạ tầng push: capability Push Notifications, đăng ký device token và push-to-start token qua bridge, lưu theo tài khoản, xóa khi đăng xuất | iOS + Supabase | 5 |
| 7 | Job hẹn giờ: `pg_cron` + edge function tính giờ nhắc theo timezone, ký JWT APNs, gửi push-to-start hoặc push thường, chống gửi trùng, tách sandbox/production | Supabase | 7-8 |
| 8 | Oath card UI: loại Live Activity mới, layout sáng/tối/kết quả, chữ ký cache trong App Group, vừa giới hạn chiều cao lock screen | iOS widget | 5-6 |
| 9 | Tiến độ buổi tối và kết quả trên card: nhận token cập nhật khi card được start từ xa, cập nhật từ HealthKit background, kết thúc card theo deadline | iOS + Supabase | 5-6 |
| 10 | Affirmation luân phiên theo ngày; fallback push thường cho iOS < 17.2 hoặc người dùng tắt Live Activities; chỉ gửi vào ngày Oath | iOS + Supabase | 3 |
| 11 | Settings: sửa giờ nhắc sau khi ký (ngày, thời hạn, target vẫn khóa) | Web + Supabase | 2 |
| 12 | Recap tuần/tháng với nội dung theo tỷ lệ kết quả | Web | 3 |
| 13 | Test trên iPhone thật, edge case (đổi timezone, DST, cài lại app, đổi tài khoản, tắt Live Activities), polish | Tất cả | 6-7 |
|  | **Tổng** |  | **62-68** |

Mức này nằm trong khoảng 49-70 giờ của scope khách. Phần nặng nhất là workstream 6 (app chưa có push nào) và workstream 7 (job gửi APNs theo timezone từng người dùng). Workstream 13 đã thu gọn còn 6-7 giờ: test trên máy thật tập trung vào luồng chính (push-to-start, fallback push, chấm điểm cuối ngày), còn các edge case như DST hay cài lại app chỉ kiểm tra những trường hợp chính.

### Tính khả thi và điểm cần khách xác nhận

1. **Push-to-start khả thi, nhưng chỉ trên iOS 17.2 trở lên.** Máy iOS 16-17.1 hoặc người dùng tắt Live Activities sẽ nhận push thường, đúng như scope.
2. **Kết quả trên card không bảo đảm hiện đúng lúc deadline.** iOS không cho app chạy đúng giờ, và dữ liệu HealthKit bị khóa khi máy khóa. Đề xuất: server chấm điểm từ `health_daily` sau deadline; nếu dữ liệu chưa đồng bộ thì ngày ở trạng thái chờ, không tự đánh BROKEN. Card hiện kết quả khi có dữ liệu. Nếu không có thì card đóng ở deadline, và kết quả hiện trong app.
3. **Tiến độ buổi tối là best-effort.** Tiến độ cập nhật theo nhịp HealthKit background (thường trễ vài phút tới khoảng một giờ), không realtime. Nếu khách không chấp nhận, bỏ thanh tiến độ sẽ giảm khoảng 3-4 giờ, đúng như scope có ghi "Jimmy to confirm".
4. **Giới hạn thời gian Live Activity.** Một card chỉ hoạt động tối đa 8 giờ. Nếu giờ nhắc tối cách deadline hơn 8 giờ, card sẽ hết hạn trước deadline. Đề xuất giới hạn khoảng cách này trong UI.
5. **Khách cần cung cấp:** APNs Auth Key (.p8), Key ID, Team ID; bật Push Notifications cho App ID. Key được lưu làm secret trên Lovable Cloud, không commit vào repo.
6. **Chỉ làm cho iOS.** Oath card và push không có bản Android trong estimate này.

## Milestone 3 - Basic Word Tracker: 34-38 giờ, đề xuất 36 giờ

### Phân bổ theo workstream

| # | Workstream | Giờ |
|---:|---|---:|
| 1 | Khảo sát kỹ thuật 3 nguồn + ghi chú khả thi cho Pages | 3-4 |
| 2 | Chọn nguồn qua Files picker, security-scoped bookmark, mở lại sau khi file bị đổi tên/di chuyển | 4 |
| 3 | Lõi xác minh: baseline, đếm ròng, quy tắc đếm thống nhất, lưu metadata, sync grace window | 5-6 |
| 4 | Adapter Word (`.docx`: giải nén, đọc XML) + TextEdit (`.txt`, `.rtf`, `.rtfd`) | 4-5 |
| 5 | Adapter Scrivener (`.scriv`: đọc binder `.scrivx`, chỉ cộng thư mục Draft) | 5-6 |
| 6 | Tích hợp Honoured: đơn vị `words` và luồng setup trên web, bridge message mới, cột Supabase, baseline theo từng ngày Oath, trạng thái lỗi | 7-8 |
| 7 | Test edge case và polish | 6 |
|  | **Tổng** | **34-38** |

### Vì sao vượt 30 giờ và cách giữ trong 30 giờ

Bảng của khách (23-30 giờ) chưa tính phần tích hợp phía web và Supabase: đơn vị `words` chưa có trong `target-units.ts`, và cần luồng chọn tài liệu trên màn hình Contract. Bảng đó cũng chưa tính việc nối baseline theo ngày với mô hình Oath của M2.

Để giữ đúng giới hạn 30 giờ, đề xuất: M3 giao Word + TextEdit + lõi + tích hợp Oath, còn Scrivener chỉ làm khảo sát và gửi báo cáo khả thi. Adapter Scrivener tính thêm 6-8 giờ nếu khách muốn làm tiếp. Cấu trúc này đúng với điều khoản "delivered unless a blocker is proven" trong scope.

### Tính khả thi và điểm cần khách xác nhận

1. **Word và TextEdit khả thi.** `.docx` cần thêm một thư viện giải nén ZIP (iOS không có API công khai). `.rtf` đọc được bằng API có sẵn. TextEdit lưu file có ảnh dưới dạng `.rtfd` (là một thư mục) nên phải hỗ trợ riêng.
2. **Scrivener rủi ro cao nhất.** Project là một thư mục gồm nhiều file. Scrivener khuyến cáo không để project trên iCloud Drive, và đồng bộ với iOS của họ dùng Dropbox. Việc mở cả thư mục qua File Provider của Dropbox/OneDrive cần kiểm chứng trên máy thật. Chỉ hỗ trợ định dạng Scrivener 3.
3. **Chỉ xác minh được khi app chạy.** Nội dung không bao giờ rời khỏi máy, nên server không tự đếm được. Nếu người dùng không mở app quanh deadline, ngày đó ở trạng thái chờ. Đề xuất: gửi thông báo tại deadline, "Mở Honoured để xác minh số từ".
4. **Baseline đầu mỗi ngày Oath.** App không chạy lúc 00:00 nên không lấy baseline đúng thời điểm đó được. Đề xuất: baseline là lần đọc cuối trước khi ngày Oath bắt đầu. Nếu file đã bị sửa sau lần đọc đó, dùng lần đọc đầu tiên trong ngày. Cần khách chấp nhận quy tắc này.
5. **Grace window và thời điểm sửa file.** Nếu người dùng tiếp tục viết sau deadline trước khi app kịp đọc, không xác minh được số từ tại deadline. Khi đó dùng lần đọc gần nhất trước deadline.

## Tổng hợp

| Milestone | Bản trước | Bản mới | Đề xuất |
|---:|---:|---:|---:|
| 1 | 26 giờ | không đổi | 26 giờ |
| 2 | 86 giờ | 62-68 giờ | 65 giờ |
| 3 | 36 giờ (1 nguồn) | 34-38 giờ (3 nguồn), hoặc 30 giờ nếu tách Scrivener | 36 giờ |
| 4 | 27 giờ | không đổi | 27 giờ |
|  | **175 giờ** |  | **154 giờ** |

Thứ tự đề xuất: làm M2 trước M3, vì baseline theo từng ngày Oath của Word Tracker dựa vào mô hình Oath của M2.

Estimate không bao gồm: thời gian chờ khách cấp APNs key hoặc tài khoản, App Review, Android, và mọi ứng dụng viết ngoài ba ứng dụng trên.
