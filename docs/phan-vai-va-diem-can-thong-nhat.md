# Phân vai và các điểm nhóm cần thống nhất

Tài liệu này tách **đề xuất phân công**, **trạng thái code đã có** và **quyết định chưa chốt**. Đây là đề xuất để nhóm xác nhận, không phải thông báo nhóm đã đồng ý hoặc tự giao thêm việc cho một thành viên.

A = UI/Flutter; B = BE/FastAPI; C = Solidity. Nhóm điền tên thật sau khi thống nhất. Người giữ ví thực hiện các bước cần mở khóa/ký; không gửi seed/private key cho người khác.

**Hiện trạng kỹ thuật 16/11/2026:** [Fuji đã deploy](fuji-deployment-2026-11-16.md), [web/API HTTPS và health check đã nghiệm thu](web-release-2026-11-16.md). Những kết quả này cập nhật cột hiện trạng, không tự nhận nhóm đã thống nhất tất cả D1–D10 hoặc gán tên thành viên. Bản tích hợp hiện ở nhánh `fix/be-nghiem-thu-1116`, chưa merge main.

## 1. Mỗi đầu việc một đầu mối

| Đầu mối | Sản phẩm phải bàn giao | Phạm vi sửa chính | Đầu vào nhận từ role khác |
| --- | --- | --- | --- |
| A — UI | Màn hình, UX ví, ký SIWE/EIP-712, gửi giao dịch, QR/camera, gọi API, phân trang, hiển thị pending và kiểm thử Flutter | apps/flutter_app; workflow frontend | OpenAPI và URL từ B; ABI/domain/địa chỉ từ C |
| B — BE | Auth/quyền, DTO REST, DB/migration, tracking/nonce proof, event projection/reorg, RPC, host API, readiness và bộ test tích hợp | backend; render.yaml; scripts/validation; scripts/browser_acceptance; workflow backend/browser/integration | ABI/manifest/event chuẩn từ C; hành vi/locator UI từ A |
| C — Solidity | Vault/adapter, luật tài chính trong contract, signing vector, ABI export, deploy/verify Fuji và receipt | contracts; shared/abi; shared/deployments; shared/check-in.*; workflow solidity | Chính sách được nhóm chốt; lỗi event/receipt do B báo; vấn đề ký do A báo |

- Phần API/schema trong docs/api.md và docs/schema.md do B cập nhật; schema EIP-712/event trong shared do C xuất. A/B đọc các file shared, tránh sửa tay bản ABI riêng.
- docs và README từng phần do đầu mối phần đó cập nhật. Báo cáo tích hợp tổng do B tổng hợp; nội dung demo/video do người nhóm chỉ định phụ trách.
- Review hoặc hỗ trợ không tự chuyển đầu mối. B test giao diện trong E2E không có nghĩa B nhận thiết kế/sửa mọi màn hình; C giúp kiểm chữ ký không nhận toàn bộ kết nối ví.
- Khi một thay đổi đụng hai role, chia thành hai đầu ra có cùng tiêu chí, ví dụ B thêm API cursor; A thêm nút tải tiếp. Người điều phối chỉ theo dõi giao điểm.

## 2. Chia việc tiếp theo thành phần không chồng nhau

