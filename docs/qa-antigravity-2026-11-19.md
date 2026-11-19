# Báo cáo Kiểm thử Toàn diện Theo Hành trình Người dùng PrePaidGuard
**Ngày kiểm thử:** 19/11/2026 (Giờ Việt Nam)  
**Đơn vị thực hiện:** Antigravity QA Engineering Team  
**Mục tiêu:** Kiểm thử thực tế theo góc nhìn người dùng (User-First & Code-First), rà soát các điểm có thể làm người dùng bị kẹt, thao tác nhầm hoặc hiểu sai trạng thái tiền; đối chiếu chi tiết số dư tài chính, gas và receipt trên blockchain.

---

## 1. Thông tin Môi trường & Phiên bản Kiểm thử

| Hạng mục | Giá trị xác nhận thực tế | Ghi chú |
| :--- | :--- | :--- |
| **Mã nguồn Git (Baseline)** | `5b6c617bd5b89bd9d86c50b7b36bc8d250afe487` | Tích hợp từ `origin/fix/be-nghiem-thu-1116`, bao gồm `bef1666`, `4c2f71d`, `fc5917f` |
| **Nhánh kiểm thử** | `fix/antigravity-ux-final` (Worktree độc lập `prepaid-final-antigravity`) | Bảo toàn nguyên vẹn 100% `work/prepaid-be-1116` |
| **Web Live (Render)** | `https://prepaidguard-web.onrender.com/` | Bundle SHA-256: `be8cd70baf24e02240535ccf2fadbf02d14ddc6f9a26c8c9740ddc317a2e3c43`, Deploy `bef1666` |
| **API Live (Render)** | `https://prepaidguard-api.onrender.com/` | Probe: `/health` (438ms), `/ready` (2.172ms), `/api/v1/config` (203ms), `/api/v1/plans/1` (766ms) |
| **Môi trường Local EVM** | Hardhat Local EVM Chain ID `31337`, RPC `http://127.0.0.1:18545` | Khởi chạy qua `local.py`, yield_mode `MOCK` |
| **Cơ sở dữ liệu Test** | PostgreSQL 16 cục bộ (`127.0.0.1:55439`), schema cô lập tự hủy | Hoàn toàn tách biệt khỏi môi trường sản xuất |
| **Trình duyệt thực thi** | Google Chrome 124+ (`C:\Program Files\Google\Chrome\Application\chrome.exe`) | Chạy tự động hóa Playwright 1.65.2 |
| **Ví QA thử nghiệm** | Injected EIP-1193 / EIP-6963 test provider | Không dùng private key thật, không dùng mainnet |

---

## 2. Bảng Ma trận Kết quả Kiểm thử (Coverage Matrix)

