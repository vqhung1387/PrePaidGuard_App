# Bàn giao bản sửa tích hợp — 15/11/2026

Nhánh: **fix/tich-hop-va-phuc-hoi**. Đã merge frontend78d2295 và Solidity16e0d3f vào nền feat/integration a9096b2, giữ lịch sử cha. Không force-push nhánh của nhóm; main chưa được merge/deploy.

**Phân vai và phạm vi:** xem [một đầu mối cho mỗi việc + 10 điểm cần nhóm thống nhất](phan-vai-va-diem-can-thong-nhat.md). Các sửa tích hợp đã có không có nghĩa BE nhận luôn UI/Solidity trong các đợt tiếp theo. Phân công dưới đây là đầu mối đề xuất, chờ nhóm xác nhận tên người/quyết định chung.

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

## Phần BE và UI hỗ trợ tích hợp đã làm tiếp

- Phục hồi legacy bằng raw transaction gốc đã ký, tối đa16KiB; kiểm hash/signer/chain. Raw không lưu DB/cache, không broadcast. Không nhận nonce tự khai làm bằng chứng.
- Endpoint original-proof cho APPROVE; replacement nhận bằng chứng optional cho giao dịch Vault. Không cần migration mới ngoài0003.
- RPC catalog tối đa4luồng, giữ block/thứ tự và không trả một phần khi lỗi; đã đo case100 gói/RPC200ms5,44s.
- Đã đo Fuji công khai ngày15/11:8lượt eth_getBalance, tuần tự0,875s vs4luồng1,250s. Đây không phải benchmark Vault; các số này không chứng minh song song luôn tốt hơn.
- Core tài khoản thật hiển thị số tiền/eligibility/yield/lịch sử đọc từ API, không còn JSON mặc định. Build có API mở thẳng luồng này, demo có nút ví để chuyển.
- Người dùng chọn **làm BE trước**. Đã kiểm ví deploy0x9B14012e9a4dccE26b4581086bC44Dc1BF5bE1f4 còn0AVAXFuji. Chưa có gas deploy; Chrome automation tự dừng do không xác minh URL. Không triển khai bằng ví khác hoặc tiền mainnet.

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

| Việc | Đầu mối đề xuất / đầu ra cụ thể | Tiêu chí |
|---|---|---|
| **Pending cũ mất cả nonce và raw** | Người giữ ví | BE đã hỗ trợ raw signed transaction để chứng minh hash/signer/chain rồi phục hồi nonce. Chỉ khi không còn cả raw gốc và nonce đã lưu thì vẫn không thể chứng minh an toàn; cần tìm lại lịch sử nguồn gốc, không sửa DB/xóa cache theo cảm tính |
| **Deploy contract Fuji** | C — Solidity (C-FUJI) | Gas testnet, deploy/verify, receipt và manifest/ABI; giao địa chỉ/chain/block cho B và A. Chưa deploy trong lượt này |
| **Host API/DB HTTPS** | B — BE (B-HOST) | Nhận manifest từ C, migrate/backup DB, cấu hình RPC/AUTH/CORS và kiểm /ready. Không nhận luôn deploy contract |
| **Build/host app** | A — UI (A-RELEASE) | Nhận URL API từ B và manifest từ C, pin chain/Vault/deployment; một URL dùng được trên thiết bị demo |
| **Core/MetaMask + hai thiết bị** | A — UI dẫn nghiệm thu (A-WALLET) | B hỗ trợ API/log, C kiểm receipt; người giữ ví ký. Provider test không thay thế extension thật |
| **Camera/native** | UI | Web EIP-1193/dán payload hiện hoạt động. Camera, Android/iOS chưa triển khai/nghiệm thu; chốt Web làm demo nếu thiếu thời gian |
| **Subscriptions/drafts/events vượt100** | UI | Catalog đã phân trang20; các danh sách còn lại vẫn giới hạn100, cần tải tiếp nếu pilot vượt ngưỡng |
| **Đo trên Vault Fuji đã deploy** | BE sau deploy | Đã đo transport Fuji và tối ưu đọc tối đa4 plan cùng block, giữ canonical/error handling. Test100 gói/RPC200ms giảm20,42→5,44s. Mẫu8lượt eth_getBalance trên Fuji không nhanh hơn với4luồng, nên cần benchmark Vault thật, không cam kết mọi RPC đều nhanh hơn |
| **Demo ngoài core** | A — UI trình scope (D5) | Build có API mở workspace thật; core đọc API/chain. Training/booking/giờ đông vẫn mô phỏng. Nhóm chốt tính năng nào làm thật rồi mới giao API mới cho B |
| **Yield contract/nguồn token** | C — Solidity (C-YIELD) | Nhóm chốt D3; hiện MOCK/DISABLED, chưa DeFi/BENQI thật; giao hành vi/event cho B và A |
| **Nhãn yield trên app** | A — UI (A-YIELD) | Tiêu thụ DTO B có sẵn; phân biệt estimate/paid/MOCK theo đầu ra C, không tự đổi chính sách |
| **Video/slide/nộp bài** | Một người nhóm chỉ định tại D10 | A cung cấp demo, B/C cung cấp bằng chứng; người điều phối chịu trách nhiệm kiểm hồ sơ và xác nhận nộp |

## Chạy lại browser giống CI

Sau khi cài dependencies đã khóa, compile contracts và build Web với CHAIN_ID31337/API_BASE_URL=http://127.0.0.1:18010:

```powershell
$env:TEST_DATABASE_URL='postgresql+psycopg://postgres@127.0.0.1:55427/prepaidguard_test'
cd backend
uv run --locked --with playwright==1.65.2 python ../scripts/browser_acceptance/local.py --browser 'C:/Program Files/Google/Chrome/Application/chrome.exe'
```

Runner yêu cầu cổng18545/18010/18090 trống, tự mở/dừng EVM/API/web, tạo/xóa schema UUID riêng. Không dùng node người khác hoặc DB production. Bỏ --browser thì cài Playwright Chromium trước như browser.yml. Báo cáo tại validation-results/browser/browser. Không commit .env, JWT, seed/private key hay ví deploy vào Git.

## Xác minh phần BE tiếp theo

- 55 test BE không cần EVM pass; 6 ca live EVM pass (MOCK/DISABLED và cancel/speed-up có/không có nonce legacy). Ca chữ ký unprotected thêm sau bộ live đã được kiểm riêng trong 55 ca.
- 103 test Flutter pass; analyze không lỗi. Browser 13 bước pass, gồm kiểm số tiền chi tiết tài khoản thật rồi hủy/retry.
- Test 100 gói, mỗi đọc plan bị chèn 200 ms trễ: 5,44 giây so với 20,42 giây trước tối ưu. Không dùng con số này để cam kết tốc độ mạng thật.
- Đã đo RPC Fuji thật tại block 61101199; ví deploy vẫn 0 AVAX testnet. Deploy/HTTPS được để sau theo lựa chọn của người dùng, không phải phần code BE chưa làm.

CI đúng head sau push là bằng chứng SDK pin; xem Actions của nhánh, không suy từ kết quả local dùngFlutter3.41.9. Lockfile gốc3.47.9 được giữ khi commit.
