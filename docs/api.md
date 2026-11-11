# API — Flutter ↔ FastAPI và contract integration

> Backend đã triển khai các endpoint bên dưới và có OpenAPI ở /openapi.json. ABI thực tế và tích hợp Fuji cần nghiệm thu riêng. B1–B6 trong [project.md](project.md) còn cần chốt.
> DTO định nghĩa tại [schema.md](schema.md). API tài chính là đọc/xác minh; giao dịch ghi được ví gửi trực tiếp tới Vault.

## 1. Convention

- Base: <API_BASE_URL>/api/v1; HTTPS cho môi trường demo; JSON UTF-8, snake_case.
- Auth: Authorization: Bearer <access_token>. JWT gắn wallet/chain/session, TTL 1 giờ; hết hạn ký lại, không refresh token trong MVP.
- Public: không cần token. User: ví đã xác thực. Merchant: user có Merchant profile; vẫn kiểm tra owner từng tài nguyên.
- Thành công trả trực tiếp DTO, list trả Page<T>; lỗi dùng ErrorResponse.
- Amount/uint256 là decimal string. timestamp là UTC RFC3339.
- Query list: limit (mặc định 20, max 100), cursor; filter được liệt kê ở từng endpoint.
- Chain/Vault lấy deployment hiện hành. Không cho client yêu cầu server gọi RPC tùy ý.
- /docs và /openapi.json do FastAPI sinh; tài liệu này là hợp đồng thiết kế ban đầu, OpenAPI phải cập nhật theo.
- Mobile decode snake_case sang Dart models bằng mapping rõ ràng.
- Mobile timeout/retry: chỉ tự retry GET với backoff giới hạn; POST tạo tài nguyên không tự retry mù.

## 2. Hợp đồng API theo mẫu bảng tham khảo