| STT | Trường hợp kiểm thử | Môi trường | Kết quả | Bằng chứng & Log |
| :---: | :--- | :---: | :---: | :--- |
| **P1.1** | Web Live: Probe HTTP `/health`, `/ready`, `/config`, `/plans/1` | Live Render | **PASS** | [step1_live_web_report.json](evidence/qa-2026-11-19/step1_live_web_report.json) (toàn bộ trả 200 OK) |
| **P1.2** | Web Live: So sánh Fresh Session vs Cached Session (`s-maxage=300`) | Live Render | **PASS** | [01_live_desktop_home_fresh.png](evidence/qa-2026-11-19/screenshots/01_live_desktop_home_fresh.png), [02_live_desktop_home_cached.png](evidence/qa-2026-11-19/screenshots/02_live_desktop_home_cached.png) (SHA bundle khớp) |
| **P1.3** | Web Live: Khách vãng lai xem điều khoản gói #1 không cần ví | Live Render | **PASS** | [04_live_plan1_direct.png](evidence/qa-2026-11-19/screenshots/04_live_plan1_direct.png), [10_live_guest_view_plan_terms.png](evidence/qa-2026-11-19/screenshots/10_live_guest_view_plan_terms.png) |
| **P1.4** | Web Live: Thao tác Back, Forward, Reload (F5) không vỡ trạng thái | Live Render | **PASS** | [05_live_after_back.png](evidence/qa-2026-11-19/screenshots/05_live_after_back.png), [07_live_after_reload.png](evidence/qa-2026-11-19/screenshots/07_live_after_reload.png) |
| **P1.5** | Web Live: Viewport Mobile 375×812 (iPhone SE) và 390×844 (iPhone 12) | Live Render | **PASS** | [08_live_mobile_375x812_iPhoneSE.png](evidence/qa-2026-11-19/screenshots/08_live_mobile_375x812_iPhoneSE.png) (overflow = False) |
| **P1.6** | Web Live: Chuyển tab khi chưa kết nối ví | Live Render | **FINDING** | Hiển thị thông báo "Chưa đọc được blockchain" gây hiểu lầm (Xem BUG-QA-01) |
| **P2.1** | Local: Cơ sở đăng nhập SIWE, tạo hồ sơ, publish gói 2 kỳ (100 mUSDC) | Local EVM | **PASS** | Plan ID #1 publish thành công, điều khoản on-chain xác nhận |
| **P2.2** | Local: Vị thế 1 (Chuẩn 50/50) — Đăng ký 100, giải ngân 50, hoàn 50 | Local EVM | **PASS** | Sub ID #1, Vault dư 0, Cơ sở nhận ròng 50, Hội viên hoàn 50 |
| **P2.3** | Local: Vị thế 2 (Hoàn tiền 100%) — 0 check-in, hết hạn rút hoàn đủ 100 | Local EVM | **PASS** | Sub ID #2, Vault dư 0, Hội viên nhận hoàn đủ 100 mUSDC |
| **P2.4** | Local: Vị thế 3 (Hoàn thành 100%) — Check-in kỳ 1 (50) + kỳ 2 (50) | Local EVM | **PASS** | Sub ID #3, Vault dư 0, Cơ sở nhận đủ 100 mUSDC, status `COMPLETED` |
| **P2.5** | Local: Chặn phát lại mã QR check-in cũ (Replay Protection) | Local EVM | **PASS** | [local_browser_acceptance_report.json](evidence/qa-2026-11-19/local_browser_acceptance_report.json) (Báo lỗi "QR đã dùng, sai kỳ") |
| **P3.1** | Phục hồi: Hủy hộp ký ví (User Reject 4001) | Local EVM | **PASS** | [33_qa_reject_4001.png](evidence/qa-2026-11-19/screenshots/33_qa_reject_4001.png) (Thông báo tiếng Việt, không mất form) |
| **P3.2** | Phục hồi: Danh mục lỗi 503 nhưng Link QR trực tiếp gói #1 vẫn 200 | Local EVM | **PASS** | [34_qa_catalog_down_direct_link.png](evidence/qa-2026-11-19/screenshots/34_qa_catalog_down_direct_link.png) (Khách vẫn đăng ký được) |
| **P3.3** | Phục hồi: Hai tab cùng ví ngăn chặn race-condition / ký trùng | Local EVM | **PASS** | Tab 2 hiển thị "Ví đang xử lý một giao dịch trong tab khác" |
| **P3.4** | Phục hồi: Lỗi mạng khi ghi pending cache (Quota / Outage) | Local EVM | **PASS** | Giữ nguyên tx hash, retry không phát sinh giao dịch thứ hai |
| **P3.5** | Phục hồi: Đối chiếu giao dịch thay thế / hủy nonce trên giao diện | Local EVM | **PASS** | Chuyển trạng thái giao dịch sang `CANCELLED` mà không broadcast lại |
| **P4.1** | UI/UX: Chặn giá 0, số âm, và dấu phân cách mơ hồ `1.000` / `1,000` | Local EVM | **PASS** | [35_qa_form_1dot000_rejected.png](evidence/qa-2026-11-19/screenshots/35_qa_form_1dot000_rejected.png) (Báo lỗi hướng dẫn rõ ràng) |
| **P4.2** | UI/UX: Bàn phím — Phím Escape đóng sạch modal dialog | Local EVM | **PASS** | Modal đóng ngay lập tức, trả focus về trang chính |
| **P4.3** | UI/UX: Độ co giãn khi thu phóng Desktop 200% (Zoom 200%) | Local EVM | **PASS** | [36_qa_zoom_200.png](evidence/qa-2026-11-19/screenshots/36_qa_zoom_200.png) (`overflow = False`, không che nút chính) |
| **P4.4** | UI/UX: Link mời demo cũ `?invite=gym-khoi-dong` | Local EVM | **PASS** | [37_qa_legacy_demo_invite.png](evidence/qa-2026-11-19/screenshots/37_qa_legacy_demo_invite.png) (Mở không gian thật theo commit `fc5917f`) |
| **P5.1** | Nghiệm thu Ví Core thật trên Web Live | Web Live | **BLOCKED** | Core hiển thị cảnh báo "Scam application" từ Blockaid (đang chờ gỡ) |
| **P5.2** | Nghiệm thu iPhone 12 Safari thật ký giao dịch | Web Live | **BLOCKED** | Cần người giữ thiết bị vật lý và ví thử nghiệm thực tế |

