# Phân công khởi đầu

| Công việc | Vai trò | Hạn tương đối | Phụ thuộc | Tiêu chí hoàn thành | Trạng thái |
| --- | --- | --- | --- | --- | --- |
| Chốt luật nghiệp vụ | Cả nhóm | Ngày 1 | Thể lệ cuộc thi | Hoàn thành các quyết định trong business-rules.md | Chưa làm |
| Chốt payload QR và giao diện contract | Cả nhóm | Ngày 1 | Luật nghiệp vụ | Flutter và contract dùng cùng định nghĩa | Chưa làm |
| Khởi tạo Flutter và thử ví/EIP-712 | Frontend | Ngày 2–3 | Payload | Ký được trên thiết bị demo | Chưa làm |
| Khởi tạo API và metadata | Backend | Ngày 2–3 | Mô hình dữ liệu | API đọc/ghi có kiểm tra quyền | Đã triển khai, chờ review tích hợp |
| Tạo gói và đăng ký | Solidity | Ngày 2–3 | Luật nghiệp vụ | Token thử nghiệm vào Vault, đọc được số dư | Chưa làm |
| QR và giải ngân | Frontend + Solidity | Ngày 4–5 | Đăng ký | Quét bằng thiết bị thứ hai; quét lại bị từ chối | Chưa làm |
| Refund và deploy Fuji | Solidity + Backend | Ngày 6–7 | Điều kiện refund | Chạy xuyên suốt trên testnet | Chưa làm |
| Yield mô phỏng | Solidity + Frontend | Ngày 8–9 | Luồng chính | Số liệu khớp contract và ghi rõ mô phỏng | Chưa làm |
| Kiểm thử và chuẩn bị bài nộp | Cả nhóm | Ngày 10–14 | MVP | Demo ổn định, README, video và slide | Chưa làm |

Nếu hết ngày 7 luồng đăng ký → check-in → refund chưa chạy trên testnet thì dừng tính năng mở rộng.
