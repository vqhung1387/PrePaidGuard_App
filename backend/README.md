# FastAPI backend

API cho SIWE, merchant, plan draft, subscription, receipt tracking và đồng bộ event. PostgreSQL giữ metadata và bản đọc từ chain. Ví người dùng ký giao dịch trực tiếp tới Vault.

## Chạy local

Cần Python 3.12, [uv](https://docs.astral.sh/uv/) và PostgreSQL 16. Tạo database `prepaidguard` rồi chạy từ thư mục `backend/`:

```sh
uv sync --locked
```

Sao chép `.env.example` thành `.env`, điền `DATABASE_URL`, rồi tạo `ACCESS_TOKEN_SECRET` mới:

```sh
uv run --locked python -c "import secrets; print(secrets.token_urlsafe(32))"
uv run --locked alembic upgrade head
uv run --locked uvicorn app.main:app --reload
```

`GET /health` kiểm tra API. `GET /ready` kiểm tra migration, chain, Vault, token và decimals. OpenAPI ở `/docs` và `/openapi.json`. Kết nối database có thể dùng URL `postgresql+psycopg://` hoặc `postgresql://`. Đặt `AUTH_DOMAIN` đúng authority của `AUTH_URI` (gồm port nếu có). Nếu dùng proxy, cấu hình Uvicorn chỉ tin IP proxy thực tế để rate limit theo IP hoạt động đúng.

Khi nối Flutter Web chạy bằng `flutter run -d chrome --web-port 8080`, đặt các biến backend theo origin của trang Flutter:

```dotenv
CORS_ORIGINS=["http://localhost:8080"]
AUTH_DOMAIN=localhost:8080
AUTH_URI=http://localhost:8080
```

Frontend gọi API ở `http://localhost:8000`. Khi deploy hai dịch vụ riêng, đặt `CORS_ORIGINS` và domain SIWE theo URL HTTPS của Flutter, rồi trỏ client tới URL HTTPS của API. Origin là scheme, hostname và port, không kèm dấu `/` cuối. Trình duyệt có thể đọc các header `X-Request-ID`, `Retry-After` và `WWW-Authenticate`.

## Nối với Vault

Đặt `ABI_FILE` và `DEPLOYMENT_FILE` trỏ tới file do contract team xuất trong `shared/`. Đường dẫn tương đối tính từ `backend/`. `CHAIN_ID` phải khớp manifest, mặc định Fuji 43113. Có thể đặt `RPC_URL` riêng cho server. API `/config` chỉ trả URL công khai đã cấu hình trong manifest. Khi chưa có ABI/manifest, health và OpenAPI vẫn hoạt động, endpoint cần Vault trả `503 CONFIG_MISMATCH`.

ABI nhận mảng ABI hoặc artifact có khóa `abi`. Khi nạp cấu hình, backend đối chiếu các trường getter, calldata, event và thứ tự/kiểu của tuple CheckIn theo [schema](../docs/schema.md) và [API](../docs/api.md). ABI không tương thích trả `503 CONFIG_MISMATCH`. Bên contract cần xác nhận mã enum thật và các trường dưới đây khi xuất manifest. Đây là **ví dụ định dạng** với placeholder, cần thay bằng dữ liệu từ deployment:

```json
{
  "deployment_id": "fuji-demo-v1",
  "chain_id": 43113,
  "chain_name": "Avalanche Fuji",
  "public_rpc_url": "https://api.avax-test.network/ext/bc/C/rpc",
  "explorer_url": "https://explorer-test.avax.network/c-chain",
  "vault_address": "<Fuji Vault address>",
  "token": {"address": "<Fuji MockUSDC address>", "symbol": "mUSDC", "decimals": 6},
  "abi_version": "1",
  "deployment_block": 0,
  "yield_mode": "DISABLED",
  "confirmations": 1,
  "subscription_status_codes": {"active": 0, "completed": 1, "refunded": 2}
}
```

Dùng block deploy thật để bắt đầu scan. `public_rpc_url` và `explorer_url` phải dùng HTTPS trong môi trường demo. `estimated_unclaimed` của bản đọc từ DB có thể là `null` trong mode MOCK. Chi tiết gói đọc estimate live. Mọi amount và ID on-chain serialize thành chuỗi decimal.

## Đồng bộ và phục hồi

```sh
uv run --locked python -m app.services.sync --max-batches 100
uv run --locked python -m app.services.sync --rebuild --max-batches 100
```

Chạy lệnh đầu sau khi deploy và trước demo để bắt kịp chain. `SYNC_INTERVAL_SECONDS` lớn hơn 0 bật sync định kỳ cho API. CLI và API dùng cùng khóa theo deployment để ghi event và cursor. Mặc định quét tối đa 90 block mới và 8 block chồng lấn mỗi lần. Giữ tổng `SYNC_BATCH_SIZE` và `SYNC_OVERLAP` không quá 100 nếu dùng RPC công khai Fuji. `--rebuild` xóa bản đọc trong phạm vi Vault đang cấu hình, bỏ liên kết publish cũ và đưa tracking về SUBMITTED để đối chiếu lại. Hồ sơ, nội dung draft và phiên đăng nhập được giữ. Dùng lệnh này khi đã kiểm tra config và có thể chờ scan từ deployment block. Event ID có thể thay đổi khi dựng lại.

Receipt chỉ thành CONFIRMED khi match sender, Vault, chain, calldata và event đã đủ xác nhận. API scan tối đa hai batch mỗi lần đối chiếu receipt. Nếu cursor chưa tới block, response vẫn SUBMITTED và client có thể poll. Phải giữ tx hash qua khi mất mạng. RPC lỗi trả 503 và giữ trạng thái để thử lại.

## Test và deploy demo

Tạo PostgreSQL database dành cho test rồi đặt `TEST_DATABASE_URL`. Test tạo schema riêng cho mỗi case, chạy Alembic và dọn schema sau đó. CI chạy với PostgreSQL 16. Bộ test RPC mô phỏng dùng Web3 thực để giải mã ABI. Bộ test bundle kiểm ABI xuất từ Solidity và chữ ký TypeScript/Python. Khi đặt thêm `CONTRACT_TEST_RPC=http://127.0.0.1:8545` với node local và contract đã build, test tích hợp chạy PrepaidVault thật ở cả DISABLED và MOCK. Xem [contracts/README.md](../contracts/README.md).

```sh
uv run --locked ruff check .
uv run --locked ruff format --check .
uv run --locked alembic check
uv run --locked pytest -q
```

Blueprint [render.yaml](../render.yaml) cấu hình API và PostgreSQL cho demo. Trong workspace của nhóm, tạo Blueprint từ nhánh `backend` sau khi ABI/manifest thật có mặt trong nhánh đó. Điền hai đường dẫn từ `backend/`, ví dụ `../shared/abi/<file>.json` và `../shared/deployments/<file>.json`. Render cấp DB URL, tạo JWT secret và công bố HTTPS. Mặc định backend dùng hostname HTTPS Render cho SIWE. Nếu đội dùng domain khác, đặt cả `AUTH_DOMAIN` và `AUTH_URI`. Điền URL HTTPS vào `API_BASE_URL` của Flutter sau khi `/ready` trả 200 và `/config` khớp bundle mobile. Bản miễn phí có cold start và DB hết hạn sau 30 ngày, nên làm nóng trước demo và giữ bản sao metadata nếu cần.

Có thể build cùng image ngoài Render từ repo root với `docker build -f backend/Dockerfile -t prepaidguard-backend .`. Container chạy migration lúc khởi động. Cấp DB URL và các biến môi trường demo từ secret store của host, rồi đặt HTTPS ở reverse proxy.

Xem [handoff](../docs/backend-handoff.md) để đối chiếu nhiệm vụ và tiêu chí nghiệm thu trên thiết bị.