---

## 3. Bảng Đối chiếu Tài chính & Giao dịch Blockchain (Accounting Matrix)

Kiểm tra trên Local EVM Hardhat Chain ID `31337`, hợp đồng `PrepaidVault` và token `MockUSDC` (6 decimals). Toàn bộ 3 vị thế đều sử dụng gói 2 kỳ × 50 mUSDC (Tổng tiền nạp khóa: **100.000.000 micro-USDC** = **100 mUSDC**).

```
========================================================================================================
VỊ THẾ 1: CHUẨN 50/50 (GIẢI NGÂN KỲ 1: 50 mUSDC, HOÀN KỲ 2: 50 mUSDC)
--------------------------------------------------------------------------------------------------------
• Mã vị thế (Subscription ID): #1 | Mã gói (Plan ID): #1
• Đăng ký (Subscribe):    Tx 0xa0018fe7b5c88538d07df591b99d819db4153505b070c3f4613ee8a07fabe9b7
                          Block: 8 | Gas Used: 300.648
• Giải ngân kỳ 1:         Tx 0x6c931c8b5b5e2b24237776e4fc4d980356c588f01d1c6230f70cd1b421226cc5
                          Block: 10 | Gas Used: 173.506
• Hoàn tiền kỳ 2:         Tx 0xaa004f6e7c21d2fc42978ed7a5769380fc1a02bb9c7075094ac2a2ebd0a52638
                          Block: 12 | Gas Used: 103.627
--------------------------------------------------------------------------------------------------------
Biến động tài chính:
  - Cơ sở (Merchant):     +50.000.000 micro-USDC (+50,0 mUSDC)
  - Hội viên (Subscriber): -50.000.000 micro-USDC (-50,0 mUSDC)
  - Vault còn lại:        0 micro-USDC (Số dư bị khóa về đúng 0)
  => ĐỐI CHIẾU: KHỚP 100%, BẢO TOÀN NGUYÊN VẸN TIỀN GỐC.
========================================================================================================

========================================================================================================
VỊ THẾ 2: HOÀN TOÀN BỘ 100% (KHÔNG CHECK-IN KỲ NÀO, RÚT HOÀN TOÀN BỘ 100 mUSDC)
--------------------------------------------------------------------------------------------------------
• Mã vị thế (Subscription ID): #2 | Mã gói (Plan ID): #1
• Đăng ký (Subscribe):    Tx 0xc79fd8350a11c1ad0f1b8480d6b3aa30b26f32ce020caea4f6c3c230f7488939
                          Block: 14 | Gas Used: 283.548
• Hoàn toàn bộ (Refund):  Tx 0x974eccb55235a11df32cc04eca080bf5557d0743d0e8f801b7fc24823822976e
                          Block: 16 | Gas Used: 117.307
--------------------------------------------------------------------------------------------------------
Biến động tài chính:
  - Cơ sở (Merchant):     0 micro-USDC (Không nhận được khoản giải ngân nào)
  - Hội viên (Subscriber): 0 micro-USDC (Thu hồi trọn vẹn 100 mUSDC đã nạp)
  - Vault còn lại:        0 micro-USDC (Số dư bị khóa về đúng 0)
  => ĐỐI CHIẾU: KHỚP 100%, HỘI VIÊN BẢO VỆ ĐƯỢC TOÀN BỘ QUYỀN LỢI TRẢ TRƯỚC.
========================================================================================================

========================================================================================================
VỊ THẾ 3: HOÀN THÀNH ĐỦ 100% KỲ (CHECK-IN KỲ 1 VÀ KỲ 2, GIẢI NGÂN ĐỦ 100 mUSDC)
--------------------------------------------------------------------------------------------------------
• Mã vị thế (Subscription ID): #3 | Mã gói (Plan ID): #1
• Đăng ký (Subscribe):    Tx 0x23969ecfeb6fac395c510ad8c395fc44cdf207fdfd8a6c87b2b5bcb3bc5e7c79
                          Block: 18 | Gas Used: 283.548
• Giải ngân kỳ 1:         Tx 0x8acdb0eb6cf5ce823f48abb3592f1afc0e661fb2a2f8329b86a3744da78cee61
                          Block: 20 | Gas Used: 156.406
• Giải ngân kỳ 2:         Tx 0x4ab35069ba21c27c184929c8f05eb44c2d6eb12495409ece33e25460fae29dc9
                          Block: 22 | Gas Used: 117.680
--------------------------------------------------------------------------------------------------------
Biến động tài chính:
  - Cơ sở (Merchant):     +100.000.000 micro-USDC (+100,0 mUSDC trọn vẹn)
  - Hội viên (Subscriber): -100.000.000 micro-USDC (-100,0 mUSDC cho 2 kỳ dịch vụ)
  - Vault còn lại:        0 micro-USDC (Số dư bị khóa về đúng 0, trạng thái: COMPLETED)
  => ĐỐI CHIẾU: KHỚP 100%, CƠ SỞ NHẬN ĐỦ DOANH THU KHI CUNG CẤP ĐỦ DỊCH VỤ.
========================================================================================================
```

