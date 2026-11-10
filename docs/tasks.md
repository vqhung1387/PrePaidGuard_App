# Tasks — Phân công nhóm 3 người

> Kế hoạch 14 ngày tương đối, design draft 0.1 — 11/11/2026. Chưa có task triển khai nào được đánh dấu Done.
> Điền tên thật thay A/B/C sau khi nhóm phân công. Ngày 1 là ngày nhóm bắt đầu thực hiện kế hoạch, không tự suy ra deadline cuộc thi.

## 1. Owner và cách phối hợp

| Thành viên | Phạm vi chính | Review chéo |
| --- | --- | --- |
| A — Flutter | app, Dart DTO, ví, camera/QR, giao diện subscriber và merchant | B kiểm API integration, C kiểm signing/amount |
| B — FastAPI/integration | auth, database, REST, receipt sync, backend deploy, README | A kiểm mobile contract, C kiểm chain verification |
| C — Solidity | Vault, adapter, contract tests, ABI export, Fuji deploy | B kiểm event/read model, A kiểm wallet flow |

Mỗi task một owner; review không chuyển trách nhiệm hoàn thành. Task chung vẫn chỉ định người điều phối.
Trạng thái dùng: TODO → IN_PROGRESS → REVIEW → DONE; BLOCKED phải ghi nguyên nhân và người có thể gỡ.
Ưu tiên P0 phải xong cho escrow demo; P1 yield/UI bổ sung sau luồng chính. Nếu cuộc thi bắt buộc yield, nâng Y01/Y02 lên P0.
Không ước tính story points trước khi thử SDK ví; các mốc là mục tiêu kiểm soát, không bảo đảm thời gian.

## 2. Chốt thiết kế và technical spike — Ngày 1–2

| ID | Task | Owner | Hạn | Phụ thuộc | Nghiệm thu |
| --- | --- | --- | --- | --- | --- |
| D01 | Đối chiếu thể lệ, deadline và tiêu chí chấm | B | D1 | Không | Ghi link thể lệ, yêu cầu yield, format bài nộp và thời lượng demo |
| D02 | Chốt B1–B6, cancellation và ranh giới thời gian | C | D1 | D01 | Cả nhóm review; sửa project/schema/api/flows đồng nhất trước code tiền |
| D03 | Chốt schema REST, event và EIP-712 | B | D1 | D02 | A/C duyệt field/type/order; có ví dụ success/error và Amount string |
| D04 | Kiểm chứng Flutter ví thật + SIWE + EIP-712 | A | D2 | D03 | Kết nối, ký cả login và typed data trên thiết bị demo; recover đúng signer |
| D05 | Fixture chữ ký dùng chung Dart/TypeScript/Python | C | D2 | D03,D04 | Cùng domain/message hash; sai chain/Vault/field order thất bại |
| D06 | Chọn Android/Web chính, host và quy trình Git | B | D2 | D01,D04 | Ghi môi trường chạy và người giữ cấu hình; quyết định SDK ví/scanner |

Gate D2: nếu SDK ví không ký typed data ổn định, đổi SDK/nền tảng demo trước khi viết thêm màn hình; không triển khai private key trong app để lách.

## 3. Flutter — Owner A

| ID | Task | Ưu tiên | Hạn | Phụ thuộc | Nghiệm thu |
| --- | --- | --- | --- | --- | --- |
| A01 | Khởi tạo Flutter, Riverpod, Dio, routing/theme/config | P0 | D2 | D06 | Chạy trên thiết bị chính, gọi health/config, chặn deployment mismatch |
| A02 | Dart DTO và API error handling | P0 | D3 | D03,A01 | Amount string, enum/null, cursor, 401/422/503 mapping đúng |
| A03 | Login/logout, secure token và đổi ví/network | P0 | D3 | A02,B03,D04 | Login thật, logout/expiry đúng, đổi ví không dùng JWT/QR cũ |
| A04 | Merchant profile và tạo/publish plan | P0 | D4 | B04,B05,C02 | Draft → ký createPlan → confirmed → QR đăng ký; không publish bằng cờ local |
| A05 | Xem plan, approve và subscribe | P0 | D5 | A03,B05,C03 | Hai transaction tách biệt, thiếu token/gas báo rõ; event mở đúng subscription |
| A06 | Thẻ hội viên, danh sách và lịch sử | P0 | D6 | B06,A05 | Số dư/kỳ/block sync khớp chain, phân biệt pending và confirmed |
| A07 | Ký CheckIn QR và countdown | P0 | D5 | D05,B06,C04 | Đúng domain/message, refresh nonce, expiry và chưa tới kỳ chặn đúng |
| A08 | Merchant scanner + preview + gửi check-in | P0 | D6 | A07,C04 | Hai thiết bị hoàn thành một release; scan trùng không trả hai lần |
| A09 | Eligibility/refund và terminal UI | P0 | D7 | B06,C05 | Trước hạn không mở quyền; confirmed refund khóa QR/check-in |
| A10 | Recovery pending tx, camera errors và UX ngoại lệ | P0 | D9 | B07,A04–A09 | Restart/mất mạng giữ hash; không báo tiền đã chuyển khi chưa confirmed |
| A11 | Yield labels và tổng quan đơn giản | P1 | D10 | Y01,Y02 | MOCK/estimate rõ ràng, số payout khớp events |
| A12 | Flutter integration test và bản Android demo | P0 | D12 | A10 | Happy path + expired QR + rejected signature + pending recovery chạy được |

