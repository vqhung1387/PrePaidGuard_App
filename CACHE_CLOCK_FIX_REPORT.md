# Báo cáo sửa lỗi cache giao dịch và đồng hồ QR

- Ngày nghiệm thu: 13/11/2026.
- Repo: `D:\HCMUS\PrePaidGuard_App`.
- Nhánh sửa: `codex/cache-clock-fixes`, xuất phát từ local `main@d3c63bb`.
- Bàn giao: cập nhật vào PR #2, nhánh nguồn `codex/integration-fixes`: https://github.com/vqhung1387/PrePaidGuard_App/pull/2.

## 1. Kết luận

Hai lỗi được tái hiện bằng regression test và đã xử lý. Flutter suite đạt **29/29**, analyzer không có issue, build web thành công. Hai lượt browser acceptance đều PASS, với lỗi cache + API tracking đồng thời và độ lệch 60 giây theo hai chiều.

Phạm vi sửa là Flutter real mode và script nghiệm thu. Không cần thay đổi backend hoặc smart contract cho hai lỗi này. Không coi kết quả local là nghiệm thu ví extension thật, hai thiết bị vật lý hoặc Fuji.

## 2. Lỗi mất tx hash khi cache thất bại

### Nguyên nhân

Giao dịch đã broadcast nhưng thao tác lưu pending cache có thể ném lỗi trước khi UI giữ được hash. Lỗi tracking/refresh sau broadcast cũng có thể bị hiển thị như lỗi thao tác chung. Người dùng bấm lại có nguy cơ gửi thêm APPROVE/SUBSCRIBE.

### Thay đổi

- Ghi hash vào bộ nhớ theo đúng ví + deployment trước mọi thao tác cache có thể lỗi.
- Giữ trạng thái SUBMITTED và hash khi cache/API lỗi; hiển thị cảnh báo lưu trữ cạnh hash có thể sao chép.
- BrowserPendingStore không nuốt lỗi đọc thành cache rỗng; tránh ghi đè cache cũ khi không đọc được.
- Chặn retry cùng plan ngay đầu subscribe, trước cả đọc balance/allowance và gửi thêm APPROVE.
- Giữ pending trong cùng controller qua logout/login và xử lý kết quả ví trả về trễ theo đúng origin.
- Tách lỗi tracking/refresh khỏi kết quả broadcast; tiếp tục phục hồi theo hash khi cache/API hoạt động lại.

### Giới hạn cần biết

RAM không phải lưu trữ bền vững. Nếu cache không ghi được, API cũng không nhận được hash và người dùng đóng/tải lại ứng dụng, bộ nhớ dự phòng mất. UI cảnh báo phải lưu hash và kiểm tra ví/explorer trước khi gửi lại. Bản sửa không tuyên bố bảo đảm khôi phục qua reload khi cả hai nơi lưu đều thất bại.

## 3. Lỗi QR bị từ chối khi hai máy lệch giờ

### Nguyên nhân

Deadline lúc ký và kiểm tra dựa vào đồng hồ thiết bị. Máy merchant chạy chậm có thể coi deadline vừa ký trên máy subscriber là quá xa; máy chạy nhanh có thể coi QR hết hạn.

### Thay đổi

- Lấy thời gian từ `eligibility.sync.block_timestamp` mới đọc, yêu cầu `source=LIVE`.
- Kiểm tra chain/Vault của subscription trùng deployment cấu hình.
- Dùng cùng mốc blockchain để tạo deadline và kiểm tra cửa sổ 900 giây; không dùng giờ thiết bị hoặc `synced_at` của API host làm thẩm quyền.
- Kiểm chặt RFC3339, ngày/tháng/năm nhuận, múi giờ và miền Unix seconds được backend/contract hỗ trợ. Không chấp nhận ngày tràn do DateTime tự chuẩn hóa.
- Giữ các kiểm tra nonce, kỳ, domain, chữ ký; contract vẫn quyết định cuối cùng lúc giao dịch được thực thi.

Thiếu thời gian LIVE hoặc timestamp sai sẽ báo lỗi có chủ đích; không fallback sang đồng hồ thiết bị.

## 4. Các phase đã thực hiện

| Phase | Người/agent và vai trò | Kết quả |
| --- | --- | --- |
| Tái hiện và sửa | Agent `fix_cache_clock`, GPT-6.1 Terra high | Regression ban đầu thất bại trên code cũ; sửa controller, UI, browser storage và bổ sung test |
| Review độc lập | Agent `review_cache_clock`, GPT-6 Astra high | Phát hiện lỗi đọc cache bị nuốt và timestamp được DateTime chuẩn hóa; đã sửa và kiểm lại |
| Tích hợp và nghiệm thu | Agent điều phối | Đồng bộ miền timestamp, mở rộng browser harness, chạy Flutter/analyzer/build và E2E thật trên local EVM |
| Bàn giao | Agent điều phối | Ghi báo cáo, giữ nguyên thay đổi để review; tắt dịch vụ test riêng sau nghiệm thu |

## 5. Kết quả kiểm thử

