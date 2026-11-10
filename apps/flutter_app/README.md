# Flutter client

Khung thư mục, chưa phải ứng dụng Flutter chạy được. Khi khởi tạo Flutter, chọn nền tảng demo chính trước và kiểm tra diff để giữ cấu trúc lib/.

- lib/app: điểm ghép ứng dụng, router, theme và providers.
- lib/core/api: Dio client và xử lý phản hồi API.
- lib/core/wallet: kết nối ví, ký typed data và gửi giao dịch.
- lib/core/config: cấu hình API/network và địa chỉ contract.
- lib/features: chức năng plans, subscriptions, check_in, refunds, merchant.
- lib/shared/widgets: widget tái sử dụng.
- test: unit/widget tests khi có logic cần kiểm chứng.

Không lưu private key hoặc backend secrets trong client. Chưa chọn SDK ví hay scanner; cần thử EIP-712 và QR trên thiết bị thật trước khi chốt.
