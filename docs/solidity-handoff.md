# Bàn giao role C — Solidity / smart contract

Cập nhật ngày 13/11/2026. Nhánh nhận bàn giao là **solidity**, tạo từ main. Code contract, script và dữ liệu shared được lấy từ commit nguồn [9268a79 trên backend](https://github.com/vqhung1387/PrePaidGuard_App/commit/9268a79e786e4a25dd21542490dbf1d04c470c6c). Phần FastAPI và bài test tích hợp API/DB nằm ở nhánh backend.

## 1. Trạng thái nhận việc

| Task | Đã thực hiện | Cần làm tiếp |
| --- | --- | --- |
| C01 | Hardhat 3, Solidity 0.8.28, OpenZeppelin 5.6.1, Node 24, lockfile; MockUSDC 6 decimals. | Dựng môi trường máy người nhận bằng npm ci. |
| C02–C03 | Plan bất biến, unique reference theo merchant, kiểm terms/overflow/token; subscribe và custody gốc. | Review chéo và nghiệm thu cùng Flutter. |
| C04–C05 | EIP-712, nonce, deadline, quyền merchant/subscriber, release/refund và trạng thái cuối. | Chạy cùng ví thật và hai thiết bị trên Fuji. |
| C06 | Xuất ABI thật, QR schema, typed fields và vector chữ ký. Script xuất manifest sau deploy thành công. | Deploy Fuji rồi commit manifest có địa chỉ và receipt thật. |
| C07 | 14 test Mocha và một test fuzz, chạy 256 mẫu chuỗi release/refund qua ba subscription. | Chạy lại khi đổi contract; bổ sung regression cho lỗi phát hiện khi review. |
| C08 | Script deploy và seed đã chạy local. | Cấp gas Fuji, deploy, seed hai ví và lưu tx evidence. |
| C09 | Đã kiểm nội bộ quyền mint/funding/bind, reentrancy, transfer failure, shortfall và giao dịch cùng block. | Review độc lập, kiểm contract thực tế được deploy và đóng surface demo. |
| Y01 | Yield MOCK có token cấp riêng từng subscription, chia 70/20/phần dư. | Cấp yield bằng script nếu muốn demo payout. |
| D05 / I02 | Vector chữ ký TypeScript/Python; test replay và check-in/refund cùng block. | Flutter/Dart đối chiếu digest/signature và chạy trên thiết bị. |

Các mục trên chưa được xem là nghiệm thu Fuji hoặc audit độc lập.

## 2. File cần đọc

| File | Vai trò |
| --- | --- |
| [PrepaidVault.sol](../contracts/contracts/PrepaidVault.sol) | Plan, subscription, chữ ký, giải ngân, hoàn tiền và payout. |
| [IYieldAdapter.sol](../contracts/contracts/interfaces/IYieldAdapter.sol) | Giao diện custody/yield theo subscription. |
| [MockYieldAdapter.sol](../contracts/contracts/mocks/MockYieldAdapter.sol) | Gốc/yield riêng từng vị thế, funding thật và bind Vault một lần. |
| [MockUSDC.sol](../contracts/contracts/mocks/MockUSDC.sol) | Token demo, chỉ owner mint. |
| [vault.ts](../contracts/test/vault.ts) | Test quyền, chữ ký, thời gian, concurrent tx, transfer failure và reentrancy. |
| [Conservation.t.sol](../contracts/contracts/test/Conservation.t.sol) | Fuzz bảo toàn tổng token, gốc và các vị thế. |
| [scripts/](../contracts/scripts/) | Deploy, seed gas/token, funding yield, export ABI/schema/signature. |
| [README contract](../contracts/README.md) | Setup và các lệnh local/Fuji. |
| [schema.md](schema.md) | Giao diện dữ liệu và typed-data dùng với A/B. |

contracts/contracts/test/ chứa contract phục vụ kiểm thử. Script deploy chỉ triển khai PrepaidVault, MockUSDC và MockYieldAdapter.

## 3. Luật tiền cần giữ khi sửa

Hai phần BE/Solidity đang dùng baseline B1–B6. Các tài liệu thiết kế gốc còn ghi một số mục đề xuất; nhóm cần nghiệm thu chính sách này trước demo.

- Kỳ đầu mở sau periodDuration kể từ subscribe. Một chữ ký giải ngân một kỳ. Kỳ tiếp theo lấy thời gian block release cộng periodDuration, không tự trả các kỳ bị bỏ lỡ.
- Check-in khi nextReleaseAt <= now < nextReleaseAt + gracePeriod. Refund khi now >= nextReleaseAt + gracePeriod, chỉ subscriber được gọi và chỉ trả gốc chưa sử dụng. Đây là hủy theo thời gian, không xác minh merchant đóng cửa.
- Caller check-in phải là merchant của plan, signer phải là subscriber. Nonce tăng sau release/refund. COMPLETED và REFUNDED là trạng thái cuối.
- Deadline phải >= now và <= now + 900 giây. Domain đúng name **PrepaidGuard**, version **1**, chainId và địa chỉ Vault.
- Plan dùng MockUSDC 6 decimals, 1–120 kỳ. Tổng gốc = pricePerPeriod × totalPeriods, kiểm overflow. clientReference duy nhất trong phạm vi merchant.
- Yield MOCK được nạp bằng token riêng cho từng subscription. Mỗi release/refund thu toàn bộ yield đã nạp cho vị thế đó, chia floor(70%) merchant, floor(20%) subscriber, phần còn lại treasury. Không có lãi tự chạy theo APY.
- Vault không có owner/upgrade/withdraw tùy ý. Token owner chỉ mint token demo. Adapter funder có quyền nạp yield và bind Vault một lần, không có hàm rút gốc.
- Chuyển token hoặc adapter rút thiếu phải revert cả giao dịch, gồm state/nonce. Giữ kiểm nhận đủ token và nonReentrant.

## 4. Chạy trên máy người nhận

Yêu cầu Node.js 24 và npm.

```sh
git clone --branch solidity https://github.com/vqhung1387/PrePaidGuard_App.git
cd PrePaidGuard_App/contracts
npm ci
npm run typecheck
npm test
npm run export
git diff --exit-code -- ../shared
```

Kết quả contract đã kiểm tra tại nguồn là 14 test Mocha qua và 256 mẫu fuzz qua. Workflow Solidity checks trên nhánh này chạy lại từ checkout sạch, gồm kiểm ABI/vector xuất ra khớp bản commit.

Để thử deploy local, mở terminal thứ nhất ở contracts/ và chạy npx hardhat node --hostname 127.0.0.1. Terminal thứ hai chạy npm run deploy:local rồi npm run seed:local. Script sinh shared/deployments/local.json, cấp gas và mUSDC cho các tài khoản local. local*.json được gitignore vì phụ thuộc node đang chạy.

## 5. Bằng chứng tích hợp với backend

Tại commit nguồn 9268a79, đã chạy 21 test backend với PostgreSQL và PrepaidVault thật trên EVM local, ở cả DISABLED và MOCK. Luồng gồm SIWE hai ví, publish, khôi phục draft sau sửa terms, subscribe, scanner phục hồi tx chưa báo hash, ký EIP-712, release, replay REVERTED và refund.

[CI tích hợp đã thành công trên commit nguồn](https://github.com/vqhung1387/PrePaidGuard_App/actions/runs/43248056579). Bài test ở backend/tests/test_live_contract.py và test_contract_bundle.py trên nhánh backend. Workflow contracts.yml của backend chạy tích hợp API/DB/contract. Nhánh solidity dùng workflow riêng solidity.yml.

Để chạy lại tích hợp trên máy, chuyển sang nhánh backend đã chứa cùng bản contract, mở node local và PostgreSQL, đặt TEST_DATABASE_URL cùng CONTRACT_TEST_RPC=http://127.0.0.1:8545 rồi chạy uv run --locked pytest -q từ backend/. Test tạo và xóa schema riêng. Chỉ dùng RPC loopback chain 31337 cho bài test này.

## 6. Thứ tự làm tiếp để lên Fuji

1. Chạy lại npm ci, typecheck và npm test, rồi review các luật ở mục 3 cùng A/B.
2. Chuẩn bị ví deploy riêng có AVAX **Fuji**, chain ID 43113. Ví đã chuẩn bị trên máy người giao có địa chỉ công khai 0x9B14012e9a4dccE26b4581086bC44Dc1BF5bE1f4. Lần kiểm tra cuối ngày 13/11/2026, ví này chưa có gas. Core đã nhận faucet nhưng bước chuyển sang ví deploy còn chờ người dùng xác nhận. Người nhận có thể thống nhất dùng ví deploy riêng của mình.
3. Khóa của các ví chuẩn bị được mã hóa trên máy người giao, ngoài Git, chưa được chuyển cho người nhận. Người nhận cần dùng ví do mình kiểm soát hoặc thống nhất bàn giao qua kênh riêng. Không gửi private key/seed trong issue, commit hoặc chat bàn giao.
4. Nạp DEPLOYER_PRIVATE_KEY vào môi trường shell của tiến trình, đặt TREASURY_ADDRESS và YIELD_MODE=MOCK hoặc DISABLED. FUJI_RPC_URL có mặc định public RPC. Hardhat không tự đọc .env.example hoặc .env.
5. Từ contracts/, chạy npm run deploy:fuji. Script deploy token/adapter/Vault, bind adapter, chờ hai xác nhận rồi ghi shared/deployments/fuji.json với chain, địa chỉ, block, tx hash, code hash, enum và deployment_id.
6. Kiểm chain 43113, receipt thành công và code tại các địa chỉ trước khi commit manifest. Adapter phải bind đúng Vault, token phải có decimals=6. Địa chỉ trong shared/check-in.fixture.json là placeholder test, không dùng để cấu hình demo.
7. Đặt MERCHANT_ADDRESS và SUBSCRIBER_ADDRESS là hai ví test khác nhau, khác deployer, rồi chạy npm run seed:fuji. Script cấp gas để mỗi ví đạt ít nhất 0.1 AVAX Fuji và subscriber đạt 500 mUSDC.
8. Seed chỉ cấp gas/token. Tiếp tục publish plan bằng merchant, approve và subscribe hai lần bằng subscriber. Giải ngân một kỳ của gói thứ nhất, chờ gói thứ hai đủ hạn rồi refund. Mốc demo có thể dùng period 60 giây, grace 120 giây nếu nhóm đồng ý.
9. Nếu demo yield, đặt SUBSCRIPTION_ID và YIELD_AMOUNT theo atomic units rồi chạy npm run yield:fuji trước release/refund. Script cần đúng ví token owner/adapter funder. Ghi rõ mode MOCK trong demo.
10. Gửi cho B manifest, ABI cùng deployment_id và bốn tx hash publish/subscribe/release/refund. B cập nhật cấu hình server, kiểm /ready và /config. A đối chiếu cấu hình Flutter và vector chữ ký, sau đó chạy trên hai thiết bị.

Khi deploy lại, Vault và deployment_id đổi. Cập nhật BE và Flutter cùng bundle mới, đối chiếu dữ liệu theo chain + Vault + ID.

## 7. Lưu ý khi ghép nhánh và review

- Branch backend đã chứa bản contract nguồn 9268a79. Khi ghép, so sánh các file contracts/shared và giữ cả CI backend lẫn CI Solidity. Người phụ trách B giữ phần FastAPI và kiểm thử PostgreSQL.
- Giữ đúng tên field calldata/event/getter. Backend đọc tên từ ABI. Enum subscription hiện là None=0, Active=1, Completed=2, Refunded=3.
- Sau đổi contract, chạy export, commit ABI cùng code rồi chạy lại bài tích hợp backend. D05 còn cần kiểm cùng vector ở Dart/thiết bị.
- npm audit tại lúc dựng bản nguồn có cảnh báo gián tiếp ở zod, glob, minimatch của toolchain build/test. Chi tiết trong README contract. Rà soát bản vá khi nâng dependency.
- Chưa có Fuji manifest/tx evidence, review độc lập, URL API HTTPS hoặc nghiệm thu hai thiết bị. Các mục này là việc còn mở, không đánh dấu DONE từ kết quả local.
