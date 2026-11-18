# Bàn giao Antigravity — kiểm thử sử dụng toàn app

Ngày bàn giao: **18/11/2026**, giờ Việt Nam. Mục tiêu là tìm lỗi khi người dùng thao tác thực tế trên PrePaidGuard, gồm UI, ví, API và giao dịch; không chỉ đọc code hoặc chạy test backend.

## 1. Prompt khởi động — có thể gửi nguyên đoạn này

> Hãy đọc toàn bộ tài liệu này và kiểm thử PrePaidGuard như người dùng thật. Bắt đầu từ URL web đang chạy, thử đầy đủ vai trò hội viên và cơ sở, kết nối ví, tạo gói, đăng ký, QR/check-in, giải ngân, hoàn tiền, reload và phục hồi pending. Kiểm cả các màn demo, điều hướng, form, mobile, thông báo lỗi và độ dễ hiểu. Với mỗi bug, lưu các bước tái hiện, kết quả mong đợi/thực tế và bằng chứng; sau đó mới đọc code/API/receipt để xác định nguyên nhân. Không thay việc kiểm thử UI bằng việc gọi API thành công. Không nhận PASS cho Core/MetaMask hoặc hai thiết bị thật từ injected provider, DevTools mobile viewport hay unit tests. Báo rõ PASS/FAIL/BLOCKED/NOT_RUN và giao một đầu mối cho mỗi bug. Nhiệm vụ hiện tại là kiểm thử và bàn giao bug; nếu được giao sửa tiếp thì dùng nhánh QA riêng, sửa nguyên nhân và retest cùng hành trình.

Repo: https://github.com/vqhung1387/PrePaidGuard_App

Nhánh đầu vào: **`fix/be-nghiem-thu-1116`**, baseline trước tài liệu này là **`023ab2d`**. Fetch origin trước khi bắt đầu; nếu nguồn đã thay đổi thì ghi SHA mới trong báo cáo. Kiểm tra working tree trước khi đổi nhánh; dùng worktree/nhánh QA riêng nếu có sửa dở, không reset hoặc ghi đè công việc của nhóm. Không tự merge main, force-push hoặc deploy lại chỉ để chạy QA.

Worktree local dùng để bàn giao: `C:\Users\nguye\Documents\Codex\2026-11-07\https-www-facebook-com-share-p\work\prepaid-be-1116`. Nếu Antigravity mở repo ở thư mục khác, đối chiếu branch/SHA trước khi kiểm code hoặc chạy build; không suy rằng mọi checkout đều chứa bản BE đã sửa.

## 2. Môi trường và phiên bản thực sự cần kiểm

| Mục | Giá trị / cách đối chiếu |
| --- | --- |
| Web đang host | https://prepaidguard-web.onrender.com |
| API origin | https://prepaidguard-api.onrender.com — không thêm `/api/v1` vào ô API URL |
| OpenAPI | https://prepaidguard-api.onrender.com/docs |
| Readiness | https://prepaidguard-api.onrender.com/ready |
| Config | https://prepaidguard-api.onrender.com/api/v1/config |
| Web source / deploy | `ccd4f38e9ee6fb8b29fa4eb2dd555c0b6ece928e` / `dep-dbtcnqrncjis739slgbg` |
| API source / deploy | `5f2528ab528f85242629356397c9011fa56cb160` / `dep-dbtdng3bc2fs73ds8log` |
| Chain | Avalanche **Fuji C-Chain**, `43113`; không dùng mainnet |
| Vault | `0xc2b19Df4e38CE6FA921120f2B16C8c3a9c6a2364` |
| Token | `0x2267Ff59D31b98E9771AF5d80E3d554d7f5eD998`, **mUSDC, 6 decimals**, token thử nghiệm |
| Deployment ID | `43113-0xc2b19df4e38ce6fa921120f2b16c8c3a9c6a2364` |
| Yield | **DISABLED**; không có lợi tức DeFi thật ở deployment này |
| Signing | SIWE domain `prepaidguard-web.onrender.com`, URI `https://prepaidguard-web.onrender.com`; EIP-712 domain/fields trong `shared/check-in.types.json` |
| Manifest / ABI | `shared/deployments/fuji.json`, `shared/abi/PrepaidVault.json`, `shared/abi/MockUSDC.json` |

