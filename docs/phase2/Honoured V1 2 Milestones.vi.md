# HONOURED

## PHẠM VI CÁC MILESTONE V1.2

Dùng để trao đổi với Jimmy - lập tháng 9/2026

*Ký cam kết. Giữ lời. Trở thành điều bạn cam kết.*

| Milestone | Mô tả | Số giờ ước tính |
|---:|---|---:|
| 1 | Bàn giao phần Cài đặt + Hoàn thiện UI + Độ chính xác HealthKit | 23 giờ |
| 2 | Phạm vi tính năng Goals - The Oath | 55 giờ |
| 3 | Basic Word Tracker (Trình theo dõi số từ cơ bản) | 30 giờ |
| 4 | Multi-Activity Calendar (Lịch đa hoạt động) | 25 giờ |
|  | **Tổng cộng** | **133 giờ** |

## Milestone 1 - 23 giờ

Gộp ba hạng mục nhỏ - những phần có thể hoàn thành nhanh để khởi động sprint gọn gàng.

- **Bàn giao phần Cài đặt** - hoàn thiện tương tác cho công tắc thông báo, xóa văn bản giữ chỗ và thêm hộp thoại xác nhận khi đặt lại. (2-3 giờ)
- **Hoàn thiện UI** - cài đặt dạng accordion/dropdown, làm mượt chữ ký bằng đường cong Bézier và thêm thao tác kéo để làm mới trên các màn hình Home, History và Contract. (7-12 giờ)
- **Độ chính xác HealthKit** - ưu tiên Apple Watch làm nguồn dữ liệu thay cho iPhone và cho phép người dùng chọn nguồn dữ liệu trong Settings. (4-8 giờ)

## Milestone 2 - 55 giờ

**The Oath** - tính năng lớn nhất trong V1.2. Đây là các goal contract được lên lịch, có Apple Wallet pass và được HealthKit xác minh.

- **UI tạo goal** - bộ chọn hoạt động, mục tiêu dạng số, thời lượng và bộ chọn ngày theo phong cách báo thức của Apple.
- **Apple Wallet pass (`.pkpass`)** - được tạo khi ký contract, chứa hình ảnh contract và chữ ký vân tay (*fingerprint signature*), đồng thời được cập nhật động.
- **Hệ thống thông báo** - công tắc bật/tắt thông báo buổi sáng cùng bộ chọn giờ, các câu khẳng định tích cực luân phiên mỗi ngày và chỉ kích hoạt vào những ngày đã lên lịch.
- **Bước xác nhận cam kết** - hiển thị thông báo: "Bạn đang cam kết hoàn thành X buổi. Hãy đảm bảo mục tiêu này khả thi." Người dùng chọn Xác nhận hoặc Hủy bỏ.
- **Xác minh cuối ngày bằng HealthKit** - lấy chỉ số, so sánh với mục tiêu và đóng dấu **HONOURED** hoặc **BROKEN**.
- **Tổng kết tuần/tháng** - thông điệp điều chỉnh theo kết quả. Tuần tốt: "Bạn đã làm rất xuất sắc." Tuần khó khăn: "Hãy dùng tuần trước làm mồi lửa để nhóm lên ngọn lửa mới."
- **Supabase** - lưu goal, lịch thực hiện và kết quả hằng ngày.
- **Thoát sớm được đánh dấu AMENDED** - không cho phép bỏ qua riêng từng ngày.

## Milestone 3 - 30 giờ

**Basic Word Tracker (Trình theo dõi số từ cơ bản)** - dành cho gói Standard. Theo dõi số từ ròng, bảo vệ quyền riêng tư và cung cấp bằng chứng cho cam kết viết.

- Người dùng chọn một tài liệu viết được hỗ trợ để dùng cho contract.
- Ghi lại số từ ban đầu và kiểm tra lại khi hoàn thành.
- Tính tiến độ ròng: số từ hiện tại trừ số từ ban đầu.
- Trả kết quả đã xác minh về Honoured và đánh dấu contract là **HONOURED** hoặc **BROKEN**.
- **Quyền riêng tư:** không lưu trữ, tải lên hoặc ghi log nội dung bản thảo.
- Xử lý hợp lý các trường hợp không có quyền truy cập, thiếu tài liệu hoặc ứng dụng không khả dụng.
- Phải khảo sát kỹ thuật ứng dụng viết dự kiến tích hợp trước khi cam kết triển khai.

## Milestone 4 - 25 giờ

**Multi-Activity Calendar (Lịch đa hoạt động)** - hiển thị theo các dải ngang và mở chi tiết đầy đủ của ngày khi chạm.

- Mỗi kết quả hoạt động được hiển thị thành một dải màu ngang trong ô lịch; các dải có chiều cao bằng nhau và chiếm toàn bộ chiều rộng.
- Giữ nguyên màu sắc: xanh lá (**HONOURED**), đỏ (**BROKEN**) và hổ phách (**AMENDED**).
- Số ngày được căn giữa bằng màu trắng trên tất cả các dải và luôn dễ đọc.
- Toàn bộ ô lịch là một vùng chạm lớn; chạm vào bất kỳ vị trí nào để mở bảng chi tiết của ngày.
- Các dải chỉ cung cấp thông tin, không phải từng vùng chạm riêng biệt. Không yêu cầu người dùng chạm vào các dải quá mỏng.
- Bảng chi tiết của ngày hiển thị: tên hoạt động, mục tiêu, kết quả, dấu thời gian, ghi chú nhật ký hoặc bản ghi **Voice of Change**.
- Trước khi triển khai, cần xác nhận schema Supabase hỗ trợ nhiều bản ghi contract cho mỗi người dùng trong cùng một ngày.

---

Đây là cấu trúc milestone dạng nháp để trao đổi với Jimmy. Số giờ chỉ là ước tính - cần xác nhận với Jimmy trước khi chốt các milestone trên Upwork. Mỗi milestone đều có tài liệu phạm vi tính năng đầy đủ.
