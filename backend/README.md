# FastAPI backend

Khung thư mục, chưa có ứng dụng hoặc dependencies.

Quản lý Python bằng uv. Khi bắt đầu triển khai, khởi tạo pyproject bằng uv init --bare; dùng uv add để thêm FastAPI, Pydantic, SQLAlchemy, Alembic và web3.py khi cần. Dùng uv run cho lệnh phát triển. Không cần cài toàn bộ trước khi có nhu cầu.

- app/api: routes và dependencies cho HTTP API.
- app/core: settings và xác thực.
- app/models: SQLAlchemy models.
- app/schemas: Pydantic request/response schemas.
- app/services: nghiệp vụ ngoài blockchain.
- app/blockchain: đọc contract và xác minh giao dịch.
- migrations: Alembic migrations sau khi khởi tạo.
- tests: kiểm thử backend.

Backend không quyết định số dư/quyền refund và không giữ private key của người dùng. Chỉ ghi nhận thanh toán sau khi xác minh giao dịch trên đúng chain và contract.
