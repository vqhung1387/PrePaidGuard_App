# Nghiệm thu PrePaidGuard ngày 19/11/2026

Render đã phát hành web [`bef1666`](https://dashboard.render.com/static/srv-dbtcnqjncjis739sldgg/deploys/dep-dbuu9ue1egvs739mag30). Cả năm workflow của mốc tích hợp đã qua. Khi kiểm lại, web và API `/health`, `/ready`, `/api/v1/config`, `/api/v1/plans/1` đều trả HTTP 200. Probe dùng `/health`. Endpoint `/ready` kiểm PostgreSQL và RPC Fuji. [Web](https://prepaidguard-web.onrender.com/) · [API readiness](https://prepaidguard-api.onrender.com/ready) · [CI tích hợp](https://github.com/vqhung1387/PrePaidGuard_App/actions/runs/44361939438)

Ngay sau deploy, trang HTML mới từng đi cùng giao diện cũ. Lần kiểm lại lấy được cùng SHA-256 từ URL bundle chuẩn và URL có tham số phiên bản. Hai phiên trình duyệt mới, Chrome desktop và WebKit giả lập iPhone 12, đều tải giao diện mới, mở màn cơ sở, xem điều khoản chưa kết nối ví và mở đúng QR gói #1 tổng 100 mUSDC. Render trả `s-maxage=300` cho bundle. Lần phát hành sau cần xác minh giao diện thật từ phiên mới bên cạnh trạng thái Live.

## Bản tích hợp UI mới

Nhánh tích hợp đã gộp [`fc5917f`](https://github.com/vqhung1387/PrePaidGuard_App/commit/fc5917f48f1091ae52017c300f9a31d44273a275) vào mốc kiểm thử chung. Bản này tách màn hội viên và cơ sở, mở catalog thật từ trang chủ để khách xem điều khoản trước khi kết nối ví, và chặn ký trùng từ hai tab. Link mời demo cũ mở workspace thật. Git xác nhận mã ứng dụng, API, contract, cấu hình và script kiểm thử sau khi gộp trùng với bản `fc5917f` đã kiểm thử.

Flutter analyze và build Web đạt, 121/121 test Flutter và 16/16 bước Chrome local đạt. Bộ Chrome kiểm khách ở viewport mobile, hai ví riêng, cùng ví trên hai tab, tạo gói, đăng ký, ký QR, giải ngân 50 mUSDC, hoàn 50 mUSDC, từ chối dùng lại QR và phục hồi sau khi hủy giao dịch. [Báo cáo Chrome local](evidence/browser-ui-fc5917f-2026-11-19.json) · [CI Flutter](https://github.com/vqhung1387/PrePaidGuard_App/actions/runs/44360667461) · [CI trình duyệt](https://github.com/vqhung1387/PrePaidGuard_App/actions/runs/44360665046)

## Kết quả kiểm thử

Các giao dịch Core và lần quét QR trên iPhone thật trong bảng dưới đây thuộc đợt nghiệm thu web `8b4ec38`.

| Môi trường | Kết quả | Bằng chứng |
| --- | --- | --- |
| Chrome, hai phiên tách riêng và hai ví QA, EVM local 31337 | 13/13 bước đạt. Hai vai đăng nhập riêng, cơ sở công bố gói, hội viên đăng ký và ký QR. Cơ sở giải ngân 50 mUSDC, QR cũ bị từ chối, hội viên nhận hoàn 50 mUSDC, gốc còn 0. Kiểm thêm lỗi cache, lệch đồng hồ hai phiên và khôi phục khi hủy giao dịch. | [Báo cáo JSON](evidence/browser-hai-vai-2026-11-19.json) |
| Web Live, Chrome và Core thật trên Fuji 43113 | Ví hội viên đăng nhập và đăng ký gói #1, khóa 100 mUSDC, sau đó hoàn đủ 100 mUSDC khi hết hạn check-in. | [Approve](https://build.avax.network/explorer/fuji/c-chain/tx/0x0ce4fca80639adc723a3e7ec2aa36ca39a4f59a49c41b27ad03feb50e4ab7fb6) · [Subscribe](https://build.avax.network/explorer/fuji/c-chain/tx/0x1c435e24b34e7f72e4278755670c4d20a58bbf001d6a6c4aaa98ee555fac4a2b) · [Refund](https://build.avax.network/explorer/fuji/c-chain/tx/0xbd5c96312dce3c2ea91ab738dd0b995247eaa016b39c5fe7944aa64d693b86eb) |
| iPhone 12 thật, Safari | Mở được web và quét QR đăng ký tới đúng gói #1 giá 100 mUSDC. Người dùng từng gặp timeout 15 giây khi API phản hồi chậm. Bản sửa chờ cấu hình tới 75 giây đã qua ca trì hoãn 25 giây trên WebKit mô phỏng iPhone 12. | Phiên kiểm thử với người dùng và [commit chỉnh timeout](https://github.com/vqhung1387/PrePaidGuard_App/commit/904869d850060e519966f147e271751623921a0d) |
| Core thật, hai vai trên web Live | Core hiện “Scam application” khi tài khoản cơ sở yêu cầu kết nối. Đã dừng trước khi duyệt và gửi tên miền, mã nguồn công khai, địa chỉ Vault Fuji đã xác minh cho Blockaid. Cổng hiện “Report Sent” và chưa hiển thị mã theo dõi. | [Cổng rà soát Blockaid](https://report.blockaid.io/mistake) |

## Việc còn lại

| Ưu tiên | Đầu mối | Tiêu chí hoàn thành |
| --- | --- | --- |
| 1 | BE | Render xác nhận PostgreSQL Free hết hạn 16/12/2026, vô hiệu hóa Export và chặn toàn bộ kết nối ngoài. Chờ duyệt quyền kết nối tạm từ đúng một IP hoặc thực hiện từ một dịch vụ đã có quyền truy cập nội bộ. Tạo dump bằng TLS, thử khôi phục vào DB rỗng riêng rồi thu hồi quyền tạm. [Recovery](https://dashboard.render.com/d/dpg-dbt6srtg1s2s738umi0g-a/recovery) |
| 2 | Lead | [PR #4](https://github.com/vqhung1387/PrePaidGuard_App/pull/4) đã mở vào `main`. GitHub yêu cầu một review chấp thuận trước khi gộp. Kiểm CI của HEAD sau khi merge. |
| 3 | UI | Sau khi cảnh báo Core được xử lý, chạy xuyên suốt bằng hai địa chỉ Core trên web Live. Cơ sở công bố gói có đủ thời gian thao tác. Hội viên đăng ký và ký QR. Cơ sở nhập QR, giải ngân, hội viên hoàn phần còn lại. Lưu receipt và đối chiếu số tiền của hai vai. |
| 4 | UI | Kiểm lại API khởi động chậm trên Safari iPhone 12 thật. Thử chuyển từ link QR sang trình duyệt ví và ký trên điện thoại. Xác nhận ca dùng hai thiết bị vật lý và hỗ trợ khóa ký của trình duyệt ví. |

MVP dùng Fuji và mUSDC thử nghiệm. Yield trên Fuji đang `DISABLED`. QR đăng ký đã mở bằng camera hệ thống trên iPhone. Nghiệp vụ check-in hiện hỗ trợ nhập payload. Booking, lịch tập và giờ đông vẫn thuộc phần demo.
