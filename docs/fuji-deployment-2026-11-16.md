# Deployment Fuji và nghiệm thu API — 16/11/2026

## Đã triển khai

| Thành phần | Giá trị |
| --- | --- |
| Chain | Avalanche Fuji C-Chain, `43113` |
| Vault | `0xc2b19Df4e38CE6FA921120f2B16C8c3a9c6a2364` |
| MockUSDC | `0x2267Ff59D31b98E9771AF5d80E3d554d7f5eD998`, symbol mUSDC, 6 decimals |
| Deployment ID | `43113-0xc2b19df4e38ce6fa921120f2b16c8c3a9c6a2364` |
| Yield | `DISABLED`, adapter zero; không có lợi tức DeFi |
| Treasury/deployer | `0x9B14012e9a4dccE26b4581086bC44Dc1BF5bE1f4` |
| Source contract khi deploy | `97e7dc9655b7f8e9a45d8c3b3067832d9df87109` |
| Compiler | Solidity `0.8.28+commit.7893614a`, optimizer 200, EVM Cancun |
| API | https://prepaidguard-api.onrender.com |
| Web | https://prepaidguard-web.onrender.com |
| OpenAPI | https://prepaidguard-api.onrender.com/docs |
| Readiness | `/ready` trả 200, kiểm DB migration, chain, code/token/mode/fingerprint và canonical block |
| Render API release | `dep-dbtcnv5ckfvc73efivvg`, source bundle `ccd4f38e9ee6fb8b29fa4eb2dd555c0b6ece928e`, Live |
| Render Web release | `dep-dbtcnqrncjis739slgbg`, cùng source bundle `ccd4f38`, Live; Flutter 3.47.9, SDK commit `c197ca5199e9ee5661e865596c9c07294dfab51c` |

AUTH_DOMAIN=`prepaidguard-web.onrender.com`, AUTH_URI=`https://prepaidguard-web.onrender.com`, CORS_ORIGINS chỉ gồm origin web này. Chi tiết phát hành và kiểm thử trình duyệt: [web HTTPS](web-release-2026-11-16.md). Đây là bản demo testnet của nhánh tích hợp, chưa merge main; không tự cập nhật mỗi lần push tài liệu.

Manifest: [shared/deployments/fuji.json](../shared/deployments/fuji.json). ABI trong shared/abi cùng nhánh `fix/be-nghiem-thu-1116`. Không merge main hoặc đổi nhánh frontend/solidity.

## Deployment và source verification

