# M3 Word Tracker: checklist test trên iPhone thật

Những phần simulator không kiểm được: nhà cung cấp file thật (iCloud Drive, Dropbox, OneDrive), file do Word/TextEdit/Scrivener lưu thật, thùng rác của Files, mạng chập chờn và giờ chốt thật. Mục A4 quyết định Scrivener có blocker hay không, nên làm trước.

## Chuẩn bị

- Bản build có ký (signed) của app, đăng nhập một tài khoản test không có Icon nào đang chạy.
- Trên iPhone: Files đã thêm iCloud Drive, Dropbox và OneDrive; cài Word cho iPhone. Trên Mac: Word, TextEdit, Scrivener 3, Dropbox.
- Mỗi lần kiểm tra, đối chiếu DB (Lovable `query_database`):

```sql
select d.day, d.status, d.resolution, d.word_baseline, d.word_latest_count,
       d.word_progress, d.word_latest_at, d.deadline_at
from icon_days d join contracts c on c.id = d.contract_id
where c.client_id = '<client id của Icon>' order by d.day;
```

- Tạo Icon "Writing · 100 words" gồm hôm nay và ngày mai; hạn chốt mặc định 00:00.

## A. Nguồn file qua nhà cung cấp thật

| # | Thao tác | Kỳ vọng |
|---|---|---|
| A1 | `.docx` trong iCloud Drive, viết bằng Word trên Mac. Chọn nguồn, ký, Check now. Thêm đúng 500 từ trên Mac, chờ đồng bộ, Check now | Mốc = số từ ban đầu; sau đó +500 |
| A2 | `.docx` trong OneDrive, sửa bằng Word trên iPhone | Như A1 |
| A3 | `.txt`, `.rtf`, `.rtfd` (có ảnh) do TextEdit trên Mac lưu vào iCloud Drive | Như A1 cho cả ba |
| A4 | Project Scrivener 3 trong `Dropbox/Apps/Scrivener`. Mở picker từ Dropbox | Project hiện là **một mục** và chọn được. Không chọn được hoặc báo lỗi quyền → đây là blocker phải báo khách kèm ước lượng giờ |
| A5 | Tiếp A4: thêm 500 từ vào một tài liệu trong Draft trên Mac, đồng bộ Dropbox; sửa một tài liệu Research | Chỉ +500; phần Research không làm thay đổi số |
| A6 | Project chỉ lưu cục bộ trong Scrivener cho iPhone (nếu xuất hiện trong Files) | Ghi lại có chọn được không |

## B. Danh tính file và lỗi

| # | Thao tác | Kỳ vọng |
|---|---|---|
| B1 | Đổi tên rồi chuyển file sang thư mục khác trong Files | Vẫn đọc được, `source_id` không đổi |
| B2 | Xoá file trong Files rồi Check now; sau đó vào Recently Deleted → Recover | Nút Reconnect + "Reconnect the same source to keep this Icon."; sau Recover đọc lại được mà không cần chọn lại |
| B3 | Duplicate tài liệu, chỉ sửa bản sao | Số của nguồn đang theo dõi không đổi |
| B4 | Hai file trùng tên ở hai thư mục, sửa file không được chọn | Không ảnh hưởng |
| B5 | Thu hồi quyền: đăng xuất Dropbox/OneDrive trong app của họ, hoặc tắt nhà cung cấp trong Files | Báo lỗi và hiện Reconnect, ngày **không** bị chấm BROKEN ngay |
| B6 | Bật chế độ máy bay khi file iCloud chưa tải về, rồi Check now | Báo lỗi thử lại; bật mạng lại thì đọc được |

## C. Giờ chốt

| # | Thao tác | Kỳ vọng |
|---|---|---|
| C1 | Viết trên Mac tới 23:50 cho đủ mục tiêu; **không mở** Honoured; mở lúc 00:10 | Ngày hôm trước được tính (khoảng ân hạn 30 phút); `word_latest_at` sau 00:00 nhưng ngày vẫn HONOURED |
| C2 | Viết tiếp sau 00:00, mở Honoured lúc 00:15 | Ngày hôm trước dùng lần đọc cuối trước giờ chốt, không được cộng phần viết sau 00:00 |
| C3 | Sáng hôm sau mở Honoured **trước khi viết** | Mốc của ngày mới = số đọc được (chính xác vì file chưa sửa từ 00:00) |
| C4 | Để app ở nền tới 23:30 | Reminder "Open Honoured to check your words before the cut-off." hiện ra; bấm vào chỉ mở app |
| C5 | Một ngày không mở app lần nào | Sau 24 giờ: BROKEN, `resolution = word_unverified`, web hiện "No usable reading before the cut-off." |

## D. Độ bền

- Tắt hẳn app rồi mở lại; khởi động lại iPhone; cài bản build mới đè lên → nguồn và mốc vẫn giữ nguyên.
- Bản thảo khoảng 150.000 từ: ghi lại thời gian từ lúc bấm Check now tới khi có số.
- Tài liệu nhiều ngôn ngữ (Việt, Nhật, Hàn, Ả Rập): số đếm khớp quy tắc trong tài liệu Word Tracker Counting Rules.

## E. Quyền riêng tư

- Mở Console.app trên Mac, lọc theo process Honoured trong lúc Check now: không có câu chữ, tên file hay đường dẫn nào.
- Bảng `word_source_readings` và `icon_days` chỉ chứa số, thời điểm và id.

## Ghi kết quả

Mỗi mục ghi: Pass/Fail, thiết bị và phiên bản iOS, nhà cung cấp file, ảnh chụp màn hình, và kết quả truy vấn DB. Nếu A4 hoặc A5 thất bại, viết báo cáo blocker cho khách trước khi nghiệm thu M3.
