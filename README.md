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

Nhánh solidity có Vault Solidity, MockUSDC, adapter yield MOCK, test, script deploy/seed và bộ ABI/chữ ký dùng chung. Đọc [bản bàn giao role C](docs/solidity-handoff.md) để chạy và tiếp tục triển khai Fuji. Backend được phát triển ở nhánh backend, Flutter ở nhánh frontend.

## Ranh giới trách nhiệm

- Contract là nguồn dữ liệu chuẩn cho số dư, giải ngân và quyền refund.
- Backend giữ metadata và dữ liệu hỗ trợ; không giữ private key của khách/merchant.
- Flutter yêu cầu ví ký giao dịch hoặc thông điệp EIP-712.
- ABI và địa chỉ theo network được xuất từ contract sang shared; không sửa tay nhiều bản.

## Bước tiếp theo

1. Chốt docs/business-rules.md và shared/check-in.schema.json theo hướng dẫn trong shared/README.md.
2. Chạy Hardhat và kiểm thử theo [README contract](contracts/README.md). Đối chiếu backend và Flutter ở các nhánh tương ứng.
3. Thử luồng kết nối ví, ký EIP-712 và xác thực contract trước khi mở rộng giao diện.
4. Làm tạo gói → đăng ký → check-in → refund bằng token thử nghiệm trên Fuji.

Xem [docs/tasks.md](docs/tasks.md) để phân công chi tiết.

## Tài liệu thiết kế

Các tài liệu dưới đây là bản thiết kế dự kiến, chưa phải mô tả API đã triển khai. Đọc project.md trước; các quyết định B1–B6 vẫn cần nhóm xác nhận.

- [Tổng quan dự án](docs/project.md)
- [Data objects, DTO và EIP-712](docs/schema.md)
- [REST API và contract interface](docs/api.md)
- [Phân công và kế hoạch 14 ngày](docs/tasks.md)
- [Luồng người dùng và xử lý ngoại lệ](docs/user_flows.md)