- [Deploy MockUSDC](https://build.avax.network/explorer/fuji/c-chain/tx/0xe98b20101051d66063e2a119f0053d72a3a0ca5e221ab7425d350a5e0fe2837e), block 61165946, gas 604084.
- [Deploy Vault](https://build.avax.network/explorer/fuji/c-chain/tx/0x0ae31c1ea847e44e7c2f15f7ca38e67e79b219db18a9f7ed005fd121306b43e9), block 61165951, gas 2260816.
- Cả hai receipt status1, canonical và ít nhất2 confirmations. Operational verifier đối chiếu runtime, creation calldata/constructor, ABI/build-info, EIP-712 domain, token/treasury/adapter. Build/test trước deploy: 34 passing (32 Mocha +2 fuzz, 256 mẫu mỗi fuzz).
- Sourcify xác minh cả creation/runtime **exact_match**: [Vault](https://repo.sourcify.dev/43113/0xc2b19Df4e38CE6FA921120f2B16C8c3a9c6a2364), [MockUSDC](https://repo.sourcify.dev/43113/0x2267Ff59D31b98E9771AF5d80E3d554d7f5eD998). [Bằng chứng job](evidence/fuji-source-verification-2026-11-16.json).
- `evidence.source_verification: NOT_VERIFIED` trong manifest là trạng thái journal lúc deploy, trước lượt Sourcify. Không sửa bằng chứng gốc; kết quả độc lập hoàn tất sau đó được lưu riêng ở liên kết trên. Không nhận đã verify trên explorer khác nếu chỉ có Sourcify.

## Cấp ví thử nghiệm

Người dùng đã cấp 0,2 AVAX Fuji vào deployer qua [giao dịch này](https://build.avax.network/explorer/fuji/c-chain/tx/0xa8b8ea1679172ca856a278abe9d73289f1e1bce5c5cd52c031214284a8ef3a97), rồi xác nhận rõ các khoản cấp tiếp:

- Merchant `0xb6b3259E4edc8e15ccd514f22dc3d2ddB5166E68`: 0,02 AVAX Fuji.
- Subscriber `0x7e75509052FDcEba5E143a4943aBFD580C6AA0Eb`: 0,02 AVAX Fuji và 500 mUSDC.
- Ví Core người dùng `0x1deAa57b166B77d8e8Af39D84f5AcfD823A9DaFE`: 500 mUSDC. Có thể thêm token bằng địa chỉ MockUSDC ở trên.

[Journal cấp gas/token](evidence/fuji-funding-2026-11-16.json) giữ đầy đủ hash/receipt. Dùng top-up 0,02 thay vì script seed mặc định 0,1/ví để không vượt tổng 0,2 AVAX đã có sau phí deploy. Không đổi script Solidity hoặc hạ guard ngân sách. Toàn bộ là tài sản thử nghiệm; khóa ví chỉ đọc trong RAM từ bản lưu bảo vệ của Windows, không ghi vào Git/chat/log.

## Nghiệm thu Fuji qua API HTTPS thật

[Kết quả chi tiết](evidence/fuji-acceptance-2026-11-16.json): **PASS**, plan1, subscriptions1 và2. Chạy bằng hai ví demo ký thật trên chain43113, API/DB Render thật; không tăng giả thời gian EVM.

| Trường hợp | Kết quả |
| --- | --- |
| SIWE hai ví, pin deployment | API/config và signer đúng; phiên test đã logout |
| Publish metadata + plan | Receipt CONFIRMED; API catalog đọc đúng tên/giá 50 mUSDC ×2 |
| Approve/subscribe | Chỉ approve200 mUSDC, hai đăng ký100 mUSDC |
| EIP-712 check-in | Đủ thời gian chain thật, giải ngân đúng50 mUSDC |
| Dùng lại QR | Giao dịch REVERTED, API phản ánh REVERTED; merchant không nhận thêm tiền |
| Client không báo hash | Đăng ký thứ hai được scanner khôi phục từ log; lịch sử API có đúng hash |
| Refund chưa sử dụng | Đăng ký2 hoàn100 mUSDC sau đúng cửa sổ thật |
| Refund sau dùng một kỳ | Đăng ký1 hoàn50 mUSDC, gốc còn lại0 |
| Bảo toàn gốc | Baseline500 → merchant50 + subscriber450 + Vault0; totalPrincipal0 |
| Mode yield | API trả DISABLED; không trình bày số liệu như yield thật |

Hai vị thế nghiệm thu đã REFUNDED; gói demo vẫn có trong catalog. Các hash trong JSON là receipt thật, gồm cả giao dịch replay thất bại có chủ đích. Test không chứng minh giao diện Core/MetaMask, camera hoặc hai thiết bị vật lý đã nghiệm thu.

## Số đo RPC/API thật

[Benchmark](evidence/fuji-benchmark-2026-11-16.json), mỗi phương thức5 mẫu tuần tự, một plan thật. Median: getPlan212,8ms; getLogs90block242,83ms; transaction+receipt116,34ms; catalog HTTPS754,33ms. Không có lỗi trong20 mẫu. Đây là số đo nhỏ tại thời điểm nghiệm thu, không phải load test/SLA hoặc bằng chứng100 plan. Giữ giới hạn4 RPC reads đồng thời/request và không cache số dư.

## Bàn giao từng role

- **BE:** API đã migrate/ready với manifest thật; endpoint receipt, scanner, principal/refund/yield có bằng chứng Fuji. AUTH/SIWE/CORS đã cấu hình theo URL web thật ở trên. Render healthCheckPath hiện vẫn `/health`; người giữ tài khoản cần đổi thành `/ready` trong Settings để nền tảng dùng kiểm tra dependency. Tích hợp Render hiện không có công cụ sửa healthCheckPath, không thay nghĩa `/health` để che khác biệt.
- **UI:** web đã build/host với `API_BASE_URL=https://prepaidguard-api.onrender.com`, `CHAIN_ID=43113`, `VAULT_ADDRESS=0xc2b19Df4e38CE6FA921120f2B16C8c3a9c6a2364`, `DEPLOYMENT_ID=43113-0xc2b19df4e38ce6fa921120f2b16c8c3a9c6a2364`. Nghiệm thu Core/MetaMask, EIP-712/QR, cancel/speed-up và hai thiết bị. Nếu đổi URL web thì giao origin mới cho BE trước khi phát hành.
- **Solidity:** giữ bundle/receipt/source compiler đã freeze, review manifest và Sourcify report; không deploy lại Vault để đổi UI. Mode DISABLED đã được xác minh; yield thật chưa triển khai.
- **Nhóm:** video/slide dùng URL/hash và số liệu trên; không lấy kiểm thử API thay bằng chứng UI hai thiết bị. DB Render Free hết hạn **16/12/2026**; cần backup trước hạn, dịch vụ Free có cold start. Backend mới chưa có API booking/training/crowd vì nhóm chưa chọn scope.