| ID | Đầu mối duy nhất | Việc thực hiện | Phụ thuộc / người kiểm | Hoàn thành khi |
| --- | --- | --- | --- | --- |
| C-FUJI | C | Chuẩn bị gas testnet, deploy/verify Vault/token/adapter, xuất manifest/ABI và receipt | Người giữ ví hỗ trợ cấp gas/ký; B đọc kiểm cấu hình | Có địa chỉ, chain43113, deployment block/hash, confirmations và manifest đúng contract |
| B-HOST | B | Host PostgreSQL/API HTTPS, backup/migrate0003, RPC/AUTH/CORS, readiness | Nhận manifest/ABI từ C và origin web từ A | /ready đạt, SIWE/receipt/sync chạy trên URL API thật |
| A-RELEASE | A | Build/host Flutter Web, pin chain/Vault/deployment, cấu hình API URL, UX ví và dữ liệu thật | Nhận URL từ B, địa chỉ/domain từ C | Một URL app dùng được, phân biệt demo và thật, không cần nhập cấu hình thủ công cho bản phát hành |
| B-RECOVERY | B | Kiểm raw proof/nonce/receipt, tracking và reorg; cung cấp lỗi/DTO chuẩn | A đọc OpenAPI; C kiểm ý nghĩa giao dịch nếu cần | Bộ test BE/EVM qua; sai ví/chain/nonce/hash không mở guard |
| A-RECOVERY | A | UI nhập hash/raw nếu có, phục hồi sau reload/hết phiên, hiển thị lỗi BE, không gửi lặp | B cung cấp API/error; người giữ ví thao tác extension | Hủy/tăng phí bằng ví thật có thể đối chiếu; không cần sửa cache/DB |
| A-PAGING | A | Tải tiếp subscriptions/drafts/events vượt100, giữ filter và trạng thái màn hình | B hỗ trợ endpoint hiện có nếu phát hiện thiếu | Xem được mục101 và không trùng/bỏ sót trong cùng cách phân trang |
| B-RPC | B | Đo getPlan/receipt/logs trên Vault Fuji thật, xử lý timeout/rate limit có giới hạn | Sau C-FUJI; A chỉ phản hồi trạng thái loading/error | Có số đo thật và test không trả dữ liệu tài chính cũ/không đầy đủ khi lỗi |
| A-WALLET | A | Dẫn buổi nghiệm thu Core/MetaMask và hai thiết bị; thực hiện UX ký/QR | B xem API/log; C kiểm receipt/số dư; người dùng ký trong ví | Luồng tạo gói→subscribe→release→replay bị từ chối→refund qua trên thiết bị thật |
| A-CAMERA | A | Camera hoặc native nếu nhóm chọn đưa vào scope | Phụ thuộc quyết định D1/D2 bên dưới | Test camera/deep-link trên thiết bị đã chọn; không suy từ browser local |
| C-YIELD | C | Bàn giao hành vi yield và nguồn token, giữ MOCK/DISABLED nếu nhóm chưa đổi chính sách | Nhóm chốt D3; B xác minh số paid từ event | Contract/test và nhãn mode không mâu thuẫn |
| A-YIELD | A | Hiển thị mode/estimate/paid từ API | C-YIELD và DTO hiện có từ B | Không gọi MOCK là lợi nhuận DeFi thật |
| B-E2E | B | Duy trì runner/workflow và báo cáo tích hợp | A cập nhật locator/accessibility khi đổi UI; C cung cấp fixture/ABI | CI đúng commit cuối xanh, có bằng chứng phạm vi local/Fuji riêng |
| NOP-BAI | Nhóm chỉ định một người | Điều phối video/slide/form nộp và deadline | A cung cấp demo; B/C cung cấp bằng chứng thật | Hồ sơ được đối chiếu thể lệ và có xác nhận nộp |

Không dùng nhãn “Solidity + BE” để gộp deploy contract và host API thành một việc. C-FUJI giao đầu vào cho B-HOST; A-RELEASE nhận đầu ra của cả hai.

## 3. Các điểm cần nhóm chốt trước khi mở thêm việc

Các lựa chọn dưới đây là đề xuất. **Trạng thái tất cả: chưa có xác nhận chung trong tài liệu này.** Trong lúc chờ, giữ hành vi code hiện có, không tự đổi contract/interface hoặc tuyên bố tính năng đã nghiệm thu.