GitHub, source web và source API có thể khác SHA. Hai source đang host ở trên đã được đối chiếu bằng Render ngày 18/11; chúng không có nghĩa main hoặc frontend là bản đã deploy. Trước mỗi lượt QA, kiểm lại URL/source/config và ghi đúng bản đang nhìn thấy. Không sửa địa chỉ hoặc enum theo fixture FakeRpc local để khớp Fuji.

**Quan sát mới cần ưu tiên, chưa xác định nguyên nhân:** lúc chuẩn bị bàn giao ngày 18/11, lần gọi `/api/v1/config` đầu timeout sau 45 giây; ngay sau đó `/ready` trả 200 (request ID `efb5cc4c-8244-42a7-b0fc-89e7bcc32cc5`). Lần thử `/api/v1/config` tiếp theo nhận trang Render **502 Bad Gateway**, request ID `a5c3779e292e7dca-SIN`; một lần `/health` sau đó cũng trả 502 HTML. Đây là quan sát từ HTTP client, chưa phải tái hiện bằng UI và chưa kết luận cold start, RPC hay lỗi ứng dụng. Render ghi deploy Live không chứng minh app hiện khả dụng. Ưu tiên kiểm A01/A02 trước; không nhận toàn môi trường đang xanh từ kết quả ngày 16/11.

## 3. Phần có bằng chứng cũ và phần vẫn cần làm

| Phạm vi | Bằng chứng đã có ngày 16/11 | Cần Antigravity kiểm tiếp |
| --- | --- | --- |
| BE / runner | 98 test BE và 11 test runner đạt, CI xanh; [bốn lỗi đã sửa](be-audit-2026-11-16.md) | Hành vi qua UI, lỗi tích hợp và khả dụng hiện tại |
| Fuji money flow | Publish/subscribe/release/refund/replay/scanner qua API và ví demo ký thật đạt | Đi hết hành trình bằng extension và thao tác UI |
| Hosted web | 24 kiểm tra HTTPS/browser đạt với provider test EIP-1193 | Core/MetaMask thật, pop-up ký, người dùng từ chối, hai thiết bị |
| Health check | Render dùng `/ready`, Blueprint API autoSync OFF; [bằng chứng](evidence/render-health-2026-11-16.json) | Startup, timeout/502 mới quan sát, thông báo và recovery trên UI |
| Camera / native | Chưa nghiệm thu; đường được hỗ trợ là dán QR payload | Ghi đúng thiếu tính năng và quyết định scope; không giả nhận camera đã làm |
| DB backup | Chưa backup/restore; DB Free hết hạn 16/12/2026 | Ghi gap vận hành riêng; không thử restore/reset trên DB đang host |

Các subscription 1 và 2 của lượt nghiệm thu cũ đã REFUNDED. Không dùng chúng làm mẫu ACTIVE hoặc sửa DB để diễn lại. Gói demo cũ không thay thế bộ dữ liệu QA mới.

## 4. Luật đúng để đối chiếu tiền và thời gian

