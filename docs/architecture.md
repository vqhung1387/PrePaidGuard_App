# Kiến trúc dự kiến

Flutter → FastAPI → PostgreSQL: metadata và hồ sơ.

Flutter → ví người dùng → Avalanche → PrepaidVault: ký quỹ, check-in, giải ngân và refund.

FastAPI → Avalanche: đọc dữ liệu và xác minh giao dịch khi cần.

Contract là nguồn dữ liệu chuẩn về tiền và trạng thái tài chính. Nếu database lưu bản sao, phải có thể đối chiếu hoặc dựng lại từ blockchain.

Ký không tốn gas không đồng nghĩa với offline. POS mất mạng chỉ báo ghi nhận tạm. Chỉ báo thanh toán thành công khi giao dịch được xác nhận.
