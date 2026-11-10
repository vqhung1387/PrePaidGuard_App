# Schema — Entity, contract data và DTO

> Design draft 0.1 — 11/11/2026. Baseline B1–B6 trong [project.md](project.md) chưa được nhóm xác nhận.
> Tên snake_case cho REST/Python; camelCase cho Solidity/EIP-712. Mapping phải explicit.

## 1. Quy ước chung

| Kiểu | Quy ước |
| --- | --- |
| UUID | UUID string do backend tạo cho entity off-chain |
| Address | 20-byte hex; validate, lưu lowercase để so sánh; UI có thể checksum |
| Hash32 | 0x + 64 hex characters: tx hash, block hash, client_reference |
| UintString | JSON string chứa integer không âm; Solidity uint256; không float/scientific notation |
| Amount | UintString theo đơn vị nhỏ nhất token; MockUSDC decimals = 6 |
| ChainId | JSON integer; baseline 43113 |
| Timestamp | REST datetime UTC RFC3339; typed data/chain dùng Unix seconds dưới dạng UintString |
| Duration | REST integer seconds dương; kiểm tra giới hạn và overflow khi tính tổng/mốc thời gian |
| Contract ID | UintString, không dùng UUID draft thay planId/subscriptionId |
| Nullable | Chỉ trường được đánh dấu ? mới nhận null |
| Pagination | limit 1–100, mặc định 20; cursor opaque, sắp xếp ổn định timestamp + id |

Ví dụ 50 token = "50000000" atomic units, 12 kỳ = "600000000". VNĐ chỉ là nhãn minh họa; không tạo tỷ giá hay thanh toán VNĐ trong MVP. Profile text plain text; không nhận HTML.

DB lưu uint256 bằng NUMERIC(78,0), CHECK >= 0 và < 2^256; SQLAlchemy/Pydantic map integer/Decimal chính xác sang UintString. Không chuyển qua double.

## 2. Database entities

Mọi timestamp DB là timestamptz. created_at/updated_at do server đặt. Không có password, private_key hoặc seed_phrase trong bất kỳ bảng nào.

### User
- id: UUID PK.
- wallet_address: Address UNIQUE NOT NULL.
- display_name: string(1..80)?.
- created_at, updated_at: Timestamp.
Vai trò subscriber là hành vi; không cần roles array do client cấp.

### AuthChallenge
- id: UUID PK; wallet_address: Address; chain_id: ChainId.
- nonce: random alphanumeric >= 16 ký tự, UNIQUE.
- message: text SIWE chuẩn, do server tạo; domain/uri lấy cấu hình server.
- issued_at, expires_at (mặc định +5 phút), consumed_at?: Timestamp.
Verify thành công phải consume nguyên tử; hai request không dùng cùng challenge hai lần.

### AuthSession
- id: UUID PK; user_id: FK User; chain_id: ChainId.
- created_at, expires_at, revoked_at?: Timestamp.
Access JWT chứa sub=user UUID, sid=session UUID, wallet, chain_id, iat, exp.
TTL baseline 1 giờ; không refresh token trong MVP; hết hạn ký challenge mới.
Endpoint protected kiểm tra cả JWT và session chưa revoked.

### Merchant
- id: UUID PK; owner_user_id: FK User UNIQUE.
- business_name: string(1..120); description: string(0..2000); location_text: string(0..300)?.
- created_at, updated_at: Timestamp.
Một merchant mỗi ví; không có badge pháp lý/verified tự cấp, không employee scanner.

### PlanDraft
- id: UUID PK; merchant_id: FK Merchant.
- client_reference: Hash32 UNIQUE, random do server cấp, dùng ràng buộc createPlan với draft.
- title: string(1..120); description: string(0..2000).
- token_address: Address lấy config allowlist.
- price_per_period: Amount > 0; total_periods: int 1..120.
- period_duration_seconds: int > 0; grace_period_seconds: int > 0.
- total_price: Amount derived = price_per_period × total_periods.
- state: DRAFT | PUBLISHED.
- chain_id: ChainId; vault_address: Address.
- onchain_plan_id: UintString?; publication_tx_hash: Hash32?.
- created_at, updated_at: Timestamp.
Draft chỉ PATCH khi DRAFT. PUBLISHED chỉ khi event hợp lệ xác nhận, không qua request set state.
Index UNIQUE(chain_id, vault_address, onchain_plan_id) khi ID không null.
Không cho client PATCH owner, contract addresses, state, client_reference hay onchain_plan_id.