1. Tổng gốc = giá mỗi kỳ × số kỳ. `1 mUSDC = 1_000_000` atomic units. Hiển thị tiền không được nhầm với AVAX gas hoặc số dư mô phỏng.
2. Kỳ đầu chỉ mở sau một `period_duration` từ subscribe. Mỗi check-in hợp lệ giải ngân đúng một kỳ; không tự trả các kỳ bỏ lỡ. Kỳ kế tiếp tính từ timestamp block **release vừa xảy ra**, không từ đồng hồ điện thoại.
3. Check-in khi `next_release_at <= block.timestamp < refund_available_at`; refund khi `block.timestamp >= refund_available_at`. `refund_available_at = next_release_at + grace_period`. Refund trả **gốc chưa dùng**; không phải cơ chế xác minh gym đóng cửa hoặc hoàn cả phần đã dùng.
4. Subscriber ký QR EIP-712; đúng ví merchant mới gửi giao dịch check-in. Một nonce/chữ ký không được giải ngân hai lần. TTL QR tối đa 900giây; dữ liệu sai chain/Vault/merchant/kỳ/nonce/deadline phải bị từ chối.
5. Trạng thái ACTIVE chỉ chuyển sang COMPLETED hoặc REFUNDED; trạng thái cuối không tiếp tục chi tiền. Mỗi release/refund tăng nonce. Sau publish, điều khoản tài chính và metadata plan không sửa trực tiếp; đổi điều khoản phải tạo plan mới.
6. Merchant trả gas check-in; subscriber trả gas approve/subscribe/refund. Với DISABLED, không nhận có yield thật; sau cùng đối chiếu **gốc ban đầu = gốc còn lại + gốc đã giải ngân + gốc đã hoàn** cho từng subscription.

Đọc [project.md](project.md), [schema.md](schema.md), [user_flows.md](user_flows.md) khi cần chi tiết. Nếu tài liệu lịch sử khác manifest/receipt hiện hành, ghi khác biệt và xác minh, không tự đổi luật để làm test pass.

## 5. Chuẩn bị tài khoản, dữ liệu và cách thao tác

- Chuẩn bị hai địa chỉ test **khác nhau**: M là merchant, S là subscriber; thêm X không có quyền để kiểm truy cập tài nguyên. M/S có gas Fuji và S có mUSDC được nhóm cho phép sử dụng. Không suy rằng số dư cấp ngày 16/11 vẫn còn nguyên. Đo số dư trước khi bắt đầu.
- Dùng hồ sơ trình duyệt test riêng cho M/S; thực hiện Core và MetaMask thật nếu có. Hai profile hoặc hai cửa sổ trên một máy **không phải** hai thiết bị vật lý. Thiếu extension, ví mở khóa hoặc thiết bị thì ghi BLOCKED và nêu đúng đầu vào còn thiếu.
- Người giữ ví xử lý mở khóa/ký khi công cụ yêu cầu. Không đọc hoặc chuyển seed/private key, cookie đăng nhập, file khóa bảo vệ của máy; không tự cấp thêm gas/token hoặc tăng allowance ngoài ngân sách được phép. Tài liệu này không cấp thêm quyền chi tiêu hay quyền quản trị Render.
- Gợi ý bộ dữ liệu mới: plan `QA-20261118-<mã duy nhất>`, giá **1 mUSDC/kỳ**, **3 kỳ**, duration **60 giây**, grace **180 giây**. Đây là đề xuất để thao tác thủ công, chưa tạo sẵn. Chuẩn bị ba vị thế riêng: S1 hoàn thành đủ kỳ, S2 dùng một kỳ rồi refund, S3 chưa dùng rồi refund. Dùng số tiền nhỏ, ghi plan/subscription ID và hash thực tế.
- Web host có pin API nên mở workspace dữ liệu thật. Bấm **Kết nối API** rồi **Kết nối ví / Đăng nhập**. **Về demo** mở luồng mô phỏng; tài khoản công khai `demo@example.com` / `demo1234` chỉ dùng trong demo, không phải tài khoản API hoặc thông tin ví.
- Trong workspace thật: **Tạo hồ sơ cơ sở**, **Tạo / publish gói**, **Publish draft**, **Đăng ký**, **Tạo QR check-in**, **Nhập QR check-in**, **Yêu cầu hoàn gốc**, **Chi tiết / lịch sử**, **Làm mới trạng thái**, **Đăng xuất ví**. Tên nút là mốc tham khảo từ source hiện hành; khám phá UI mới nếu nhánh đã đổi, không hard-code tọa độ.
- Thời gian boundary theo block/eligibility LIVE. Chờ chain thật khi test Fuji; chỉ dùng tăng thời gian EVM hoặc giả đồng hồ trong môi trường local do mình sở hữu. Không chỉnh giờ hệ điều hành hoặc can thiệp chain public để ép test.

