# PrePaidGuard

MVP UniHack cho quản lý ký quỹ dịch vụ trả trước trên Avalanche.

## Stack dự kiến

- Client: Flutter / Dart, Riverpod, Dio.
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

Backend đã có FastAPI, migration PostgreSQL và bộ kiểm thử. Xem [hướng dẫn backend](backend/README.md) và [handoff tích hợp](docs/backend-handoff.md). Nghiệm thu demo cần bản Flutter và deployment Fuji của nhóm.

## Ranh giới trách nhiệm

- Contract là nguồn dữ liệu chuẩn cho số dư, giải ngân và quyền refund.
- Backend giữ metadata và dữ liệu hỗ trợ; không giữ private key của khách/merchant.
- Flutter yêu cầu ví ký giao dịch hoặc thông điệp EIP-712.
- ABI và địa chỉ theo network được xuất từ contract sang shared; không sửa tay nhiều bản.

## Bước tiếp theo

1. Chốt docs/business-rules.md và shared/check-in.schema.json theo hướng dẫn trong shared/README.md.
2. Chạy Flutter, Hardhat và backend theo README từng thư mục; kiểm tra deployment và ABI trước tích hợp.
3. Thử luồng kết nối ví, ký EIP-712 và xác thực contract trước khi mở rộng giao diện.
4. Làm tạo gói → đăng ký → check-in → refund bằng token thử nghiệm trên Fuji.

Xem [docs/tasks.md](docs/tasks.md) để phân công chi tiết.

## Tài liệu thiết kế

Đọc project.md trước. Backend triển khai theo baseline B1–B6 dự kiến và OpenAPI sinh từ mã nguồn. Nhóm cần xác nhận baseline cùng ABI thực tế trước demo.

- [Tổng quan dự án](docs/project.md)
- [Data objects, DTO và EIP-712](docs/schema.md)
- [REST API và contract interface](docs/api.md)
- [Phân công và kế hoạch 14 ngày](docs/tasks.md)
- [Luồng người dùng và xử lý ngoại lệ](docs/user_flows.md)

Solidity có Vault, adapter MOCK, kiểm thử và script deploy/seed. Xem [bàn giao Solidity](docs/solidity-handoff.md). Nhánh tích hợp giữ cả frontend, backend và contract; main chưa thay đổi.
