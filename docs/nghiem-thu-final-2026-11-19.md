# Nghiệm thu PrePaidGuard ngày 19/11/2026

Web và API đã phát hành mã ứng dụng [`8b4ec38`](https://github.com/vqhung1387/PrePaidGuard_App/commit/8b4ec380cfa65df901f17f677bf000bd40a645c9). Năm workflow CI của mốc này đã qua. Render ghi web `dep-dbut178m7kps73ddh0dg` và API `dep-dbussl6i0phs73bhmm1g` cùng SHA. Khi bàn giao, web, API `/health`, `/ready`, `/api/v1/config` và `/api/v1/plans/1` đều trả HTTP 200. Cấu hình probe trong repo dùng `/health`; `/ready` kiểm PostgreSQL và RPC Fuji. [Web](https://prepaidguard-web.onrender.com/) · [API readiness](https://prepaidguard-api.onrender.com/ready) · [GitHub Actions](https://github.com/vqhung1387/PrePaidGuard_App/actions/runs/44343776881)

## Kết quả kiểm thử

| Môi trường | Kết quả | Bằng chứng |
| --- | --- | --- |
| Chrome, hai phiên tách riêng và hai ví QA, EVM local 31337 | 13/13 bước đạt. Hai vai đăng nhập riêng, cơ sở công bố gói, hội viên đăng ký và ký QR. Cơ sở giải ngân 50 mUSDC, QR cũ bị từ chối, hội viên nhận hoàn 50 mUSDC, gốc còn 0. Kiểm thêm lỗi cache, lệch đồng hồ hai phiên và khôi phục khi hủy giao dịch. | [Báo cáo JSON](evidence/browser-hai-vai-2026-11-19.json) |
| Web Live, Chrome và Core thật trên Fuji 43113 | Ví hội viên đăng nhập và đăng ký gói #1, khóa 100 mUSDC, sau đó hoàn đủ 100 mUSDC khi hết hạn check-in. | [Approve](https://build.avax.network/explorer/fuji/c-chain/tx/0x0ce4fca80639adc723a3e7ec2aa36ca39a4f59a49c41b27ad03feb50e4ab7fb6) · [Subscribe](https://build.avax.network/explorer/fuji/c-chain/tx/0x1c435e24b34e7f72e4278755670c4d20a58bbf001d6a6c4aaa98ee555fac4a2b) · [Refund](https://build.avax.network/explorer/fuji/c-chain/tx/0xbd5c96312dce3c2ea91ab738dd0b995247eaa016b39c5fe7944aa64d693b86eb) |
| iPhone 12 thật, Safari | Mở được web và quét QR đăng ký tới đúng gói #1 giá 100 mUSDC. Người dùng từng gặp timeout 15 giây khi API phản hồi chậm. Bản sửa chờ cấu hình tới 75 giây đã qua ca trì hoãn 25 giây trên WebKit mô phỏng iPhone 12. | Phiên kiểm thử với người dùng và [commit chỉnh timeout](https://github.com/vqhung1387/PrePaidGuard_App/commit/904869d850060e519966f147e271751623921a0d) |
| Core thật, hai vai trên web Live | Core hiện “Scam application” khi tài khoản cơ sở yêu cầu kết nối. Đã dừng trước khi duyệt và gửi tên miền, mã nguồn công khai, địa chỉ Vault Fuji đã xác minh cho Blockaid. Cổng hiện “Report Sent” và chưa hiển thị mã theo dõi. | [Cổng rà soát Blockaid](https://report.blockaid.io/mistake) |

## Việc còn lại

| Ưu tiên | Đầu mối | Tiêu chí hoàn thành |
| --- | --- | --- |
| 1 | UI | Sau khi cảnh báo được xử lý, chạy xuyên suốt bằng hai địa chỉ Core trên web Live. Cơ sở công bố gói có đủ thời gian thao tác. Hội viên đăng ký và ký QR. Cơ sở nhập QR, giải ngân, hội viên hoàn phần còn lại. Lưu receipt và đối chiếu số tiền của hai vai. |
| 2 | UI | Kiểm lại API khởi động chậm trên Safari iPhone 12 thật. Thử chuyển từ link QR sang trình duyệt ví và ký trên điện thoại. Xác nhận ca dùng hai thiết bị vật lý. |
| 3 | BE | Kiểm ngày hết hạn PostgreSQL trên Render. Mốc đã ghi nhận là 16/12/2026. Sao lưu và thử khôi phục vào DB riêng trước mốc hết hạn. |
| 4 | Lead | Rà PR đưa nhánh tích hợp vào `main` sau khi kiểm thử. Kiểm CI và URL bản phát hành sau khi chốt. |

MVP dùng Fuji và mUSDC thử nghiệm. Yield trên Fuji đang `DISABLED`. QR đăng ký đã mở bằng camera hệ thống trên iPhone. Nghiệp vụ check-in hiện hỗ trợ nhập payload. Booking, lịch tập và giờ đông vẫn thuộc phần demo.
