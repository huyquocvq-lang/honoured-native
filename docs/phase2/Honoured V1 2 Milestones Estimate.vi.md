# HONOURED V1.2 - ĐÁNH GIÁ KHẢ THI VÀ ƯỚC TÍNH TRIỂN KHAI

Tài liệu này là bản estimate kỹ thuật riêng, được lập từ phạm vi trong **Honoured V1.2 Milestone Scope**. Tất cả bốn milestone đều khả thi nếu giữ đúng các giả định và giới hạn phạm vi bên dưới.

## Tổng quan estimate

| Milestone | Phạm vi | Khoảng ước tính | Mức đề xuất |
|---:|---|---:|---:|
| 1 | Settings Handoff + UI Polish + HealthKit Accuracy | 25-27 giờ | 26 giờ |
| 2 | Goals Feature - The Oath | 84-88 giờ | 86 giờ |
| 3 | Basic Word Tracker | 35-37 giờ | 36 giờ |
| 4 | Multi-Activity Calendar | 26-28 giờ | 27 giờ |
|  | **Tổng cộng** | **170-180 giờ** | **175 giờ** |

Estimate đã bao gồm phát triển, tích hợp, xử lý lỗi chính và kiểm thử cho từng milestone. Mức **175 giờ** là con số đề xuất để trao đổi và chia milestone trên Upwork; **170-180 giờ** là khoảng dao động kỹ thuật hợp lý nếu phạm vi không thay đổi.

## Milestone 1 - 25-27 giờ

### Phạm vi

- Hoàn thiện công tắc thông báo, xóa placeholder và thêm xác nhận khi reset.
- Settings dạng accordion/dropdown.
- Làm mượt chữ ký bằng đường cong Bézier.
- Pull-to-refresh trên Home, History và Contract.
- Cho phép chọn nguồn HealthKit và ưu tiên dữ liệu Apple Watch trong cách Honoured truy vấn dữ liệu.

### Phân bổ

| Hạng mục | Estimate |
|---|---:|
| Settings handoff | 3 giờ |
| UI polish | 9-10 giờ |
| HealthKit source selection và fallback | 8-9 giờ |
| Kiểm thử và sửa lỗi | 5 giờ |
| **Tổng** | **25-27 giờ** |

### Điều kiện kỹ thuật

Honoured có thể ưu tiên Apple Watch hoặc nguồn do người dùng chọn khi truy vấn HealthKit, nhưng không thể thay đổi thứ tự ưu tiên nguồn của toàn hệ thống Apple Health. Khi nguồn được chọn không có dữ liệu, ứng dụng cần hiển thị trạng thái phù hợp hoặc dùng quy tắc fallback đã thống nhất.

## Milestone 2 - 84-88 giờ

### Phạm vi

- Tạo goal contract: hoạt động, mục tiêu, thời lượng và lịch ngày thực hiện.
- Commitment gate trước khi ký.
- Lưu goal, lịch và kết quả hằng ngày trên Supabase.
- Tạo Apple Wallet pass có hình ảnh contract và fingerprint signature artwork.
- Cập nhật Wallet pass khi trạng thái contract thay đổi.
- Thông báo buổi sáng và affirmation theo ngày đã lên lịch.
- Xác minh kết quả bằng HealthKit và đánh dấu HONOURED hoặc BROKEN.
- Tổng kết tuần/tháng.
- Thoát sớm chuyển contract sang AMENDED; không cho bỏ qua riêng từng ngày.

### Phân bổ

| Hạng mục | Estimate |
|---|---:|
| Goal UI, schedule model, Supabase và AMENDED flow | 22 giờ |
| Tạo, ký, cài đặt và cập nhật động Wallet pass | 24-26 giờ |
| Morning notification và affirmation schedule | 8-9 giờ |
| HealthKit end-of-day verification | 12-13 giờ |
| Recap tuần/tháng và nội dung theo kết quả | 8 giờ |
| Kiểm thử tích hợp và sửa lỗi | 10 giờ |
| **Tổng** | **84-88 giờ** |

### Điều kiện kỹ thuật

- Wallet pass động cần Pass Type ID, certificate hợp lệ, backend đăng ký pass/device, APNs và endpoint trả về pass đã cập nhật.
- Người dùng vẫn phải xác nhận thêm pass vào Apple Wallet; ứng dụng không thể tự thêm hoàn toàn trong nền.
- `fingerprint signature` trong estimate là artwork/chữ ký hình ảnh được cung cấp hoặc đã có trong hệ thống, không phải ảnh vân tay lấy từ Touch ID.
- HealthKit có thể xác minh dữ liệu của ngày, nhưng iOS không bảo đảm chạy background chính xác lúc 00:00. Nếu dữ liệu chưa đồng bộ hoặc thiết bị đang khóa, kết quả phải ở trạng thái chờ rồi được đối soát lại; không tự đánh dấu BROKEN chỉ vì chưa đọc được dữ liệu.