## 6. Ma trận hành trình quan trọng — chạy bằng UI trước

Tất cả testcase dưới đây bắt đầu ở **NOT_RUN**; tester điền kết quả và bằng chứng vào báo cáo của lượt mình, không chuyển PASS theo các báo cáo cũ.

| ID | Thao tác người dùng | Kết quả cần kiểm |
| --- | --- | --- |
| A01 | Mở app từ tab mới sau thời gian không sử dụng; quan sát lần kết nối đầu | Có loading/trạng thái lỗi rõ, không trắng màn hình hoặc treo vô hạn. Ghi timing, HTTP status/content-type và request ID nếu timeout/502; thử lại có phục hồi, không tự phát giao dịch |
| A02 | API lỗi/trả HTML502 rồi hoạt động trở lại | UI không crash do tưởng HTML là JSON, không báo giao dịch thành công; cho retry có kiểm soát, giữ dữ liệu form và pending cần thiết. Xác minh lại quan sát ngày 18/11 |
| A03 | Mở khi chưa cài ví; cài/khởi động ví và kết nối lại | Thông báo thiếu provider rõ ràng, có đường tiếp tục. Không coi lỗi extension là token đã mất hoặc khóa ví sai |
| A04 | Kết nối M/S, ký SIWE; thử từ chối pop-up và kết nối lại | Không đăng nhập khi chưa có chữ ký; hủy không làm kẹt nút/loading. Sau khi ký thấy đúng ví, chain và tài nguyên |
| A05 | M tạo profile, tạo draft, kiểm form rồi publish plan | Nội dung/giá/kỳ trong màn xác nhận và ví khớp plan on-chain. Reject ký giữ draft có thể thử lại; thành công không tạo plan thứ hai khi bấm nhanh |
| A06 | S mở plan, đọc tổng giá, approve rồi subscribe | Hiển thị đúng token/decimals/tổng gốc/allowance; không subscribe trước approve confirmed. Nhận đúng một vị thế, lịch và số gốc khớp receipt |
| A07 | S1 tới kỳ, tạo QR; M nhận trên thiết bị khác và xác nhận | Chữ ký được ký bởi S, merchant đúng; dán payload hoạt động. M chỉ nhận một kỳ, số dư/nonce/lịch/history trên cả hai phía cập nhật đúng |
| A08 | Nhập lại QR đã dùng; sửa một trường, dùng QR hết hạn/sai ví/chain/Vault | Không giải ngân thêm; lỗi hiểu được, không kẹt modal hoặc làm mất vị thế. Không cần cố broadcast nếu UI đã chặn đúng |
| A09 | S1 hoàn thành lần lượt đủ ba kỳ | M nhận tổng 3 mUSDC của vị thế này, remaining 0, status COMPLETED; không còn nút chi tiếp hoặc lịch kỳ tương lai giả |
| A10 | S2 dùng một kỳ rồi chờ refund_available_at và yêu cầu hoàn gốc | Trước hạn không hoàn; đúng/sau hạn check-in đóng, refund mở. Refund đúng 2 mUSDC, merchant giữ 1 mUSDC đã giải ngân; trạng thái cuối REFUNDED |
| A11 | S3 chưa dùng kỳ nào rồi refund sau hạn | Hoàn đúng 3 mUSDC, merchant không được trả gốc của S3. Không mô tả là hoàn do cơ sở vi phạm |
| A12 | X hoặc S khác mở/tìm vị thế của M/S | Không lộ dữ liệu riêng hoặc cho thao tác tài nguyên của người khác. Chọn chế độ Cơ sở không cấp quyền merchant; ví merchant của plan khác không được giải ngân |
| A13 | Đối chiếu cả ba vị thế sau hoàn thành | Nếu dùng đúng fixture trên, tổng gốc vào là 9 mUSDC, merchant nhận 4, S được hoàn 5, gốc còn trong Vault cho ba vị thế là 0; tách khỏi các vị thế khác, gas AVAX và số dư có trước |

