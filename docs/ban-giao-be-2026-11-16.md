# Bàn giao BE — 16/11/2026

**Cập nhật mới nhất:** [Fuji/API và bằng chứng](fuji-deployment-2026-11-16.md), [web HTTPS đã phát hành](web-release-2026-11-16.md). API `/ready`200, luồng tiền Fuji PASS; AUTH/SIWE/CORS đã pin `https://prepaidguard-web.onrender.com`. Bảng BE dưới đây là trạng thái hiện tại. Các ghi chép thiếu gas/deploy ở mục lịch sử cuối tài liệu không còn là việc đang chờ.

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

## Trạng thái công việc BE hiện tại

| Mã | Chủ việc duy nhất | Đã chuẩn bị / đầu vào còn thiếu | Điều kiện đóng |
| --- | --- | --- | --- |
| BE-01 | BE | API/DB/Fuji Live, migration0003, `/ready`200, AUTH/CORS pin URL web thật | Còn healthCheckPath Render: người giữ tài khoản đổi `/health` thành `/ready`; endpoint đã hoạt động, không sửa liveness để che thiếu cấu hình |
| BE-02 | BE | Đã đóng: publish/subscribe/release/refund/replay/scanner trên Fuji/API/DB thật PASS | Bằng chứng JSON và tx trong bản deployment, không cần chờ gas/manifest nữa |
| BE-03 | BE | Đã đóng mẫu đo Fuji thật: getPlan/logs/tx+receipt và catalog, 20 mẫu không lỗi | Giữ concurrency4, không cache số dư; chưa nhận là load test100 plan/SLA |
| BE-04 | BE | Đã có proof/replacement và test local với/không nonce; không có incident pending cụ thể cần sửa | Nếu xuất hiện case thật thì nhận hash/raw/nguồn nonce từ người giữ ví; không tự mở guard hoặc chỉnh DB |
| BE-05 | BE | Local/CI và luồng tiền Fuji PASS; cả 5 CI của `ccd4f38` xanh | Bằng chứng web HTTPS ở bản release; nghiệm thu extension/hai thiết bị do UI thực hiện |
| BE-06 | BE | Đã test trên 100 bản ghi, owner/filter/order/cursor; đạt | Đã đóng phần API; state/nút tải tiếp là UI |
| BE-07 | BE | Ngoài scope core: chưa chọn booking/training/crowd | Không tự thêm API khi nhóm chưa có đặc tả/nguồn dữ liệu; các màn tương ứng vẫn mô phỏng |
| BE-08 | BE | Đã đóng: có URL API/web, tx/hash, source verification, CI và bàn giao từng role | Cập nhật lại nếu đổi release hoặc origin; không ghi nghiệm thu chưa chạy |

DB Render được tạo ngày 16/11/2026, dashboard ghi hết hạn 16/12/2026. Gói free phục vụ demo; cần sao lưu trước hạn. Không lưu database URL/JWT/private key trong tài liệu hoặc repo.

## Đầu vào từ các role khác

- **Solidity:** review manifest Fuji/ABI, receipt và Sourcify exact match đã có. Mode DISABLED, không cần deploy lại. Thay đổi contract/tooling vẫn do Solidity phụ trách.
- **UI:** web hiện đã phát hành và pin bundle Fuji; nghiệm thu Core/MetaMask thực, QR/cancel/speed-up trên hai thiết bị. Nếu đổi URL web thì cung cấp origin mới cho BE. Camera/native và các màn demo vẫn do UI phụ trách.
- **Người giữ tài khoản:** xác nhận các bước cấp quyền tài khoản/đăng nhập hoặc mở khóa ví khi dịch vụ yêu cầu; không gửi seed/private key qua chat.

Fuji/HTTPS có bằng chứng nghiệm thu thật riêng; kết quả local hoặc injected provider không thay nghiệm thu extension.

## Lịch sử trước khi nạp gas và deploy Fuji — chỉ để tra cứu

Phần này giữ kết quả staging ban đầu. Không dùng các trạng thái thiếu gas/manifest hoặc domain API ở đây làm trạng thái hiện tại; dùng bảng BE và hai bản deployment/release ở đầu tài liệu.