## 4. Backend — Owner B

| ID | Task | Ưu tiên | Hạn | Phụ thuộc | Nghiệm thu |
| --- | --- | --- | --- | --- | --- |
| B01 | Khởi tạo FastAPI/uv, routers, settings và error envelope | P0 | D2 | D03 | Health/config/OpenAPI chạy, không lộ secrets, format error thống nhất |
| B02 | SQLAlchemy/Alembic entities và migrations | P0 | D3 | D03,B01 | DB mới migrate được; unique/check/index/precision theo schema |
| B03 | SIWE challenge/verify/session/me/logout | P0 | D3 | B02,D04 | Nonce consume nguyên tử, token expiry/revoke và sai chain được kiểm thử |
| B04 | Merchant API và ownership | P0 | D4 | B03 | CRUD phạm vi đề xuất; ví khác không sửa được; duplicate 409 |
| B05 | Draft API và published plan reads | P0 | D4 | B04,C02 | Draft terms validated, client_reference server cấp, published chỉ qua event |
| B06 | Subscription/list/eligibility/event reads | P0 | D6 | C03,C04,B02 | Subscriber/merchant scope đúng; live eligibility, sync metadata và pagination |
| B07 | Transaction submit/status + receipt verification | P0 | D5 | C02,C03,B03 | Tx sai contract/sender/event không CONFIRMED; retry hash không duplicate |
| B08 | Log sync command, cursor và rebuild projection | P0 | D7 | B07,C06 | App không báo tx vẫn phục hồi được; overlap scan không trùng event |
| B09 | API integration tests và OpenAPI rà soát | P0 | D10 | B03–B08 | Ownership, replay, receipt mismatch, amount precision, RPC outage được test |
| B10 | Deploy API/DB HTTPS và cấu hình demo | P0 | D7 | B01,B02,D06 | Thiết bị A gọi được host chung; không phụ thuộc localhost của người khác |
| B11 | README setup, migration, env, sync/recovery | P0 | D12 | B08,B10 | Người khác làm theo có thể dựng backend mà không cần hỏi secrets |

## 5. Smart contract — Owner C

| ID | Task | Ưu tiên | Hạn | Phụ thuộc | Nghiệm thu |
| --- | --- | --- | --- | --- | --- |
| C01 | Khởi tạo Hardhat, compiler/deps pin và MockUSDC | P0 | D2 | D02 | Compile/test local chạy, token decimals=6, không commit private key |
| C02 | Plan immutable + unique reference + PlanCreated | P0 | D3 | C01,D03 | Terms invalid/overflow/token sai bị từ chối; create trùng không tạo hai gói |
| C03 | Subscribe, transferFrom và read state | P0 | D3 | C02 | Đúng gốc, owner/nonce/mốc thời gian; thiếu allowance revert |
| C04 | EIP-712 check-in và giải ngân theo kỳ | P0 | D5 | C03,D05 | Đúng caller/signature/nonce/period/deadline; reject early và replay |
| C05 | Refund + trạng thái cuối + time boundary | P0 | D6 | C03,D02 | Đúng caller/hạn, gốc trả đúng, refund và check-in không chi trùng |
| C06 | ABI/event/deployment export | P0 | D4–D7 | C02–C05 | shared có ABI thật, deployment_id/chain/address/block; A/B không copy tay |
| C07 | Contract edge/invariant tests | P0 | D7 | C04,C05 | Multi-user, rounding, transfer/adapter failure, double spend, bảo toàn gốc |
| C08 | Deploy Fuji và seed demo | P0 | D7 | C06,C07 | Hai ví đủ gas/token, có subscription đủ kỳ và đủ refund; explorer xác minh |
| C09 | Rà soát quyền/withdraw paths và khóa surface demo | P0 | D11 | C08,Y01 | Không có public drain/mint/time override; mock funding tách script |

