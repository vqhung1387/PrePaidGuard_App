# Bảng công việc tích hợp

Bảng task ID: [tasks.md](tasks.md). **Trạng thái hiện tại và phân công tiếp tục:** [bàn giao 15/11/2026](ban-giao-sua-loi-2026-11-15.md). Bảng này thay danh sách khởi tạo chưa cập nhật trước đây.

**Giao việc:** [mỗi task một đầu mối và D1–D10 cần thống nhất](phan-vai-va-diem-can-thong-nhat.md). Các nhãn chung trong bảng này chỉ mô tả giao điểm; không giao đồng thời một task cho hai role.

| Việc | Vai trò | Trạng thái | Còn lại |
| --- | --- | --- | --- |
| Baseline luật tiền / signing | C — Solidity chuẩn bị | Có code B1–B6 và signing vector | Nhóm chốt D3/D4; C không tự đổi chính sách |
| Flutter catalog / merchant | UI | Có demo và workspace ví thật | Ghép UI sản phẩm với API |
| SIWE / metadata / tracking / sync | BE | Có test PostgreSQL/EVM | HTTPS và ví thật |
| Vault / release / refund | Solidity | Có contract/fuzz/live test | Deploy và xác minh Fuji |
| Recovery API | B — BE (B-RECOVERY) | Có nonce proof/cancel/speed-up | Test API/reorg; mất cả nonce/raw cần người giữ ví tìm bằng chứng |
| Recovery UI | A — UI (A-RECOVERY) | Có luồng đối chiếu hash/raw | Nghiệm thu UX bằng extension thật |
| Deploy contract | C — Solidity (C-FUJI) | Có script/contract tests | Gas/receipt/manifest/ABI Fuji thật |
| Host API/DB | B — BE (B-HOST) | Migration0003/readiness | Nhận manifest từ C; host HTTPS/AUTH/CORS |
| Build/host app | A — UI (A-RELEASE) | Có cấu hình pin/API | Nhận URL từ B và manifest từ C; phát hành Web |
| Yield contract | C — Solidity (C-YIELD) | Hạch toán MOCK | Nhóm chốt D3; bàn giao mode/event |
| Yield UI | A — UI (A-YIELD) | Core đọc DTO hiện có | Giữ nhãn đúng theo mode từ API/contract |
| Browser / CI tích hợp | B — BE (B-E2E) | Workflow tự dựng môi trường local | A cung cấp locator mới, C cung cấp ABI; xem Actions đúng head |
| Camera / native / thiết bị | UI | Chưa nghiệm thu | Chốt Web hoặc làm tiếp |
| Video/slide/bài nộp | Một người nhóm chọn ở D10 | Chưa xác minh hoàn tất | A/B/C cung cấp đầu vào; một người xác nhận nộp |

Ưu tiên core, phục hồi và triển khai trước tính năng demo mới. Đã test local không đồng nghĩa đã chạy Fuji. Không reset DB/xóa pending chỉ để UI hết chờ.
