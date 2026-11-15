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

Bạn cũng có thể mở **Chế độ Cơ sở → Tạo gói** để tạo gói riêng. Mỗi gói trong bản demo cho thử xác nhận kỳ đầu một lần. Số tiền, hồ sơ và lời mời là dữ liệu mô phỏng trong phiên. Đây là phạm vi của chế độ demo; chế độ API/ví thật bên dưới triển khai riêng, không dùng các Map mô phỏng này.

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
- lib/real: http client, controller, ví EIP-1193, signing/QR và workspace dữ liệu thật.
- lib/features: màn hình và dữ liệu demo, training, catalog, subscriptions, merchant.
- shared ngoài app: ABI và deployment; client đối chiếu API config và các pin khi build.
- lib/features: chức năng plans, subscriptions, check_in, refunds, merchant.
- lib/shared/widgets: widget tái sử dụng.
- test: unit/widget tests khi có logic cần kiểm chứng.

Không lưu private key hoặc backend secrets trong client. Chưa chọn SDK ví hay scanner; cần thử EIP-712 và QR trên thiết bị thật trước khi chốt.

## Chế độ API / ví thật (Flutter Web)

Bấm **Kết nối API / ví thật** trên màn hình đăng nhập demo hoặc mở URL có `?real=1`. Chế độ này tách khỏi dữ liệu mô phỏng; các số dư, trạng thái và lịch sử lấy từ API/backend và blockchain.

Yêu cầu backend đã migrate, có ABI/manifest đúng, `/ready` trả 200, và origin Flutter được khai báo trong `CORS_ORIGINS`. Cần ví trình duyệt EIP-1193 (MetaMask/Core tương thích) mở đúng network. App không nhận private key/seed.

Local chain 31337, ví dụ:

```sh
flutter pub get --enforce-lockfile
flutter run -d chrome --web-port 8080 --dart-define=CHAIN_ID=31337 --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

Fuji dùng `CHAIN_ID=43113` (mặc định), API HTTPS của nhóm và token testnet. Có thể pin `VAULT_ADDRESS` và `DEPLOYMENT_ID` bằng dart-define; nếu pin không khớp thì client chặn giao dịch. Client kiểm ABI version `prepaidguard-1`, token 6 decimals và mode MOCK/DISABLED. Hiển thị chain/Vault/deployment để người dùng kiểm trước khi ký.

Luồng:
1. Nhập API origin → **Kết nối API** → **Kết nối ví / Đăng nhập**. Ví ký SIWE message từ backend bằng personal_sign; JWT chỉ ở RAM, không localStorage.
2. Merchant tạo hồ sơ, tạo draft và publish gói bằng ví. Có thể publish lại draft đã tạo nhưng chưa gửi thành công.
3. Subscriber đọc điều khoản, approve đúng số token nếu thiếu allowance rồi subscribe. Nếu approve còn pending thì refresh và đăng ký lại sau khi confirmed.
4. Mở gói và **Tạo QR check-in** khi eligibility cho phép. Client ký EIP-712, kiểm signer và hiển thị QR/payload.
5. Merchant dùng **Nhập QR check-in** để dán payload. Client kiểm network/Vault, chữ ký, nonce, kỳ, deadline và eligibility trước yêu cầu ví gửi giao dịch. Hiện chưa tích hợp camera scanner; copy/paste là đường nhập được hỗ trợ.
6. Subscriber dùng **Refund** khi đủ điều kiện thời gian. Terminal state không tiếp tục check-in/refund.
7. **Chi tiết / lịch sử** đối chiếu subscription, live eligibility và event; cảnh báo `UNSUPPORTED_TIMESTAMP` được hiển thị, không giả là gốc bằng 0.

Hash transaction được lưu theo ví và deployment trước khi gọi tracking API. Sau reload, đăng nhập lại cùng ví rồi refresh để khôi phục pending; không gửi giao dịch lặp chỉ vì API/RPC timeout. Khi đổi ví/network trong lúc chờ chữ ký, hash trả về vẫn được lưu dưới ví bắt đầu giao dịch; không dùng JWT của ví mới để theo dõi thay. Người dùng vẫn cần kiểm tra lịch sử ví nếu provider lỗi trước khi trả hash.

Bản hiện tại ưu tiên Flutter Web và nhận check-in bằng cách dán payload QR. Native wallet, quét camera và luồng HTTPS/Fuji trên hai thiết bị cần nghiệm thu riêng. Registration QR ràng buộc plan ID + chain + Vault và mở plan tương ứng sau khi kết nối API.

Danh sách đăng ký có bộ lọc trạng thái riêng cho khách và cơ sở. **Tải thêm đăng ký của tôi**, **Tải thêm đăng ký tại cơ sở**, **Tải thêm bản nháp** và **Tải thêm lịch sử** xuất hiện khi API còn cursor. Dùng các nhãn nút này trong script nghiệm thu. Nút **Chi tiết / lịch sử** vẫn mở chi tiết đăng ký.

Thẻ đăng ký và lịch sử phân biệt lợi tức mô phỏng `MOCK` với `DISABLED`. Mức ước tính chưa nhận và các khoản đã trả lấy từ `yield_summary` của API.

Kiểm tra:

```sh
flutter analyze
flutter test
flutter build web --dart-define=CHAIN_ID=31337
```

Bộ real-mode tests kiểm HTTP envelope, ABI với contract xuất thật, vector EIP-712 TypeScript/Python/Dart, QR sai network/size, pin deployment, logout/đổi ví, refund eligibility và phục hồi hash khi RPC/API lỗi hoặc đổi account/network trong lúc ví đang gửi.

Tài liệu: [MetaMask RPC](https://docs.metamask.io/metamask-connect/evm/reference/json-rpc-api/eth_sendTransaction/), [ký dữ liệu](https://docs.metamask.io/metamask-connect/evm/guides/sign-data/), [Dart JS interop](https://dart.dev/interop/js-interop).

## Khôi phục khi cache lỗi và đồng hồ lệch

Tx hash được giữ ngay trong bộ nhớ theo ví/deployment trước khi ghi cache. Lỗi đọc/ghi cache không được coi là giao dịch chưa gửi; app vẫn đối chiếu API và hiển thị hash/cảnh báo. Khi cùng thao tác còn pending, app chặn gửi lặp trước cả bước approve. Bộ nhớ khôi phục được qua logout/login trong cùng controller; nếu vừa mất cache vừa mất API rồi reload/đóng app, cần đối chiếu lịch sử ví/explorer bằng hash đã giữ trước khi gửi lại.

QR dùng timestamp block trong eligibility LIVE để tạo và kiểm deadline900giây, không dùng đồng hồ thiết bị hoặc synced_at của server làm căn cứ tài chính. Timestamp sai định dạng/ngoài miền0..253402300799 và nguồn PROJECTION bị từ chối; contract vẫn xác thực nonce, kỳ, chữ ký và deadline lần cuối.

Xem [bàn giao 15/11](../../docs/ban-giao-sua-loi-2026-11-15.md): catalog20 mục/cursor, đối chiếu hash cancel/speed-up đã xác nhận, migration0003 và phần còn cần nghiệm thu.

Build có `--dart-define=API_BASE_URL=...` mở thẳng workspace dữ liệu thật; bản demo không cấu hình API vẫn mở đăng nhập mô phỏng và có nút ví để chuyển sang luồng thật. Chi tiết tài khoản hiển thị gốc trả trước/giải ngân/refund, eligibility, yield MOCK/DISABLED và lịch sử từ API, không lấy từ DemoWorkspace. Training/booking/giờ đông demo vẫn mô phỏng.

Pending legacy thiếu nonce có thêm ô raw giao dịch gốc đã ký khi đối chiếu hash thay thế. Chỉ nhập signed transaction đã có (không seed/private key); raw được gửi cho API đang kết nối để kiểm chứng và không lưu trong cache. Không còn raw/nonce thì giữ guard và đối chiếu nguồn gốc, không tự xóa pending.
