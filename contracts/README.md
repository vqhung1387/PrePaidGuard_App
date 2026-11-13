# Smart contracts PrePaidGuard

Solidity 0.8.28, OpenZeppelin 5.6.1, Hardhat 3 và Node.js 24. Phiên bản npm được khóa trong package-lock.json. Script deploy hỗ trợ local 31337 và Avalanche Fuji 43113.

## Cài và kiểm tra

```sh
cd contracts
npm ci
npm run typecheck
npm test
npm run export
```

Test gồm quyền, allowance, amount, chữ ký EIP-712, thời hạn QR, replay, refund boundary, reentrancy, chuyển token/adapter thất bại, hai giao dịch cùng block và fuzz bảo toàn tiền qua ba subscription. Hardhat chạy 256 mẫu fuzz. Workflow contracts.yml kiểm tra thêm FastAPI với PostgreSQL và giao dịch của contract thật.

## Luật được triển khai

- Plan bất biến, clientReference duy nhất theo merchant, 1–120 kỳ, token allowlisted có 6 decimals. Tổng gốc dùng integer, kiểm overflow.
- Kỳ đầu mở sau periodDuration. Release từng kỳ và lấy thời gian block release làm mốc cho kỳ sau. Không tự giải ngân kỳ bỏ lỡ.
- Check-in trong khoảng nextReleaseAt <= now < nextReleaseAt + gracePeriod. Refund mở tại now >= nextReleaseAt + gracePeriod và trả phần gốc còn lại cho subscriber.
- Caller check-in là merchant của plan. Subscriber ký CheckIn theo thứ tự trong shared/check-in.types.json. Domain có name PrepaidGuard, version 1, chainId và địa chỉ Vault. Deadline nằm từ now đến now + 900 giây.
- Mỗi release/refund tăng nonce. COMPLETED và REFUNDED là trạng thái cuối.
- Vault có paymentToken, treasury và adapter cố định từ constructor. Các hàm tài chính dùng SafeERC20, kiểm token nhận đủ và nonReentrant. State và chuyển token cùng thành công hoặc cùng revert.

Đây là baseline B1–B6 đã dùng trong backend, được triển khai tiếp cho Solidity theo phạm vi người dùng giao. Nhóm cần nghiệm thu chính sách hủy do không sử dụng trước demo. Xem docs/project.md và docs/schema.md.

## Yield MOCK

Vault nhận adapter zero khi YIELD_MODE=DISABLED. Mode MOCK dùng MockYieldAdapter, được bind với đúng Vault một lần bởi funder. Chỉ Vault gọi deposit/withdraw. Funder nạp token yield cho vị thế đang có gốc và không có hàm rút tiền.

Yield không tự sinh theo APY. fundYield chuyển token testnet vào adapter rồi mới ghi yield cho subscription đó. Mỗi release/refund lấy toàn bộ yield đã nạp cho vị thế tại thời điểm ấy. Merchant nhận floor(70%), subscriber floor(20%), treasury nhận phần còn lại. Các vị thế khác giữ nguyên gốc và yield.

Từ contracts/, đặt SUBSCRIPTION_ID và YIELD_AMOUNT là integer atomic units, rồi chạy npm run yield:local hoặc npm run yield:fuji. Ví funder cần có gas. Script mint số token mock cần nạp, approve adapter và fundYield. Không đưa key vào source, Flutter, backend hoặc log.

## Deploy local

Terminal đầu tiên:

```sh
npx hardhat node --hostname 127.0.0.1
```

Terminal thứ hai:

```sh
npm run deploy:local
npm run seed:local
```

Script xuất shared/deployments/local.json và nạp token cho tài khoản subscriber thứ ba của node. File local phụ thuộc node đang chạy và được gitignore. Node local trả receipt status=0 cho giao dịch đã mine nhưng revert để API kiểm tra recovery.

Backend trỏ CHAIN_ID=31337, ABI_FILE=../shared/abi/PrepaidVault.json và DEPLOYMENT_FILE=../shared/deployments/local.json. Chạy migration và API theo backend/README.md.

Để chạy test tích hợp từ backend/ khi node và PostgreSQL đang chạy:

```sh
CONTRACT_TEST_RPC=http://127.0.0.1:8545 TEST_DATABASE_URL=postgresql+psycopg://postgres:postgres@127.0.0.1:5432/prepaidguard_test uv run --locked pytest -q
```

Test tạo schema DB riêng, deploy contract mới, tạo hai ví test và dọn schema sau khi kết thúc. Test chỉ nhận RPC loopback và chain 31337. Chạy cả DISABLED lẫn MOCK, kiểm receipt, scanner recovery, ký SIWE/EIP-712, replay revert, payout và bảo toàn số dư.

## Deploy Fuji

1. Cấp AVAX Fuji cho ví deploy riêng. Nạp DEPLOYER_PRIVATE_KEY vào môi trường tiến trình hoặc Hardhat keystore. .env.example chỉ là mẫu, Hardhat không tự đọc .env.
2. Đặt TREASURY_ADDRESS và YIELD_MODE=MOCK hoặc DISABLED. FUJI_RPC_URL mặc định là public Fuji C-Chain RPC.
3. Chạy npm run deploy:fuji. Script kiểm chain 43113, deploy token/adapter/Vault, bind adapter và chờ hai xác nhận trước khi xuất shared/deployments/fuji.json. ABI cũng được xuất từ build hiện tại. Mỗi lần deploy có deployment_id mới theo địa chỉ Vault.
4. Đặt MERCHANT_ADDRESS và SUBSCRIBER_ADDRESS là hai ví test khác nhau, khác ví deploy, rồi chạy npm run seed:fuji. Script cấp gas để mỗi ví có ít nhất 0.1 AVAX Fuji và subscriber có ít nhất 500 mUSDC. Script kiểm người chạy là token owner.
5. Trỏ backend tới ABI và manifest Fuji, chạy /ready, kiểm /config rồi publish, subscribe hai gói, release một kỳ và refund gói còn lại khi tới hạn. Lưu tx hash và kiểm số dư trên explorer.

Chỉ commit manifest Fuji sau khi receipt, chain và code đã được kiểm tra. Triển khai lại Vault làm đổi deployment_id và cần đổi cấu hình client/backend cùng nhau.

## Giới hạn và review

MockUSDC chỉ mint bởi owner để cấp token demo. MockYieldAdapter có funder cố định và bind Vault một lần. Vault không có owner, upgrade, emergency withdraw, public mint, đổi thời gian hoặc hàm tùy ý lấy tiền gốc. Các contract trong contracts/test phục vụ kiểm thử. Script deploy chỉ chọn ba contract demo có tên rõ ràng.

Toolchain hiện có cảnh báo npm audit ở dependency gián tiếp zod, glob và minimatch. Registry chưa có bản vá tương thích cho toàn bộ toolchain đã chọn. Các gói này chạy ở máy build/test, không nằm trong bytecode Vault. Kiểm lại npm audit khi nâng Hardhat. Test nội bộ chưa thay thế đánh giá độc lập trước khi dùng tài sản thật.

Tài liệu đối chiếu khi triển khai. [Hardhat](https://hardhat.org/docs/getting-started), [OpenZeppelin EIP712/ECDSA](https://docs.openzeppelin.com/contracts/5.x/api/utils/cryptography), [SafeERC20](https://docs.openzeppelin.com/contracts/5.x/api/token/erc20).

Xem [bàn giao Solidity](../docs/solidity-handoff.md).
