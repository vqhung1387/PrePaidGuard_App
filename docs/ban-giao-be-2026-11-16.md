# Bàn giao BE — 16/11/2026

## Source được rà soát

- Frontend `70a9add`: phân trang subscription/draft/events, bộ lọc trạng thái, giữ cửa sổ dữ liệu khi refresh và chi tiết principal/yield.
- Solidity `aa5a416`: preflight, deployment verifier/journal, rehearsal và tăng kiểm conservation; không đổi contract nghiệp vụ hoặc ABI.
- Nhánh BE `fix/be-nghiem-thu-1116` ghép hai bản trên tại `b33b419`. Không merge vào main, không ghi đè nhánh frontend/solidity.

## BE đã sửa

1. `/ready` trước đây chấp nhận mọi revision không rỗng. Test tái hiện DB ghi `0001`, `0002` hoặc revision lạ vẫn trả 200. Nay phải khớp tập Alembic heads trong source; sai/thiếu trả 503 `DATABASE_UNAVAILABLE`. Không sửa/xóa dữ liệu ứng dụng để làm health check đạt.
2. Readiness trước đây chỉ kiểm code tại Vault/token và decimals. Test tái hiện Vault trả token khác hoặc adapter không khớp mode nhưng vẫn báo 200. Nay kiểm `paymentToken()`, `adapter()` và mode. Manifest có fingerprint/adapter/treasury thì đối chiếu cả các trường này, cùng block và kiểm canonical. Sai trả 503 `CONFIG_MISMATCH`.
3. Thêm nghiệm thu phân trang thật với PostgreSQL: 205 drafts cùng timestamp, 205 subscription ACTIVE cùng timestamp, trạng thái terminal, 121 events cùng block, hai chủ ví, cursor sai. Thứ tự, cursor, filter và quyền đều đạt; không cần đổi DTO hoặc migration.

## Bằng chứng local

| Kiểm tra | Kết quả |
| --- | --- |
| BE hồi quy, PostgreSQL 16 và RPC mô phỏng | 72 passed; 6 live tests không chạy trong lượt này |
| 6 live tests chạy riêng với Vault thật/Hardhat 31337 | 6 passed: MOCK/DISABLED và cancel/speed-up với/không có nonce cũ |
| Solidity của bản mới | 32 Mocha + 2 fuzz (256 mẫu mỗi fuzz) passed; TypeScript typecheck đạt |
| Flutter của bản mới | 104 passed; analyze không có issue; build web đạt |
| Browser/API/DB/contract local | 13 bước đạt, hai browser context độc lập |

Browser bao gồm SIWE hai ví, publish, approve/subscribe, lỗi cache và lỗi API sau broadcast, khôi phục hash không gửi lặp, ký QR/giải ngân, từ chối replay, refund bảo toàn principal, chi tiết principal/yield, cancel và retry đúng một subscription. Đây là provider test trên local, chưa phải Core/MetaMask thật hoặc hai điện thoại.

Evidence local nằm ngoài Git: `work/be-1116-browser`, `work/be-1116-flutter-tests.log`, `work/be-1116-web-build.log`. Flutter local 3.41.9 khác pin CI 3.47.9; không đưa thay đổi pubspec.lock do SDK local vào commit. CI trên SHA được push là kiểm chứng bổ sung bằng SDK đã pin.

## Việc BE còn phụ thuộc môi trường

| Mã | Chủ việc duy nhất | Đã chuẩn bị / đầu vào còn thiếu | Điều kiện đóng |
| --- | --- | --- | --- |
| BE-01 | BE | PostgreSQL 16 miễn phí đã tạo ở Render Singapore; external connections bị chặn. Tiếp tục tạo API Docker từ nhánh này; cần manifest Fuji thật trước readiness | API HTTPS, migrate head, JWT/AUTH/CORS đúng origin đã chọn và `/ready` 200 |
| BE-02 | BE | Bộ local đã đạt; chưa có API/Vault Fuji để chạy | Bằng chứng SIWE, ownership, publish/tracking/scanner và lỗi trên URL thật |
| BE-03 | BE | Giữ 4 RPC reads đồng thời/request; chưa có plan/receipt Fuji thật để đo | Latency/error getPlan/logs/receipt trên deployment thật; không lấy transport benchmark thay thế |
| BE-04 | BE | Endpoint proof/replacement và các test đã có; chưa nhận case/hash pending hỏng cụ thể | Đối chiếu case thật nếu có; thiếu raw/nonce thì giữ guard, không chỉnh DB thủ công |
| BE-05 | BE | Browser local 13 bước đạt trên source đã ghép | CI của SHA cuối xanh; thêm nghiệm thu Fuji khi có môi trường |
| BE-06 | BE | Đã test trên 100 bản ghi, owner/filter/order/cursor; đạt | Đã đóng phần API; state/nút tải tiếp là UI |
| BE-07 | BE | Chưa chọn scope booking/training/crowd ngoài core | Chỉ triển khai khi nhóm có đặc tả và nguồn dữ liệu; hiện vẫn là demo, không nhận DONE cho API chưa tồn tại |
| BE-08 | BE | README và bản bàn giao này đã cập nhật | Bổ sung URL/tx/hash/CI thật sau triển khai, không ghi nghiệm thu chưa chạy |

