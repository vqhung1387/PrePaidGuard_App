# PrePaidGuard

MVP UniHack cho quản lý ký quỹ dịch vụ trả trước trên Avalanche.

## Stack hiện tại

- Client: Flutter / Dart, http; ví trình duyệt EIP-1193 trên Web.
- Backend: Python / FastAPI / Pydantic; quản lý môi trường bằng uv.
- Database: PostgreSQL, SQLAlchemy, Alembic.
- Blockchain: Solidity, OpenZeppelin, Hardhat; Avalanche Fuji.

## Cấu trúc

| Thư mục | Trách nhiệm |
| --- | --- |
| apps/flutter_app | Giao diện khách hàng và merchant, kết nối ví, ký/quét QR |
| backend | API, xác thực quyền sửa metadata, dữ liệu ngoài blockchain |
| contracts | Smart contract, kiểm thử và script deploy |
| shared | ABI, địa chỉ triển khai và đặc tả payload dùng chung |
| docs | Luật nghiệp vụ, kiến trúc, phân công và demo |

## Trạng thái

Web và API đã phát hành trên Render với Avalanche Fuji. Xem [kết quả nghiệm thu và việc còn lại](docs/nghiem-thu-final-2026-11-19.md). Các màn hình lịch tập và đặt lịch demo dùng dữ liệu mô phỏng.

Xem [hướng dẫn backend](backend/README.md), [bàn giao tích hợp](docs/backend-handoff.md) và [deployment Fuji](docs/fuji-deployment-2026-11-16.md).

## Ranh giới trách nhiệm

- Contract là nguồn dữ liệu chuẩn cho số dư, giải ngân và quyền refund.
- Backend giữ metadata và dữ liệu hỗ trợ; không giữ private key của khách/merchant.
- Flutter yêu cầu ví ký giao dịch hoặc thông điệp EIP-712.
- ABI và địa chỉ theo network được xuất từ contract sang shared; không sửa tay nhiều bản.

Xem [bảng công việc](docs/task-board.md) để theo dõi phân công.

## Tài liệu thiết kế

Đọc project.md trước. Backend triển khai theo baseline B1–B6 dự kiến và OpenAPI sinh từ mã nguồn. Nhóm cần xác nhận baseline cùng ABI thực tế trước demo.

- [Tổng quan dự án](docs/project.md)
- [Data objects, DTO và EIP-712](docs/schema.md)
- [REST API và contract interface](docs/api.md)
- [Phân công và kế hoạch 14 ngày](docs/tasks.md)
- [Luồng người dùng và xử lý ngoại lệ](docs/user_flows.md)

Solidity có Vault, adapter MOCK, kiểm thử và script deploy/seed. Xem [bàn giao Solidity](docs/solidity-handoff.md). Nhánh tích hợp giữ cả frontend, backend và contract; main chưa thay đổi.