Tham khảo cấu trúc tab api (gid=1522506644) của [ProActive Hợp đồng API](https://docs.google.com/spreadsheets/d/1RTI0Hv0DydDX5S0DMq1clSFmGggCuGkAMORynke6J0w/edit?gid=1522506644). Chỉ áp dụng bố cục 10 cột; giữ schema và semantics của PrePaidGuard. Không sao chép endpoints, trạng thái kiểm thử, idempotency policy hoặc response envelope của ProActive.

Các endpoint bên dưới đã được triển khai ở backend. Status là tiến độ công việc; HTTP status nằm trong Success JSON / Fail JSON. Authority Owner/Participant được kiểm bằng wallet trong session; tài nguyên private không thuộc ví trả 404. Success/Fail JSON trong bảng dẫn tới ví dụ đầy đủ ngay trong file.

| Method | Endpoint | Description | RequestBody / Params | Authority | Token | Status | Success JSON | Fail JSON | Thành viên thực hiện |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| GET | `/health` | Kiểm tra tiến trình API | [Không](#api-01) | Public | Không | Đã triển khai (BE) | [200 · Health](#api-01) | [503 SERVICE_UNAVAILABLE](#api-01) | B: API; A: mobile |
| GET | `/ready` | Kiểm tra DB, RPC và chain | [Không](#api-02) | Public | Không | Đã triển khai (BE) | [200 · Readiness](#api-02) | [503 DATABASE_UNAVAILABLE, 503 RPC_UNAVAILABLE, 503 CONFIG_MISMATCH](#api-02) | B: API; A: mobile |
| GET | `/api/v1/config` | Cấu hình công khai cho mobile | [Không](#api-03) | Public | Không | Đã triển khai (BE) | [200 · ConfigResponse](#api-03) | [503 CONFIG_MISMATCH](#api-03) | B: API; A: mobile |
| POST | `/api/v1/auth/challenge` | Tạo SIWE challenge | [body: wallet_address, chain_id](#api-04) | Public | Không | Đã triển khai (BE) | [201 · AuthChallengeResponse](#api-04) | [422 VALIDATION_ERROR, 400 UNSUPPORTED_CHAIN, 429 RATE_LIMITED](#api-04) | B: API; A: mobile |
| POST | `/api/v1/auth/verify` | Xác thực chữ ký và tạo phiên | [body: challenge_id, signature](#api-05) | Public | Không | Đã triển khai (BE) | [200 · AuthTokenResponse](#api-05) | [422 VALIDATION_ERROR, 401 INVALID_SIGNATURE, 401 CHALLENGE_EXPIRED, 401 CHALLENGE_USED](#api-05) | B: API; A: mobile |
| POST | `/api/v1/auth/logout` | Thu hồi session hiện tại | [Không](#api-06) | User | Bearer access_token | Đã triển khai (BE) | [204 · No content](#api-06) | [401 UNAUTHORIZED](#api-06) | B: API; A: mobile |
| GET | `/api/v1/me` | Đọc profile ví hiện tại | [Không](#api-07) | User | Bearer access_token | Đã triển khai (BE) | [200 · UserResponse](#api-07) | [401 UNAUTHORIZED](#api-07) | B: API; A: mobile |
| PATCH | `/api/v1/me` | Đổi tên hiển thị | [body: display_name](#api-08) | User | Bearer access_token | Đã triển khai (BE) | [200 · UserResponse](#api-08) | [401 UNAUTHORIZED, 422 VALIDATION_ERROR](#api-08) | B: API; A: mobile |
| POST | `/api/v1/merchants` | Tạo hồ sơ cơ sở cho ví đã login | [body: business_name, description, location_text](#api-09) | User | Bearer access_token | Đã triển khai (BE) | [201 · MerchantResponse](#api-09) | [401 UNAUTHORIZED, 422 VALIDATION_ERROR, 409 MERCHANT_EXISTS](#api-09) | B: API; A: mobile |
| GET | `/api/v1/merchants/{merchant_id}` | Đọc hồ sơ cơ sở | [path: merchant_id](#api-10) | Public | Không | Đã triển khai (BE) | [200 · MerchantResponse](#api-10) | [404 NOT_FOUND, 422 VALIDATION_ERROR](#api-10) | B: API; A: mobile |
| PATCH | `/api/v1/merchants/{merchant_id}` | Sửa profile cơ sở mình sở hữu | [path: merchant_id; body: description](#api-11) | Owner | Bearer access_token | Đã triển khai (BE) | [200 · MerchantResponse](#api-11) | [401 UNAUTHORIZED, 404 NOT_FOUND, 422 VALIDATION_ERROR](#api-11) | B: API; A: mobile |
| POST | `/api/v1/plan-drafts` | Tạo nháp điều khoản gói | [body: title, description, price_per_period, total_periods, period_duration_seconds, grace_period_seconds](#api-12) | Merchant | Bearer access_token | Đã triển khai (BE) | [201 · PlanDraftResponse](#api-12) | [401 UNAUTHORIZED, 422 VALIDATION_ERROR, 403 MERCHANT_REQUIRED](#api-12) | B: API; A: mobile |
| GET | `/api/v1/plan-drafts` | Danh sách draft thuộc merchant | [query: limit](#api-13) | Merchant | Bearer access_token | Đã triển khai (BE) | [200 · Page&lt;PlanDraftResponse&gt;](#api-13) | [401 UNAUTHORIZED, 403 MERCHANT_REQUIRED, 422 VALIDATION_ERROR](#api-13) | B: API; A: mobile |
| GET | `/api/v1/plan-drafts/{draft_id}` | Đọc draft của mình | [path: draft_id](#api-14) | Owner | Bearer access_token | Đã triển khai (BE) | [200 · PlanDraftResponse](#api-14) | [401 UNAUTHORIZED, 404 NOT_FOUND, 422 VALIDATION_ERROR](#api-14) | B: API; A: mobile |
| PATCH | `/api/v1/plan-drafts/{draft_id}` | Chỉnh draft chưa publish | [path: draft_id; body: title](#api-15) | Owner | Bearer access_token | Đã triển khai (BE) | [200 · PlanDraftResponse](#api-15) | [401 UNAUTHORIZED, 404 NOT_FOUND, 422 VALIDATION_ERROR, 409 PLAN_IMMUTABLE](#api-15) | B: API; A: mobile |
| GET | `/api/v1/plans` | Danh sách plan đã publish | [query: merchant_address, limit](#api-16) | Public | Không | Đã triển khai (BE) | [200 · Page&lt;PlanResponse&gt;](#api-16) | [422 VALIDATION_ERROR, 503 RPC_UNAVAILABLE](#api-16) | B: API; A: mobile |
| GET | `/api/v1/plans/{plan_id}` | Đọc plan và điều khoản on-chain | [path: plan_id](#api-17) | Public | Không | Đã triển khai (BE) | [200 · PlanResponse](#api-17) | [404 NOT_FOUND, 422 VALIDATION_ERROR, 503 RPC_UNAVAILABLE](#api-17) | B: API; A: mobile |
| GET | `/api/v1/me/subscriptions` | Gói thuộc subscriber hiện tại | [query: status, limit](#api-18) | User | Bearer access_token | Đã triển khai (BE) | [200 · Page&lt;SubscriptionResponse&gt;](#api-18) | [401 UNAUTHORIZED, 422 VALIDATION_ERROR](#api-18) | B: API; A: mobile |
| GET | `/api/v1/merchant/subscriptions` | Gói khách thuộc merchant hiện tại | [query: plan_id, status, limit](#api-19) | Merchant | Bearer access_token | Đã triển khai (BE) | [200 · Page&lt;SubscriptionResponse&gt;](#api-19) | [401 UNAUTHORIZED, 422 VALIDATION_ERROR, 404 NOT_FOUND, 403 MERCHANT_REQUIRED](#api-19) | B: API; A: mobile |
| GET | `/api/v1/subscriptions/{subscription_id}` | Chi tiết gói và số dư | [path: subscription_id](#api-20) | Participant | Bearer access_token | Đã triển khai (BE) | [200 · SubscriptionResponse](#api-20) | [401 UNAUTHORIZED, 404 NOT_FOUND, 422 VALIDATION_ERROR, 503 RPC_UNAVAILABLE](#api-20) | B: API; A: mobile |
| GET | `/api/v1/subscriptions/{subscription_id}/eligibility` | Kiểm điều kiện check-in/refund live | [path: subscription_id](#api-21) | Participant | Bearer access_token | Đã triển khai (BE) | [200 · EligibilityResponse](#api-21) | [401 UNAUTHORIZED, 404 NOT_FOUND, 422 VALIDATION_ERROR, 503 RPC_UNAVAILABLE](#api-21) | B: API; A: mobile |
| GET | `/api/v1/subscriptions/{subscription_id}/events` | Lịch sử event đã đối chiếu | [path: subscription_id; query: limit](#api-22) | Participant | Bearer access_token | Đã triển khai (BE) | [200 · Page&lt;EventResponse&gt;](#api-22) | [401 UNAUTHORIZED, 404 NOT_FOUND, 422 VALIDATION_ERROR](#api-22) | B: API; A: mobile |
| POST | `/api/v1/transactions` | Theo dõi giao dịch đã broadcast | [body: tx_hash, action, plan_id](#api-23) | User | Bearer access_token | Đã triển khai (BE) | [202 · TransactionResponse](#api-23) | [401 UNAUTHORIZED, 422 VALIDATION_ERROR, 503 RPC_UNAVAILABLE, 409 TX_MISMATCH, 409 TRANSACTION_CONFLICT](#api-23) | B: API; A: mobile; C: receipt/ABI |
| GET | `/api/v1/transactions/{tx_hash}` | Tra cứu và đối chiếu trạng thái tx | [path: tx_hash](#api-24) | Submitter | Bearer access_token | Đã triển khai (BE) | [200 · TransactionResponse](#api-24) | [401 UNAUTHORIZED, 404 NOT_FOUND, 422 VALIDATION_ERROR, 409 TX_MISMATCH, 503 RPC_UNAVAILABLE](#api-24) | B: API; A: mobile; C: receipt/ABI |

Participant = subscriber hoặc merchant của chính subscription. Submitter = user đăng ký tracking record. Blockchain vẫn công khai; đây là access policy của backend.

Không có REST POST /refund, /check-in, /subscribe hoặc /mint-yield: các hành động tài chính do ví gửi tới contract ở mục 7.

## 3. Auth và profile

### POST /auth/challenge
Input: wallet_address, chain_id. Server validate EOA address và supported chain, sinh nonce và SIWE message theo AUTH_DOMAIN/AUTH_URI cấu hình; không nhận domain do client tùy ý chọn.
Output: challenge_id, message, expires_at. Không tạo merchant hay cấp role.
Rate limit theo IP và ví; trả 429 nếu vượt giới hạn cấu hình.

### POST /auth/verify
Input: challenge_id, signature. Mobile ký chính xác message nhận về bằng wallet personal_sign/SIWE, không ký transaction.
Server kiểm format message, domain, URI, chain, address, issued/expiry time, unused nonce và signature.
Consume challenge + tạo user nếu chưa có + tạo session trong một DB transaction sau verify; tránh hai request dùng lại challenge.
Output JWT và UserResponse. Sai signature/expired/used challenge trả 401 với mã riêng. Không log signature.

### POST /auth/logout
Revoke sid trong DB. Mobile xóa token khỏi secure storage; mất kết nối thì xóa token local ngay, server session tự hết TTL. Khi API đang online, gọi logout để revoke trước khi xóa.
Đổi account/network: xóa session local và QR hiện tại; xác thực lại ví mới.

### Merchant ownership
POST /merchants tạo một profile thuộc ví session; trùng trả 409 MERCHANT_EXISTS.
PATCH chỉ sửa name/description/location. Không nhận owner_user_id/owner_wallet trong body.
GET /me trả is_merchant để UI chọn màn hình, nhưng mọi API vẫn kiểm tra quyền.

## 4. Plan lifecycle

### POST /plan-drafts

```json
{
  "title": "Gym 12 kỳ",
  "description": "Gói demo thanh toán theo kỳ",
  "price_per_period": "50000000",
  "total_periods": 12,
  "period_duration_seconds": 2592000,
  "grace_period_seconds": 2592000
}
```

Server chọn token/chain/Vault từ config, sinh UUID và client_reference bytes32, tính total_price. Độ dài field/range theo schema.md. Trong demo có thể dùng kỳ ngắn được chốt riêng; không lén thay đổi điều khoản sau subscribe.

Response thêm id, merchant_id, client_reference, state="DRAFT", total_price="600000000", onchain_plan_id=null.
PATCH draft tính lại total_price; mọi field đã publish bị khóa.
Trong lúc ký publish, mobile khóa chỉnh sửa draft. Backend đối chiếu toàn bộ financial fields với PlanCreated; nếu user sửa draft giữa lúc tx pending, trả TX_MISMATCH và đối chiếu lại on-chain trước khi thử mới.

### Publish
Không có API đặt state=PUBLISHED. Mobile gọi createPlan qua ví merchant, rồi POST /transactions với action=CREATE_PLAN và plan_draft_id.
Backend chỉ publish draft khi receipt/event từ đúng Vault, đúng merchant, đúng client_reference và toàn bộ điều khoản khớp draft.
Nếu giao dịch đã xác nhận nhưng app chưa gửi hash, log scanner khôi phục linkage qua merchant + client_reference.
Published plan GET trả metadata cùng financial terms đọc on-chain; không dùng database draft ghi đè terms.

### Lists
/plan-drafts chỉ owner; /plans chỉ published, cursor theo projection block/ID hoặc metadata stable key.
Một plan tạo trực tiếp ngoài app có thể thiếu metadata; backend hiển thị fallback title.
Không có DELETE plan hoặc sửa terms on-chain trong MVP.

## 5. Subscription reads

/me/subscriptions và /merchant/subscriptions dùng danh sách đã index, có thể chậm sau block mới.
Sau transaction CONFIRMED, backend cập nhật projection ngay; scanner phục hồi các tx chưa được client báo.

/subscriptions/{id} trả nguồn và block sync. Trước ký check-in/refund, eligibility phải đọc live; RPC lỗi trả 503, không giả can_refund=true từ cache.
Status filter chỉ ACTIVE|COMPLETED|REFUNDED.
Không cho client truyền subscriber_address để đọc danh sách của ví khác.
Merchant filter plan_id chỉ chấp nhận plan thuộc merchant đó.

Eligibility áp dụng B1–B4; các quyền caller vẫn do contract kiểm tra. Snapshot cũ không được dùng làm bảo đảm giao dịch sẽ thành công.
Events gồm thông tin theo receipt, không hiển thị signature QR.

## 6. Transaction tracking

Ví dụ báo đăng ký đã broadcast:

```json
{
  "tx_hash": "<64-hex-transaction-hash-with-0x>",
  "action": "SUBSCRIBE",
  "plan_id": "1"
}
```

Các fields theo action:
- CREATE_PLAN: plan_draft_id bắt buộc; sender phải là owner draft.
- SUBSCRIBE: plan_id bắt buộc; subscriber trong event phải là session wallet.
- CHECK_IN: subscription_id bắt buộc; sender phải là merchant tương ứng.
- REFUND: subscription_id bắt buộc; sender phải là subscriber.
Không cho phép extra/mâu thuẫn reference fields; Pydantic discriminated union theo action.

Quy trình verify:
1. Tìm hoặc upsert tracking record theo (chain_id, tx_hash); user/action/reference phải khớp record cũ.
2. Đọc transaction + receipt qua RPC cấu hình; chưa thấy receipt vẫn SUBMITTED.
3. Kiểm tra đúng chain, tx.to=Vault, sender, calldata function và expected references.
4. Receipt status=0 → REVERTED, không tạo event tài chính.
5. Status=1 → decode logs từ đúng Vault và event/action/resource expected; không chấp nhận log giả từ contract khác.
6. CONFIRMED chỉ sau receipt hợp lệ trong block được node xác nhận theo confirmation policy deployment. Demo có thể cấu hình 1 confirmation; không hard-code thời gian 0.8 giây.
7. Trong một DB transaction: upsert event, cập nhật projection, publish draft nếu cần, update tracking.
8. Receipt thành công nhưng action/reference không khớp → 409 TX_MISMATCH; không gắn thành công với tài nguyên đã yêu cầu.

POST lặp cùng tx/action/reference bởi cùng user trả cùng record (202). Khác action/ref trả 409. User khác không claim record của người gửi.
GET chỉ chủ tracking record. Transaction replacement: mobile đăng ký hash mới; hash cũ có thể ở SUBMITTED, UI cho thử lại/tra explorer, không tự kết luận đã revert.
RPC lỗi không đổi SUBMITTED sang REVERTED.

Worker/scanner MVP chạy bằng command quản lý backend, không endpoint public. Quét từ deployment block đến block đã xác nhận, upsert logs, chỉ commit cursor sau commit projection. Có thể chạy khi startup/demo và lặp có giới hạn theo cấu hình; không dùng vòng lặp vô hạn trong HTTP request.
Cần kiểm block hash, quét lại vùng overlap và rebuild projection bị ảnh hưởng nếu node trả chain thay đổi.

## 7. Smart contract interface dự kiến

Đây là thiết kế, ABI cuối generate từ contract. Flutter dùng ABI/shared deployment, không tự encode string thủ công.

| Hàm | Caller | Ý nghĩa |
| --- | --- | --- |
| ERC20.approve(vault, amount) | Subscriber | Cấp đúng số token cần nạp; transaction đến token contract |
| createPlan(clientReference, token, pricePerPeriod, totalPeriods, periodDuration, gracePeriod) | Merchant | Tạo terms bất biến; chống reference trùng |
| subscribe(planId) | Subscriber | transferFrom và tạo subscription ACTIVE |
| checkInWithSignature(CheckIn message, bytes signature) | Merchant | Kiểm domain, owner, nonce, kỳ, deadline rồi giải ngân |
| refund(subscriptionId) | Subscriber | Hoàn gốc còn lại khi đủ điều kiện B3/B4 |
| getPlan(planId) | Bất kỳ | Terms của plan |
| getSubscription(subscriptionId) | Bất kỳ | Trạng thái, nonce và số dư |
| estimateYield(subscriptionId) | Bất kỳ | Estimate, không bảo đảm payout |

Không gọi backend để approve, tạo chữ ký thay người dùng hoặc chuyển tiền. QR payload và typed data xem schema.md.

Contract errors cần map UI: InvalidPlan, InvalidTerms, DuplicateReference, Unauthorized,
InvalidState, TooEarly, RefundWindowOpen, RefundNotAvailable, InvalidSignature,
InvalidNonce, InvalidPeriod, ExpiredSignature, InvalidDeadline, InsufficientAdapterLiquidity.
Tên thực tế đồng bộ theo ABI; lỗi EVM và ERC20 khác cần fallback "giao dịch thất bại" có tx hash.

## 8. HTTP errors

| HTTP | Code điển hình | Mobile xử lý |
| --- | --- | --- |
| 400 | INVALID_REQUEST, UNSUPPORTED_CHAIN, UNSUPPORTED_WALLET | Hiển thị input/network cần sửa |
| 401 | UNAUTHORIZED, TOKEN_EXPIRED, CHALLENGE_EXPIRED, CHALLENGE_USED, INVALID_SIGNATURE | Xác thực lại; không gửi transaction tự động |
| 403 | FORBIDDEN, MERCHANT_REQUIRED | Không hiển thị thao tác không có quyền |
| 404 | NOT_FOUND | Quay danh sách, refresh |
| 409 | MERCHANT_EXISTS, PLAN_IMMUTABLE, TX_MISMATCH, TRANSACTION_CONFLICT | Refresh/đối chiếu, không retry mù |
| 422 | VALIDATION_ERROR | Hiển thị lỗi theo field |
| 429 | RATE_LIMITED | Tôn trọng Retry-After |
| 503 | RPC_UNAVAILABLE, DATABASE_UNAVAILABLE, CONFIG_MISMATCH | Báo tạm lỗi; giữ tx hash để đối chiếu |

Không trả stack trace hoặc credential; trả request_id. Lỗi business như chưa tới kỳ trong eligibility được trả 200 với can_check_in=false; transaction bị contract từ chối là lỗi ví/EVM, không biến thành thành công HTTP.

## 9. API acceptance checklist

- Swagger/OpenAPI và Dart DTO đúng enum, nullability, Amount string.
- Ownership tests cho mọi endpoint private; chain/network session mismatch bị từ chối.
- Challenge replay và JWT revoked không được dùng.
- Transaction submit trùng không tạo hai event; receipt giả/sai contract/sai sender không CONFIRMED.
- Chưa xác nhận không thay tiền; app chết trước báo hash vẫn phục hồi qua logs.
- Không phát sinh endpoints ngoài inventory mà chưa cập nhật tài liệu.



## 10. Request và response examples theo endpoint

Các case độc lập, không phải một chuỗi fixture đã ký. Địa chỉ 0x111…/222…/333…/444…, hash và UUID là dữ liệu demo, chưa phải deployment thật. Placeholder chữ ký/JWT phải thay bằng giá trị thật. JSON HTTP response body theo DTO của schema.md, không tự thêm data/meta từ dự án mẫu. Mỗi Fail JSON là danh sách case độc lập, không phải server trả một mảng lỗi.

<a id="api-01"></a>

### API-01 — GET /health

Kiểm tra tiến trình API. Authority: **Public**. Status: **Đã triển khai (BE)**. Owner: **B (API), A (mobile)**.

**RequestBody / Params** — path/query/headers chỉ là các phần mô tả; HTTP body chỉ gửi object trong body.

```json
{}
```

**Success JSON** — http_status là HTTP status, không phải field được server thêm vào response.

```json
{
  "http_status": 200,
  "body": {
    "status": "ok"
  }
}
```

**Fail JSON**

```json
[
  {
    "http_status": 503,
    "body": {
      "error": {
        "code": "SERVICE_UNAVAILABLE",
        "message": "Dịch vụ chưa sẵn sàng.",
        "details": {},
        "request_id": "req-demo"
      }
    }
  }
]
```

**Ghi chú:** Ngoài /api/v1. Nếu process ngừng hoàn toàn có thể không có JSON HTTP response.

<a id="api-02"></a>

### API-02 — GET /ready

Kiểm tra DB, RPC và chain. Authority: **Public**. Status: **Đã triển khai (BE)**. Owner: **B (API), A (mobile)**.

**RequestBody / Params** — path/query/headers chỉ là các phần mô tả; HTTP body chỉ gửi object trong body.

```json
{}
```

**Success JSON** — http_status là HTTP status, không phải field được server thêm vào response.

```json
{
  "http_status": 200,
  "body": {
    "status": "ready"
  }
}
```

**Fail JSON**

```json
[
  {
    "http_status": 503,
    "body": {
      "error": {
        "code": "DATABASE_UNAVAILABLE",
        "message": "Database chưa sẵn sàng.",
        "details": {},
        "request_id": "req-demo"
      }
    }
  },
  {
    "http_status": 503,
    "body": {
      "error": {
        "code": "RPC_UNAVAILABLE",
        "message": "Chưa đọc được blockchain. Vui lòng thử lại.",
        "details": {},
        "request_id": "req-demo"
      }
    }
  },
  {
    "http_status": 503,
    "body": {
      "error": {
        "code": "CONFIG_MISMATCH",
        "message": "Chain thực tế không khớp cấu hình.",
        "details": {},
        "request_id": "req-demo"
      }
    }
  }
]
```

**Ghi chú:** Ngoài /api/v1; không công khai thông tin kết nối nội bộ.

<a id="api-03"></a>

### API-03 — GET /api/v1/config

Cấu hình công khai cho mobile. Authority: **Public**. Status: **Đã triển khai (BE)**. Owner: **B (API), A (mobile)**.

**RequestBody / Params** — path/query/headers chỉ là các phần mô tả; HTTP body chỉ gửi object trong body.

```json
{}
```

**Success JSON** — http_status là HTTP status, không phải field được server thêm vào response.

```json
{
  "http_status": 200,
  "body": {
    "environment": "demo",
    "deployment_id": "fuji-demo-v1",
    "chain_id": 43113,
    "chain_name": "Avalanche Fuji",
    "rpc_url": "https://api.avax-test.network/ext/bc/C/rpc",
    "explorer_url": "https://explorer-test.avax.network/c-chain",
    "vault_address": "0x4444444444444444444444444444444444444444",
    "token": {
      "address": "0x3333333333333333333333333333333333333333",
      "symbol": "mUSDC",
      "decimals": 6
    },
    "abi_version": "0.1.0",
    "yield_mode": "MOCK",
    "check_in_ttl_seconds": 900,
    "supported_wallet_kind": "EOA",
    "auth_domain": "app.example.com",
    "auth_uri": "https://app.example.com"
  }
}
```

**Fail JSON**

```json
[
  {
    "http_status": 503,
    "body": {
      "error": {
        "code": "CONFIG_MISMATCH",
        "message": "Deployment chưa có cấu hình hợp lệ.",
        "details": {},
        "request_id": "req-demo"
      }
    }
  }
]
```

<a id="api-04"></a>

### API-04 — POST /api/v1/auth/challenge

Tạo SIWE challenge. Authority: **Public**. Status: **Đã triển khai (BE)**. Owner: **B (API), A (mobile)**.

**RequestBody / Params** — path/query/headers chỉ là các phần mô tả; HTTP body chỉ gửi object trong body.

```json
{
  "body": {
    "wallet_address": "0x2222222222222222222222222222222222222222",
    "chain_id": 43113
  }
}
```

**Success JSON** — http_status là HTTP status, không phải field được server thêm vào response.

```json
{
  "http_status": 201,
  "body": {
    "challenge_id": "40000000-0000-4000-8000-000000000001",
    "message": "app.example.com wants you to sign in with your Ethereum account:\n0x2222222222222222222222222222222222222222\n\nSign in to PrepaidGuard.\n\nURI: https://app.example.com\nVersion: 1\nChain ID: 43113\nNonce: DemoNonce12345678\nIssued At: 2026-11-11T03:00:00Z\nExpiration Time: 2026-11-11T03:05:00Z",
    "expires_at": "2026-11-11T03:05:00Z"
  }
}
```

**Fail JSON**

```json
[
  {
    "http_status": 422,
    "body": {
      "error": {
        "code": "VALIDATION_ERROR",
        "message": "Dữ liệu không đúng schema.",
        "details": {},
        "request_id": "req-demo"
      }
    }
  },
  {
    "http_status": 400,
    "body": {
      "error": {
        "code": "UNSUPPORTED_CHAIN",
        "message": "Chain không được hỗ trợ.",
        "details": {},
        "request_id": "req-demo"
      }
    }
  },
  {
    "http_status": 429,
    "body": {
      "error": {
        "code": "RATE_LIMITED",
        "message": "Vui lòng chờ trước khi tạo challenge mới.",
        "details": {},
        "request_id": "req-demo"
      }
    }
  }
]
```

**Ghi chú:** Domain/URI/nonce do server cấu hình; message ví dụ không được dùng để login thật.

<a id="api-05"></a>

### API-05 — POST /api/v1/auth/verify

Xác thực chữ ký và tạo phiên. Authority: **Public**. Status: **Đã triển khai (BE)**. Owner: **B (API), A (mobile)**.

**RequestBody / Params** — path/query/headers chỉ là các phần mô tả; HTTP body chỉ gửi object trong body.

```json
{
  "body": {
    "challenge_id": "40000000-0000-4000-8000-000000000001",
    "signature": "<65-byte-EOA-signature>"
  }
}
```

**Success JSON** — http_status là HTTP status, không phải field được server thêm vào response.

```json
{
  "http_status": 200,
  "body": {
    "access_token": "<server-issued-JWT>",
    "token_type": "bearer",
    "expires_at": "2026-11-11T04:00:00Z",
    "user": {
      "id": "10000000-0000-4000-8000-000000000001",
      "wallet_address": "0x2222222222222222222222222222222222222222",
      "display_name": "Demo subscriber",
      "is_merchant": false,
      "created_at": "2026-11-11T03:00:00Z"
    }
  }
}
```

**Fail JSON**

```json
[
  {
    "http_status": 422,
    "body": {
      "error": {
        "code": "VALIDATION_ERROR",
        "message": "Dữ liệu không đúng schema.",
        "details": {},
        "request_id": "req-demo"
      }
    }
  },
  {
    "http_status": 401,
    "body": {
      "error": {
        "code": "INVALID_SIGNATURE",
        "message": "Chữ ký không hợp lệ.",
        "details": {},
        "request_id": "req-demo"
      }
    }
  },
  {
    "http_status": 401,
    "body": {
      "error": {
        "code": "CHALLENGE_EXPIRED",
        "message": "Challenge đã hết hạn.",
        "details": {},
        "request_id": "req-demo"
      }
    }
  },
  {
    "http_status": 401,
    "body": {
      "error": {
        "code": "CHALLENGE_USED",
        "message": "Challenge đã được sử dụng.",
        "details": {},
        "request_id": "req-demo"
      }
    }
  }
]
```

**Ghi chú:** MVP chỉ EOA. consume challenge và tạo session nguyên tử.

<a id="api-06"></a>

### API-06 — POST /api/v1/auth/logout

Thu hồi session hiện tại. Authority: **User**. Status: **Đã triển khai (BE)**. Owner: **B (API), A (mobile)**.

**RequestBody / Params** — path/query/headers chỉ là các phần mô tả; HTTP body chỉ gửi object trong body.

```json
{
  "headers": {
    "Authorization": "Bearer <access_token>"
  }
}
```

**Success JSON** — http_status là HTTP status, không phải field được server thêm vào response.

```json
{
  "http_status": 204,
  "body": null
}
```

**Fail JSON**

```json
[
  {
    "http_status": 401,
    "body": {
      "error": {
        "code": "UNAUTHORIZED",
        "message": "Cần đăng nhập bằng ví.",
        "details": {},
        "request_id": "req-demo"
      }
    }
  }
]
```

**Ghi chú:** 204 thực tế không có HTTP body; body:null trong mẫu chỉ để mô tả.

<a id="api-07"></a>

### API-07 — GET /api/v1/me

Đọc profile ví hiện tại. Authority: **User**. Status: **Đã triển khai (BE)**. Owner: **B (API), A (mobile)**.

**RequestBody / Params** — path/query/headers chỉ là các phần mô tả; HTTP body chỉ gửi object trong body.

```json
{
  "headers": {
    "Authorization": "Bearer <access_token>"
  }
}
```

**Success JSON** — http_status là HTTP status, không phải field được server thêm vào response.

```json
{
  "http_status": 200,
  "body": {
    "id": "10000000-0000-4000-8000-000000000001",
    "wallet_address": "0x2222222222222222222222222222222222222222",
    "display_name": "Demo subscriber",
    "is_merchant": false,
    "created_at": "2026-11-11T03:00:00Z"
  }
}
```

**Fail JSON**

```json
[
  {
    "http_status": 401,
    "body": {
      "error": {
        "code": "UNAUTHORIZED",
        "message": "Cần đăng nhập bằng ví.",
        "details": {},
        "request_id": "req-demo"
      }
    }
  }
]
```

<a id="api-08"></a>

### API-08 — PATCH /api/v1/me

Đổi tên hiển thị. Authority: **User**. Status: **Đã triển khai (BE)**. Owner: **B (API), A (mobile)**.

**RequestBody / Params** — path/query/headers chỉ là các phần mô tả; HTTP body chỉ gửi object trong body.

```json
{
  "body": {
    "display_name": "Tên mới"
  },
  "headers": {
    "Authorization": "Bearer <access_token>"
  }
}
```

**Success JSON** — http_status là HTTP status, không phải field được server thêm vào response.

```json
{
  "http_status": 200,
  "body": {
    "id": "10000000-0000-4000-8000-000000000001",
    "wallet_address": "0x2222222222222222222222222222222222222222",
    "display_name": "Tên mới",
    "is_merchant": false,
    "created_at": "2026-11-11T03:00:00Z"
  }
}
```

**Fail JSON**

```json
[
  {
    "http_status": 401,
    "body": {
      "error": {
        "code": "UNAUTHORIZED",
        "message": "Cần đăng nhập bằng ví.",
        "details": {},
        "request_id": "req-demo"
      }
    }
  },
  {
    "http_status": 422,
    "body": {
      "error": {
        "code": "VALIDATION_ERROR",
        "message": "Dữ liệu không đúng schema.",
        "details": {},
        "request_id": "req-demo"
      }
    }
  }
]
```

<a id="api-09"></a>

### API-09 — POST /api/v1/merchants

Tạo hồ sơ cơ sở cho ví đã login. Authority: **User**. Status: **Đã triển khai (BE)**. Owner: **B (API), A (mobile)**.

**RequestBody / Params** — path/query/headers chỉ là các phần mô tả; HTTP body chỉ gửi object trong body.

```json
{
  "body": {
    "business_name": "Demo Gym",
    "description": "Cơ sở thử nghiệm",
    "location_text": "TP.HCM"
  },
  "headers": {
    "Authorization": "Bearer <access_token>"
  }
}
```

**Success JSON** — http_status là HTTP status, không phải field được server thêm vào response.

```json
{
  "http_status": 201,
  "body": {
    "id": "20000000-0000-4000-8000-000000000001",
    "owner_wallet": "0x1111111111111111111111111111111111111111",
    "business_name": "Demo Gym",
    "description": "Cơ sở thử nghiệm",
    "location_text": "TP.HCM",
    "created_at": "2026-11-11T03:00:00Z",
    "updated_at": "2026-11-11T03:00:00Z"
  }
}
```

**Fail JSON**

```json
[
  {
    "http_status": 401,
    "body": {
      "error": {
        "code": "UNAUTHORIZED",
        "message": "Cần đăng nhập bằng ví.",
        "details": {},
        "request_id": "req-demo"
      }
    }
  },
  {
    "http_status": 422,
    "body": {
      "error": {
        "code": "VALIDATION_ERROR",
        "message": "Dữ liệu không đúng schema.",
        "details": {},
        "request_id": "req-demo"
      }
    }
  },
  {
    "http_status": 409,
    "body": {
      "error": {
        "code": "MERCHANT_EXISTS",
        "message": "Ví này đã có hồ sơ merchant.",
        "details": {},
        "request_id": "req-demo"
      }
    }
  }
]
```

**Ghi chú:** Ví session trong case này là ví merchant 0x111…; owner không lấy từ body.

<a id="api-10"></a>

### API-10 — GET /api/v1/merchants/{merchant_id}

Đọc hồ sơ cơ sở. Authority: **Public**. Status: **Đã triển khai (BE)**. Owner: **B (API), A (mobile)**.

**RequestBody / Params** — path/query/headers chỉ là các phần mô tả; HTTP body chỉ gửi object trong body.

```json
{
  "path": {
    "merchant_id": "20000000-0000-4000-8000-000000000001"
  }
}
```

**Success JSON** — http_status là HTTP status, không phải field được server thêm vào response.

```json
{
  "http_status": 200,
  "body": {
    "id": "20000000-0000-4000-8000-000000000001",
    "owner_wallet": "0x1111111111111111111111111111111111111111",
    "business_name": "Demo Gym",
    "description": "Cơ sở thử nghiệm",
    "location_text": "TP.HCM",
    "created_at": "2026-11-11T03:00:00Z",
    "updated_at": "2026-11-11T03:00:00Z"
  }
}
```

**Fail JSON**

```json
[
  {
    "http_status": 404,
    "body": {
      "error": {
        "code": "NOT_FOUND",
        "message": "Không tìm thấy tài nguyên trong phạm vi được phép.",
        "details": {},
        "request_id": "req-demo"
      }
    }
  },
  {
    "http_status": 422,
    "body": {
      "error": {
        "code": "VALIDATION_ERROR",
        "message": "Dữ liệu không đúng schema.",
        "details": {},
        "request_id": "req-demo"
      }
    }
  }
]
```

<a id="api-11"></a>

### API-11 — PATCH /api/v1/merchants/{merchant_id}

Sửa profile cơ sở mình sở hữu. Authority: **Owner**. Status: **Đã triển khai (BE)**. Owner: **B (API), A (mobile)**.

**RequestBody / Params** — path/query/headers chỉ là các phần mô tả; HTTP body chỉ gửi object trong body.

```json
{
  "path": {
    "merchant_id": "20000000-0000-4000-8000-000000000001"
  },
  "body": {
    "description": "Mô tả cập nhật"
  },
  "headers": {
    "Authorization": "Bearer <access_token>"
  }
}
```

**Success JSON** — http_status là HTTP status, không phải field được server thêm vào response.

```json
{
  "http_status": 200,
  "body": {
    "id": "20000000-0000-4000-8000-000000000001",
    "owner_wallet": "0x1111111111111111111111111111111111111111",
    "business_name": "Demo Gym",
    "description": "Mô tả cập nhật",
    "location_text": "TP.HCM",
    "created_at": "2026-11-11T03:00:00Z",
    "updated_at": "2026-11-11T03:00:00Z"
  }
}
```

**Fail JSON**

```json
[
  {
    "http_status": 401,
    "body": {
      "error": {
        "code": "UNAUTHORIZED",
        "message": "Cần đăng nhập bằng ví.",
        "details": {},
        "request_id": "req-demo"
      }
    }
  },
  {
    "http_status": 404,
    "body": {
      "error": {
        "code": "NOT_FOUND",
        "message": "Không tìm thấy tài nguyên trong phạm vi được phép.",
        "details": {},
        "request_id": "req-demo"
      }
    }
  },
  {
    "http_status": 422,
    "body": {
      "error": {
        "code": "VALIDATION_ERROR",
        "message": "Dữ liệu không đúng schema.",
        "details": {},
        "request_id": "req-demo"
      }
    }
  }
]
```

**Ghi chú:** Tài nguyên thuộc người khác trả 404. Không nhận owner_wallet.

<a id="api-12"></a>

### API-12 — POST /api/v1/plan-drafts

Tạo nháp điều khoản gói. Authority: **Merchant**. Status: **Đã triển khai (BE)**. Owner: **B (API), A (mobile)**.

**RequestBody / Params** — path/query/headers chỉ là các phần mô tả; HTTP body chỉ gửi object trong body.

```json
{
  "body": {
    "title": "Gym 12 kỳ",
    "description": "Gói thử nghiệm",
    "price_per_period": "50000000",
    "total_periods": 12,
    "period_duration_seconds": 2592000,
    "grace_period_seconds": 2592000
  },
  "headers": {
    "Authorization": "Bearer <access_token>"
  }
}
```

**Success JSON** — http_status là HTTP status, không phải field được server thêm vào response.

```json
{
  "http_status": 201,
  "body": {
    "id": "30000000-0000-4000-8000-000000000001",
    "merchant_id": "20000000-0000-4000-8000-000000000001",
    "client_reference": "0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
    "title": "Gym 12 kỳ",
    "description": "Gói thử nghiệm",
    "price_per_period": "50000000",
    "total_periods": 12,
    "period_duration_seconds": 2592000,
    "grace_period_seconds": 2592000,
    "token_address": "0x3333333333333333333333333333333333333333",
    "total_price": "600000000",
    "state": "DRAFT",
    "chain_id": 43113,
    "vault_address": "0x4444444444444444444444444444444444444444",
    "onchain_plan_id": null,
    "publication_tx_hash": null,
    "created_at": "2026-11-11T03:00:00Z",
    "updated_at": "2026-11-11T03:00:00Z"
  }
}
```

**Fail JSON**

```json
[
  {
    "http_status": 401,
    "body": {
      "error": {
        "code": "UNAUTHORIZED",
        "message": "Cần đăng nhập bằng ví.",
        "details": {},
        "request_id": "req-demo"
      }
    }
  },
  {
    "http_status": 422,
    "body": {
      "error": {
        "code": "VALIDATION_ERROR",
        "message": "Dữ liệu không đúng schema.",
        "details": {},
        "request_id": "req-demo"
      }
    }
  },
  {
    "http_status": 403,
    "body": {
      "error": {
        "code": "MERCHANT_REQUIRED",
        "message": "Cần tạo merchant profile trước.",
        "details": {},
        "request_id": "req-demo"
      }
    }
  }
]
```

<a id="api-13"></a>

### API-13 — GET /api/v1/plan-drafts

Danh sách draft thuộc merchant. Authority: **Merchant**. Status: **Đã triển khai (BE)**. Owner: **B (API), A (mobile)**.

**RequestBody / Params** — path/query/headers chỉ là các phần mô tả; HTTP body chỉ gửi object trong body.

```json
{
  "query": {
    "limit": 20
  },
  "headers": {
    "Authorization": "Bearer <access_token>"
  }
}
```

**Success JSON** — http_status là HTTP status, không phải field được server thêm vào response.

```json
{
  "http_status": 200,
  "body": {
    "items": [
      {
        "id": "30000000-0000-4000-8000-000000000001",
        "merchant_id": "20000000-0000-4000-8000-000000000001",
        "client_reference": "0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
        "title": "Gym 12 kỳ",
        "description": "Gói thử nghiệm",
        "price_per_period": "50000000",
        "total_periods": 12,
        "period_duration_seconds": 2592000,
        "grace_period_seconds": 2592000,
        "token_address": "0x3333333333333333333333333333333333333333",
        "total_price": "600000000",
        "state": "DRAFT",
        "chain_id": 43113,
        "vault_address": "0x4444444444444444444444444444444444444444",
        "onchain_plan_id": null,
        "publication_tx_hash": null,
        "created_at": "2026-11-11T03:00:00Z",
        "updated_at": "2026-11-11T03:00:00Z"
      }
    ],
    "next_cursor": null
  }
}
```

**Fail JSON**

```json
[
  {
    "http_status": 401,
    "body": {
      "error": {
        "code": "UNAUTHORIZED",
        "message": "Cần đăng nhập bằng ví.",
        "details": {},
        "request_id": "req-demo"
      }
    }
  },
  {
    "http_status": 403,
    "body": {
      "error": {
        "code": "MERCHANT_REQUIRED",
        "message": "Cần merchant profile.",
        "details": {},
        "request_id": "req-demo"
      }
    }
  },
  {
    "http_status": 422,
    "body": {
      "error": {
        "code": "VALIDATION_ERROR",
        "message": "Dữ liệu không đúng schema.",
        "details": {},
        "request_id": "req-demo"
      }
    }
  }
]
```

**Ghi chú:** cursor chỉ gửi khi next_cursor khác null.

<a id="api-14"></a>

### API-14 — GET /api/v1/plan-drafts/{draft_id}

Đọc draft của mình. Authority: **Owner**. Status: **Đã triển khai (BE)**. Owner: **B (API), A (mobile)**.

**RequestBody / Params** — path/query/headers chỉ là các phần mô tả; HTTP body chỉ gửi object trong body.

```json
{
  "path": {
    "draft_id": "30000000-0000-4000-8000-000000000001"
  },
  "headers": {
    "Authorization": "Bearer <access_token>"
  }
}
```

**Success JSON** — http_status là HTTP status, không phải field được server thêm vào response.

```json
{
  "http_status": 200,
  "body": {
    "id": "30000000-0000-4000-8000-000000000001",
    "merchant_id": "20000000-0000-4000-8000-000000000001",
    "client_reference": "0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
    "title": "Gym 12 kỳ",
    "description": "Gói thử nghiệm",
    "price_per_period": "50000000",
    "total_periods": 12,
    "period_duration_seconds": 2592000,
    "grace_period_seconds": 2592000,
    "token_address": "0x3333333333333333333333333333333333333333",
    "total_price": "600000000",
    "state": "DRAFT",
    "chain_id": 43113,
    "vault_address": "0x4444444444444444444444444444444444444444",
    "onchain_plan_id": null,
    "publication_tx_hash": null,
    "created_at": "2026-11-11T03:00:00Z",
    "updated_at": "2026-11-11T03:00:00Z"
  }
}
```

**Fail JSON**

```json
[
  {
    "http_status": 401,
    "body": {
      "error": {
        "code": "UNAUTHORIZED",
        "message": "Cần đăng nhập bằng ví.",
        "details": {},
        "request_id": "req-demo"
      }
    }
  },
  {
    "http_status": 404,
    "body": {
      "error": {
        "code": "NOT_FOUND",
        "message": "Không tìm thấy tài nguyên trong phạm vi được phép.",
        "details": {},
        "request_id": "req-demo"
      }
    }
  },
  {
    "http_status": 422,
    "body": {
      "error": {
        "code": "VALIDATION_ERROR",
        "message": "Dữ liệu không đúng schema.",
        "details": {},
        "request_id": "req-demo"
      }
    }
  }
]
```

<a id="api-15"></a>

### API-15 — PATCH /api/v1/plan-drafts/{draft_id}

Chỉnh draft chưa publish. Authority: **Owner**. Status: **Đã triển khai (BE)**. Owner: **B (API), A (mobile)**.

**RequestBody / Params** — path/query/headers chỉ là các phần mô tả; HTTP body chỉ gửi object trong body.

```json
{
  "path": {
    "draft_id": "30000000-0000-4000-8000-000000000001"
  },
  "body": {
    "title": "Gym 12 kỳ — cập nhật"
  },
  "headers": {
    "Authorization": "Bearer <access_token>"
  }
}
```

**Success JSON** — http_status là HTTP status, không phải field được server thêm vào response.

```json
{
  "http_status": 200,
  "body": {
    "id": "30000000-0000-4000-8000-000000000001",
    "merchant_id": "20000000-0000-4000-8000-000000000001",
    "client_reference": "0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
    "title": "Gym 12 kỳ — cập nhật",
    "description": "Gói thử nghiệm",
    "price_per_period": "50000000",
    "total_periods": 12,
    "period_duration_seconds": 2592000,
    "grace_period_seconds": 2592000,
    "token_address": "0x3333333333333333333333333333333333333333",
    "total_price": "600000000",
    "state": "DRAFT",
    "chain_id": 43113,
    "vault_address": "0x4444444444444444444444444444444444444444",
    "onchain_plan_id": null,
    "publication_tx_hash": null,
    "created_at": "2026-11-11T03:00:00Z",
    "updated_at": "2026-11-11T03:00:00Z"
  }
}
```

**Fail JSON**

```json
[
  {
    "http_status": 401,
    "body": {
      "error": {
        "code": "UNAUTHORIZED",
        "message": "Cần đăng nhập bằng ví.",
        "details": {},
        "request_id": "req-demo"
      }
    }
  },
  {
    "http_status": 404,
    "body": {
      "error": {
        "code": "NOT_FOUND",
        "message": "Không tìm thấy tài nguyên trong phạm vi được phép.",
        "details": {},
        "request_id": "req-demo"
      }
    }
  },
  {
    "http_status": 422,
    "body": {
      "error": {
        "code": "VALIDATION_ERROR",
        "message": "Dữ liệu không đúng schema.",
        "details": {},
        "request_id": "req-demo"
      }
    }
  },
  {
    "http_status": 409,
    "body": {
      "error": {
        "code": "PLAN_IMMUTABLE",
        "message": "Không thể sửa gói đã publish.",
        "details": {},
        "request_id": "req-demo"
      }
    }
  }
]
```

**Ghi chú:** PATCH tối thiểu một field; không cho sửa state hoặc onchain_plan_id.

<a id="api-16"></a>

### API-16 — GET /api/v1/plans

Danh sách plan đã publish. Authority: **Public**. Status: **Đã triển khai (BE)**. Owner: **B (API), A (mobile)**.

**RequestBody / Params** — path/query/headers chỉ là các phần mô tả; HTTP body chỉ gửi object trong body.

```json
{
  "query": {
    "merchant_address": "0x1111111111111111111111111111111111111111",
    "limit": 20
  }
}
```

**Success JSON** — http_status là HTTP status, không phải field được server thêm vào response.

```json
{
  "http_status": 200,
  "body": {
    "items": [
      {
        "plan_id": "1",
        "chain_id": 43113,
        "vault_address": "0x4444444444444444444444444444444444444444",
        "merchant_address": "0x1111111111111111111111111111111111111111",
        "merchant": {
          "id": "20000000-0000-4000-8000-000000000001",
          "owner_wallet": "0x1111111111111111111111111111111111111111",
          "business_name": "Demo Gym",
          "description": "Cơ sở thử nghiệm",
          "location_text": "TP.HCM",
          "created_at": "2026-11-11T03:00:00Z",
          "updated_at": "2026-11-11T03:00:00Z"
        },
        "title": "Gym 12 kỳ",
        "description": "Gói thử nghiệm",
        "token": {
          "address": "0x3333333333333333333333333333333333333333",
          "symbol": "mUSDC",
          "decimals": 6
        },
        "price_per_period": "50000000",
        "total_periods": 12,
        "period_duration_seconds": 2592000,
        "grace_period_seconds": 2592000,
        "total_price": "600000000",
        "sync": {
          "block_number": "100",
          "block_hash": "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
          "block_timestamp": "2026-11-11T03:00:00Z",
          "synced_at": "2026-11-11T03:00:00Z",
          "source": "LIVE"
        }
      }
    ],
    "next_cursor": null
  }
}
```

**Fail JSON**

```json
[
  {
    "http_status": 422,
    "body": {
      "error": {
        "code": "VALIDATION_ERROR",
        "message": "Dữ liệu không đúng schema.",
        "details": {},
        "request_id": "req-demo"
      }
    }
  },
  {
    "http_status": 503,
    "body": {
      "error": {
        "code": "RPC_UNAVAILABLE",
        "message": "Chưa đọc được blockchain. Vui lòng thử lại.",
        "details": {},
        "request_id": "req-demo"
      }
    }
  }
]
```

**Ghi chú:** merchant_address là filter tùy chọn; list có thể dùng projection.

<a id="api-17"></a>

### API-17 — GET /api/v1/plans/{plan_id}

Đọc plan và điều khoản on-chain. Authority: **Public**. Status: **Đã triển khai (BE)**. Owner: **B (API), A (mobile)**.

**RequestBody / Params** — path/query/headers chỉ là các phần mô tả; HTTP body chỉ gửi object trong body.

```json
{
  "path": {
    "plan_id": "1"
  }
}
```

**Success JSON** — http_status là HTTP status, không phải field được server thêm vào response.

```json
{
  "http_status": 200,
  "body": {
    "plan_id": "1",
    "chain_id": 43113,
    "vault_address": "0x4444444444444444444444444444444444444444",
    "merchant_address": "0x1111111111111111111111111111111111111111",
    "merchant": {
      "id": "20000000-0000-4000-8000-000000000001",
      "owner_wallet": "0x1111111111111111111111111111111111111111",
      "business_name": "Demo Gym",
      "description": "Cơ sở thử nghiệm",
      "location_text": "TP.HCM",
      "created_at": "2026-11-11T03:00:00Z",
      "updated_at": "2026-11-11T03:00:00Z"
    },
    "title": "Gym 12 kỳ",
    "description": "Gói thử nghiệm",
    "token": {
      "address": "0x3333333333333333333333333333333333333333",
      "symbol": "mUSDC",
      "decimals": 6
    },
    "price_per_period": "50000000",
    "total_periods": 12,
    "period_duration_seconds": 2592000,
    "grace_period_seconds": 2592000,
    "total_price": "600000000",
    "sync": {
      "block_number": "100",
      "block_hash": "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      "block_timestamp": "2026-11-11T03:00:00Z",
      "synced_at": "2026-11-11T03:00:00Z",
      "source": "LIVE"
    }
  }
}
```

**Fail JSON**

```json
[
  {
    "http_status": 404,
    "body": {
      "error": {
        "code": "NOT_FOUND",
        "message": "Không tìm thấy tài nguyên trong phạm vi được phép.",
        "details": {},
        "request_id": "req-demo"
      }
    }
  },
  {
    "http_status": 422,
    "body": {
      "error": {
        "code": "VALIDATION_ERROR",
        "message": "Dữ liệu không đúng schema.",
        "details": {},
        "request_id": "req-demo"
      }
    }
  },
  {
    "http_status": 503,
    "body": {
      "error": {
        "code": "RPC_UNAVAILABLE",
        "message": "Chưa đọc được blockchain. Vui lòng thử lại.",
        "details": {},
        "request_id": "req-demo"
      }
    }
  }
]
```

<a id="api-18"></a>

### API-18 — GET /api/v1/me/subscriptions

Gói thuộc subscriber hiện tại. Authority: **User**. Status: **Đã triển khai (BE)**. Owner: **B (API), A (mobile)**.

**RequestBody / Params** — path/query/headers chỉ là các phần mô tả; HTTP body chỉ gửi object trong body.

```json
{
  "query": {
    "status": "ACTIVE",
    "limit": 20
  },
  "headers": {
    "Authorization": "Bearer <access_token>"
  }
}
```

**Success JSON** — http_status là HTTP status, không phải field được server thêm vào response.

```json
{
  "http_status": 200,
  "body": {
    "items": [
      {
        "subscription_id": "1",
        "plan_id": "1",
        "chain_id": 43113,
        "vault_address": "0x4444444444444444444444444444444444444444",
        "merchant_address": "0x1111111111111111111111111111111111111111",
        "subscriber_address": "0x2222222222222222222222222222222222222222",
        "token": {
          "address": "0x3333333333333333333333333333333333333333",
          "symbol": "mUSDC",
          "decimals": 6
        },
        "initial_principal": "600000000",
        "remaining_principal": "600000000",
        "principal_released": "0",
        "principal_refunded": "0",
        "total_periods": 12,
        "completed_periods": 0,
        "next_period_index": "1",
        "started_at": "2026-11-11T03:00:00Z",
        "next_release_at": "2026-12-11T03:00:00Z",
        "refund_available_at": "2027-01-10T03:00:00Z",
        "nonce": "0",
        "status": "ACTIVE",
        "yield_summary": {
          "mode": "MOCK",
          "estimated_unclaimed": "0",
          "paid_merchant": "0",
          "paid_subscriber": "0",
          "paid_platform": "0"
        },
        "sync": {
          "block_number": "100",
          "block_hash": "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
          "block_timestamp": "2026-11-11T03:00:00Z",
          "synced_at": "2026-11-11T03:00:00Z",
          "source": "LIVE"
        }
      }
    ],
    "next_cursor": null
  }
}
```

**Fail JSON**

```json
[
  {
    "http_status": 401,
    "body": {
      "error": {
        "code": "UNAUTHORIZED",
        "message": "Cần đăng nhập bằng ví.",
        "details": {},
        "request_id": "req-demo"
      }
    }
  },
  {
    "http_status": 422,
    "body": {
      "error": {
        "code": "VALIDATION_ERROR",
        "message": "Dữ liệu không đúng schema.",
        "details": {},
        "request_id": "req-demo"
      }
    }
  }
]
```

**Ghi chú:** Không nhận subscriber_address tùy ý.

<a id="api-19"></a>

### API-19 — GET /api/v1/merchant/subscriptions

Gói khách thuộc merchant hiện tại. Authority: **Merchant**. Status: **Đã triển khai (BE)**. Owner: **B (API), A (mobile)**.

**RequestBody / Params** — path/query/headers chỉ là các phần mô tả; HTTP body chỉ gửi object trong body.

```json
{
  "query": {
    "plan_id": "1",
    "status": "ACTIVE",
    "limit": 20
  },
  "headers": {
    "Authorization": "Bearer <access_token>"
  }
}
```

**Success JSON** — http_status là HTTP status, không phải field được server thêm vào response.

```json
{
  "http_status": 200,
  "body": {
    "items": [
      {
        "subscription_id": "1",
        "plan_id": "1",
        "chain_id": 43113,
        "vault_address": "0x4444444444444444444444444444444444444444",
        "merchant_address": "0x1111111111111111111111111111111111111111",
        "subscriber_address": "0x2222222222222222222222222222222222222222",
        "token": {
          "address": "0x3333333333333333333333333333333333333333",
          "symbol": "mUSDC",
          "decimals": 6
        },
        "initial_principal": "600000000",
        "remaining_principal": "600000000",
        "principal_released": "0",
        "principal_refunded": "0",
        "total_periods": 12,
        "completed_periods": 0,
        "next_period_index": "1",
        "started_at": "2026-11-11T03:00:00Z",
        "next_release_at": "2026-12-11T03:00:00Z",
        "refund_available_at": "2027-01-10T03:00:00Z",
        "nonce": "0",
        "status": "ACTIVE",
        "yield_summary": {
          "mode": "MOCK",
          "estimated_unclaimed": "0",
          "paid_merchant": "0",
          "paid_subscriber": "0",
          "paid_platform": "0"
        },
        "sync": {
          "block_number": "100",
          "block_hash": "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
          "block_timestamp": "2026-11-11T03:00:00Z",
          "synced_at": "2026-11-11T03:00:00Z",
          "source": "LIVE"
        }
      }
    ],
    "next_cursor": null
  }
}
```

**Fail JSON**

```json
[
  {
    "http_status": 401,
    "body": {
      "error": {
        "code": "UNAUTHORIZED",
        "message": "Cần đăng nhập bằng ví.",
        "details": {},
        "request_id": "req-demo"
      }
    }
  },
  {
    "http_status": 422,
    "body": {
      "error": {
        "code": "VALIDATION_ERROR",
        "message": "Dữ liệu không đúng schema.",
        "details": {},
        "request_id": "req-demo"
      }
    }
  },
  {
    "http_status": 404,
    "body": {
      "error": {
        "code": "NOT_FOUND",
        "message": "Không tìm thấy tài nguyên trong phạm vi được phép.",
        "details": {},
        "request_id": "req-demo"
      }
    }
  },
  {
    "http_status": 403,
    "body": {
      "error": {
        "code": "MERCHANT_REQUIRED",
        "message": "Cần merchant profile.",
        "details": {},
        "request_id": "req-demo"
      }
    }
  }
]
```

**Ghi chú:** Filter plan_id phải thuộc merchant đang login.

<a id="api-20"></a>

### API-20 — GET /api/v1/subscriptions/{subscription_id}

Chi tiết gói và số dư. Authority: **Participant**. Status: **Đã triển khai (BE)**. Owner: **B (API), A (mobile)**.

**RequestBody / Params** — path/query/headers chỉ là các phần mô tả; HTTP body chỉ gửi object trong body.

```json
{
  "path": {
    "subscription_id": "1"
  },
  "headers": {
    "Authorization": "Bearer <access_token>"
  }
}
```

**Success JSON** — http_status là HTTP status, không phải field được server thêm vào response.

```json
{
  "http_status": 200,
  "body": {
    "subscription_id": "1",
    "plan_id": "1",
    "chain_id": 43113,
    "vault_address": "0x4444444444444444444444444444444444444444",
    "merchant_address": "0x1111111111111111111111111111111111111111",
    "subscriber_address": "0x2222222222222222222222222222222222222222",
    "token": {
      "address": "0x3333333333333333333333333333333333333333",
      "symbol": "mUSDC",
      "decimals": 6
    },
    "initial_principal": "600000000",
    "remaining_principal": "600000000",
    "principal_released": "0",
    "principal_refunded": "0",
    "total_periods": 12,
    "completed_periods": 0,
    "next_period_index": "1",
    "started_at": "2026-11-11T03:00:00Z",
    "next_release_at": "2026-12-11T03:00:00Z",
    "refund_available_at": "2027-01-10T03:00:00Z",
    "nonce": "0",
    "status": "ACTIVE",
    "yield_summary": {
      "mode": "MOCK",
      "estimated_unclaimed": "0",
      "paid_merchant": "0",
      "paid_subscriber": "0",
      "paid_platform": "0"
    },
    "sync": {
      "block_number": "100",
      "block_hash": "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      "block_timestamp": "2026-11-11T03:00:00Z",
      "synced_at": "2026-11-11T03:00:00Z",
      "source": "LIVE"
    }
  }
}
```

**Fail JSON**

```json
[
  {
    "http_status": 401,
    "body": {
      "error": {
        "code": "UNAUTHORIZED",
        "message": "Cần đăng nhập bằng ví.",
        "details": {},
        "request_id": "req-demo"
      }
    }
  },
  {
    "http_status": 404,
    "body": {
      "error": {
        "code": "NOT_FOUND",
        "message": "Không tìm thấy tài nguyên trong phạm vi được phép.",
        "details": {},
        "request_id": "req-demo"
      }
    }
  },
  {
    "http_status": 422,
    "body": {
      "error": {
        "code": "VALIDATION_ERROR",
        "message": "Dữ liệu không đúng schema.",
        "details": {},
        "request_id": "req-demo"
      }
    }
  },
  {
    "http_status": 503,
    "body": {
      "error": {
        "code": "RPC_UNAVAILABLE",
        "message": "Chưa đọc được blockchain. Vui lòng thử lại.",
        "details": {},
        "request_id": "req-demo"
      }
    }
  }
]
```

<a id="api-21"></a>

### API-21 — GET /api/v1/subscriptions/{subscription_id}/eligibility

Kiểm điều kiện check-in/refund live. Authority: **Participant**. Status: **Đã triển khai (BE)**. Owner: **B (API), A (mobile)**.

**RequestBody / Params** — path/query/headers chỉ là các phần mô tả; HTTP body chỉ gửi object trong body.

```json
{
  "path": {
    "subscription_id": "1"
  },
  "headers": {
    "Authorization": "Bearer <access_token>"
  }
}
```

**Success JSON** — http_status là HTTP status, không phải field được server thêm vào response.

```json
{
  "http_status": 200,
  "body": {
    "subscription_id": "1",
    "status": "ACTIVE",
    "can_check_in": false,
    "can_refund": false,
    "next_period_index": "1",
    "nonce": "0",
    "next_release_at": "2026-12-11T03:00:00Z",
    "refund_available_at": "2027-01-10T03:00:00Z",
    "reasons": [
      "TOO_EARLY"
    ],
    "sync": {
      "block_number": "100",
      "block_hash": "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      "block_timestamp": "2026-11-11T03:00:00Z",
      "synced_at": "2026-11-11T03:00:00Z",
      "source": "LIVE"
    }
  }
}
```

**Fail JSON**

```json
[
  {
    "http_status": 401,
    "body": {
      "error": {
        "code": "UNAUTHORIZED",
        "message": "Cần đăng nhập bằng ví.",
        "details": {},
        "request_id": "req-demo"
      }
    }
  },
  {
    "http_status": 404,
    "body": {
      "error": {
        "code": "NOT_FOUND",
        "message": "Không tìm thấy tài nguyên trong phạm vi được phép.",
        "details": {},
        "request_id": "req-demo"
      }
    }
  },
  {
    "http_status": 422,
    "body": {
      "error": {
        "code": "VALIDATION_ERROR",
        "message": "Dữ liệu không đúng schema.",
        "details": {},
        "request_id": "req-demo"
      }
    }
  },
  {
    "http_status": 503,
    "body": {
      "error": {
        "code": "RPC_UNAVAILABLE",
        "message": "Chưa đọc được blockchain. Vui lòng thử lại.",
        "details": {},
        "request_id": "req-demo"
      }
    }
  }
]
```

**Ghi chú:** 200 với can_check_in=false là kết quả nghiệp vụ bình thường, không phải HTTP failure.

<a id="api-22"></a>

### API-22 — GET /api/v1/subscriptions/{subscription_id}/events

Lịch sử event đã đối chiếu. Authority: **Participant**. Status: **Đã triển khai (BE)**. Owner: **B (API), A (mobile)**.

**RequestBody / Params** — path/query/headers chỉ là các phần mô tả; HTTP body chỉ gửi object trong body.

```json
{
  "path": {
    "subscription_id": "1"
  },
  "query": {
    "limit": 20
  },
  "headers": {
    "Authorization": "Bearer <access_token>"
  }
}
```

**Success JSON** — http_status là HTTP status, không phải field được server thêm vào response.

```json
{
  "http_status": 200,
  "body": {
    "items": [
      {
        "id": "50000000-0000-4000-8000-000000000001",
        "event_name": "SUBSCRIBED",
        "plan_id": "1",
        "subscription_id": "1",
        "tx_hash": "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        "log_index": 0,
        "block_number": "100",
        "block_timestamp": "2026-11-11T03:00:00Z",
        "payload": {
          "subscriber": "0x2222222222222222222222222222222222222222",
          "principal": "600000000",
          "startedAt": "1794366000",
          "nextReleaseAt": "1796958000"
        },
        "explorer_url": "https://explorer-test.avax.network/c-chain/tx/0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
      }
    ],
    "next_cursor": null
  }
}
```

**Fail JSON**

```json
[
  {
    "http_status": 401,
    "body": {
      "error": {
        "code": "UNAUTHORIZED",
        "message": "Cần đăng nhập bằng ví.",
        "details": {},
        "request_id": "req-demo"
      }
    }
  },
  {
    "http_status": 404,
    "body": {
      "error": {
        "code": "NOT_FOUND",
        "message": "Không tìm thấy tài nguyên trong phạm vi được phép.",
        "details": {},
        "request_id": "req-demo"
      }
    }
  },
  {
    "http_status": 422,
    "body": {
      "error": {
        "code": "VALIDATION_ERROR",
        "message": "Dữ liệu không đúng schema.",
        "details": {},
        "request_id": "req-demo"
      }
    }
  }
]
```

<a id="api-23"></a>

### API-23 — POST /api/v1/transactions

Theo dõi giao dịch đã broadcast. Authority: **User**. Status: **Đã triển khai (BE)**. Owner: **B (API), A (mobile)**, C review chain verification.

**RequestBody / Params** — path/query/headers chỉ là các phần mô tả; HTTP body chỉ gửi object trong body.

```json
{
  "body": {
    "tx_hash": "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "action": "SUBSCRIBE",
    "plan_id": "1"
  },
  "headers": {
    "Authorization": "Bearer <access_token>"
  }
}
```

**Success JSON** — http_status là HTTP status, không phải field được server thêm vào response.

```json
{
  "http_status": 202,
  "body": {
    "tx_hash": "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "chain_id": 43113,
    "expected_action": "SUBSCRIBE",
    "status": "SUBMITTED",
    "block_number": null,
    "failure_code": null,
    "checked_at": "2026-11-11T03:00:00Z",
    "explorer_url": "https://explorer-test.avax.network/c-chain/tx/0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "event_ids": []
  }
}
```

**Fail JSON**

```json
[
  {
    "http_status": 401,
    "body": {
      "error": {
        "code": "UNAUTHORIZED",
        "message": "Cần đăng nhập bằng ví.",
        "details": {},
        "request_id": "req-demo"
      }
    }
  },
  {
    "http_status": 422,
    "body": {
      "error": {
        "code": "VALIDATION_ERROR",
        "message": "Dữ liệu không đúng schema.",
        "details": {},
        "request_id": "req-demo"
      }
    }
  },
  {
    "http_status": 503,
    "body": {
      "error": {
        "code": "RPC_UNAVAILABLE",
        "message": "Chưa đọc được blockchain. Vui lòng thử lại.",
        "details": {},
        "request_id": "req-demo"
      }
    }
  },
  {
    "http_status": 409,
    "body": {
      "error": {
        "code": "TX_MISMATCH",
        "message": "Receipt không khớp action/tài nguyên.",
        "details": {},
        "request_id": "req-demo"
      }
    }
  },
  {
    "http_status": 409,
    "body": {
      "error": {
        "code": "TRANSACTION_CONFLICT",
        "message": "Hash đã đăng ký với action/reference khác.",
        "details": {},
        "request_id": "req-demo"
      }
    }
  }
]
```

**Ghi chú:** 202 là nhận theo dõi, KHÔNG bảo đảm thanh toán thành công. Variants: CREATE_PLAN + plan_draft_id; SUBSCRIBE + plan_id; CHECK_IN/REFUND + subscription_id. Chỉ một nhóm reference tương ứng được gửi.

<a id="api-24"></a>

### API-24 — GET /api/v1/transactions/{tx_hash}

Tra cứu và đối chiếu trạng thái tx. Authority: **Submitter**. Status: **Đã triển khai (BE)**. Owner: **B (API), A (mobile)**, C review chain verification.

**RequestBody / Params** — path/query/headers chỉ là các phần mô tả; HTTP body chỉ gửi object trong body.

```json
{
  "path": {
    "tx_hash": "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  },
  "headers": {
    "Authorization": "Bearer <access_token>"
  }
}
```

**Success JSON** — http_status là HTTP status, không phải field được server thêm vào response.

```json
{
  "http_status": 200,
  "body": {
    "tx_hash": "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "chain_id": 43113,
    "expected_action": "SUBSCRIBE",
    "status": "CONFIRMED",
    "block_number": "100",
    "failure_code": null,
    "checked_at": "2026-11-11T03:00:00Z",
    "explorer_url": "https://explorer-test.avax.network/c-chain/tx/0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "event_ids": [
      "50000000-0000-4000-8000-000000000001"
    ]
  }
}
```

**Fail JSON**

```json
[
  {
    "http_status": 401,
    "body": {
      "error": {
        "code": "UNAUTHORIZED",
        "message": "Cần đăng nhập bằng ví.",
        "details": {},
        "request_id": "req-demo"
      }
    }
  },
  {
    "http_status": 404,
    "body": {
      "error": {
        "code": "NOT_FOUND",
        "message": "Không tìm thấy tài nguyên trong phạm vi được phép.",
        "details": {},
        "request_id": "req-demo"
      }
    }
  },
  {
    "http_status": 422,
    "body": {
      "error": {
        "code": "VALIDATION_ERROR",
        "message": "Dữ liệu không đúng schema.",
        "details": {},
        "request_id": "req-demo"
      }
    }
  },
  {
    "http_status": 503,
    "body": {
      "error": {
        "code": "RPC_UNAVAILABLE",
        "message": "Chưa đọc được blockchain. Vui lòng thử lại.",
        "details": {},
        "request_id": "req-demo"
      }
    }
  }
]
```

**Ghi chú:** CONFIRMED trong ví dụ là một nhánh độc lập; thực tế có thể SUBMITTED hoặc REVERTED. HTTP 200 không tự có nghĩa tx thành công.
