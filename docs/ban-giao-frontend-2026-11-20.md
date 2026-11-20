# Bàn giao giao diện hội viên PrepaidGuard · 20/11/2026

**Bản bàn giao** là commit [d693b2e trên nhánh frontend](https://github.com/vqhung1387/PrePaidGuard_App/commit/d693b2ee179c400955fe52ab871ce7636424b966). Commit `6126b75` chứa thay đổi giao diện và API cộng đồng. Commit `d693b2e` sửa cảnh báo Flutter.

## Kiểm tra giao diện

| Mục | Thao tác và kết quả cần thấy |
| --- | --- |
| Trang chủ | Chuyển qua năm mục ở thanh dưới cùng. Mở **Tìm cơ sở**, chọn chi nhánh rồi đổi ngày trên biểu đồ hội viên để xem 24 khung giờ. |
| Lớp học hôm nay | Mở **Xem tất cả** để xem giờ và thời lượng. Ở lịch có Pilates cơ bản, Cardio Dance và Yoga phục hồi, ba thẻ dùng ba ảnh khác nhau. |
| Huấn luyện viên | Tại Lê Hồng Phong, khi chưa có hồ sơ công bố, danh sách minh họa gồm Minh Anh, Gia Huy và Thảo Nguyên. Bốn chi nhánh có danh sách riêng. Hồ sơ do cơ sở công bố được ưu tiên. |
| Gói dịch vụ | Mở một gói và đổi kỳ để xem ước tính phần chuyển cho cơ sở và phần còn giữ cho khách. Đơn vị hiển thị là PG Credit, quy đổi thử nghiệm 1 PG Credit = 1 mUSDC. |
| Ví và gói của tôi | Dùng MetaMask trên Avalanche Fuji (43113), ký yêu cầu đăng nhập rồi mở **Gói của tôi**. Đăng ký gói cần đủ mUSDC thử nghiệm và AVAX Fuji cho phí mạng. |

Số hội viên theo giờ, lịch lớp và hồ sơ huấn luyện viên có dữ liệu minh họa khi chi nhánh chưa có bản ghi tương ứng.

## Mở bản local

Trên máy phát triển đã cấu hình, mở `Mo-PrepaidGuard.cmd` ở thư mục cha của `PrePaidGuard_Latest` và giữ cửa sổ đó mở. Truy cập [web local](http://127.0.0.1:18092/). Khi trang mở nhưng không tải được dữ liệu, kiểm tra [trạng thái API](http://127.0.0.1:18011/ready). Đường dẫn localhost trỏ về chính máy đang mở trình duyệt.

Khi đưa bản này sang môi trường khác, backend cần cấu hình PostgreSQL của môi trường đó và migration `0004_club_community` cho các tính năng cộng đồng.

## Bằng chứng và phạm vi nghiệm thu

- Trên máy phát triển, Flutter analyze hoàn tất với `No issues found`. Cả 125 bài kiểm thử Flutter đã đạt sau khi bỏ hàm không còn sử dụng.
- Đã kiểm tra trên Chrome việc tải ba ảnh lớp khác nhau và hiển thị ba hồ sơ tại Lê Hồng Phong.
- GitHub ghi nhận [Browser acceptance đạt ở commit 6126b75](https://github.com/vqhung1387/PrePaidGuard_App/actions/runs/44652785397). Đối chiếu thêm [các lần chạy frontend](https://github.com/vqhung1387/PrePaidGuard_App/actions/workflows/frontend.yml?query=branch%3Afrontend) theo mã commit trước khi phát hành.
- Chưa xác nhận bản web công khai chạy commit `d693b2e` hoặc giao dịch đăng ký gói đã hoàn tất bằng ví thật trên bản này.
