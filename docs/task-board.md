# Bảng công việc tích hợp

Bảng task ID: [tasks.md](tasks.md). **Trạng thái hiện tại và phân công tiếp tục:** [bàn giao 15/11/2026](ban-giao-sua-loi-2026-11-15.md). Bảng này thay danh sách khởi tạo chưa cập nhật trước đây.

| Việc | Vai trò | Trạng thái | Còn lại |
| --- | --- | --- | --- |
| Baseline / payload | Cả nhóm | Có code B1–B6 và signing vector | Nghiệm thu chính sách/thể lệ |
| Flutter catalog / merchant | UI | Có demo và workspace ví thật | Ghép UI sản phẩm với API |
| SIWE / metadata / tracking / sync | BE | Có test PostgreSQL/EVM | HTTPS và ví thật |
| Vault / release / refund | Solidity | Có contract/fuzz/live test | Deploy và xác minh Fuji |
| Pending recovery | UI + BE | Có nonce proof/cancel/speed-up | Legacy thiếu nonce đối chiếu riêng |
| Deploy | BE + Solidity | Script, migration0003, readiness | Host/manifest/receipt/CORS thật |
| Yield | Solidity + UI | Hạch toán MOCK | Giữ nhãn đúng, kiểm yêu cầu cuộc thi |
| Browser / CI | BE + UI | Workflow tự dựng môi trường local | Xem Actions đúng head trước merge |
| Camera / native / thiết bị | UI | Chưa nghiệm thu | Chốt Web hoặc làm tiếp |
| Video/slide/bài nộp | Cả nhóm | Chưa xác minh hoàn tất | Bằng chứng thực tế và nộp bài |

Ưu tiên core, phục hồi và triển khai trước tính năng demo mới. Đã test local không đồng nghĩa đã chạy Fuji. Không reset DB/xóa pending chỉ để UI hết chờ.
