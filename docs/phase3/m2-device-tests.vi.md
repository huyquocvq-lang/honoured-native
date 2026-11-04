# M2: test trên iPhone thật

Checklist cho phần Core Motion, chọn nguồn và diagnostics của M2
(`docs/phase3/core-motion-plan.vi.md`, mục "Trạng thái M2"). Mỗi bài chỉ cần đi
100–150 bước. Phần thời gian còn lại là khóa máy hoặc chờ.

## Chuẩn bị

1. Cài bản Debug hoặc Release từ Xcode lên iPhone, có ký và có entitlement
   HealthKit. Simulator không có pedometer.
2. Đăng nhập tài khoản dev (huyrambo2k).
3. Web:
   - Bản đã publish vẫn hiện mục "Core Motion", vì danh sách lấy từ
     native. Chọn mục này thì native tự hỏi quyền Motion sau khi trả lời.
   - Muốn test luồng mới (xin quyền trước khi lưu, các thông báo, dòng calo ước
     tính, số live và dòng nguồn trên Home), trỏ `HONOURED_WEB_APP_URL` vào URL
     preview của Lovable, hoặc publish trước.
4. Tạo contract bước chân với target = tổng bước hôm nay + 100. Web nhận số
   nguyên bất kỳ tới 50.000.
5. Settings › Health › Steps & distance source → "Core Motion" → cho
   phép Motion & Fitness.
6. Mỗi bài: quay màn hình, và ghi lại Honoured đang mở hay ở nền (đã bấm Home)
   khi bắt đầu.

## Các bài

| # | Tình huống | Làm | Kỳ vọng |
|---|---|---|---|
| M2-1 | Honoured đang mở (T1) | Để Home mở, đi khoảng 150 bước | Số bước trên Home và thẻ contract tăng sau mỗi vài giây khi đi. Dưới "Health · Updated…" có dòng "Steps & distance · Core Motion". Màn chúc mừng hiện trong vài giây, Live Activity đổi số. Diagnostics: `goal_detected` với trigger `motion_live`, `goal_crossed` với method `motion_live`. |
| M2-2 | Ở nền, chưa khóa (T2) | Bấm Home, đi 150 bước, rồi mở lại Honoured | Không có gì trước khi mở app (Core Motion không đánh thức được app). Mở app thì báo đạt ngay (trigger `live_start`) và Home hiện số mới. |
| M2-3 | Ở nền, khóa máy | Bấm Home, khóa máy, đi 150 bước, mở khóa, chờ 2 phút rồi mới mở Honoured | Ghi lại notification có tới không, tới lúc nào. Đối chiếu bản quay với timeline diagnostics. |
| M2-4 | Chỉ đeo Watch (T7) | iPhone để trên bàn, đi 150 bước | Số Core Motion không tăng, không báo đạt. Đổi sang "Automatic" thì bước của Watch được tính sau khi Health sync. |
| M2-5 | Watch và iPhone (T8) | Mang cả hai, đi 150 bước | Home hiện số của Core Motion. Số không bị cộng với Watch. |
| M2-6 | Đổi nguồn khi chưa đạt | Core Motion → Apple Health → Core Motion | Lưu xong là thẻ contract bỏ số live của nguồn cũ. Quay lại Home thì số và dòng nguồn đổi theo nguồn mới. Không có `GOAL_REACHED` nào. |
| M2-7 | Đổi nguồn sau khi đạt | Đạt bằng Core Motion, rồi đổi sang Apple Health (số thấp hơn) | Không có notification hay màn chúc mừng lần hai. Contract vẫn HONOURED. |
| M2-8 | Tắt quyền Motion | Settings iOS › Privacy & Security › Motion & Fitness › tắt Honoured, rồi mở lại app | Settings › Health báo Motion bị tắt (bản web mới, có nút Open Settings). Số chuyển về Apple Health. |
| M2-9 | Đổi giờ reset | Đổi Daily reset hour khi app đang mở | Đếm lại từ đầu ngày mới; goal còn đạt chỉ được báo một lần, trong app. |
| M2-10 | Đổi tài khoản | Đăng xuất, đăng nhập tài khoản khác | Diagnostics trên máy bị xoá. Đếm live dừng nếu tài khoản mới không có goal bước chân. Thẻ contract của tài khoản mới không hiện số live của tài khoản cũ. |

## Xem diagnostics

Dòng diagnostics được upload sau mỗi lượt sync, hoặc khi mở app. Chạy được qua
Lovable `query_database` (vai trò `postgres`):

```sql
select event, certainty, occurred_at, window_start, window_end, method, reason,
       source, value, target, details
from public.goal_diagnostics
where user_id = (select id from auth.users where email = 'huyrambo2k@gmail.com')
order by coalesce(occurred_at, window_start), event;
```

`goal_diagnostics_timeline()` dùng `auth.uid()`, nên phải gọi trong vai trò
người dùng. Khối dưới đây trả timeline qua thông báo lỗi; lỗi đó cũng rollback
mọi thứ, nên không để lại gì:

```sql
do $$
declare uid uuid := (select id from auth.users where email = 'huyrambo2k@gmail.com'); t text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', uid::text, true);
  set local role authenticated;
  select string_agg(row_to_json(x)::text, E'\n') into t from public.goal_diagnostics_timeline(current_date - 1, current_date) x;
  raise exception E'TIMELINE\n%', t;
end $$;
```

## Ghi lại

- Thiết bị, phiên bản iOS, Low Power Mode bật hay tắt.
- Mỗi bài: giờ bắt đầu, Honoured đang mở hay ở nền, giờ notification hiện (theo
  bản quay), và dòng timeline tương ứng.
- Lưu bằng chứng vào `docs/phase3/evidence/<ngày>-m2/`.
