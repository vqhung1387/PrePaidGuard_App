# Phát hành Web HTTPS — 16/11/2026

## Bản đang chạy

- Web: https://prepaidguard-web.onrender.com
- API: https://prepaidguard-api.onrender.com/docs
- Source của cả hai: `ccd4f38e9ee6fb8b29fa4eb2dd555c0b6ece928e`, nhánh `fix/be-nghiem-thu-1116`. Cả 5 CI của SHA này success. Không merge main hoặc đổi nhánh của thành viên khác.
- Web Render: `srv-dbtcnqjncjis739sldgg`, release `dep-dbtcnqrncjis739slgbg`, Live. Static site, không tạo thêm backend/DB. Auto-deploy OFF để chỉ phát hành bản đã review; push tài liệu không thay bundle web.
- API Render: `srv-dbt75f0ae00c739s69rg`, release `dep-dbtcnv5ckfvc73efivvg`, Live. Bản này kích hoạt AUTH/CORS mới. Không thay secret/DB URL hoặc mở firewall DB.
- Flutter `3.47.9` như CI; build kiểm SDK commit chính xác `c197ca5199e9ee5661e865596c9c07294dfab51c`, `pub get --enforce-lockfile`, `build web --release --no-pub`. Publish `apps/flutter_app/build/web`, không commit binary build.

Build pin `API_BASE_URL=https://prepaidguard-api.onrender.com`, `CHAIN_ID=43113`, `VAULT_ADDRESS=0xc2b19Df4e38CE6FA921120f2B16C8c3a9c6a2364`, `DEPLOYMENT_ID=43113-0xc2b19df4e38ce6fa921120f2b16c8c3a9c6a2364`. App mở thẳng workspace thật; màn mô phỏng vẫn có nút chuyển riêng. Không sửa giao diện/nghiệp vụ của role UI trong lượt phát hành này.

## AUTH và CORS đã áp dụng

```dotenv
AUTH_DOMAIN=prepaidguard-web.onrender.com
AUTH_URI=https://prepaidguard-web.onrender.com
CORS_ORIGINS=["https://prepaidguard-web.onrender.com"]
```

Không cho wildcard, localhost hoặc domain nhìn gần giống. `/api/v1/config` công khai trả đúng SIWE origin mới. Phiên ký theo URI API cũ cần đăng nhập lại, không xóa dữ liệu ứng dụng. Nếu nhóm đổi URL web, BE phải cập nhật ba giá trị trên và kiểm thử origin trước release.

## Kết quả kiểm thử

[Bằng chứng JSON](evidence/web-https-smoke-2026-11-16.json): **PASS**. HTTP/Chrome headless chạy trên URL HTTPS thật với profile tạm riêng, không đọc trình duyệt cá nhân. 21 kiểm tra và một bản ghi kết thúc.

- `/ready`200; config pin đúng chain/Vault/deployment/mode DISABLED và domain web.
- Preflight cho Authorization/Content-Type của web đạt. Origin ngoài, domain giả gần giống và localhost không được grant CORS; GET ngoài origin không có header cho phép đọc. CORS kiểm soát trình duyệt, không thay authentication/authorization.
- Tạo SIWE challenge trên DB thật, ký/xác minh đúng tài khoản, từ chối chain sai và replay challenge; logout rồi bearer cũ trả401. Không ghi JWT/chữ ký/private key vào evidence.
- Chrome mở bản release, gọi API mặc định mà không sửa textbox, tải gói Fuji thật, đăng nhập qua provider test EIP-1193 chỉ cho đọc account/chain và `personal_sign`, đọc danh sách của đúng chủ ví, logout qua UI và kiểm token bị thu hồi. Không có JavaScript page error.
- Không gửi giao dịch blockchain, không mint hoặc tiêu gas trong lượt smoke web này. Các phiên kiểm thử đã logout. Luồng chuyển tiền Fuji có bằng chứng riêng trong [bản deployment](fuji-deployment-2026-11-16.md).

Provider test không phải extension Core/MetaMask; chưa nhận đã nghiệm thu camera, native, QR giữa hai thiết bị vật lý hoặc UI speed-up/cancel bằng extension.

## Việc còn lại, mỗi việc một đầu mối

| Việc | Đầu mối | Thao tác / tiêu chí |
| --- | --- | --- |
| Health check Render | Người giữ tài khoản Render | [Settings API](https://dashboard.render.com/web/srv-dbt75f0ae00c739s69rg/settings) → Health Checks → Edit → `/ready` → Save Changes. BE kiểm lại service details và `/ready`200. Hiện vẫn `/health`; MCP không có thao tác sửa trường này. Browser Dashboard chưa kết nối; không nhận đã sửa hoặc đổi ý nghĩa `/health` để thay thế. |
| Nghiệm thu ví và hai thiết bị | UI | Mở URL web này với Core/MetaMask, thử từ chối ký/sai mạng/đổi account; SIWE, QR EIP-712 và cancel/speed-up. Ghi URL/hash/thiết bị thực tế. |
| Phát hành bản kế tiếp | UI | Build cùng các pin ở trên; review source SHA, dùng Manual Deploy trên static site, chờ Live và kiểm API/config/login. Không tự thay Vault hoặc mở CORS. |
| Contract bundle | Solidity | Review manifest/receipt và Sourcify exact match đã có; mode DISABLED, không deploy lại chỉ để đổi web. |
| DB và bài nộp | Người nhóm chọn | DB Free hết hạn16/12/2026; sao lưu trước hạn. Video/slide tách phần escrow Fuji thật và màn mô phỏng; kiểm quyền xem trước khi nộp. |

Health check Dashboard bị dừng ở bước đọc cửa sổ Chrome vì bộ duyệt tự động chưa xác định được tab Render và lo đọc nhầm nội dung riêng tư. Đã báo người dùng và đề nghị công cụ trình duyệt; chưa có kết nối Browse/TinyFish được xác nhận. Việc build/host/AUTH/CORS hoàn tất độc lập qua Render.
