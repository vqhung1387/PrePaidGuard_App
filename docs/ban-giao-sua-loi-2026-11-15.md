# Bàn giao theo từng role — PrePaidGuard

Nhánh bàn giao: **fix/tich-hop-va-phuc-hoi**. Bản code đã kiểm: **a80c8ae**; các cập nhật phân công sau đó chỉ sửa tài liệu. Nhánh đã tích hợp frontend 78d2295 và Solidity 16e0d3f trên nền a9096b2. Tại thời điểm bàn giao, chưa merge main, chưa nghiệm thu Fuji/HTTPS.

**Cách nhận việc:** A phụ trách UI/Flutter; B phụ trách BE/FastAPI; C phụ trách Solidity. Tên thật do nhóm điền. Mỗi mã việc bên dưới chỉ thuộc một role. “Nhận đầu vào” không có nghĩa cùng nhận trách nhiệm triển khai. Các quyết định phạm vi chưa chốt nằm ở mục 4.

## 1. Role UI/Flutter — A

### Phần UI đã có, cần tiếp nhận bảo trì

- Giao diện catalog, so sánh/tìm kiếm, hội viên, merchant và training demo.
- Workspace dùng ví EIP-1193; gọi API, ký SIWE/EIP-712, gửi transaction, hiển thị QR và dán payload.
- Hiển thị tiền gốc, giải ngân, refund, eligibility, yield và lịch sử từ API trên tài khoản thật.
- Catalog tải 20 gói/cursor; chart đã sửa màn hình nhỏ/chữ lớn.
- UI đối chiếu hash cancel/speed-up, nhập raw gốc khi thiếu nonce; giữ hash khi hết phiên/cache lỗi.
- Build có API_BASE_URL mở thẳng workspace thật; tài khoản demo có nút chuyển sang ví thật.

**Phạm vi file:** apps/flutter_app và workflow frontend. Controller, Dart DTO, kết nối ví và việc hiển thị phản hồi API trong Flutter thuộc role này.

### Việc UI làm tiếp

| ID | UI phải thực hiện | Đầu vào cần có | Đầu ra và tiêu chí hoàn thành |
| --- | --- | --- | --- |
| UI-01 | Build và host bản Flutter Web dùng dữ liệu thật | URL API HTTPS; origin web đã chọn; manifest Fuji | Một URL app; cấu hình API, pin chain/Vault/deployment đúng; kết nối ví và tải được gói. UI bàn giao origin chính xác để cấu hình CORS |
| UI-02 | Nghiệm thu kết nối và ký bằng Core/MetaMask thật | Ví/thiết bị đã chọn; token/gas testnet; URL app | Test login/logout, từ chối ký, sai mạng, đổi ví, hết phiên và reload. Không dùng khóa riêng trong app |
| UI-03 | Nghiệm thu UX pending/cancel/speed-up | API replacement/original-proof đã có; giao dịch testnet | Người dùng đối chiếu hash đã xác nhận, thấy rõ trạng thái và không gửi lặp. Mất cả nonce/raw thì hiển thị lý do, không tự xóa cache để mở guard |
| UI-04 | Nghiệm thu QR trên hai thiết bị | Luật/domain EIP-712 và môi trường thật | Subscriber ký, merchant nhận QR, gửi release; replay/QR hết hạn/sai merchant bị từ chối. Đây là buổi test do UI tổ chức, không phải tự đổi contract |
| UI-05 | Thêm tải tiếp subscriptions/drafts/events | API cursor hiện có | Xem được mục 101, giữ filter, không trùng/mất mục khi tải tiếp. Catalog đã có phân trang; ba danh sách này còn giới hạn 100 trên UI |
| UI-06 | Camera hoặc native wallet nếu nhóm đưa vào scope | Quyết định Web/native và camera ở mục 4 | Camera/deep-link chạy trên thiết bị được chọn. Nếu nhóm chọn Web+dán payload thì đánh dấu ngoài scope, không ghi là đã triển khai |
| UI-07 | Chốt và thể hiện phần demo ngoài core | Quyết định về training/booking/giờ đông | Giữ nhãn mô phỏng cho dữ liệu RAM. Nếu muốn dữ liệu thật, UI bàn giao màn hình, field, thao tác và nguồn dữ liệu cần dùng trước khi yêu cầu API mới |
| UI-08 | Hoàn thiện nhãn yield và lịch sử cho người dùng | DTO API hiện có và mode do contract cung cấp | Phân biệt MOCK/DISABLED, estimated/paid; không gọi token được cấp thử là lãi DeFi thật; không tự thay tỷ lệ hay điều kiện payout |
| UI-09 | Duy trì kiểm thử Flutter và locator khi đổi UI | Bộ unit/widget test và browser script đang có | Analyze/test/build qua đúng Flutter 3.47.9/lockfile; bàn giao tên/key/accessible label mới cho script nghiệm thu khi đổi nút hoặc ô nhập |

