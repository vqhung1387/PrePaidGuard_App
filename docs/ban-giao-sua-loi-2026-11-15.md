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

## Phần BE đã làm tiếp

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

| Việc | Người tiếp tục | Tiêu chí |
|---|---|---|
| **Pending cũ mất cả nonce và raw** | Người giữ ví | BE đã hỗ trợ raw signed transaction để chứng minh hash/signer/chain rồi phục hồi nonce. Chỉ khi không còn cả raw gốc và nonce đã lưu thì vẫn không thể chứng minh an toàn; cần tìm lại lịch sử nguồn gốc, không sửa DB/xóa cache theo cảm tính |
| **Fuji + HTTPS/Render thật** | Solidity + BE | Deploy, receipt, manifest/ABI, RPC/DB/AUTH/CORS; pin chain/Vault/deployment, /ready trên URL thật. Lượt này chưa deploy |
| **Core/MetaMask + hai thiết bị** | UI + cả nhóm | Nghiệm thu SIWE/EIP-712/cancel/speed-up/refund bằng extension thật; provider test không thay thế |
| **Camera/native** | UI | Web EIP-1193/dán payload hiện hoạt động. Camera, Android/iOS chưa triển khai/nghiệm thu; chốt Web làm demo nếu thiếu thời gian |
| **Subscriptions/drafts/events vượt100** | UI | Catalog đã phân trang20; các danh sách còn lại vẫn giới hạn100, cần tải tiếp nếu pilot vượt ngưỡng |
| **Đo trên Vault Fuji đã deploy** | BE sau deploy | Đã đo transport Fuji và tối ưu đọc tối đa4 plan cùng block, giữ canonical/error handling. Test100 gói/RPC200ms giảm20,42→5,44s. Mẫu8lượt eth_getBalance trên Fuji không nhanh hơn với4luồng, nên cần benchmark Vault thật, không cam kết mọi RPC đều nhanh hơn |
| **Demo ngoài core** | UI + nhóm sản phẩm | Build có API mở thẳng workspace thật; chi tiết gốc/refund/eligibility/yield/lịch sử đã lấy API/chain, có lối vào ví từ tài khoản demo. Training/booking/giờ đông mở rộng vẫn mô phỏng, không có nguồn số liệu thật; cần chốt scope trước khi bổ sung backend mới |
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

## Xác minh phần BE tiếp theo

-55 test BE không cần EVM pass;6 ca live EVM pass (MOCK/DISABLED và cancel/speed-up có/không có nonce legacy). Ca chữ ký unprotected thêm sau bộ live đã được kiểm riêng trong55 ca.
-103 test Flutter pass; analyze không lỗi. Browser13 bước pass, gồm kiểm số tiền chi tiết tài khoản thật rồi hủy/retry.
-Test100 gói, mỗi đọc plan bị chèn200ms trễ:5,44giây so với20,42giây trước tối ưu. Không dùng con số này để cam kết tốc độ mạng thật.
-Đã đo RPC Fuji thật tại block61101199; ví deploy vẫn0AVAXtestnet. Deploy/HTTPS được để sau theo lựa chọn của người dùng, không phải phần code BE chưa làm.

CI đúng head sau push là bằng chứng SDK pin; xem Actions của nhánh, không suy từ kết quả local dùngFlutter3.41.9. Lockfile gốc3.47.9 được giữ khi commit.