### SubscriptionSnapshot — projection, không phải ledger chuẩn
- id: UUID PK; chain_id, vault_address, subscription_id: unique composite.
- plan_id: UintString; merchant_address, subscriber_address: Address.
- price_per_period, initial_principal, remaining_principal: Amount.
- total_periods, completed_periods: int.
- started_at: Timestamp; next_release_at, refund_available_at: Timestamp?.
- nonce: UintString; status: ACTIVE | COMPLETED | REFUNDED.
- principal_released, principal_refunded: Amount.
- yield_paid_merchant, yield_paid_subscriber, yield_paid_platform: Amount.
- synced_block_number: UintString; synced_block_hash: Hash32; updated_at: Timestamp.
Hoàn tất/refund thì API trả next_release_at/refund_available_at = null dù DB có thể giữ mốc lịch sử; dùng nullable cho hai cột này nếu lưu read view.
Có thể lấy live contract khi snapshot cũ; API phải công khai block freshness.

### TransactionRecord
- id: UUID PK; submitted_by_user_id: FK User; chain_id: ChainId.
- tx_hash: Hash32; UNIQUE(chain_id, tx_hash).
- expected_action: CREATE_PLAN | SUBSCRIBE | CHECK_IN | REFUND.
- plan_draft_id: UUID?; subscription_id: UintString?; plan_id: UintString?.
- status: SUBMITTED | CONFIRMED | REVERTED.
- block_number: UintString?; block_hash: Hash32?; failure_code: string?.
- created_at, checked_at?: Timestamp.
Expected fields là gợi ý đối chiếu, không chứng minh giao dịch. APPROVE được mobile theo dõi trực tiếp, không cần lưu ở API MVP.
SUBMITTED gồm trường hợp RPC chưa tìm thấy; chưa tìm thấy không được kết luận REVERTED.

### EventRecord — lịch sử tái dựng từ receipt/log
- id: UUID PK; chain_id, vault_address, tx_hash, log_index: unique composite.
- block_number: UintString; block_hash: Hash32; block_timestamp: Timestamp.
- event_name: PLAN_CREATED | SUBSCRIBED | PERIOD_RELEASED | REFUNDED.
- plan_id, subscription_id?: UintString (plan_id luôn có; subscription_id null cho PLAN_CREATED).
- merchant_address: Address; subscriber_address: Address?.
- payload: JSONB đã decode/validate theo ABI; không nhận trực tiếp từ client.
Dùng block_number + log_index cho thứ tự; upsert để receipt verifier và log scanner không tạo bản ghi trùng.

### SyncCursor
- chain_id + vault_address: composite PK.
- last_processed_block: UintString; last_processed_block_hash: Hash32; updated_at: Timestamp.
Chỉ tăng sau khi transaction DB chứa đầy đủ events/projection commit. Quét lại vùng block nhỏ phải idempotent.

## 3. Quan hệ và migration

User 1–1 Merchant; Merchant 1–N PlanDraft; PlanDraft published map đến Plan on-chain.
User 1–N AuthSession/AuthChallenge theo ví. Plan on-chain 1–N Subscription on-chain.
Một user có thể có nhiều subscription của cùng plan; không khóa unique(subscriber, plan).
TransactionRecord 1–N EventRecord theo chain/tx; EventRecord có thể được scanner tìm thấy khi chưa có TransactionRecord.
Không cascade-delete dữ liệu tài chính. Index subscriber_address và merchant_address cho danh sách; index plan draft state và event subscription ID. Login nonce/session có thể dọn sau hết hạn theo retention sau này.

## 4. On-chain structs và derived data

### Plan (proposed)
planId:uint256, clientReference:bytes32, merchant:address, token:address,
pricePerPeriod:uint256, totalPeriods:uint32, periodDuration:uint64, gracePeriod:uint64.
Terms bất biến. UNIQUE(merchant, clientReference) để createPlan trùng không tạo hai plan.
Vault dùng một token allowlisted; token đầu vào phải khớp config.

### Subscription (proposed)
subscriptionId:uint256, planId:uint256, subscriber:address,
initialPrincipal:uint256, remainingPrincipal:uint256,
completedPeriods:uint32, nonce:uint256, startedAt:uint64, nextReleaseAt:uint64,
status:ACTIVE|COMPLETED|REFUNDED.
Terms đọc từ Plan bất biến; refundAvailableAt = nextReleaseAt + plan.gracePeriod khi ACTIVE.
periodIndex = completedPeriods + 1.
Các kiểu integer nhỏ phải kiểm tra range, overflow và encode nhất quán.