**UI không tự nhận:** sửa migration/auth/receipt verification của BE; sửa Vault/chính sách tiền; deploy contract; chọn nguồn yield mới.

## 2. Role BE/FastAPI — B

### Phần BE đã hoàn thành trong code

- Auth SIWE/JWT, phân quyền metadata, PostgreSQL và migration tới 0003.
- Tracking transaction, sender nonce, receipt/confirmation policy, replacement, reorg và projection/event sync.
- Phục hồi legacy bằng raw transaction đã ký: kiểm hash/signer/chain; không lưu DB/cache hoặc broadcast raw.
- Endpoint original-proof cho APPROVE; replacement nhận bằng chứng optional cho transaction Vault.
- Catalog đọc tối đa 4 plan đồng thời tại cùng block, giữ thứ tự và lỗi; không cache số dư hoặc trả một phần khi RPC lỗi.
- API cung cấp principal/release/refund/eligibility/yield/events; /ready và blueprint Render đã có.
- Test PostgreSQL/EVM, runner browser tự dựng môi trường, workflow tích hợp và bản mô tả OpenAPI.

**Phạm vi file:** backend, render.yaml, scripts/validation, scripts/browser_acceptance và workflow backend/browser/integration. OpenAPI và tài liệu REST thuộc BE.

### Việc BE làm tiếp

| ID | BE phải thực hiện | Đầu vào cần có | Đầu ra và tiêu chí hoàn thành |
| --- | --- | --- | --- |
| BE-01 | Host DB/API HTTPS | Nơi host/ngân sách đã chốt; manifest/ABI Fuji; origin web | URL API, cấu hình RPC/DB/AUTH/CORS; backup rồi migrate head 0003, /ready đạt. Không reset DB để migrate |
| BE-02 | Kiểm chứng API trên deployment thật | BE-01 và Vault Fuji đã có | SIWE/domain, quyền truy cập, publish metadata, tracking, scanner/reorg và error envelope chạy trên URL thật. Thu bằng chứng bằng request ID/hash, không log seed/raw/JWT |
| BE-03 | Đo hiệu năng Vault Fuji thật | Manifest, RPC và dữ liệu plan/receipt đã triển khai | Báo cáo getPlan/logs/receipt, latency/error/rate limit; chỉnh giới hạn khi có số đo. Đo transport công khai đã làm không thay thế benchmark Vault |
| BE-04 | Hỗ trợ case pending legacy có vấn đề dữ liệu | Hash gốc, trạng thái tracking; raw đã ký nếu còn | Xác minh bằng endpoint/test đã có. Nếu mất cả raw lẫn nonce và không truy được nguồn gốc thì ghi rõ không đủ chứng cứ; không sửa status bằng tay để cho gửi lại |
| BE-05 | Duy trì CI và browser nghiệm thu | Locator UI do UI cung cấp; ABI/fixture do Solidity cung cấp | Chạy trên commit cuối, lưu báo cáo và chỉ rõ local/Fuji. Khi test lỗi, truy vết về role gây lỗi; việc điều phối không có nghĩa BE viết lại màn hình hoặc contract |
| BE-06 | Kiểm tra phân trang và DTO khi UI nghiệm thu | Case UI-05 phát hiện và dữ liệu trên 100 mục | API cursor trả đúng thứ tự/quyền/filter. Sửa API nếu có lỗi; nút tải tiếp và state Flutter vẫn thuộc UI |
| BE-07 | Thiết kế API cho tính năng ngoài core nếu được chọn | Scope được nhóm chốt; đặc tả UI-07 và nguồn dữ liệu thật | DTO, lưu trữ/quyền/validation, test và tài liệu cho đúng tính năng đã nhận. Chưa có scope thì không tự mở backend cho mọi trang demo |
| BE-08 | Cập nhật tài liệu kỹ thuật backend | Kết quả deploy/test mới | URL công khai, migration, error/DTO, cách chạy và bằng chứng đúng commit. Không ghi đã nghiệm thu extension/thiết bị nếu mới chạy provider test |