---

## 4. Chi tiết Các Phát hiện Lỗi & Điểm Cần Cải tiến (Bug & UX Findings)

### BUG-QA-01: Thông báo lỗi gây hiểu lầm "Chưa đọc được blockchain" khi khách chưa kết nối ví
- **Mức độ:** `P2` (Trải nghiệm người dùng & Độ rõ ràng tài chính)
- **Môi trường:** Web Live (`https://prepaidguard-web.onrender.com/`), bản build `bef1666`.
- **Thiết bị & Trình duyệt:** Google Chrome 124+ trên Windows, Safari trên iOS.
- **Vai trò:** Khách vãng lai (Guest) / Người dùng chưa kết nối ví.
- **Điều kiện ban đầu:** Mở ứng dụng lần đầu, chưa bấm "Kết nối ví / Đăng nhập".
- **Các bước tái hiện:**
  1. Truy cập `https://prepaidguard-web.onrender.com/`.
  2. Bấm vào tab **"Gói của tôi"**, **"Cơ sở"**, hoặc **"Giao dịch"**.
- **Kết quả mong đợi:** Giao diện hiển thị trạng thái rỗng thân thiện (Empty State), ví dụ:  
  *“Bạn chưa kết nối ví. Hãy bấm nút 'Kết nối ví / Đăng nhập' để xem danh sách gói đăng ký và lịch sử giao dịch của bạn.”*
- **Kết quả thực tế:** Màn hình hiển thị dòng chữ màu cam/đỏ:  
  *“Chưa đọc được blockchain. Vui lòng thử lại.”* kèm nút *“Tải lại”*.
- **Tần suất:** 100% (tái hiện mọi lần khi chưa có ví).
- **Bằng chứng:** Hình ảnh [12_live_guest_tab_Gói của tôi.png](evidence/qa-2026-11-19/screenshots/12_live_guest_tab_Gói của tôi.png) và tệp log [step1b_modals_report.json](evidence/qa-2026-11-19/step1b_modals_report.json).
- **Ảnh hưởng:** Người dùng mới lầm tưởng rằng mạng lưới blockchain bị lỗi hoặc ứng dụng bị sập, trong khi nguyên nhân chỉ là chưa kết nối ví.
- **Nguyên nhân đã xác minh:** Trong `apps/flutter_app/lib/real/screen.dart`, khối điều kiện hiển thị kiểm tra trạng thái lỗi chung khi danh sách rỗng hoặc controller chưa khởi tạo phiên kết nối ví, dẫn đến rơi vào nhánh `_errorMessage ?? 'Chưa đọc được blockchain'`.
- **Đầu mối chịu trách nhiệm:** `UI`.
- **Hướng sửa nhỏ nhất:** Thêm kiểm tra `if (!controller.isLoggedIn)` trước khi hiển thị lỗi đọc blockchain trên các tab cần ví, trả về widget thông báo yêu cầu kết nối ví rõ ràng.

---

### BUG-QA-02: Phân tách nội dung cảnh báo Modal QR đăng ký và QR check-in
- **Mức độ:** `P3` (Trình bày & Hướng dẫn sử dụng)
- **Môi trường:** Web Live & Local EVM.
- **Trạng thái:** **ĐÃ ĐƯỢC XÁC MINH SỬA TỐT (PASS)** trên bản `fc5917f` / `5b6c617`.
- **Chi tiết:** Trước đây, modal QR đăng ký gói từng hiển thị kèm khuyến cáo "hết hạn sau 15 phút" (vốn thuộc về mã QR check-in), làm cơ sở e ngại mã QR in dán tại quầy sẽ bị hết hạn. Bản kiểm thử hiện tại đã phân tách hoàn toàn: QR đăng ký ghi rõ *“Đây là mã QR đăng ký gói”* và không có cảnh báo 15 phút.
- **Bằng chứng:** [11_live_guest_registration_qr_modal.png](evidence/qa-2026-11-19/screenshots/11_live_guest_registration_qr_modal.png).