## 6. Yield và tích hợp

| ID | Task | Owner | Ưu tiên | Hạn | Phụ thuộc | Nghiệm thu |
| --- | --- | --- | --- | --- | --- | --- |
| Y01 | IYieldAdapter + mock có backing, hạch toán từng subscription | C | P1 | D8–D9 | C07 | Không trộn gốc/lãi; rút thiếu revert nguyên tử; payout 70/20/remainder |
| Y02 | Expose yield summary và ghép UI | B | P1 | D9–D10 | Y01,A06 | Estimated khác paid, mode MOCK rõ ràng, contract/API/UI khớp |
| I01 | Chạy xuyên suốt local rồi Fuji trên hai thiết bị | B | P0 | D5,D7 | A05,A08,A09,B07,C08 | Tạo plan → subscribe → check-in → refund gói khác; lưu tx evidence |
| I02 | Ngoại lệ tích hợp và simultaneous operations | C | P0 | D10 | I01 | QR hết hạn/sai merchant, scan đôi, refund boundary, adapter fail không mất gốc |
| I03 | Quan sát người dùng thử và chỉnh UX | A | P1 | D11 | I01 | Một người ngoài nhóm làm flow; ghi vướng mắc và sửa lỗi cản demo |
| I04 | Bộ tài liệu và link nộp chính thức | B | P0 | D12 | D01,I01 | README, env examples, ABI/address, tx mẫu, slide draft đầy đủ |
| I05 | Đóng băng, video và rehearsal | A | P0 | D13 | I02,I04 | Video có thể dùng khi RPC lỗi; cả nhóm diễn tập đúng thời lượng |
| I06 | Kiểm tra cuối và nộp | B | P0 | D14 | I05 | Link truy cập được, bản app sẵn, tài khoản/token/gas đủ, đúng thể lệ |

Cần giữ interface adapter sớm khi thiết kế Vault, nhưng chưa tích hợp yield trước khi escrow P0 ổn định. Nếu thay adapter làm thay Vault/ABI, deploy lại trước freeze và cập nhật deployment_id; chạy lại mọi contract/integration tests liên quan.

## 7. Các gate và phương án cắt phạm vi

| Gate | Điều kiện | Nếu không đạt |
| --- | --- | --- |
| Cuối D2 | Ví ký SIWE/EIP-712 trên thiết bị thật | Đổi SDK/nền tảng trước; không thêm embedded wallet |
| Cuối D3 | Local createPlan + subscribe chạy | A/B tiếp tục với fixture đã chốt, C ưu tiên gỡ luồng tiền |
| Cuối D5 | Check-in xuyên suốt local | Dừng dashboard đẹp và tính năng phụ |
| Cuối D7 | Subscribe/check-in/refund trên Fuji | Bỏ P1; giữ escrow và test, báo nhóm để điều chỉnh scope |
| Cuối D10 | Error cases + recovery ổn định | Không tích hợp BENQI thật hoặc công nghệ mới |
| D13 | Freeze tính năng | Chỉ sửa lỗi cản chạy/demo, regression test phần bị sửa |

## 8. Definition of Done

- Output đáp ứng nghiệm thu trong bảng, không chỉ có màn hình/mock response.
- Đúng quyền, amount precision, schema/API/EIP-712, có loading/error/pending cần thiết.
- Test có ý nghĩa cho logic thay đổi; không cần viết test chỉ để kiểm file/thư mục tồn tại.
- Reviewer khác owner đã xem phần giao tiếp giữa hai lớp.
- Document/ABI/config cập nhật cùng thay đổi; không commit .env, token hoặc private key.
- Môi trường demo chạy được; chain transaction có explorer evidence.
- Chưa có migration/deploy/receipt thì không đánh dấu task đó DONE.

## 9. Nhịp làm việc

Mỗi ngày 10–15 phút: kết quả đã chạy được, blocker, task tiếp theo. Merge nhỏ mỗi ngày sau review.
Thay interface phải báo hai thành viên còn lại và cập nhật cả schema/api/flows trước khi ghép.
Track issue theo ID trên bảng; log quyết định B1–B6 trong project.md.
Không phân công riêng người “làm slide” toàn kỳ; chuẩn bị bài nộp là việc song song sau khi có demo.
