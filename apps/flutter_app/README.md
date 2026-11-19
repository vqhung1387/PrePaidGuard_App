# PrepaidGuard Business · Flutter Web

Trang Khám phá mở từ URL gốc và tự tải danh sách gói. Khách có thể xem tổng trả trước, số kỳ, thời lượng và điều kiện hoàn gốc trước khi kết nối ví. Ba mục Gói của tôi, Cơ sở và Giao dịch yêu cầu đăng nhập bằng ví.

Bản phát hành chỉ có luồng API/ví. Các bài kiểm thử nội bộ vẫn có fixture mô phỏng tách khỏi điểm khởi động của app.

Yêu cầu backend đã migrate, có ABI/manifest đúng, `/ready` trả 200, và origin Flutter được khai báo trong `CORS_ORIGINS`. Cần ví trình duyệt EIP-1193 (MetaMask/Core tương thích) mở đúng network. App không nhận private key/seed.

Local chain 31337, ví dụ:

```sh
flutter pub get --enforce-lockfile
flutter run -d chrome --web-port 8080 --dart-define=CHAIN_ID=31337 --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

Fuji dùng `CHAIN_ID=43113` (mặc định), API HTTPS của nhóm và token testnet. Có thể pin `VAULT_ADDRESS` và `DEPLOYMENT_ID` bằng dart-define; nếu pin không khớp thì client chặn giao dịch. Client kiểm ABI version `prepaidguard-1`, token 6 decimals và mode MOCK/DISABLED. Hiển thị chain/Vault/deployment để người dùng kiểm trước khi ký.

Luồng:
1. Mở trang. Khi API đã kết nối, chọn **Kết nối ví / Đăng nhập**. Ví ký SIWE message từ backend bằng personal_sign; JWT chỉ ở RAM, không localStorage.
2. Trong mục Cơ sở, tạo hồ sơ rồi tạo gói dịch vụ. Nhập thời lượng như `30 ngày` hoặc `12 giờ`, hoặc nhập số ngày. Ví xác nhận công bố. Có thể mở lại bản nháp để công bố nếu lần ký trước chưa thành công.
3. Subscriber đọc điều khoản, approve đúng số token nếu thiếu allowance rồi subscribe. Nếu approve còn pending thì refresh và đăng ký lại sau khi confirmed.
4. Mở gói và **Tạo QR check-in** khi eligibility cho phép. Client ký EIP-712, kiểm signer và hiển thị QR/payload.
5. Merchant dùng **Nhập QR check-in** để dán payload. Client kiểm network/Vault, chữ ký, nonce, kỳ, deadline và eligibility trước yêu cầu ví gửi giao dịch. Hiện chưa tích hợp camera scanner; copy/paste là đường nhập được hỗ trợ.
6. Subscriber dùng **Refund** khi đủ điều kiện thời gian. Terminal state không tiếp tục check-in/refund.
7. **Chi tiết / lịch sử** đối chiếu subscription, live eligibility và event; cảnh báo `UNSUPPORTED_TIMESTAMP` được hiển thị, không giả là gốc bằng 0.

Hash transaction được lưu theo ví và deployment trước khi gọi tracking API. Sau reload, đăng nhập lại cùng ví rồi refresh để khôi phục pending; không gửi giao dịch lặp chỉ vì API/RPC timeout. Khi đổi ví/network trong lúc chờ chữ ký, hash trả về vẫn được lưu dưới ví bắt đầu giao dịch; không dùng JWT của ví mới để theo dõi thay. Người dùng vẫn cần kiểm tra lịch sử ví nếu provider lỗi trước khi trả hash.

Bản hiện tại ưu tiên Flutter Web và nhận check-in bằng cách dán payload QR. Native wallet, quét camera và luồng HTTPS/Fuji trên hai thiết bị cần nghiệm thu riêng. Registration QR ràng buộc plan ID + chain + Vault và mở plan tương ứng sau khi kết nối API.

Danh sách đăng ký có bộ lọc trạng thái riêng cho khách và cơ sở. **Tải thêm đăng ký của tôi**, **Tải thêm đăng ký tại cơ sở**, **Tải thêm gói của cơ sở** và **Tải thêm lịch sử** xuất hiện khi có trang tiếp theo. Nút **Chi tiết / lịch sử** mở chi tiết đăng ký. Thông tin kỹ thuật về mạng và Vault nằm trong hộp thoại tài khoản hoặc thông tin thanh toán.

Thẻ đăng ký và lịch sử phân biệt lợi tức mô phỏng `MOCK` với `DISABLED`. Mức ước tính chưa nhận và các khoản đã trả lấy từ `yield_summary` của API.

Kiểm tra:

```sh
flutter analyze
flutter test
flutter build web --dart-define=CHAIN_ID=31337 --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

Bộ real-mode tests kiểm HTTP envelope, ABI với contract xuất thật, vector EIP-712 TypeScript/Python/Dart, QR sai network/size, pin deployment, logout/đổi ví, refund eligibility và phục hồi hash khi RPC/API lỗi hoặc đổi account/network trong lúc ví đang gửi.

Tài liệu: [MetaMask RPC](https://docs.metamask.io/metamask-connect/evm/reference/json-rpc-api/eth_sendTransaction/), [ký dữ liệu](https://docs.metamask.io/metamask-connect/evm/guides/sign-data/), [Dart JS interop](https://dart.dev/interop/js-interop).

## Khôi phục khi cache lỗi và đồng hồ lệch

Tx hash được giữ ngay trong bộ nhớ theo ví/deployment trước khi ghi cache. Lỗi đọc/ghi cache không được coi là giao dịch chưa gửi; app vẫn đối chiếu API và hiển thị hash/cảnh báo. Khi cùng thao tác còn pending, app chặn gửi lặp trước cả bước approve. Bộ nhớ khôi phục được qua logout/login trong cùng controller; nếu vừa mất cache vừa mất API rồi reload/đóng app, cần đối chiếu lịch sử ví/explorer bằng hash đã giữ trước khi gửi lại.

QR dùng timestamp block trong eligibility LIVE để tạo và kiểm deadline900giây, không dùng đồng hồ thiết bị hoặc synced_at của server làm căn cứ tài chính. Timestamp sai định dạng/ngoài miền0..253402300799 và nguồn PROJECTION bị từ chối; contract vẫn xác thực nonce, kỳ, chữ ký và deadline lần cuối.

Xem [bàn giao 15/11](../../docs/ban-giao-sua-loi-2026-11-15.md): catalog20 mục/cursor, đối chiếu hash cancel/speed-up đã xác nhận, migration0003 và phần còn cần nghiệm thu.

Bản Fuji dùng API đã chọn lúc build. Thông tin gốc, giải ngân, hoàn gốc, điều kiện check-in và lịch sử đều lấy từ API theo ví đang đăng nhập.

Pending legacy thiếu nonce có thêm ô raw giao dịch gốc đã ký khi đối chiếu hash thay thế. Chỉ nhập signed transaction đã có (không seed/private key); raw được gửi cho API đang kết nối để kiểm chứng và không lưu trong cache. Không còn raw/nonce thì giữ guard và đối chiếu nguồn gốc, không tự xóa pending.