---

### BUG-QA-03: Cảnh báo "Scam application" từ Blockaid trên tiện ích Core Wallet thật
- **Mức độ:** `P2` (Vận hành & Phát hành sản phẩm)
- **Môi trường:** Web Live (`https://prepaidguard-web.onrender.com/`), mạng Avalanche Fuji.
- **Vai trò:** Cơ sở & Hội viên sử dụng ví Core thật.
- **Hiện tượng:** Tiện ích Core chặn kết nối với thông báo cảnh báo lừa đảo tự động từ mạng Blockaid.
- **Nguyên nhân xác minh:** Tên miền mới trên Render chưa tích lũy đủ điểm tín nhiệm (domain reputation). Nhóm đã nộp hồ sơ giải trình kèm hợp đồng đã xác minh tại cổng Blockaid (`https://report.blockaid.io/mistake`) và đang chờ hệ thống gỡ bộ lọc.
- **Trạng thái:** Đánh dấu **`BLOCKED`** đối với nghiệm thu hai ví Core thật trên web Live.
- **Đầu mối chịu trách nhiệm:** `Vận hành`.

---

### BUG-QA-04: Giới hạn thiết bị vật lý và độ trễ khởi động khi quét QR bằng iPhone thật
- **Mức độ:** `P2` (Nghiệm thu thiết bị thật)
- **Môi trường:** Safari trên iPhone 12, mạng Avalanche Fuji.
- **Hiện tượng:** Camera nhận diện liên kết QR chuẩn xác. Tuy nhiên, việc ký giao dịch trực tiếp trong Safari đòi hỏi tích hợp sâu với trình duyệt nội tại của app ví di động (Core/MetaMask mobile).
- **Trạng thái:** Đánh dấu **`BLOCKED`** cho đến khi có người giữ thiết bị vật lý thực hiện ca ký thật.
- **Đầu mối chịu trách nhiệm:** `UI / Vận hành`.

---

## 5. Rà soát An toàn Dữ liệu & Bí mật (Security & Secret Scan)

Đã chạy công cụ quét tự động `scratch/scan_secrets.py` đối với toàn bộ thư mục bằng chứng `docs/evidence/qa-2026-11-19/`, mã kiểm thử và báo cáo:
- **Private Key phát hiện:** `0`
- **Mnemonic / Seed phrase phát hiện:** `0`
- **JWT token / Authorization cookie phát hiện:** `0`
- **Database password / Chuỗi kết nối nhạy cảm:** `0`
- **Kết luận:** Đạt chuẩn an toàn 100%, sẵn sàng công khai và bàn giao cho ban giám khảo UniHack.

---

## 6. Kết luận & Đề xuất Hướng tới Chung kết UniHack (21/11/2026)

1. **Về tính toàn vẹn nghiệp vụ tài chính:**  
   Hệ thống chứng minh độ chính xác tuyệt đối trên cả 3 kịch bản: hoàn 50/50, hoàn tiền 100% khi chưa sử dụng, và giải ngân 100% khi hoàn thành đủ kỳ. Số dư Vault luôn quay về đúng 0 micro-USDC cho từng vị thế khép lại.
2. **Về khả năng phục hồi sự cố:**  
   Ứng dụng xử lý xuất sắc các tình huống gián đoạn: từ chối ký ví, API danh mục lỗi nhưng mã QR trực tiếp vẫn đăng ký được, chặn ký trùng trên hai tab cùng lúc, và đối chiếu giao dịch thay thế / hủy nonce.
3. **Đề xuất hành động tiếp theo:**  
   - **UI:** Tinh chỉnh câu thông báo ở các tab khi chưa kết nối ví (BUG-QA-01) để mang lại trải nghiệm chuyên nghiệp nhất cho khách vãng lai.
   - **Vận hành:** Tiếp tục theo dõi trạng thái phản hồi từ Blockaid để hoàn tất gỡ nhãn cảnh báo trên Core Wallet trước giờ nộp bài chính thức.