Với mỗi bước tiền: lưu trạng thái/số dư trước-sau, hash, block/receipt, plan/subscription ID và wallet public address. Không nhận toast hoặc tx hash đơn thuần là CONFIRMED. Kiểm explorer/receipt canonical, đủ confirmations theo manifest, rồi đối chiếu UI/API; projection có thể chậm, phải đánh giá UI có nói rõ pending hay báo sai thành công.

## 7. Những tình huống sử dụng thật dễ lộ bug

| ID | Cách thử | Điều kiện / kết quả cần quan sát |
| --- | --- | --- |
| B01 | Reject SIWE, approve, publish, subscribe, check-in và refund lần lượt | Mỗi lần hủy đều thoát loading, không mất form hoặc tạo thêm transaction khi retry |
| B02 | Chuyển account/network lúc pop-up đang mở hoặc sau broadcast | Phiên cũ hết hiệu lực đúng; hash vẫn gắn ví/deployment bắt đầu. Không dùng token ví mới đọc pending cũ hoặc ký nhầm chain |
| B03 | Reload, đóng/mở tab, logout/login khi transaction đang chờ | Khôi phục pending/hash trước khi cho gửi lại; không approve/subscribe trùng. Chuẩn bị hash ngoài app trước khi làm thử |
| B04 | Bấm hai lần nhanh, hai tab cùng tài khoản, Back/đóng modal lúc chờ | Không trả tiền/gửi giao dịch lặp; trạng thái hội tụ sau refresh và thông báo không tự mâu thuẫn |
| B05 | Mất mạng sau broadcast, API tracking lỗi nhưng RPC đã nhận tx | Giữ hash, đối chiếu receipt/scanner và phục hồi; không tự coi thất bại là chưa gửi. Fault injection phải ở profile test hoặc local |
| B06 | Hủy/tăng phí một pending bằng extension; đối chiếu replacement qua UI | Đúng sender/nonce và hash đã confirmed mới mở trạng thái cũ. Thiếu nonce lẫn signed raw gốc thì ORIGINAL_TX_UNAVAILABLE là guard đúng, không xóa DB/cache để cho qua |
| B07 | Signed raw sai hash/chain/owner; replacement chưa confirmed | Không nhận proof sai hoặc coi cancel đã xong. Signed raw không phải seed/private key, không đưa vào ảnh/log công khai |
| B08 | Phiên hết hạn, API 401/403/404/409/422/429/503; retry sau phục hồi | Lỗi hiển thị rõ bằng tiếng Việt và hành động tiếp theo; không mất pending hoặc lặp POST mù. Không spam/load-test API shared để tạo 429 |
| B09 | Form trống, nhiều dấu cách, số0/âm/quá nhiều decimals, số rất lớn, tên dài, emoji, NUL | Chặn hoặc báo 422 đúng; tiền/decimals không làm tròn sai. Tên tiếng Việt/emoji/mô tả nhiều dòng hợp lệ vẫn lưu được; NUL không bị báo nhầm DB hỏng |
| B10 | Browser refresh sau publish, đổi bộ lọc rồi tải thêm danh sách | Không trùng/bỏ mục, không reset filter bất ngờ; draft đã publish không sửa được. Thử vượt 100 ở local/test dataset, không tạo hàng trăm giao dịch Fuji để lấy dữ liệu |
| B11 | Storage bị chặn/hỏng/đầy; mất cache và API cùng lúc | Có cảnh báo giữ hash, không gửi lặp. Chỉ thao tác storage của profile test; không xóa pending để giả sửa lỗi. Nếu mất mọi bằng chứng sau đóng tab, phải đối chiếu lịch sử ví |
| B12 | Máy có Core và MetaMask cùng lúc; ví khóa, sai mạng hoặc thiếu gas/mUSDC | Ghi provider thực sự được chọn, ví được ký và lỗi khi không hỗ trợ; không kết nối nhầm ví âm thầm hoặc nhầm số dư gas với token |
| B13 | QR bị cắt, JSON rác, registration QR mở plan khác/chain khác | Không crash; phân biệt QR đăng ký và QR check-in, không hiện nhầm điều khoản hoặc tự chuyển pin deployment |

