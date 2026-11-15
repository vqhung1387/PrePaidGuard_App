# Bàn giao bản sửa tích hợp — 15/11/2026

Nhánh: **fix/tich-hop-va-phuc-hoi**. Đã merge frontend78d2295 và Solidity16e0d3f vào nền feat/integration a9096b2, giữ lịch sử cha. Không force-push nhánh của nhóm; main chưa được merge/deploy.

## Đã sửa

| Việc | Kết quả |
|---|---|
| Conflict real/screen.dart | Giữ UI mới và controller có bảo vệ pending/clock |
| Biểu đồ giờ đông | Đo nhãn theo text scale, giảm số mốc; nếu cực hẹp thì cuộn cả chart/trục. Test54 cấu hình |
| Script browser / CI | Đồng bộ locator/nhãn UI, thêm runner tự dựng môi trường và workflow browser; chạy trên feat/**, fix/** và PR. Flutter pin3.47.9, Node24 |
| Cancel/speed-up | BE lưu nonce, xác minh owner + sender/nonce + canonical receipt + confirmations. Gốc thành CANCELLED/REPLACED; tracking hash mới nếu cùng action/resource |
| APPROVE bị thay thế | Lưu nonce khi pending, đối chiếu hash mới qua provider ví và block/confirmations. Không gửi lại để thử khi chưa có chứng cứ |
| Reorg sau cancel | BE hủy kết luận cũ khi block đổi; client đối chiếu lại trước khi thử lại cùng thao tác |
| JWT hết hạn sau broadcast | Giữ hash trước, xóa phiên hết hạn ngay, yêu cầu SIWE lại |
| Catalog timeout | Tải20 gói/cursor và nút Tải thêm; không trùng ID |
| Readiness | Render dùng /ready; /health chỉ kiểm process |
| Tech debt tài liệu | README ghi stack thực tế; task-board liên kết trạng thái mới |

## Bắt buộc khi nhận nhánh

1. Pull đúng nhánh trên, review trước khi merge feat/integration/main.
2. **Backup DB hiện hữu, chạy alembic upgrade head tới0003 trước frontend mới. Không reset/xóa DB.**
3. Xem Actions của đúng commit cuối. Local dùng Flutter3.41.9 với dependency SDK tương thích; pubspec.lock commit giữ pin gốc3.47.9.
4. /config trả thêm confirmations; TransactionResponse có sender_nonce và replacement_tx_hash. Hợp đồng chuẩn tại /openapi.json và docs/api.md.
5. Nút đối chiếu giao dịch SUBMITTED nhận hash tăng phí/hủy **đã mined**. Chưa đủ xác nhận, sai ví/nonce/block đều bị từ chối; đừng bỏ guard để làm UI hết chờ.

## Kiểm thử

- Flutter: test hiện có +54 layout +128 chuỗi giải ngân + phân trang/JWT/recovery/approval/reorg.
- BE: quyền sở hữu, sai nonce/ví/block, pending/confirmations, idempotence, reorg, legacy nonce.
- Live EVM: cancel cùng nonce rồi retry chỉ tạo1 subscription; speed-up tracking hash mới.
- Browser12 bước: cache/API lỗi, clock lệch60giây, replay/refund, hủy qua UI rồi retry đúng1 lần.
- Contract:18 Mocha +2 fuzz test ×256 input; migration upgrade/check và readiness.
- Local pass không có nghĩa ví extension/Fuji/HTTPS đã nghiệm thu. CI fail ở commit cuối phải sửa trước merge.

## Chưa sửa / còn cần tiếp tục

| Việc | Người tiếp tục | Tiêu chí |
|---|---|---|
| **Pending cũ không có nonce gốc** | BE + người giữ ví | Nếu API chưa từng thấy tx trước khi node bỏ, không có bằng chứng để tự mở guard. Trả ORIGINAL_TX_UNAVAILABLE. Cần tìm dữ liệu gốc từ nguồn tin cậy/lịch sử ví hoặc RPC từng giữ tx; không sửa DB/xóa cache theo cảm tính |
| **Fuji + HTTPS/Render thật** | Solidity + BE | Deploy, receipt, manifest/ABI, RPC/DB/AUTH/CORS; pin chain/Vault/deployment, /ready trên URL thật. Lượt này chưa deploy |
| **Core/MetaMask + hai thiết bị** | UI + cả nhóm | Nghiệm thu SIWE/EIP-712/cancel/speed-up/refund bằng extension thật; provider test không thay thế |
| **Camera/native** | UI | Web EIP-1193/dán payload hiện hoạt động. Camera, Android/iOS chưa triển khai/nghiệm thu; chốt Web làm demo nếu thiếu thời gian |
| **Subscriptions/drafts/events vượt100** | UI | Catalog đã phân trang20; các danh sách còn lại vẫn giới hạn100, cần tải tiếp nếu pilot vượt ngưỡng |
| **RPC Fuji chậm** | BE | Backend vẫn đọc từng plan. Đo trên Fuji trước khi quyết định batch; không cache số dư sai nguồn chuẩn |
| **Demo vs dữ liệu thật** | UI + BE | Catalog mở rộng, training/booking/giờ đông/dashboard demo vẫn RAM, có nhãn mô phỏng. Ghép core vào UI sản phẩm trước |
| **Yield** | Solidity + UI | MOCK/DISABLED, chưa DeFi/BENQI thật; phân biệt estimate/paid và funding testnet |
| **Video/slide/nộp bài** | Cả nhóm | Chốt baseline/refund theo thời gian, URL và bằng chứng thực tế; không nhận là đã deploy cho phần mới test local |

## Chạy lại browser giống CI

Sau khi cài dependencies đã khóa, compile contracts và build Web với CHAIN_ID31337/API_BASE_URL=http://127.0.0.1:18010:

```powershell
$env:TEST_DATABASE_URL='postgresql+psycopg://postgres@127.0.0.1:55427/prepaidguard_test'
cd backend
uv run --locked --with playwright==1.65.2 python ../scripts/browser_acceptance/local.py --browser 'C:/Program Files/Google/Chrome/Application/chrome.exe'
```

Runner yêu cầu cổng18545/18010/18090 trống, tự mở/dừng EVM/API/web, tạo/xóa schema UUID riêng. Không dùng node người khác hoặc DB production. Bỏ --browser thì cài Playwright Chromium trước như browser.yml. Báo cáo tại validation-results/browser/browser. Không commit .env, JWT, seed/private key hay ví deploy vào Git.

