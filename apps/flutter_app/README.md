# PrepaidGuard · Flutter

Bản demo web mở ở màn hình đăng nhập. Dùng `demo@example.com` với mật khẩu `demo1234` hoặc tạo tài khoản bằng thông tin giả. Tải lại trang sẽ đặt lại tài khoản tự tạo, gói tự tạo, lịch sử và lời mời.

## Chạy local

Mở terminal tại `apps/flutter_app` với Flutter SDK trên PATH.

```sh
flutter pub get
flutter run -d edge
```

Dùng `-d chrome` nếu chạy bằng Chrome.

1. Trong **Tổng quan**, chọn **Khám phá gói tập** hoặc **Đăng ký gói tập**. Chọn **Gym Khởi Động** (3 tháng) và xác nhận tổng 43,2 USDC demo.
2. Bấm **Check-in kỳ đầu (demo)** ngay trên **Tổng quan**. Tiền gốc vẫn là 43,2 USDC trong lúc chờ cơ sở.
3. Mở menu chế độ trên thanh đầu trang và chọn **Chế độ Cơ sở**. Dùng tài khoản chủ gói để **Duyệt check-in** và **Xác nhận kỳ demo**. Tài khoản chủ của gói mẫu là `demo@example.com`.
4. Chuyển về **Chế độ Hội viên**. Trên **Tổng quan**, số dư mô phỏng còn 28,8 USDC, đã giải ngân 1/3 kỳ và hoạt động gần đây có mục xác nhận kỳ đầu.
5. Thử **Giới thiệu bạn tập** để sao chép liên kết gói mẫu. Liên kết trên localhost cần được mở trên cùng máy. Trong **Bạn tập**, lọc mục tiêu và thử gửi/hủy lời mời mô phỏng.

Bạn cũng có thể mở **Chế độ Cơ sở → Tạo gói** để tạo gói riêng. Mỗi gói trong bản demo cho thử xác nhận kỳ đầu một lần. Số tiền, hồ sơ và lời mời là dữ liệu mô phỏng trong phiên. Tích hợp ví, API, Avalanche Fuji, ký/quét QR và refund còn chờ triển khai.

Chạy `flutter analyze`, `flutter test` và `flutter build web` để kiểm tra.

## Giá gói tập mô phỏng

| Gói | USDC/tháng | Tổng USDC | Giảm so với mua từng tháng |
| --- | ---: | ---: | ---: |
| 1 tháng | 16 | 16 | 0% |
| 3 tháng | 14,40 | 43,20 | 10% |
| 6 tháng | 12,80 | 76,80 | 20% |
| 12 tháng | 12 | 144 | 25% |
| 24 tháng | 10,40 | 249,60 | 35% |

Gói 12 tháng tặng 7 ngày tập và gói 24 tháng tặng 15 ngày tập. Ngày tập tặng được cộng một lần sau khi cơ sở xác nhận check-in kỳ đầu. Ngày tặng cộng vào thời hạn tập. Tiền gốc giải ngân theo số kỳ đã mua.

Các gói dùng kỳ 30 ngày trong demo. Mức giá do PrepaidGuard đặt cho USDC thử nghiệm. Tham khảo thang giá 1–24 tháng của [Transform Gym](https://transformgym.vn/kien-thuc/gia-tap-gym-quan-6/) và cách dùng ngày tập tặng của [The New Gym](https://thenewgym.vn/cong-truong-sieu-peak-sap-toi-se-co-gi/).

## Cấu trúc

- lib/app: điểm ghép ứng dụng, router, theme và providers.
- lib/core/api: Dio client và xử lý phản hồi API.
- lib/core/wallet: kết nối ví, ký typed data và gửi giao dịch.
- lib/core/config: cấu hình API/network và địa chỉ contract.
- lib/features: chức năng plans, subscriptions, check_in, refunds, merchant.
- lib/shared/widgets: widget tái sử dụng.
- test: unit/widget tests khi có logic cần kiểm chứng.

Không lưu private key hoặc backend secrets trong client. Chưa chọn SDK ví hay scanner; cần thử EIP-712 và QR trên thiết bị thật trước khi chốt.