| Kiểm tra | Kết quả |
| --- | --- |
| Regression trên code cũ | Tái hiện lỗi cache write làm mất luồng theo dõi hash và QR dùng đồng hồ thiết bị |
| `flutter test --no-pub` | 29 passed |
| `flutter analyze --no-pub` | No issues found |
| Build web với chain31337/API loopback | PASS; còn warning font CupertinoIcons không chặn build |
| `git diff --check` | PASS |
| E2E merchant -30s / subscriber +30s | PASS, 10 bước |
| E2E merchant +30s / subscriber -30s, build cuối cùng | PASS, 10 bước |

Regression bao gồm lỗi đọc/ghi cache, API outage, retry trước APPROVE, chuyển ví và login lại, clock skew ±60/±7200 giây của thiết bị/API host, timestamp thiếu/sai/PROJECTION, QR quá hạn hoặc deadline quá xa và dữ liệu ngày tháng không hợp lệ.

Mỗi lượt E2E dùng hai browser context độc lập, FastAPI/PostgreSQL thật, contract triển khai trên Hardhat local chain31337:

1. Merchant/subscriber đăng nhập SIWE riêng và publish plan xác nhận thành công.
2. Cố tình làm localStorage ghi thất bại sau broadcast và trả503 cho API tracking SUBSCRIBE.
3. Ghi nhận **3 lần lỗi ghi thực sự**; bấm subscribe lại không tạo thêm giao dịch ví. Số giao dịch ở bước này vẫn là **2: APPROVE + SUBSCRIBE** và chỉ có một subscription.
4. Phục hồi cache/API, refresh và xác nhận giao dịch về CONFIRMED.
5. Ký/render QR, merchant nhập QR và giải ngân dù hai clock cách nhau60giây.
6. QR cũ bị từ chối replay, không có khoản chi thêm.
7. Refund xác nhận; tiền gốc gói100 mUSDC được bảo toàn: giải ngân50, hoàn50, còn0.

Kết quả máy đọc được và ảnh nằm trong các thư mục đã gitignore:

- `validation-results/cache-clock-browser/browser-report.json`
- `validation-results/cache-clock-browser-final/browser-report.json`
- `subscriber-final.png`, `merchant-final.png` trong từng thư mục tương ứng.

Không chạy lại toàn bộ backend/contract unit suite trong lượt sửa này. E2E đã chạy backend/contract thật để xác nhận liên kết hệ thống cho hai lỗi được báo.

## 6. File bàn giao

| File | Nội dung |
| --- | --- |
| `apps/flutter_app/lib/real/controller.dart` | Pending dự phòng, chặn retry, xử lý lỗi sau broadcast, thời gian QR |
| `apps/flutter_app/lib/real/wallet_web.dart` | Truyền lỗi đọc browser storage về controller |
| `apps/flutter_app/lib/real/screen.dart` | Cảnh báo lưu trữ và hash trên UI |
| `apps/flutter_app/test/real_mode_test.dart` | Regression cache/clock |
| `apps/flutter_app/README.md` | Hành vi và giới hạn phục hồi |
| `scripts/browser_acceptance/run.py` | Fault injection, clock skew, kiểm retry/recovery/replay/bảo toàn tiền |
| `scripts/browser_acceptance/README.md` | Điều kiện chạy và lệnh nghiệm thu |

## 7. Chạy lại

Trong `apps/flutter_app`:

```powershell
flutter test --no-pub
flutter analyze --no-pub
flutter build web --no-pub --dart-define=CHAIN_ID=31337 --dart-define=API_BASE_URL=http://127.0.0.1:18000
```

Dựng DB/API/EVM riêng theo điều kiện trong README của browser harness, rồi chạy từ repo root:

```powershell
uv run scripts/browser_acceptance/run.py --browser 'C:/Program Files/Google/Chrome/Application/chrome.exe' --inject-cache-failure --merchant-clock-skew 30 --subscriber-clock-skew -30 --output-dir validation-results/cache-clock-browser-final
```

Đảo hai giá trị skew để kiểm chiều ngược. Script thay đổi trạng thái/time của EVM test; chỉ dùng môi trường thử riêng. Script không tự dựng/tắt dịch vụ.

Môi trường nghiệm thu lượt này dùng PostgreSQL cổng55643/database `prepaidguard_cache_clock_ae850e4e`, EVM8545, API18000 và web18080. Manifest thử ở thư mục temp ngoài Git; không sửa manifest triển khai của nhóm. Sau nghiệm thu tắt các tiến trình do phiên này tạo; giữ artifacts và dữ liệu thử để đối chiếu.

## 8. Việc còn lại trước triển khai thật

- Review diff và merge PR #2 theo quy trình của nhóm.
- Nghiệm thu thêm ví extension thật và môi trường triển khai mục tiêu; kiểm thao tác chép hash/khôi phục sau reload khi storage bị chặn.
- Không tự động gửi lại giao dịch chưa biết kết quả. Khi cả cache/API thất bại sau broadcast, đối chiếu ví/explorer trước khi thao tác lại.