### YieldPosition / adapter accounting
Dùng subscriptionId làm khóa: principal, redeemableYield và position/shares nếu adapter cần.
Mỗi deposit/withdraw gắn subscription; không suy yield của A từ tổng balance của Vault.
estimateYield chỉ là giá trị dự kiến. realizeYield phải có token chi trả.
Mock adapter cấp token ngoài phần gốc; không tạo lãi bằng cách hạch toán thiếu backing.

### Events (proposed ABI)
- PlanCreated(planId, merchant, clientReference, token, pricePerPeriod, totalPeriods, periodDuration, gracePeriod).
- Subscribed(subscriptionId, planId, subscriber, principal, startedAt, nextReleaseAt).
- PeriodReleased(subscriptionId, planId, periodIndex, principal, merchantYield, subscriberYield, platformYield, nonceAfter, nextReleaseAt, completed).
- Refunded(subscriptionId, planId, principal, merchantYield, subscriberYield, platformYield, nonceAfter).
Chọn indexed fields phù hợp giới hạn EVM khi triển khai; signatures và types thực tế do shared/abi công bố.

## 5. Auth DTOs

- AuthChallengeRequest: wallet_address:Address, chain_id:ChainId.
- AuthChallengeResponse: challenge_id:UUID, message:string, expires_at:Timestamp.
- AuthVerifyRequest: challenge_id:UUID, signature:hex bytes 65-byte EOA signature.
- AuthTokenResponse: access_token:string, token_type:"bearer", expires_at:Timestamp, user:UserResponse.
- UserResponse: id, wallet_address, display_name?, is_merchant:boolean, created_at.
- UserUpdateRequest: display_name:string(1..80).
MVP hỗ trợ EOA; smart-contract wallet/ERC-1271 là ngoài phạm vi, báo unsupported thay vì giả vờ verify.

## 6. Profile và plan DTOs

- MerchantCreateRequest / MerchantUpdateRequest: business_name, description, location_text?; PATCH chỉ fields được gửi.
- MerchantResponse: id, owner_wallet, business_name, description, location_text?, created_at, updated_at.
- PlanDraftCreateRequest: title, description, price_per_period, total_periods, period_duration_seconds, grace_period_seconds.
- PlanDraftUpdateRequest: subset các field tạo, tối thiểu một field.
- PlanDraftResponse: toàn bộ draft công khai cho owner, gồm client_reference, total_price, state và onchain_plan_id?.
- PlanResponse: plan_id, chain_id, vault_address, merchant_address, merchant:MerchantResponse?, title, description, token:TokenConfig, price_per_period, total_periods, period_duration_seconds, grace_period_seconds, total_price, sync:SyncInfo.
Nếu plan được tạo ngoài app không có metadata, title fallback "Plan #<plan_id>"; không tự gán profile merchant khác.

## 7. Read DTOs

### TokenConfig / ConfigResponse
TokenConfig = address:Address, symbol:string, decimals:int.
ConfigResponse = environment:"local"|"demo", deployment_id:string, chain_id:int,
chain_name:string, rpc_url:public HTTPS URL, explorer_url:URL,
vault_address:Address, token:TokenConfig, abi_version:string,
yield_mode:"MOCK"|"DISABLED", check_in_ttl_seconds:900,
supported_wallet_kind:"EOA", auth_domain:string, auth_uri:string.
Chỉ public RPC, không trả secret provider URL/API key. Không có private key/JWT secret trong config.

### SyncInfo
block_number:UintString, block_hash:Hash32, block_timestamp:Timestamp,
synced_at:Timestamp, source:"LIVE"|"PROJECTION".
Mobile hiển thị thời điểm dữ liệu; lỗi RPC không được chuyển snapshot cũ thành dữ liệu LIVE.

### SubscriptionResponse
subscription_id, plan_id, chain_id, vault_address, merchant_address, subscriber_address,
token:TokenConfig, initial_principal, remaining_principal, principal_released, principal_refunded,
total_periods, completed_periods, next_period_index:UintString?,
started_at:Timestamp, next_release_at:Timestamp?, refund_available_at:Timestamp?,
nonce:UintString, status, yield_summary:YieldSummary, sync:SyncInfo.

### YieldSummary
mode:"MOCK"|"DISABLED", estimated_unclaimed:Amount?,
paid_merchant:Amount, paid_subscriber:Amount, paid_platform:Amount.
Không đặt estimated = guaranteed/claimable; token thiếu backing không có quyền payout.

