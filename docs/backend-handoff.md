# Tích hợp backend PrePaidGuard

## D01 — Thể lệ đối chiếu ngày 11/11/2026

- [FAQ Team1 Vietnam](https://team1vn.xyz/#faq-submit) hướng dẫn nộp từ mục Submit Project trên profile và đóng lúc **23:59 ngày 21/11/2026, giờ Việt Nam**. Hồ sơ gồm repo, link slide Canva/Google Slides, video demo 2–3 phút và tài liệu bổ sung. Kiểm tra quyền xem trước khi nộp. Nếu repo private, FAQ yêu cầu cấp quyền cho tài khoản BTC nêu trong trang.
- [Avalanche Builder Hub](https://build.avax.network/events/596c0b2d-63aa-4cf0-a0ad-a7e34ddbfdc0) hiển thị đường nộp và hạn khác. Nhóm lấy mốc sớm hơn trên Team1 làm hạn nội bộ. Cần xác nhận kênh nộp nếu hai dashboard vẫn khác nhau.
- FAQ chấm kỹ thuật 25, tích hợp Avalanche 25, sáng tạo 15, tác động 15, pitch 10 và UI/UX/demo 10. Fuji là mạng được chấp nhận. Hai trang công khai đã đọc không nêu yield thật là điều kiện bắt buộc hoặc thời lượng pitch trực tiếp từng đội. Demo có thể trình bày escrow trên Fuji và ghi rõ yield là MOCK nếu bật.

## D03 — Bản giao diện để mobile và contract review

- Chạy API và mở `/docs` hoặc tải `/openapi.json`. Đối chiếu đủ 24 thao tác với [docs/api.md](api.md). HTTP body gồm DTO trực tiếp. Số tiền/ID chain/block number là chuỗi số nguyên. Phiên JWT mang chain ID, ví và session; logout thu hồi session ở DB.
- Mobile ký chính xác chuỗi SIWE do `POST /api/v1/auth/challenge` trả về. Client chỉ gửi `challenge_id` và chữ ký 65 byte đến verify. Kiểm thử ví Flutter trên thiết bị thật vẫn thuộc D04.
- Ký CheckIn theo domain, thứ tự, kiểu trường và TTL trong [docs/schema.md](schema.md). API eligibility chỉ trả điều kiện theo block, QR và giao dịch do ví ký. Payload QR và fixture chữ ký dùng chung cần bên C chốt cùng A/B trước nghiệm thu.
- Adapter BE đọc tên trường getter, calldata và event theo ABI do contract xuất. Hai getter có thể trả tuple có tên trường hoặc các đầu ra có tên. Xem [backend/README.md](../backend/README.md) cho manifest, mã enum, đường dẫn và dữ liệu cần xác nhận với C. Test RPC hiện dùng ABI fixture theo tài liệu draft. Chạy lại test với ABI thật trước khi deploy demo.
- Backend dùng B1–B6 trong [docs/project.md](project.md) làm baseline đọc trạng thái. Đặc biệt, tại đúng `refund_available_at` thì check-in đóng và refund mở. Luồng chuyển tiền vẫn thực thi trong Vault.

## D06, B10, I01, I04 và I06 — Môi trường và điều kiện nghiệm thu

- Nền tảng demo theo thiết kế hiện tại là Android sau D04. Host đề xuất là Render HTTPS + PostgreSQL cho demo, có Blueprint và hướng dẫn trong backend README. Nhóm cần workspace được cấp quyền repo và người quản lý biến môi trường.
- Làm và push trên nhánh `backend`. A review API/DTO, C review ABI/đối chiếu receipt. Chạy CI trên PR backend → main và ghép sau review. ABI và manifest phải là bản xuất từ C.
- B10 cần URL HTTPS đã deploy, `/ready` trả 200 và Android gọi được URL đó. I01 cần hai ví/thiết bị trên Fuji, có tx hash publish, subscribe, release và refund của gói đủ hạn. Kiểm tra thêm việc sync lịch sử khi client chưa báo hash.
- I04 cần link repo/slide/video, cấu hình demo công khai, ABI và địa chỉ thật, cùng explorer evidence. I06 cần kiểm lại trên thiết bị và dashboard, xem link với tư cách người chấm rồi xác nhận đã submit. Trạng thái hiện tại của các bước này phụ thuộc bản Flutter, Vault Fuji, quyền host và bộ bài nộp của nhóm.

### Kiểm thử I01 local

Đã chạy BE tại commit `ce8e154` với PostgreSQL 16, Anvil chain 31337 và Vault fixture biên dịch bằng Solidity 0.8.28. Hai ví test ký SIWE và CheckIn EIP-712. API xác nhận publish, subscribe, giải ngân và refund từ receipt thật trên Anvil. Scanner khôi phục gói thứ hai từ log khi client chưa báo hash. Giao dịch quét lại trả REVERTED. Với 200 mUSDC cấp ban đầu, kết thúc luồng có 50 mUSDC ở ví merchant, 100 ở ví subscriber và 50 còn trong Vault của gói đang chạy. Fixture tắt yield. Vẫn cần chạy luồng này với bản Flutter và deployment Fuji thật để nghiệm thu I01.

## I04 — Nội dung nháp cho pitch và demo

1. **Vấn đề.** Khách trả trước toàn bộ gói dịch vụ. Nhóm muốn merchant nhận tiền theo kỳ đã sử dụng và khách có thể hoàn phần chưa dùng theo thời hạn đã công bố.
2. **Cơ chế.** Vault giữ gốc bằng MockUSDC. Khách ký QR cho từng kỳ, merchant gửi giao dịch check-in. Refund và giải ngân áp dụng điều kiện tại block thực thi.
3. **Demo.** Hiển thị publish và subscribe trên hai ví, quét QR để giải ngân một kỳ, rồi quét lại và quan sát từ chối. Mở gói thứ hai đã đến hạn, refund và đối chiếu lịch sử với explorer.
4. **Bằng chứng cần điền.** Git SHA, URL API, deployment ID, Vault, token, bốn tx hash Fuji và mode yield. Ghi rõ token thử nghiệm và trạng thái từng phần. Kiểm tra quyền truy cập repo, slide và video trước khi bấm Submit.