Chỉ giả lập lỗi transport/storage/clock trong môi trường test có kiểm soát. Không gây outage, chỉnh dữ liệu tài chính hoặc reorg public Fuji. Ghi rõ môi trường khi báo bug; lỗi dùng sai API origin/CORS local không tự biến thành bug production.

## 8. UI/UX, mobile và phần demo cũng phải kiểm

- Đi qua mọi màn người dùng nhìn thấy: onboarding/kết nối, catalog, chi tiết gói, hội viên/lịch sử, cơ sở/draft, QR, refund, tài khoản; cả training/booking/giờ đông/dashboard/bạn tập nếu chúng đang có trên UI. Kiểm menu, Back, chuyển chế độ, modal, nút chết, trạng thái rỗng/loading/error/success và dữ liệu sau reload.
- Mở **Về demo**, đăng nhập bằng tài khoản demo công khai hoặc tạo tài khoản giả. Thử tìm/đăng ký gói, check-in mô phỏng, chuyển Cơ sở, tạo gói, giới thiệu/bạn tập và tải lại trang. Dữ liệu demo theo phiên có thể reset; đó chỉ là bug nếu UI hứa lưu thật hoặc trộn số liệu demo với vị thế Fuji. Email/password demo không đăng nhập được API là chủ đích.
- Đánh giá người dùng có hiểu “tiền đang ở đâu”, vì sao chờ, khi nào nhận/hoàn tiền, ai phải ký, bước kế tiếp là gì. Ghi rõ điểm gây nhầm giữa MOCK/DISABLED, mUSDC/tiền thật, dữ liệu tạm/dữ liệu chain. Tách bug chức năng khỏi đề xuất UX; mô tả hành vi gây nhầm cụ thể thay vì chỉ nhận xét giao diện chưa đẹp.
- Kiểm desktop và viewport 375/390px, phóng to 200%, tên/giao dịch dài, bàn phím nhập liệu, cuộn, vị trí nút chính, focus/Tab và lỗi chữ tràn/che modal. Viewport mô phỏng chỉ là kiểm layout; mobile thật cần ghi máy/OS/browser và khả năng ví của máy đó.
- Nếu yêu cầu camera/native không có trong scope/bản build, ghi “chưa triển khai/chưa nghiệm thu”, không gọi dán payload là quét camera. Một tính năng hiển thị là dùng thật nhưng chỉ chạy RAM phải được báo là gap tích hợp; không tự xây thêm API booking/training hoặc DeFi để khép checklist.

## 9. Khi cần đọc code hoặc tái hiện ở local

| Đầu mối đọc | Vị trí |
| --- | --- |
| Điều hướng, ghép demo/thật | `apps/flutter_app/lib/app/`, `apps/flutter_app/lib/features/` |
| HTTP, ví, controller, QR, pending | `apps/flutter_app/lib/real/` |
| Auth/quyền/metadata/tracking/read | `backend/app/api/` |
| RPC / scanner / rebuild / cursor | `backend/app/blockchain/vault.py`, `backend/app/services/` |
| Luật tiền, signature, ABI | `contracts/contracts/`, `shared/` |
| Test tích hợp có sẵn | `scripts/browser_acceptance/README.md`, `scripts/validation/README.md`, `backend/tests/`, `apps/flutter_app/test/` |