**BE không tự nhận:** thiết kế/viết tất cả UI, camera/native, xuất ABI, deploy contract hoặc đổi luật tài chính. Phần Flutter từng sửa để tích hợp đã được ghi trong mục UI, không tạo trách nhiệm UI lâu dài cho BE.

### Dữ liệu BE bàn giao cho UI

- API_BASE_URL và /openapi.json đúng phiên bản.
- AUTH_DOMAIN/AUTH_URI công khai; chain/Vault/token/deployment/confirmations từ /config.
- Mẫu request/response/error cho auth, plan, subscription, eligibility, transaction/replacement và events.
- Cách dùng cursor; trạng thái pending/confirmed/reverted/replaced/cancelled.
- Giới hạn đã biết và bằng chứng test. Không gửi DB password, JWT secret hoặc thông tin ví deploy vào app/Git.

## 3. Role Solidity — C

### Phần Solidity đã có, cần tiếp nhận bảo trì

- Vault/token/adapter, immutable plan, subscribe, check-in theo chữ ký và refund.
- Giới hạn lịch/timestamp, xử lý kỳ cuối, nonce/domain, reentrancy và accounting.
- Yield MOCK được cấp token theo vị thế; chế độ DISABLED; tỷ lệ payout theo baseline hiện có.
- ABI export, signing vector/schema EIP-712, script deploy/seed và bộ contract/fuzz test.

**Phạm vi file:** contracts, shared/abi, shared/deployments, shared/check-in.* và workflow solidity. C xuất file chuẩn; các role khác đọc, tránh sửa tay các bản ABI riêng.

### Việc Solidity làm tiếp

| ID | Solidity phải thực hiện | Đầu vào cần có | Đầu ra và tiêu chí hoàn thành |
| --- | --- | --- | --- |
| SOL-01 | Chuẩn bị deployment Fuji | Quyết định ví deploy/treasury/token/yield; gas testnet | Ví đúng chain 43113 có đủ gas. Lần kiểm gần nhất ví deploy 0x9B14012e9a4dccE26b4581086bC44Dc1BF5bE1f4 có 0 AVAX Fuji; người giữ ví thực hiện cấp gas/ký nếu cần |
| SOL-02 | Deploy và verify contract | SOL-01 và source đã freeze/review | Token/Vault/adapter theo mode đã chọn; receipt thành công, địa chỉ/code đúng source. Không lấy test local làm bằng chứng đã deploy |
| SOL-03 | Xuất bundle triển khai | SOL-02 | ABI, manifest, chain ID, deployment_id, addresses, block/hash, confirmations, mode và signing vector đúng phiên bản; giao cùng một bundle cho BE/UI |
| SOL-04 | Đối chiếu luật tiền và số dư trên Fuji | Giao dịch demo thật và baseline nhóm đã chốt | Kiểm principal/yield, release/refund boundary, replay, terminal state; cung cấp hash/receipt cho các kết quả. Không thay chính sách một mình |
| SOL-05 | Quản lý yield/funding và phạm vi DeFi | Quyết định giữ MOCK/DISABLED hay làm yield thật | Với MOCK: funding đủ token testnet, hạch toán đúng, mô tả rõ nguồn token. Yield DeFi thật chỉ triển khai khi nhóm chốt scope và yêu cầu cuộc thi |
| SOL-06 | Duy trì contract test, export và hướng dẫn | Thay đổi source/ABI hoặc yêu cầu chính sách đã được chốt | Mocha/fuzz/export drift qua, ABI/manifest đồng bộ, ghi tác động nếu cần deploy lại Vault. Không đổi deployment_id lặng lẽ dưới frontend cũ |

