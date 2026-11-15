# Vận hành Solidity và bàn giao deployment

Nhánh công việc `codex/solidity-fuji-handoff`. Người dùng đã chọn **DISABLED cho Fuji**. Local rehearsal vẫn kiểm MOCK để giữ khả năng tương thích; không có nguồn yield DeFi thật.

## 1. Lệnh và đầu vào

Chạy từ contracts/, Node24 và dependencies theo lockfile. Hardhat không tự đọc `.env.example` hoặc `.env`: cấu hình biến môi trường cho tiến trình. Các giá trị rỗng trong ví dụ phải được thay bằng địa chỉ công khai thực tế. Không đưa key/seed vào lệnh, chat hoặc tài liệu.

| Lệnh | Công việc | Đầu vào |
| --- | --- | --- |
| `npm.cmd run preflight` | Kiểm read-only chain, địa chỉ, balance so với ngân sách khai báo | EXPECTED_CHAIN_ID, DEPLOYER_ADDRESS, TREASURY_ADDRESS, YIELD_MODE, GAS_BUDGET_WEI; RPC_URL/FUJI_RPC_URL; SEED_TOPUP_BUDGET_WEI optional |
| `npm.cmd run verify:deployment` | Kiểm read-only manifest, code/getter/domain/receipt và artifact nếu có evidence | EXPECTED_CHAIN_ID, MANIFEST_PATH, RPC_URL/FUJI_RPC_URL; build artifacts từ đúng source |
| `npm.cmd run deploy:local` / `deploy:fuji` | Deploy bundle mới, ghi journal từng bước | Treasury, mode, MANIFEST_PATH mới, ATTEMPT_DIR mới; signer được cấu hình; Fuji cần GAS_BUDGET_WEI |
| `npm.cmd run seed:local` / `seed:fuji` | Top-up gas và token cho hai ví demo | Manifest đã kiểm; MERCHANT_ADDRESS/SUBSCRIBER_ADDRESS; ATTEMPT_DIR mới; Fuji cần gas budget; SEED_EVIDENCE_PATH mới nếu đã seed trước |
| `npm.cmd run yield:local` / `yield:fuji` | Nạp thêm yield, chỉ MOCK | Manifest MOCK, SUBSCRIPTION_ID/YIELD_AMOUNT nguyên dương uint256, đúng funder và position Active |
| Local rehearsal | Sở hữu node31337 riêng, chạy hai mode và đóng node sau test | `node node_modules/hardhat/dist/src/cli.js run scripts/rehearsal.ts`; dùng executable Node24 |

`GAS_BUDGET_WEI` là ngưỡng balance khai báo để kiểm trước giao dịch, **không tự estimate tổng phí và không phải trần chi tiêu transaction**. Preflight so balance với gas budget + seed top-up budget. Cần chọn ngân sách từ estimate và dữ liệu phí lúc thực hiện trước khi deploy Fuji; không kết luận đủ phí từ việc balance lớn hơn0.

Read-only scripts không gọi getSigners hoặc cần private key. Chúng dùng JsonRpcProvider riêng dù entry point Hardhat chọn localhost. Khi đổi từ local sang Fuji, bỏ RPC_URL local còn sót hoặc đặt lại đúng endpoint; EXPECTED_CHAIN_ID kiểm chain thực tế. Script write cũng kiểm EXPECTED_CHAIN_ID nếu đặt, Fuji config pin43113.

Ví dụ chuẩn bị read-only Fuji DISABLED:

```powershell
$env:EXPECTED_CHAIN_ID = '43113'
$env:YIELD_MODE = 'DISABLED'
$env:DEPLOYER_ADDRESS = '<địa chỉ công khai do bạn kiểm soát>'
$env:TREASURY_ADDRESS = '<địa chỉ công khai treasury>'
$env:GAS_BUDGET_WEI = '<ngân sách phí đã ước tính bằng wei>'
# Nếu trước đó có RPC_URL local, đổi nó về RPC Fuji đúng hoặc gỡ khỏi tiến trình.
npm.cmd run preflight
```

Đây là mẫu chuẩn bị, không phải kết quả đã deploy. Signer cho write scripts vẫn cần được chủ ví cấu hình qua phương thức đang hỗ trợ; không gửi secret cho người nhận bundle.