DB Render được tạo ngày 16/11/2026, dashboard ghi hết hạn 16/12/2026. Gói free phục vụ demo; cần sao lưu trước hạn. Không lưu database URL/JWT/private key trong tài liệu hoặc repo.

## Đầu vào từ các role khác

- **Solidity:** manifest Fuji và ABI đúng deployment, receipt/bundle/source verification. Gas deployer hiện vẫn 0 AVAX Fuji ở lần kiểm ngày 16/11; chưa deploy. Mode đã chọn DISABLED. Việc hỗ trợ deploy theo yêu cầu người dùng không biến thay đổi contract/tooling thành task của UI.
- **UI:** cung cấp origin web HTTPS cuối cùng để BE cấu hình AUTH_DOMAIN/AUTH_URI/CORS; pin chain/Vault/deployment theo config; nghiệm thu Core/MetaMask thực và hai thiết bị. Camera/native và các màn demo vẫn do UI phụ trách.
- **Người giữ tài khoản:** xác nhận các bước cấp quyền tài khoản/đăng nhập hoặc mở khóa ví khi dịch vụ yêu cầu; không gửi seed/private key qua chat.

Không có kết luận đã hoàn thành Fuji/HTTPS/extension từ kết quả test local.

## Cập nhật nghiệm thu và triển khai

- Commit sửa BE `f67e710` đã push lên `fix/be-nghiem-thu-1116`. Cả 5 CI của đúng SHA đều success: [backend](https://github.com/vqhung1387/PrePaidGuard_App/actions/runs/43795116651), [frontend](https://github.com/vqhung1387/PrePaidGuard_App/actions/runs/43795116630), [Solidity](https://github.com/vqhung1387/PrePaidGuard_App/actions/runs/43795116638), [contract tích hợp](https://github.com/vqhung1387/PrePaidGuard_App/actions/runs/43795116673), [browser](https://github.com/vqhung1387/PrePaidGuard_App/actions/runs/43795116745).
- Lượt bổ sung kiểm toàn bộ manifest: live fixture giờ chứa `vault_code_hash`, `adapter_address`, `treasury_address` lấy từ EVM thật. Thêm 6 ca kiểm adapter/mode và tương thích manifest cũ. Chạy toàn bộ BE với PostgreSQL/Hardhat thật: **84 passed, 0 skipped**; lint và format đạt. Hai cảnh báo deprecation của thư viện còn tồn tại, chưa nâng dependency chỉ để bỏ cảnh báo.
- Render: DB `prepaidguard-db` đã Available, PostgreSQL 16/Singapore/Free; external traffic đã bị chặn. Form `prepaidguard-api` dùng public repo, nhánh `fix/be-nghiem-thu-1116`, Dockerfile `backend/Dockerfile`, build context repo root và Free. Đã điền kết nối DB nội bộ, JWT secret riêng, chain 43113, ABI/manifest Fuji path và sync 20 giây, rồi bấm Deploy. Chưa nhận được service URL hoặc trạng thái Live trước khi công cụ trình duyệt mất kết nối; không coi thao tác bấm Deploy là triển khai thành công.
- Health check Render tạm đặt `/health` để dựng process/OpenAPI trước khi có manifest. **Đây chỉ là staging chưa sẵn sàng giao dịch.** Sau khi Solidity bàn giao Fuji manifest và UI bàn giao origin HTTPS, BE cấu hình AUTH_DOMAIN/AUTH_URI/CORS, kiểm `/ready` 200 rồi đổi health check Render sang `/ready`. Không để cấu hình liveness tạm này trở thành tiêu chí nghiệm thu.
- Chưa có private key/DB URL/JWT nào được đưa vào source, commit hoặc tài liệu. Không copy địa chỉ placeholder thành manifest Fuji để làm readiness xanh.
- Browser hiện không truy cập được trong chat. Đã tìm được tích hợp Render để người giữ tài khoản kết nối; chưa xác nhận kết nối. Chưa lấy được gas Fuji hoặc deploy contract, không có transaction hash Fuji để ghi nhận.