**Solidity không tự nhận:** host FastAPI/DB/HTTPS, state Flutter, camera hoặc thiết kế REST. Vai trò này bàn giao contract/bundle/receipt để các role còn lại làm phần của mình.

### Bundle Solidity phải bàn giao

- Chain/network và các địa chỉ công khai: Vault, token, adapter nếu có, treasury.
- Deployment transaction hash, block, code hash và source/commit tương ứng.
- ABI và schema/domain EIP-712 đúng contract; token decimals, status codes và confirmations.
- Mode MOCK/DISABLED và cách cấp token/yield thử nghiệm.
- Không đưa seed/private key, file khóa đã giải mã hay mật khẩu ví vào repo.

## 4. Các điểm cần nhóm thống nhất trước khi chia thêm việc

Đây là **quyết định chung**, không phải một task triển khai gán đồng thời cho nhiều role. Chưa có xác nhận thì giữ hành vi hiện tại, không tự đổi contract/interface hoặc mở scope.

| Điểm cần chốt | Điều cần trả lời rõ | Người chuẩn bị thông tin | Sau khi chốt, ai làm phần nào |
| --- | --- | --- | --- |
| Nền tảng | Web là bản chính hay phải có Android/native? | UI | UI làm nền tảng đã chọn; BE giữ API; Solidity giữ contract |
| Cách nhận QR | Camera bắt buộc trong MVP hay chấp nhận dán payload? | UI | UI thực hiện; BE/Solidity không nhận việc camera |
| Chính sách tiền | Giữ baseline B1–B6, lịch release/refund hiện tại hay đổi? | Solidity | Solidity sửa contract nếu được giao; BE đổi validation/read model tương ứng; UI đổi điều khoản/UX tương ứng thành các task riêng |
| Yield | MOCK/DISABLED đủ hay thể lệ buộc DeFi thật? | Solidity kiểm yêu cầu và khả thi | Solidity làm nguồn yield/adapter; BE ánh xạ dữ liệu; UI hiển thị. Chưa chốt thì không tự thêm BENQI |
| Scope sản phẩm | Training/booking/giờ đông tiếp tục demo hay làm thật? Nguồn số liệu là gì? | UI mô tả màn hình và thao tác | UI chốt đặc tả; chỉ sau đó BE nhận API cụ thể. Không mặc định mọi màn hình cần backend mới |
| Ví và gas | Ai giữ deployer/treasury, ai cấp AVAX Fuji và tài khoản demo nào? | Solidity | Solidity chuẩn bị deploy; người giữ ví làm thao tác cá nhân cần ký/mở khóa. Không chia sẻ khóa |
| Hosting | Nơi host, URL web/API, DB, ngân sách tối đa và người giữ cấu hình? | BE chuẩn bị API/DB; UI chuẩn bị web | BE host API/DB; UI host app; Solidity không nhận host API |
| Git và merge | Nhánh chuẩn, người merge, review và mốc freeze? | BE chuẩn bị diff/CI | Mỗi role có nhánh riêng; một người được nhóm chỉ định merge, không tự force-push nhánh người khác |
| Buổi nghiệm thu | Core hay MetaMask, thiết bị nào, ai đóng vai khách/cơ sở? | UI | UI tổ chức thao tác; BE cung cấp log/API; Solidity cung cấp đối chiếu receipt. Mỗi role ghi kết quả riêng |
| Nộp bài | Deadline thật, format, ai chịu trách nhiệm xác nhận nộp? | Nhóm chọn một người điều phối | UI giao bản demo/video; BE giao URL/API/bằng chứng; Solidity giao địa chỉ/receipt; người điều phối kiểm hồ sơ và xác nhận nộp |

