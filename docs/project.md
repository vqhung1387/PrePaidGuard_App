# PrePaidGuard — Tổng quan dự án

> Đặc tả gốc 0.1 — 11/11/2026. Cập nhật 12/11/2026: backend và Solidity đã được triển khai trên nhánh backend. Nghiệm thu thiết bị/Fuji theo docs/backend-handoff.md.
> Nhóm: 3 người, thời gian dự kiến: 14 ngày. Ngày là mốc tương đối; cần xác nhận hạn nộp chính thức.

## 1. Mục tiêu

PrePaidGuard là MVP ký quỹ dịch vụ trả trước trên Avalanche. Khách nạp token vào Vault; merchant chỉ nhận phần gốc tương ứng kỳ dịch vụ được khách ký xác nhận. Người dùng có thể hoàn số dư theo điều kiện đã thống nhất. Yield là chức năng bổ sung, không thay thế giá trị cốt lõi của escrow.

Tiêu chí thành công: hai thiết bị thực hiện được tạo gói → đăng ký → ký/quét QR → giải ngân → hoàn tiền một gói khác trên Fuji; số dư và giao dịch kiểm chứng được trên explorer.

Nguồn ý tưởng: [Google Docs](https://docs.google.com/document/d/1ofSaI_PZpnQOB1h2R9Mm8ww9vNDmaTPR1pbC-rq8iSY/edit).
Repo: [PrePaidGuard_App](https://github.com/vqhung1387/PrePaidGuard_App).

## 2. Bộ tài liệu và thứ tự đọc

| Tài liệu | Nội dung |
| --- | --- |
| [project.md](project.md) | Phạm vi, quyết định kiến trúc và các điểm cần chốt |
| [schema.md](schema.md) | Entity, dữ liệu on-chain, DTO, QR và event |
| [api.md](api.md) | REST API và ranh giới với contract |
| [user_flows.md](user_flows.md) | Các luồng thực thi và xử lý lỗi |
| [tasks.md](tasks.md) | Công việc, phụ thuộc, owner và tiêu chí nghiệm thu |

Các file architecture.md, business-rules.md, task-board.md và demo-script.md là ghi chú ban đầu. Bộ tài liệu này chi tiết hóa đề xuất; không có nghĩa các quyết định còn mở đã được nhóm phê duyệt. Nếu có khác biệt, cần cập nhật cả bộ sau khi chốt, không triển khai hai luật khác nhau.

## 3. Actor và quyền

- Subscriber: kết nối ví, đăng ký, ký check-in và yêu cầu refund gói của mình.
- Merchant: ví chủ cơ sở tạo gói, xem người đăng ký thuộc cơ sở, quét QR và gửi giao dịch giải ngân.
- Backend: xác thực ví, lưu metadata, xác minh receipt/event và cung cấp read model.
- Vault: nguồn dữ liệu chuẩn của quyền sở hữu, số dư, kỳ, nonce và trạng thái tài chính.
- Yield adapter: hạch toán tài sản riêng từng subscription; bản thi mặc định mô phỏng có cấp token.
- Platform treasury: địa chỉ cố định nhận phần yield nền tảng, không có quyền rút tiền gốc tùy ý.

Một ví có thể là cả subscriber và merchant. Chọn tab trên UI không cấp quyền. MVP không có vai trò quản trị có thể tự đánh dấu đã thanh toán, tùy ý rút gốc hoặc xác nhận gym đóng cửa.

## 4. Phạm vi

P0: đăng nhập bằng ví; merchant profile; tạo draft gói và publish on-chain; đăng ký/approve; thẻ hội viên; QR EIP-712; giải ngân; refund; transaction tracking và lịch sử; deploy/demo.

P1: adapter yield mô phỏng, báo cáo tổng quan đơn giản và video/demo hoàn chỉnh. Nếu thể lệ bắt buộc yield, nâng P1 này lên P0 ngày đầu.

Ngoài MVP: tiền pháp định, BENQI production, ví nhúng, PWA offline hoàn chỉnh, chuyển nhượng, nhân viên POS có ví riêng, arbitrator/tranh chấp, thông báo push, nhiều token, native iOS nếu Android được chọn làm nền tảng chính.

## 5. Baseline nghiệp vụ được triển khai

Theo phạm vi người dùng giao tiếp tục cả backend và Solidity, hai phần dùng B1–B6 dưới đây. Flutter và nhóm cần nghiệm thu cùng baseline này trước demo.

| ID | Quyết định đề xuất | Trạng thái |
| --- | --- | --- |
| B1 | Giải ngân theo kỳ, kỳ đầu sau một period_duration kể từ subscribe. Một chữ ký giải ngân một kỳ. | Đã triển khai, chờ nghiệm thu |
| B2 | Không tự trả các kỳ bỏ lỡ; sau mỗi release, next_release_at = thời gian release + period_duration. Thời gian hoàn tất có thể kéo dài. | Đã triển khai, chờ nghiệm thu |
| B3 | refund_available_at = next_release_at + grace_period. Khách được hủy do không sử dụng, không được mô tả là bằng chứng gym đóng cửa. | Đã triển khai, chờ nghiệm thu |
| B4 | Check-in chỉ khi next_release_at <= block.timestamp < refund_available_at; refund khi block.timestamp >= refund_available_at. Không có vùng chồng lấn. | Đã triển khai, chờ nghiệm thu |
| B5 | MockUSDC 6 decimals; giá kỳ cố định, tổng gốc = giá kỳ × số kỳ; chia yield 70/20/10. | Đã triển khai, chờ nghiệm thu |
| B6 | Quyền scanner dùng chính ví merchant; merchant chịu gas check-in. Khách chịu approve/subscribe/refund. | Đã triển khai, chờ nghiệm thu |

Không check-in không chứng minh cơ sở vi phạm. Nếu nhóm muốn chỉ hoàn khi merchant đóng cửa, B3/B4 và DTO refund phải được thiết kế lại với nguồn xác nhận/trust model rõ ràng.

Plan tài chính bất biến sau publish; cần thay giá/kỳ thì tạo plan mới. Profile và mô tả marketing không phải điều khoản tài chính. Nội dung metadata plan trong MVP cũng khóa sau publish để hạn chế lệch nội dung.

Subscription: ACTIVE → COMPLETED hoặc REFUNDED; trạng thái cuối không quay lại ACTIVE. Bắt đầu completed_periods = 0, nonce = 0, remaining_principal = total_price.

Mọi release/refund thay đổi trạng thái và chuyển tiền nguyên tử; adapter không rút đủ thì toàn giao dịch revert.

## 6. Kiến trúc và stack

| Lớp | Lựa chọn |
| --- | --- |
| Client | Flutter, Riverpod, Dio; chọn SDK ví/QR sau technical spike |
| API | Python 3.12, FastAPI, Pydantic; uv quản lý dependencies |
| Database | PostgreSQL, SQLAlchemy, Alembic |
| Blockchain backend | web3.py cho read/receipt verification |
| Contract | Solidity, OpenZeppelin, Hardhat; TypeScript cho test/deploy |
| Network | Avalanche Fuji, chain ID 43113; MockUSDC |
| Testing | pytest cho API; Flutter test/integration_test; Hardhat contract tests |

Client → ví → RPC → Vault: các giao dịch tài chính.
Client → FastAPI → PostgreSQL: profile, metadata, auth và read models.
FastAPI → RPC: đối chiếu receipt, event và trạng thái contract.
Contract build → shared/abi + shared/deployments → client/backend.

Không có server tự ký thay khách, relayer, Redis, Celery, microservices hoặc indexer độc lập trong MVP. UI poll có giới hạn; backend đồng bộ receipt theo tx hash, bổ sung quét log theo block để phục hồi khi app đóng trước khi báo transaction.

## 7. Chia nguồn dữ liệu

- PostgreSQL là nguồn chuẩn cho profile và plan draft.
- Contract là nguồn chuẩn cho plan tài chính và subscription.
- SubscriptionSnapshot/EventRecord chỉ là projection có thể rebuild.
- Không dùng số tiền hoặc cờ eligible do mobile gửi làm căn cứ chi tiền.
- API eligibility chỉ là tư vấn theo block đã đọc; contract kiểm tra lại lúc thực thi.
- Tiền dùng atomic-unit integer; JSON truyền decimal string; không float.
- Chain ID + vault + on-chain ID xác định duy nhất một tài nguyên.

## 8. Tích hợp và môi trường

Local: PostgreSQL + FastAPI, Flutter thiết bị/emulator, Hardhat local node.
Demo: backend HTTPS và database dùng chung, Flutter bản Android thử nghiệm, Fuji contract.
Không bắt buộc Docker để viết code; có thể thêm Compose nếu cả nhóm cần.

Cấu hình server: DATABASE_URL, RPC_URL, CHAIN_ID, VAULT_ADDRESS, TOKEN_ADDRESS, AUTH_DOMAIN, AUTH_URI, ACCESS_TOKEN_SECRET, ACCESS_TOKEN_TTL_SECONDS, CORS_ORIGINS.
Cấu hình mobile công khai: API_BASE_URL; cấu hình network/ABI lấy từ shared và đối chiếu /config.
Private key deploy chỉ ở môi trường deploy cục bộ; không đưa vào Flutter, API hoặc Git.

ABI version và deployment_id phải khớp. Khi deploy Vault mới, đổi deployment_id, reset dữ liệu demo tương ứng; không trộn ID của hai Vault.

## 9. Yield và tiền

Yield mode = MOCK trong baseline; chưa có tích hợp BENQI thật. Mock adapter phải được cấp đủ token và hạch toán yield theo subscription, không lấy gốc người khác để trả lãi.

Realized yield chỉ ghi nhận khi có token thật trong môi trường test để rút. Giá trị nội suy chỉ là estimated yield, không dùng quyết định payout. Merchant nhận 70%, subscriber 20%, treasury nhận phần còn lại để xử lý rounding; áp dụng cả release và refund. Gốc chưa dùng trả subscriber khi refund.

Không có nút mint yield hoặc đổi thời gian công khai trên production/demo Vault. Cấp yield mock bằng script testnet quản lý riêng. APY 5% nếu dùng chỉ là giả định; không quảng cáo bảo vệ vốn tuyệt đối.

## 10. Điều kiện nghiệm thu và ưu tiên

- Luồng tiền chạy trên Fuji với hai thiết bị và hai ví.
- Sai chữ ký, nonce, deadline, merchant, chain/domain và kỳ đều không chuyển tiền.
- Đồng thời check-in/refund không tạo thanh toán hai lần.
- Có kiểm thử nhiều subscription và bảo toàn gốc.
- Backend không thể tự tạo trạng thái CONFIRMED bằng input client.
- Người khác theo README chạy được dự án; video, ABI, địa chỉ và tx mẫu đầy đủ.
- Hết ngày 7 chưa xong escrow → bỏ tính năng mở rộng, tập trung luồng chính.
- Ngày 13 đóng băng tính năng.

## 11. Việc cần xác nhận trước ngày 2

B1–B6; thể lệ/yêu cầu yield thật; hạn nộp và thời lượng demo; Android hay Web là nền tảng chính; SDK ví có ký typed data trên thiết bị thật; môi trường host backend/database; tên thật của ba người.

Tài liệu tham khảo: [EIP-712](https://eips.ethereum.org/EIPS/eip-712), [SIWE/ERC-4361](https://eips.ethereum.org/EIPS/eip-4361), [FastAPI routers](https://fastapi.tiangolo.com/tutorial/bigger-applications/).
