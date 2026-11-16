# Bảng công việc tích hợp

Bảng task ID: [tasks.md](tasks.md). **Trạng thái triển khai mới nhất:** [Fuji/API và bằng chứng 16/11/2026](fuji-deployment-2026-11-16.md). Phân vai nền: [bàn giao 15/11/2026](ban-giao-sua-loi-2026-11-15.md).

**Giao việc:** [mỗi task một đầu mối và D1–D10 cần thống nhất](phan-vai-va-diem-can-thong-nhat.md). Các nhãn chung trong bảng này chỉ mô tả giao điểm; không giao đồng thời một task cho hai role.

| Việc | Vai trò | Trạng thái | Còn lại |
| --- | --- | --- | --- |
| Baseline luật tiền / signing | C — Solidity chuẩn bị | Có code B1–B6 và signing vector | Nhóm chốt D3/D4; C không tự đổi chính sách |
| Flutter catalog / merchant | UI | Có demo và workspace ví thật | Ghép UI sản phẩm với API |
| SIWE / metadata / tracking / sync | BE | PASS trên API HTTPS/DB Render/Vault Fuji thật | Nối origin web và nghiệm thu extension UI |
| Vault / release / refund | Solidity | Fuji DISABLED, Sourcify exact match; release/refund/replay PASS | Review bundle và nghiệm thu UI trên thiết bị |
| Recovery API | B — BE (B-RECOVERY) | Có nonce proof/cancel/speed-up | Test API/reorg; mất cả nonce/raw cần người giữ ví tìm bằng chứng |
| Recovery UI | A — UI (A-RECOVERY) | Có luồng đối chiếu hash/raw | Nghiệm thu UX bằng extension thật |
| Deploy contract | C — Solidity (C-FUJI) | Đã deploy/verify/seed Fuji, có receipt/manifest | Review bằng chứng; không deploy lại để sửa UI |
| Host API/DB | B — BE (B-HOST) | HTTPS Live, migration0003 và /ready200 | AUTH/CORS theo origin UI; đổi healthCheckPath Render sang /ready |
| Build/host app | A — UI (A-RELEASE) | API/manifest Fuji đã được bàn giao | Build pin đúng bundle, phát hành Web và gửi origin cho BE |
| Yield contract | C — Solidity (C-YIELD) | Hạch toán MOCK | Nhóm chốt D3; bàn giao mode/event |
| Yield UI | A — UI (A-YIELD) | Core đọc DTO hiện có | Giữ nhãn đúng theo mode từ API/contract |
| Browser / CI tích hợp | B — BE (B-E2E) | 84 test BE + browser local; luồng API Fuji thật PASS | Xem Actions đúng head; kiểm UI bằng ví extension/thiết bị thật |
| Camera / native / thiết bị | UI | Chưa nghiệm thu | Chốt Web hoặc làm tiếp |
| Video/slide/bài nộp | Một người nhóm chọn ở D10 | Chưa xác minh hoàn tất | A/B/C cung cấp đầu vào; một người xác nhận nộp |

Ưu tiên core, phục hồi và triển khai trước tính năng demo mới. Đã test local không đồng nghĩa đã chạy Fuji. Không reset DB/xóa pending chỉ để UI hết chờ.
