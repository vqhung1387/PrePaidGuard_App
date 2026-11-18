# Bảng công việc tích hợp

Bảng task ID: [tasks.md](tasks.md). **Trạng thái mới nhất** ở [nghiệm thu 19/11/2026](nghiem-thu-final-2026-11-19.md). Xem [bằng chứng triển khai Fuji](fuji-deployment-2026-11-16.md) và [bàn giao 15/11/2026](ban-giao-sua-loi-2026-11-15.md) để biết thông tin nền.

**Giao việc:** [mỗi task một đầu mối và D1–D10 cần thống nhất](phan-vai-va-diem-can-thong-nhat.md). Các nhãn chung trong bảng này chỉ mô tả giao điểm; không giao đồng thời một task cho hai role.

| Việc | Vai trò | Trạng thái | Còn lại |
| --- | --- | --- | --- |
| Baseline luật tiền / signing | C — Solidity chuẩn bị | Có code B1–B6 và signing vector | Nhóm chốt D3/D4; C không tự đổi chính sách |
| Flutter catalog / merchant | UI | Có demo và workspace ví thật | Ghép UI sản phẩm với API |
| SIWE / metadata / tracking / sync | BE | PASS trên API HTTPS/DB Render/Vault Fuji thật; AUTH/CORS đã pin origin web | Duy trì config nếu nhóm đổi URL web |
| Vault / release / refund | Solidity | Fuji DISABLED, Sourcify exact match; release/refund/replay PASS | Review bundle và nghiệm thu UI trên thiết bị |
| Recovery API | B — BE (B-RECOVERY) | Có nonce proof/cancel/speed-up | Test API/reorg; mất cả nonce/raw cần người giữ ví tìm bằng chứng |
| Recovery UI | A — UI (A-RECOVERY) | Có luồng đối chiếu hash/raw | Nghiệm thu UX bằng extension thật |
| Deploy contract | C — Solidity (C-FUJI) | Đã deploy/verify/seed Fuji, có receipt/manifest | Review bằng chứng; không deploy lại để sửa UI |
| Host API/DB | B — BE (B-HOST) | HTTPS Live, migration0003, AUTH/CORS đúng web. Cấu hình Render dùng `/health`; `/ready` kiểm DB và RPC. | Kiểm ngày hết hạn DB, sao lưu và thử khôi phục vào DB riêng. |
| Build/host app | A — UI (A-RELEASE) | Web HTTPS Live, pin đúng API/chain/Vault/deployment; [chi tiết](web-release-2026-11-16.md) | Nghiệm thu extension và hai thiết bị; review trước release mới |
| Yield contract | C — Solidity (C-YIELD) | Fuji đang DISABLED; MOCK chỉ có ở kiểm thử local | Không trình bày lợi tức thật; thay scope cần nhóm chốt |
| Yield UI | A — UI (A-YIELD) | Core đọc DTO hiện có | Giữ nhãn đúng theo mode từ API/contract |
| Browser / CI tích hợp | B — BE (B-E2E) | 84 test BE + browser local; luồng API Fuji thật PASS | Xem Actions đúng head; kiểm UI bằng ví extension/thiết bị thật |
| Camera / native / thiết bị | UI | Chưa nghiệm thu | Chốt Web hoặc làm tiếp |
| Video/slide/bài nộp | Một người nhóm chọn ở D10 | Chưa xác minh hoàn tất | A/B/C cung cấp đầu vào; một người xác nhận nộp |

Ưu tiên core, phục hồi và triển khai trước tính năng demo mới. Đã test local không đồng nghĩa đã chạy Fuji. Không reset DB/xóa pending chỉ để UI hết chờ.