### EligibilityResponse
subscription_id, status, can_check_in:bool, can_refund:bool,
next_period_index:UintString?, nonce:UintString, next_release_at:Timestamp?,
refund_available_at:Timestamp?, reasons:array<string>, sync:SyncInfo.
Reasons: TOO_EARLY, REFUND_WINDOW_OPEN, TERMINAL_STATE, READY.
Đây là eligibility theo dữ liệu block; không phải ủy quyền gửi thay subscriber/merchant.

### EventResponse / TransactionResponse / Page
EventResponse: id, event_name, plan_id, subscription_id?, tx_hash, log_index:int,
block_number, block_timestamp, payload:decoded event object, explorer_url:string.
TransactionResponse: tx_hash, chain_id, expected_action, status, block_number?,
failure_code?, checked_at?, explorer_url, event_ids:UUID[].
Page<T>: items:T[], next_cursor:string?. Không mặc định cần total_count.

## 8. Transaction submission DTO

TransactionSubmitRequest:
- tx_hash:Hash32; action:enum TransactionRecord.expected_action.
- plan_draft_id:UUID? (bắt buộc cho CREATE_PLAN).
- plan_id:UintString? (bắt buộc cho SUBSCRIBE).
- subscription_id:UintString? (bắt buộc cho CHECK_IN/REFUND).
Backend dùng chain/deployment từ session/config, không nhận contract address tùy ý.
Client không gửi status, amount, block_number, event payload hoặc owner để ghi thẳng DB.
RPC receipt chưa sẵn sàng trả SUBMITTED; tx receipt có status 0 trả REVERTED; receipt thành công nhưng không khớp action/event phải trả lỗi TX_MISMATCH, không đánh dấu CONFIRMED.

## 9. QR và EIP-712

Hai QR khác nhau:
- Registration QR: URI https://<configured-app-host>/subscribe?chain_id=43113&plan_id=<id>&vault=<address>. Host được nhóm cấu hình khi deploy; không phải URL đã tồn tại. Flutter xử lý deep link hoặc có màn hình scan mở trong app; fallback nhập plan ID.
- Check-in QR: JSON envelope bên dưới; có chữ ký cho một kỳ, không chứa seed/private key.

Envelope: version:1, kind:"PREPAIDGUARD_CHECK_IN", chainId:int, verifyingContract:Address,
message:CheckInMessage, signature:hex bytes. Max payload 4096 UTF-8 bytes.
Không tự mở URL tùy ý khi scan, không dùng hostname/RPC trong QR làm cấu hình.

EIP-712 domain: name="PrepaidGuard", version="1", chainId=43113, verifyingContract=Vault.
PrimaryType = CheckIn.
Thứ tự fields chính xác:
1. subscriptionId:uint256
2. merchant:address
3. periodIndex:uint256
4. nonce:uint256
5. deadline:uint256

JSON uint256 đều serialize decimal string. deadline = Unix seconds hiện tại + tối đa 900 giây; contract cần kiểm tra deadline >= now và deadline <= now + 900, ngoài điều kiện kỳ/nonce.
Signer phải là subscriber hiện tại; msg.sender phải là plan.merchant.
Domain và schema JSON phải được generate/đối chiếu chung giữa Dart, Solidity và backend.

Ví dụ payload (giá trị placeholder, KHÔNG phải fixture ký hợp lệ):

```json
{
  "version": 1,
  "kind": "PREPAIDGUARD_CHECK_IN",
  "chainId": 43113,
  "verifyingContract": "<deployed-vault-address>",
  "message": {
    "subscriptionId": "1",
    "merchant": "<merchant-wallet-address>",
    "periodIndex": "1",
    "nonce": "0",
    "deadline": "<unix-seconds>"
  },
  "signature": "<wallet-signature>"
}
```

Không lưu signature QR vào DB hoặc application logs. Sau release/refund nonce tăng; QR đã dùng không dùng lại được. Tạo QR mới không tự thu hồi QR cũ chưa dùng; chỉ một giao dịch có thể tiêu thụ nonce.

## 10. ErrorResponse

```json
{
  "error": {
    "code": "FORBIDDEN",
    "message": "Bạn không có quyền truy cập tài nguyên này.",
    "details": {},
    "request_id": "<server-request-id>"
  }
}
```

details chỉ dữ liệu validation an toàn; không stack trace, RPC credentials hay chữ ký. Validation error của FastAPI cần chuẩn hóa vào cùng envelope; OpenAPI khai báo mọi schema. Danh sách mã và HTTP mapping ở [api.md](api.md).