| ID | Nhóm cần quyết định cụ thể | Hiện trạng / đề xuất để thảo luận | Ai chuẩn bị thông tin | Quyết định này ảnh hưởng gì |
| --- | --- | --- | --- | --- |
| D1 | Bản nộp chính là Web hay Android/native? | Web là đường đã có test local/CI; đề xuất chốt Web trước | A | Thiết bị demo, SDK ví, host, scope A-CAMERA |
| D2 | Có bắt buộc quét camera trong MVP, hay chấp nhận dán payload QR? | Hiện dán payload; đề xuất không ghi “đã quét camera” trước nghiệm thu | A | Việc camera, quyền truy cập và demo hai thiết bị |
| D3 | Yield chỉ MOCK/DISABLED hay bắt buộc DeFi thật theo thể lệ? | Code hiện MOCK/DISABLED; chưa BENQI. Cần kiểm thể lệ thay vì suy đoán | C, người đọc thể lệ | Phạm vi adapter, funding, UI và pitch; BE không tự chọn thêm giao thức |
| D4 | Luật release/refund có giữ baseline B1–B6 không? | Refund theo mốc thời gian/không sử dụng; không tự chứng minh cơ sở vi phạm | C giải thích luật, A/B đối chiếu luồng | Contract, API, UI phải đổi cùng phiên bản nếu đổi chính sách |
| D5 | Demo chính xác các chức năng nào? | Core ví/API/escrow có test; training/giờ đông/booking mở rộng vẫn mô phỏng | A trình bày màn hình; B/C nêu dữ liệu có thật | Có cần thêm backend mới hay chỉ ghi rõ dữ liệu demo; tránh B tự xây API cho mọi màn hình |
| D6 | Chọn chain/Vault/token, ví treasury/deployer, ai cấp gas và giữ ví? | Đã cấp gas/deploy Fuji43113, mode DISABLED; manifest/receipt và hai ví demo đã có trong bản deployment | C | Nhóm tiếp tục chốt người giữ ví; chỉ chia sẻ địa chỉ công khai, không chờ cấp gas/deploy lại |
| D7 | URL web/API, nơi host DB, ai giữ cấu hình và chi phí tối đa? | Web/API/DB Render đã Live; AUTH/CORS và health check /ready đã kiểm chứng, DB Free hết hạn16/12 | B đề xuất API/DB; A đề xuất web | Nhóm chốt người quản trị và chi phí tiếp theo; backup DB chưa cấu hình, không nhận đã sao lưu |
| D8 | Nhánh tích hợp nào là nguồn chuẩn; ai merge; có freeze trước demo không? | Nhánh fix/be-nghiem-thu-1116; runtime web nguồn ccd4f38, API nguồn 5f2528a đã kiểm tương thích; main chưa tự merge | B chuẩn bị diff và CI; A/C review phần mình | Nhóm chọn người merge/freeze; không tự ghi đè nhánh frontend/solidity |
| D9 | Ai giữ vai trò subscriber/merchant khi nghiệm thu; Core hay MetaMask; dùng hai thiết bị nào? | Test provider đã qua; extension và hai thiết bị vật lý chưa được thay thế bởi kết quả CI | A | Lịch nghiệm thu, account/profile và người xác nhận ký |
| D10 | Ai điều phối bài nộp, hạn thật và bằng chứng cần có? | Tài liệu kế hoạch ngày tương đối không phải deadline chính thức | Người nhóm chỉ định | Không để “cả nhóm” đồng nghĩa không ai chịu trách nhiệm nộp |

Mẫu ghi kết quả sau buổi thống nhất:

> D…: chọn …; phạm vi …; đầu mối …; người phối hợp …; đầu ra …; mốc hoàn thành …; ngày xác nhận … .

Không điền tên người, ngân sách, ngày hẹn hoặc quyết định của nhóm thay các thành viên khi chưa được xác nhận.

## 4. Quy trình phối hợp đề xuất

1. Mỗi người nhận một task ID và nhánh của mình; không force-push nhánh người khác.
2. Người phụ trách BE mặc định sửa backend/test/runner và cấu hình host API. Nếu cần đổi UX/UI hoặc contract, ghi ticket và đầu ra cần từ A/C; chỉ sửa phần đó khi đã nhận task cụ thể.
3. Thay đổi interface ghi DTO/event/domain/ABI, lỗi và fixture trước. A/B/C review đúng phần tiêu thụ đầu vào, không buộc mọi sửa nhỏ đều chờ cả nhóm.
4. Cần hỗ trợ ngoài role thì ghi rõ “hỗ trợ task A-…/C-…”, người nào làm và phạm vi file. Việc hỗ trợ không tự tạo quyền sở hữu lâu dài.
5. B giữ báo cáo E2E; A chịu trách nhiệm locator/UX sau khi đổi UI; C chịu trách nhiệm export/fixture sau khi đổi contract. Người gây thay đổi cập nhật phần kiểm thử liên quan.
6. Người nhóm chọn ở D8 merge sau CI/review. Nếu lỗi tích hợp, mở ticket theo nguyên nhân: UI gọi sai→A, API sai quyền/DTO→B, contract/event sai→C; chưa rõ thì B điều phối truy vết, chưa tự gán lỗi.

## 5. Đọc các sửa đã có mà không hiểu nhầm role

Các commit sửa a0026d9/a80c8ae trước đây có cả BE và phần UI/script liên quan vì người dùng đã giao sửa tích hợp. Mã ấy đã được push, giữ nguyên và có CI; tài liệu này không hoàn tác hay viết lại lịch sử.

Từ đợt công việc tiếp theo, dùng phân công được nhóm xác nhận ở trên. Đầu mối A tiếp nhận bảo trì các màn hình/controller Flutter; B tiếp nhận API/DB/tracking/RPC/host; C tiếp nhận contract/ABI/deploy. Nhóm cần chốt D1–D10 để tránh cả ba người tự mở rộng scope.

Đọc trạng thái kỹ thuật và điều kiện chạy ở [bàn giao sửa lỗi](ban-giao-sua-loi-2026-11-15.md); tài liệu này là nơi chốt ranh giới và giao điểm, không thay bằng chứng test.
