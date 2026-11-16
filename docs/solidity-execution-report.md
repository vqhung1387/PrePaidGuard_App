# Báo cáo thực hiện Solidity — 15/11/2026

Nhánh `codex/solidity-fuji-handoff`, nền `b341fa2`. Cấu hình Fuji người dùng chọn: **DISABLED**. Bản thay đổi được đóng gói để review trên nhánh này và bàn giao bằng PR vào fix/tich-hop-va-phuc-hoi. Chưa deploy Fuji. Các evidence local được tạo trên working tree trước khi commit; chúng không phải evidence của source commit nền b341fa2 hoặc của một deployment Fuji.

## Kết quả chính

Đã bổ sung công cụ preflight/verifier chỉ đọc, journal từng transaction cho deploy/seed/yield và các kiểm tra trước broadcast. Không đổi source contract nghiệp vụ, ABI, typed data hoặc chính sách tiền. Suite cuối: **34 passing (32 Mocha + 2 Solidity fuzz, 256 mẫu mỗi fuzz)**; typecheck/build/export drift PASS. Rehearsal actual scripts trên local31337 PASS cho MOCK và DISABLED, node test được đóng.

Fuji chỉ thực hiện kiểm tra read-only: RPC xác nhận chain43113, balance của địa chỉ deploy được bàn giao `0x9B14012e9a4dccE26b4581086bC44Dc1BF5bE1f4` là **0 wei** tại lần kiểm trong evidence. Tiến trình không có DEPLOYER_PRIVATE_KEY hoặc các địa chỉ role được cấu hình; chưa xác nhận người dùng kiểm soát ví này. Không gửi transaction hoặc tạo ví mới.

## Phân công agent và các phase

| Vai trò | Model | Việc thực hiện |
| --- | --- | --- |
| Coding | GPT-6.1 Terra high | Tooling/checkpoint/verifier và sửa findings |
| Testing | GPT-6.1 Sol high | 14 test công cụ, tăng invariant, rehearsal local |
| Review | GPT-6 Astra high | Receipt/chain/source match, retry, timeout và ngân sách |
| Điều phối | Agent chính | Baseline/final suite, tương thích DTO, tổng hợp và giới hạn |

| Phase | Kết quả |
| --- | --- |
| 0 — baseline | PASS: 20 test cũ, typecheck/build/export drift |
| 1–2 — tooling | Đã triển khai và review; verifier tách operational/artifact checks với source/explorer verification chưa hoàn tất |
| 3 — test/sửa/review | PASS: 34 test cuối, các findings quan trọng đã sửa |
| 4 — rehearsal | PASS: actual scripts MOCK và DISABLED; 4 ca lỗi actual deploy sau token/adapter/Vault/bind đều PASS |
| 5 — freeze/Fuji input | Chưa hoàn tất: có mode DISABLED, thiếu ví ký/gas/role/budget và commit freeze |
| 6–7 — deploy/nghiệm thu Fuji | NOT_RUN; chưa có đủ đầu vào, receipt Fuji, source verification và môi trường ví thật |
| 8 — tổng hợp | Báo cáo hiện tại đã tạo; bàn giao deployment Fuji cuối cùng còn chờ |

## Thay đổi

- `contracts/scripts/lib/deployment.ts`: validation chain/identity/mode, uint256; receipt canonical và confirmations; liên kết token/Vault/adapter; ABI/build-info checksum, exact creation calldata/constructor và runtime ngoài immutable spans; EIP-712 domain. Journal intent → broadcast → confirmed/reverted/unknown, timeout mặc định120giây và chặn cùng attempt chạy lại.
- `preflight.ts`, `verify-deployment.ts`: chỉ đọc với địa chỉ công khai, không yêu cầu signer; output không chứa secret.
- `deploy.ts`: provenance/build evidence, receipt từng token/adapter/Vault/bind; không ghi đè manifest đã có; source/config dirty chặn deploy Fuji; lưu manifest sau kiểm tra.
- `seed-demo.ts`: kiểm nguồn funding/liên kết/role/budget trước gửi; top-up theo số dư; evidence không ghi đè, lần có chủ đích dùng path mới.
- `fund-yield.ts`: kiểm uint256, mode, subscription Active/principal và linkage trước mint/approve; journal giữ dấu bước dở dang. Funding vẫn là thao tác cộng dồn, không retry tự động khi chưa rõ kết quả.
- `hardhat.config.ts`: RPC_URL override cho local node riêng. package.json thêm lệnh preflight/verifier.
- `.env.example`: chọn DISABLED theo người dùng; bổ sung public input/budget/attempt/timeout mẫu, không chứa key.
- `Conservation.t.sol`: tăng assertion Active/Completed principal equality, nonce theo settlement và tổng allocatedYield bằng totalYield.
- `deployment-tools.ts`, `rehearsal.ts`: test công cụ và actual-script local lifecycle. README, [kế hoạch](solidity-execution-plan.md) và [runbook](solidity-operations.md) ghi cách dùng và giới hạn.

## Các findings đã xử lý trong vòng review

1. Kiểm Git dirty ban đầu dùng đường dẫn tương đối sai cwd → dùng git -C repoRoot.
2. Manifest local ghi cứng8545 → public_rpc_url theo origin của RPC local đang dùng, không đưa credentials/query vào manifest.
3. Fingerprint đơn thuần không chứng minh artifact → thêm creation calldata/args, runtime immutable-aware, ABI/build-info và domain/getter checks.
4. Bind receipt có thể chỉ là giao dịch thành công bất kỳ → kiểm sender/target/calldata bindVault đúng.
5. Chờ receipt không có timeout → bounded TX_TIMEOUT_MS và journal unknown giữ hash.
6. Seed evidence mặc định làm mất khả năng top-up có chủ đích lần sau → SEED_EVIDENCE_PATH riêng; giữ evidence cũ, không overwrite.
7. Funding ID/amount/position sai có thể mint/approve trước khi lỗi → preflight Active/backed position và uint256 trước giao dịch đầu.
8. Deployment/write thiếu chain dự kiến và gate balance khai báo → kiểm EXPECTED_CHAIN_ID khi đặt và yêu cầu gas budget khi write Fuji.

