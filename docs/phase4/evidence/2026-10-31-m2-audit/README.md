# Audit M2 (Phase 4), 31/10/2026

Audit lại phần đã làm của M2: SQL `icon_revisions_v1.sql` (đã deploy), native
(chưa commit, TestFlight 1.0.9 (2)) và web (Lovable `1059ffd6`, `58400096`).
Ba agent đọc độc lập từng phần (chỉ có code và tiêu chí nghiệm thu, không có
kết luận trước); mọi điểm được kiểm lại trên code đầy đủ và production (chỉ
đọc) trước khi sửa. Điểm báo sai hoặc quá mức đã bỏ hoặc hạ mức.

## Production lúc audit (chỉ đọc)

- md5 6 hàm M2 trùng lúc deploy 28/10: `contracts_icon_days` `bc7b184a…`,
  `icon_days_to_measure` `889fc89d…`, `icon_push_jobs` `407c6a09…`,
  `record_icon_measurements` `4363134a…`, `revise_icon_target` `80e9f0d1…`,
  `icon_revisions_immutable` `401d66db…`.
- `icon_revisions` bật RLS; `authenticated` chỉ SELECT dòng của mình; anon
  không có quyền; `revise_icon_target` chỉ `authenticated` và `service_role`.
- 0 revision; không ngày nào thiếu target theo ngày; 6 Icon (1 active), mọi
  `primary_target` đúng dạng `<số> <đơn vị>`, mọi `client_id` hợp với regex,
  tỉ lệ `icon_target`/số đã ký khớp; 38 file chữ ký đều có owner = thư mục.

## Đã sửa

| ID | Phần | Lỗi | Mức | Sửa ở |
|---|---|---|---|---|
| B01 | Web | Sau một lần ký ngang, lần "Revise target" sau trên cùng màn: nét đầu biến khung ký thành ảnh, không ký tiếp được | Medium | Lovable `9c43f998` |
| B02 | Native | Danh sách revision chỉ ghi sau khi tải xong ảnh; sync bị ngắt/lỗi thì thẻ ngày sau có thể hiện chữ ký gốc cạnh target mới | Medium | `IconSignatureCache`/`IconSignatureSync`: ghi danh sách trước, ảnh đặt tên theo đường dẫn chữ ký, danh sách đọc lỗi thì không hiện chữ ký; thẻ app tự mở mang `targetRevision` |
| B03 | Native | Tải ảnh lỗi vẫn `synced: true` và chặn sync 15 phút | Medium | `IconSignatureSync`: thiếu ảnh hay không đọc được revision → `false`, không đặt `lastRun` |
| B04 | Web | Sau lỗi mất phản hồi, sửa số/ký lại rồi thử lại: server giữ số cũ hoặc ghép số mới với chữ ký cũ | Low–Medium | Khoá ô nhập, khung ký, Clear khi kết quả chưa rõ (`9c43f998`, ngang: `d8a64d12`) |
| B05 | Web | Hai revision cùng ngày: câu preview ghi sai "Today … keep" | Low | `targetInForceToday` |
| B06 | Web | `save()` chạy lại khi đang lưu; Cancel tra lỗi không refresh/sync; xoá file lỗi bị coi là xong; upload lỗi để lại file rác; flow giữ qua đăng xuất; ngang không có trạng thái lưu/lỗi; fallback cột target tắt nhầm; `removeAllUnder` không chặn prefix rỗng | Low | `9c43f998`, `d8a64d12` |
| B07 | Native | Cache dùng lại ảnh cũ sau rollback rồi deploy lại; đổi tài khoản giữa lúc sync; mọi 404 bị coi là chưa có bảng; lỗi đọc revision chặn cả chữ ký gốc; reply `SYNC_ICON_REVISIONS` không ở main actor; Dynamic Island mở rộng không giới hạn cỡ chữ | Low | generation counter, `PGRST205`/`42P01`, `Task { @MainActor in }`, `.dynamicTypeSize(...xxLarge)` |
| B08 | SQL | `service_role` TRUNCATE được lịch sử; "hôm nay" theo `now()`; chữ ký nhận được file ở thư mục Icon khác hoặc của người khác; nested delete không phải cascade vẫn xoá được; rollback v1 đếm mà không khoá bảng | Low | `icon_revisions_v1_1.sql` + rollback (chưa deploy); khoá bảng trong `icon_revisions_v1_rollback.sql` |

## Chưa sửa (có chủ đích)

| ID | Điểm | Lý do |
|---|---|---|
| B09 | Cùng tài khoản dùng thêm bản app cũ trên máy khác: thẻ do bản cũ tự mở hiện target đã ký (plan §4.3 bước 6) | Không chặn được app cũ; hết khi bản mới lên App Store |
| B10 | Chủ tài khoản ghi đè/xoá được ảnh chữ ký revision của chính mình (policy storage bucket `signatures`) | Sửa policy storage đụng luồng ký đang chạy; để sau (Jimmy đồng ý 31/10) |

## Kiểm tra đã chạy

- SQL: `docs/db/tests/icon_revisions_v1/run.sh` trên Postgres 17.6 local
  (embedded), 243 check, ALL STEPS PASSED (`sql-icon-revisions-v1-1-tests.log`).
  Pass 3 mới: v1.1 trên v1 với default privileges của Supabase (mọi check v1
  vẫn đúng + 25 check v1.1 + rollback v1.1 + rollback v1 sau v1.1). Pass 4 mới:
  rollback v1 trong lúc một revision đang commit; mutation test (bỏ dòng khoá)
  làm Pass 4 fail như mong đợi.
- md5 sau v1.1 (để so khi deploy): `revise_icon_target`
  `aca7ea9cee15c372aa2f0c9b9787f280`, `icon_revisions_immutable`
  `aaa8d362ce4f89601261e219c7864e31`.
- Native: `HonouredTests` 288 test, 0 fail (`honouredtests.txt`, có
  `IconSignatureCacheTests` mới chạy trên thư mục tạm); build Debug/Release
  simulator (`builds.txt`); BridgeStub `icon-revisions` 2/2, `icon-card` 6/6,
  `icon-card-end` 1/1 (`stub-*.log`).
- Web: Lovable báo type check sạch, Vitest 61 file, 827 pass (chạy 2 lần ở
  `d8a64d12`; một lần chạy ở `9c43f998` có 1 fail không tên, 3 lần sau pass).
  Chưa kiểm trên trình duyệt hay máy thật.

## Phát hành (Jimmy duyệt 31/10)

- Web: Lovable `d8a64d12` published (deployment
  `7109cd4f-4145-4e05-92d0-c6a24509a73b`); bundle `routes-CCJQQ5Pg.js` có code
  mới; trang production 0 lỗi/cảnh báo console.
- TestFlight 1.0.9 (3) upload 19:43, Apple đang xử lý
  (`testflight-1.0.9-3.txt`); gồm cả bố cục Lock Screen khách yêu cầu 31/10.

## Chưa làm

- Deploy `icon_revisions_v1_1.sql`: sau khi khách test xong M2 (đã thống nhất).
- Thiết bị thật: không kiểm được trên simulator (thẻ push, App Group thật,
  Lock Screen/Dynamic Island chữ lớn).