## Milestone 3 - 35-37 giờ

### Phạm vi đã tính trong estimate

- Hỗ trợ **một nguồn tài liệu** qua Files/iCloud Drive với định dạng văn bản thống nhất, ưu tiên `.txt` hoặc `.md`.
- Người dùng chọn tài liệu gốc cho contract.
- Đọc số từ khi bắt đầu và đọc lại cùng tài liệu khi hoàn thành.
- Tính số từ ròng và trả kết quả HONOURED hoặc BROKEN.
- Chỉ lưu định danh tài liệu, số đếm, thời gian và kết quả; không lưu, upload hoặc log nội dung bản thảo vào Honoured/Supabase.
- Xử lý quyền bị thu hồi, bookmark hết hiệu lực, file bị di chuyển/xóa và tài liệu chưa tải về máy.

### Phân bổ

| Hạng mục | Estimate |
|---|---:|
| Technical spike xác nhận cách truy cập tài liệu | 5 giờ |
| Document picker, quyền truy cập và mở lại tài liệu | 7-8 giờ |
| Word count, baseline, completion và result flow | 10-11 giờ |
| Privacy, error handling, kiểm thử và sửa lỗi | 13 giờ |
| **Tổng** | **35-37 giờ** |

### Điều kiện kỹ thuật

Estimate này không bao gồm việc hỗ trợ mọi ứng dụng viết. Nếu khách chọn Google Docs, Microsoft Word/OneDrive, Pages hoặc một ứng dụng có định dạng/API riêng, cần khảo sát và estimate lại phần tích hợp. Google Docs cần OAuth và Docs API; file `.docx` cần thêm bộ đọc định dạng và quy tắc xác định phần nội dung nào được tính là từ.

## Milestone 4 - 26-28 giờ

### Phạm vi

- Hiển thị nhiều kết quả hoạt động trong cùng một ô ngày bằng các dải màu ngang.
- Giữ số ngày căn giữa và dễ đọc.
- Toàn bộ ô lịch là vùng chạm mở day detail.
- Hiển thị activity, target, result, timestamp, journal hoặc Voice of Change recording.
- Kiểm tra và điều chỉnh schema/query để hỗ trợ nhiều contract của một người dùng trong cùng ngày.

### Phân bổ

| Hạng mục | Estimate |
|---|---:|
| Kiểm tra và điều chỉnh schema/query | 5-6 giờ |
| Calendar bands và touch interaction | 7 giờ |
| Day detail, journal và Voice of Change | 8-9 giờ |
| Kiểm thử và sửa lỗi | 6 giờ |
| **Tổng** | **26-28 giờ** |

## Giả định để giữ tổng trong 170-180 giờ

- Có quyền truy cập source web hiện tại, Supabase project/schema và cấu hình triển khai cần thiết.
- Tái sử dụng design system, contract image, signature artwork, journal và Voice of Change hiện có.
- Chỉ triển khai iOS và phần web/backend cần thiết cho iOS; không bao gồm Android parity.
- Word Tracker chỉ tích hợp một nguồn tài liệu Files/iCloud với định dạng đã thống nhất.
- Không có thay đổi lớn về thiết kế hoặc business rule sau khi bắt đầu.
- Certificate, Apple Developer account, Pass Type ID và quyền APNs được khách cung cấp đúng hạn.
- Kiểm thử HealthKit và Wallet được thực hiện trên iPhone thật; simulator không đủ để xác nhận toàn bộ luồng.

## Ngoài phạm vi estimate này

- Hỗ trợ đồng thời nhiều ứng dụng viết hoặc nhiều cloud provider.
- Android implementation.
- Thời gian chờ certificate, tài khoản, quyền truy cập, khách duyệt hoặc App Review.

## Kết luận

Phạm vi V1.2 có thể triển khai với estimate **170-180 giờ** nếu giữ các giả định trên. Con số nên dùng để lập kế hoạch là **175 giờ**. Bất kỳ yêu cầu nào mở rộng Word Tracker sang Google Docs/Word/Pages, thêm Android hoặc bổ sung các lỗi Dynamic Island cần được estimate thành hạng mục riêng.