## Bằng chứng kiểm thử

Evidence được lưu dưới `validation-results/solidity-handoff` (gitignored):

- baseline/typecheck.txt, build.txt, tests.txt, export.txt.
- final/typecheck.txt, build.txt, tests.txt, export.txt.
- backend-manifest-compatibility.json: cả MOCK/DISABLED parse được bằng DTO Deployment backend hiện tại. Đây là kiểm tương thích DTO, không phải chạy API/DB integration.
- fuji-public-check.json: balance công khai và cấu hình còn thiếu.
- Rehearsal ban đầu: `C:\Windows\TEMP\prepaidguard-rehearsal-zJBIeA\report.json`; journal/manifest public theo từng mode, đã đóng node PID22248, cổng57855.

Rehearsal kiểm actual preflight/verify không có signer key; deploy/seed/fund scripts; seed lại khi đủ không gửi tx; invalid funding/manifest/deploy-existing/wrong chain bị chặn. Hai subscription cùng gói: một Completed, một release rồi refund phần còn lại, nonce/replay/terminal và accounting đúng. MOCK minted tổng500000122 raw units, DISABLED500000000; token bảo toàn. Yield MOCK tổng122 phân bổ merchant84/subscriber24/treasury14; DISABLED không có adapter và không có yield.

14 test công cụ còn kiểm actual transaction accepted/pending, receipt response loss, giữ earlier confirmed steps và từ chối replay cùng attempt; thử calldata/ABI/build info/runtime mismatch, canonical/confirmation và timeout. Các test fault dùng Attempt chung không tự đồng nghĩa đã tiêm lỗi actual deploy process sau mọi bước; bằng chứng mở rộng ghi riêng.

Lệnh cuối đã chạy bằng Node24.22.3, từ contracts:

```text
node node_modules/typescript/bin/tsc --noEmit
node node_modules/hardhat/dist/src/cli.js build
node node_modules/hardhat/dist/src/cli.js test
node node_modules/hardhat/dist/src/cli.js run scripts/export.ts
```

`git diff --check` pass sau sửa whitespace; không có ABI/schema/vector drift. Không chạy lại toàn bộ BE/FE/browser suite vì không thay code của các lớp đó hoặc contract runtime; rehearsal lần này không phải nghiệm thu extension wallet.

## Giới hạn và bước tiếp theo

- `LOCAL_ARTIFACT_MATCH` chứng minh tương ứng với artifact ở máy kiểm theo cơ chế nêu trong runbook. Chưa hoàn tất liên kết source Git commit/build hoặc explorer verify; `source_verification: NOT_VERIFIED` được giữ trung thực.
- GAS_BUDGET_WEI là ngưỡng balance khai báo, không tự estimate phí và không phải spending cap. Cần estimate/budget thực trước Fuji.
- Journal không tự resume và không bảo đảm tìm lại hash nếu mất response trước khi provider trả hash. Không xóa bằng chứng để chạy lại; đối chiếu với ví/node trước.
- Đã fault actual deploy process đủ bốn bước trong lượt mở rộng; giữ limitation còn lại là source commit/explorer verification và Fuji chưa chạy.
- Ví deploy nêu trong bàn giao chưa đủ điều kiện:0AVAX, quyền kiểm soát chưa xác nhận. Chưa có treasury/merchant/subscriber được chủ ví xác nhận; không chọn thay các ví không rõ quyền ký.
- Source/tooling được đưa vào commit để review; việc chọn release commit và freeze deployment Fuji còn cần hoàn tất. Fuji deployment, source verification, HTTPS API/web, ví extension và hai thiết bị chưa nghiệm thu. Không ghi toàn bộ SOL-01–06 DONE từ kết quả local.

Có thể chốt bộ địa chỉ và ngân sách sau khi người giữ ví mở ví do mình kiểm soát. Với DISABLED, treasury chưa nhận yield nhưng vẫn là địa chỉ constructor cần được xác nhận. Không yêu cầu gửi seed/private key qua chat. Khi đủ đầu vào, tiếp Phase5–7 theo kế hoạch; source/bundle mới được bàn giao đồng thời cho BE/FE.

## Nghiệm thu mở rộng cuối cùng

Evidence cuối: `validation-results/solidity-handoff/rehearsal/report.json`; bản gốc temp `C:\Windows\TEMP\prepaidguard-rehearsal-38Mu70`. Đã copy evidence công khai vào thư mục gitignored để không phụ thuộc việc giữ temp.

Bốn ca actual deploy qua loopback proxy cố tình mất hash response sau khi node chấp nhận transaction: token/adapter/Vault/bind đều PASS. Nonce tăng đúng1/2/3/4, proxy ghi nhận0 retry; manifest cuối không được xuất; journal giữ các bước trước confirmed và bước hiện tại unknown không hash. Chạy lại cùng attempt không phát sinh giao dịch. Hash bị proxy giữ được lưu riêng trong fault.json để đối chiếu, không giả rằng client đã nhận hash đó.

Sau các ca lỗi, actual-script lifecycle MOCK và DISABLED đều PASS; node PID29172/cổng51139 được đóng. Manifest cuối hai mode vẫn parse được bởi DTO backend. Đây là bằng chứng local cho cơ chế dừng/đối chiếu, không phải cơ chế tự khôi phục mọi loại provider outage.