Ưu tiên tái hiện từ UI và Network trước, sau đó trace đúng caller và receipt. Backend không tự ký gửi giao dịch thay người dùng. Bốn bug đã sửa ở `5f2528a` là log RPC thiếu/sai, replacement hash cũ sau rebuild, NUL validation và chia suite EVM; đọc [báo cáo](be-audit-2026-11-16.md) trước khi báo trùng.

Local dùng Python 3.12/uv, Node 24, Flutter 3.47.9 theo CI, PostgreSQL 16 và EVM riêng chain 31337; xem README từng phần để dựng. `TEST_DATABASE_URL` chỉ trỏ DB test được phép tạo/drop schema, không dùng DB Render. Injected test provider và tăng thời gian EVM chỉ là local/simulated; không đổi tên kết quả thành nghiệm thu extension thật. Localhost gọi hosted API bị CORS chặn là cấu hình hiện hành; không mở CORS wildcard trên live để chạy test.

## 10. Đầu ra phải bàn giao lại

Lưu vào `docs/qa-antigravity-<ngày>.md` hoặc đường dẫn QA của nhóm; ảnh/video/log đã che dữ liệu nhạy cảm để cùng thư mục evidence. Nếu có code, ghi nhánh/SHA và tách báo cáo khỏi bản sửa. Mỗi testcase có **PASS / FAIL / BLOCKED / NOT_RUN**, môi trường, provider thật/test, thiết bị/OS/browser, thời điểm và evidence path. Không dùng một chữ PASS chung cho toàn app.

Mẫu cho mỗi bug:

```text
ID / tiêu đề:
Mức độ: P0 / P1 / P2 / P3
Env + web/API SHA + URL + thời điểm:
Thiết bị/OS/browser + Core/MetaMask/test provider:
Vai trò + wallet public address + plan/subscription ID liên quan:
Điều kiện ban đầu:
Bước tái hiện 1..n:
Mong đợi:
Thực tế:
Tần suất: n lần lỗi / m lần thử:
Ảnh/video; console/network đã che; HTTP status + request ID; tx hash/receipt:
Ảnh hưởng đến tiền/dữ liệu/khả năng hoàn thành hành trình:
Nguyên nhân đã xác minh hoặc giả thuyết chưa xác minh:
Một đầu mối: UI / BE / Solidity / vận hành / chưa xác định:
Hướng sửa nhỏ nhất; testcase phải chạy lại:
Trạng thái sửa + SHA + kết quả retest (nếu có):
```

P0: mất/chi sai tiền, lộ khóa hoặc vượt quyền nghiêm trọng. P1: chặn hành trình core, gửi trùng, hiển thị sai trạng thái tài chính. P2: sai form/danh sách/recovery còn đường tiếp tục. P3: trình bày/UX nhỏ. Mức độ dựa ảnh hưởng tái hiện được, không suy chỉ từ tên exception. Nếu chưa rõ nguyên nhân thì ghi “chưa xác định”, không gộp owner kiểu “UI+BE”.

Không ghi JWT, cookie, seed/private key, connection string, signed raw hoặc chữ ký/QR còn hiệu lực vào Git, HAR công khai hay screenshot. Screenshot/video chỉ cần bằng chứng liên quan; che dữ liệu của tab/tài khoản khác. Khi kết thúc, logout phiên test, ghi các vị thế còn mở/số dư/allowance và những bước dọn dữ liệu cần người giữ ví thực hiện; không xóa dữ liệu người khác.

Tiêu chí kết thúc lượt QA: có bảng coverage cho core và demo, danh sách bug ưu tiên kèm repro/evidence, gap môi trường/thiết bị ghi BLOCKED rõ ràng, và kết quả retest nếu có sửa. Nếu chưa có hai thiết bị/extension hoặc API còn 502, bàn giao đúng các giới hạn đó; không tuyên bố đã nghiệm thu toàn app.
