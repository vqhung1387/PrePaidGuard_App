# Local browser acceptance

Script này chạy hai browser context độc lập với injected EIP-1193 test provider, FastAPI thật và EVM local chain31337. Provider yêu cầu Hardhat ký bằng tài khoản test đã mở khóa; không dùng private key, ví thật hay mạng Fuji của người dùng.

## Chuẩn bị

- Backend và PostgreSQL test đã migrate, /ready trả200, ABI/manifest khớp EVM.
- EVM HTTP loopback chain31337, tài khoản merchant=eth_accounts[1], subscriber=eth_accounts[2] có gas và token thử nghiệm.
- Build Flutter với CHAIN_ID=31337, host static trên loopback và CORS đúng origin.
- Đường dẫn Chrome/Edge cục bộ, uv để chạy dependencies PEP723 của script.

## Kiểm hai lỗi cache và clock cùng lúc

```powershell
uv run scripts/browser_acceptance/run.py `
  --browser 'C:/Program Files/Google/Chrome/Application/chrome.exe' `
  --app-url http://127.0.0.1:18080 `
  --api-url http://127.0.0.1:18000 `
  --rpc-url http://127.0.0.1:8545 `
  --inject-cache-failure `
  --merchant-clock-skew -30 `
  --subscriber-clock-skew 30 `
  --output-dir validation-results/cache-clock-browser
```

Đảo hai giá trị clock-skew để kiểm chiều ngược lại. Các giá trị là giây lệch so với đồng hồ máy chạy test. -30/+30 tạo độ lệch60giây giữa hai trình duyệt.

Fault injection bật lỗi localStorage.setItem CHỈ SAU khi subscriber đã broadcast giao dịch đến Vault, đồng thời trả503 cho API tracking SUBSCRIBE. Test xác nhận lỗi thực sự xảy ra, retry không gửi thêm approve/subscribe, chỉ có một subscription, rồi phục hồi cache/API và đợi tracking CONFIRMED. Sau đó ký/nhập QR, giải ngân, từ chối replay và refund; kiểm tiền gốc50+50+0 mUSDC cho gói hai kỳ100 mUSDC.

Kết quả browser-report.json và ảnh được lưu trong output-dir (validation-results đã gitignore). Script trả exitcode1 nếu bước cần thiết không đạt; không ghi JWT/chữ ký vào log hoặc trace. Kết quả pass không thay thế nghiệm thu ví extension thật, hai thiết bị vật lý hoặc Fuji.

Script thay đổi thời gian và trạng thái EVM TEST. Chỉ trỏ tới môi trường test riêng; không trỏ vào node đang dùng cho công việc khác. Script không tự dựng/tắt DB/API/EVM của bạn.