## 2. Journal và xử lý gián đoạn

- ATTEMPT_DIR mặc định cố định theo loại deploy/seed/yield; thư mục đã tồn tại bị từ chối để tránh vô tình chạy lặp. Khi vận hành dùng đường dẫn rõ trong validation-results cho từng lần có chủ đích.
- Lưu intent trước send, hash khi nhận được, receipt/block/gas khi confirmed. TX_TIMEOUT_MS mặc định120000, nhận1000–600000ms. Timeout hoặc mất kết quả ghi unknown và dừng.
- Nếu unknown: đối chiếu hash, ví, nonce và chain; không xóa journal/cache để gửi lại. Trường hợp send đã được chấp nhận nhưng mất response trước khi nhận hash chỉ có intent, cần người giữ ví/node giúp đối chiếu. Bản này không tự động resume/rebroadcast.
- Nếu file `.tmp` còn sau lỗi ghi/rename, giữ lại làm evidence và đối chiếu; không tự xóa để chạy lại.
- Manifest output đã tồn tại không bị ghi đè. Deploy chỉ ghi manifest sau bước operational/artifact verification; nếu lỗi trước đó, các contract đã tạo có thể tồn tại và nằm trong journal.
- Seed là top-up theo số dư, không luôn cộng thêm500mUSDC. Lần seed mới có chủ đích dùng attempt mới và SEED_EVIDENCE_PATH mới để giữ lịch sử; cùng số dư đã đủ không phát sinh tx.
- Yield funding cộng dồn, không idempotent. Không chạy lại mint/approve/fund để xử lý timeout; phải xác minh lần cũ. Với deployment DISABLED, không chạy fund-yield.

## 3. Verifier chứng minh gì

Verifier kiểm chain/deployment identity, decimals, token owner, Vault paymentToken/treasury/adapter, adapter linkage nếu MOCK, domain EIP-712, code fingerprint, canonical receipts và confirmations. Bundle mới có evidence cho token/adapter/Vault/bind; bind được kiểm sender/target/calldata.

Khi có đủ build evidence, còn đối chiếu creation calldata + constructor args, ABI/build-info checksum và runtime bytecode ngoài immutable spans với artifact tại máy kiểm. Linked artifacts không được hỗ trợ và sẽ fail; không tự bỏ qua phần chưa hiểu.

- `LOCAL_ARTIFACT_MATCH`: code giao dịch/runtime khớp artifact local theo kiểm tra trên.
- `NOT_CHECKED`: manifest legacy chưa có đủ artifact evidence; không coi là source-verified.
- `source_verification: NOT_VERIFIED`: chưa hoàn tất liên kết source Git commit/build hoặc public explorer verification. Fingerprint do script tự lưu không chứng minh source; đừng đổi nhãn thành verified chỉ để đóng phase.

Freeze source/config và build từ commit được review trước Fuji. Source_dirty được ghi ở local; deploy Fuji từ source/config contract còn dirty bị chặn. Các script/tooling mới và plan chưa commit cũng cần được review/commit trước khi freeze toàn bộ bản giao.

Vector `shared/check-in.fixture.json` là fixture công khai với placeholder, giữ nguyên. Domain deployment thật lấy chain43113 và Vault từ manifest. Không dùng địa chỉ placeholder để cấu hình backend/frontend.

## 4. Bàn giao cho BE/FE

Giao cùng bundle: source commit, compiler/settings/build evidence, ABI/checksum, chain/deployment_id, Vault/token/adapter/treasury công khai, mode, decimals/status codes, deployment hashes/blocks/confirmations và verifier report. Với DISABLED adapter là zero và yield không được hiển thị như lợi nhuận đã sinh.

BE backup/migrate0003 và cấu hình manifest/ABI trước /ready; FE pin chain/Vault/deployment. Không đổi deployment_id lặng lẽ. Vault không upgradeable; sửa source không đổi bytecode contract cũ. Nếu redeploy, vị thế đang có ở Vault cũ không tự chuyển sang Vault mới.

Nghiệm thu Fuji phải dùng receipt thật và thời gian chain thực, extension wallet/thiết bị theo scope. Local fuzz/boundary và injected provider không thay bằng chứng Fuji hoặc explorer source verification.