Mẫu chốt: “Chọn …; scope …; UI nhận …; BE nhận …; Solidity nhận …; người merge/nộp …; mốc hoàn thành …”. Không tự điền tên người, ngân sách hoặc hạn thay nhóm.

## 5. Thứ tự bàn giao đầu vào

1. Nhóm chốt nền tảng, scope, luật tiền/yield, ví và hosting.
2. Solidity hoàn thành SOL-01→SOL-03, giao bundle cho BE và UI.
3. BE thực hiện BE-01→BE-02, giao URL/OpenAPI; UI giao origin web chính xác để BE cấu hình CORS.
4. UI hoàn thành UI-01→UI-04 trên môi trường thật.
5. BE chạy BE-05; lỗi thuộc UI/API/contract được giao lại đúng role để sửa, không biến thành task “tích hợp” không có chủ.
6. Người nhóm chỉ định thực hiện merge/freeze/nộp bài sau bằng chứng và review.

Các task không phụ thuộc deployment vẫn làm trước được: UI phân trang/UX, BE test/DTO, Solidity contract tests/bundle. Không bắt mọi việc phải đợi nhau.

## 6. Bằng chứng hiện có và điều kiện nhận nhánh

- Code a80c8ae đã có 5 nhóm CI xanh: backend, frontend, Solidity, API–contract integration và browser.
- Local: 55 test BE không cần EVM; 6 ca live EVM; 103 test Flutter; browser 13 bước. Bộ contract có 18 Mocha và 2 bài fuzz ×256 input.
- Catalog giả lập 100 gói, RPC trễ 200 ms/lượt: 20,42→5,44 giây sau sửa. Đây không phải benchmark Vault Fuji.
- Đo 8 lượt eth_getBalance trên Fuji: tuần tự 0,875 giây, 4 luồng 1,250 giây; không chứng minh song song luôn nhanh hơn. BE còn cần đo Vault đã deploy.
- Local Flutter 3.41.9 khác pin CI 3.47.9; lockfile commit giữ pin gốc. CI đúng commit mới là bằng chứng cấu hình pin.
- **BE backup DB rồi chạy alembic upgrade head tới 0003 trước frontend mới. Không reset/xóa DB.**
- Pending mất cả nonce lẫn raw gốc không thể tự chứng minh. UI giữ guard; BE trả lỗi rõ; người giữ ví tìm dữ liệu nguồn. Không “sửa cho hết pending” bằng cách xóa cache/status tùy ý.
- Người dùng đã chọn làm BE trước. Tại lần kiểm gần nhất, ví deploy chưa có gas Fuji; chưa deploy/kiểm HTTPS hoặc ví extension/hai thiết bị thật. Không dùng tiền mainnet để thay thế.
- Chưa có nguồn dữ liệu thật cho training/booking/giờ đông; chưa có camera/native, DeFi yield thật hoặc xác nhận hoàn tất bài nộp.

### BE chạy lại browser giống CI

Sau khi có compiled contracts và Web build CHAIN_ID=31337, API_BASE_URL=http://127.0.0.1:18010:

    $env:TEST_DATABASE_URL='postgresql+psycopg://postgres@127.0.0.1:55427/prepaidguard_test'
    cd backend
    uv run --locked --with playwright==1.65.2 python ../scripts/browser_acceptance/local.py --browser 'C:/Program Files/Google/Chrome/Application/chrome.exe'

Runner cần cổng 18545/18010/18090 trống; tự mở/dừng EVM/API/web và tạo/xóa schema UUID riêng. Không dùng DB production/node người khác. Bỏ --browser thì cài Playwright Chromium như workflow browser.yml. Báo cáo ở validation-results/browser/browser.

**Ranh giới cuối cùng:** tài liệu này giao rõ từng role. Các thay đổi BE và Flutter từng làm trong đợt sửa được ghi nhận theo phần code của chúng; chúng không tự chuyển trách nhiệm bảo trì UI hoặc deploy contract sang BE.