- Commit sửa BE `f67e710` đã push lên `fix/be-nghiem-thu-1116`. Cả 5 CI của đúng SHA đều success: [backend](https://github.com/vqhung1387/PrePaidGuard_App/actions/runs/43795116651), [frontend](https://github.com/vqhung1387/PrePaidGuard_App/actions/runs/43795116630), [Solidity](https://github.com/vqhung1387/PrePaidGuard_App/actions/runs/43795116638), [contract tích hợp](https://github.com/vqhung1387/PrePaidGuard_App/actions/runs/43795116673), [browser](https://github.com/vqhung1387/PrePaidGuard_App/actions/runs/43795116745).
- Lượt bổ sung kiểm toàn bộ manifest: live fixture giờ chứa `vault_code_hash`, `adapter_address`, `treasury_address` lấy từ EVM thật. Thêm 6 ca kiểm adapter/mode và tương thích manifest cũ. Chạy toàn bộ BE với PostgreSQL/Hardhat thật: **84 passed, 0 skipped**; lint và format đạt. Hai cảnh báo deprecation của thư viện còn tồn tại, chưa nâng dependency chỉ để bỏ cảnh báo.
- Render đã xác minh qua tích hợp tài khoản: API [prepaidguard-api](https://prepaidguard-api.onrender.com) **Live**, deploy `dep-dbt75fgae00c739s6atg`, source `f67e7109566368ea284e3be2dc5fc845d5b8638b`. Nhánh source là `fix/be-nghiem-thu-1116`; runtime Docker, `backend/Dockerfile`, build context repo root, Free/Singapore. `f65e98e` chỉ bổ sung test và bàn giao, không đổi runtime so với bản đang chạy.
- DB [prepaidguard-db](https://dashboard.render.com/d/dpg-dbt6srtg1s2s738umi0g-a) Available, PostgreSQL 16/Singapore/Free; external connections vẫn bị chặn. Không mở firewall để cho công cụ truy vấn SQL bên ngoài vào. Kết nối DB nội bộ được kiểm chứng qua SIWE/session trên HTTPS; `/ready` đã vượt qua kiểm Alembic head rồi trả lỗi thiếu manifest.
- Health check Render tạm đặt `/health` để dựng process/OpenAPI trước khi có manifest. **Đây chỉ là staging chưa sẵn sàng giao dịch.** Sau khi Solidity bàn giao Fuji manifest và UI bàn giao origin HTTPS, BE cấu hình AUTH_DOMAIN/AUTH_URI/CORS, kiểm `/ready` 200 rồi đổi health check Render sang `/ready`. Không để cấu hình liveness tạm này trở thành tiêu chí nghiệm thu.
- Chưa có private key/DB URL/JWT nào được đưa vào source, commit hoặc tài liệu. Không copy địa chỉ placeholder thành manifest Fuji để làm readiness xanh.
- Tích hợp Render đã kết nối và dùng được. Công cụ điều khiển trình duyệt/Core hiện chưa có, chưa lấy được gas Fuji. Đọc RPC lần cuối ngày 16/11 vẫn cho balance deployer `0x9B14012e9a4dccE26b4581086bC44Dc1BF5bE1f4` bằng 0 wei; không có transaction deploy Fuji.

### Nghiệm thu API HTTPS thật

[OpenAPI](https://prepaidguard-api.onrender.com/docs), [health](https://prepaidguard-api.onrender.com/health), [readiness](https://prepaidguard-api.onrender.com/ready). Bằng chứng đã loại token/chữ ký nằm trong [JSON nghiệm thu](evidence/be-hosted-smoke-2026-11-16.json).

**12 kiểm tra đạt:** health 200; readiness/config 503 `CONFIG_MISMATCH` khi thiếu Fuji manifest; tài khoản chưa đăng nhập bị từ chối 401; OpenAPI có endpoint phục hồi giao dịch; tạo SIWE challenge trên DB thật; ký/xác minh bằng ví test chỉ ở RAM; đọc đúng chủ tài khoản; dùng lại challenge bị chặn; logout thành công; JWT đã logout bị chặn; sai chain bị từ chối. Phiên test đã logout, không phát giao dịch blockchain. Domain/URI SIWE hiện trỏ API HTTPS, phải đổi cùng CORS khi UI bàn giao origin web cuối cùng.

DB hết hạn 16/12/2026; API Free có cold start. `/health` 200 và trạng thái Render Live không chứng minh Vault Fuji hoạt động. BE-01/02/03 còn phần nghiệm thu blockchain đã ghi trong bảng; UI vẫn tự nghiệm thu ví extension và hai thiết bị.
