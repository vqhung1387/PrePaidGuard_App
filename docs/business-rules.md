# Luật nghiệp vụ cần chốt

Backend và Solidity hiện dùng baseline B1–B6 trong project.md theo phạm vi người dùng giao. Các điểm dưới đây cần nhóm nghiệm thu trên bản demo.

- [ ] Giải ngân theo tháng hay từng buổi; thời điểm giải ngân kỳ đầu.
- [ ] Một kỳ chỉ giải ngân một lần; quy tắc với kỳ bị bỏ qua.
- [ ] Điều kiện refund: hủy do không sử dụng hay phải xác nhận cơ sở vi phạm.
- [ ] Mốc tính ân hạn và hành vi tại đúng ranh giới kỳ/refund.
- [ ] Quyền merchant/scanner và địa chỉ nhận tiền.
- [ ] Tỷ lệ yield dự kiến 70/20/10; làm tròn và phân phối khi refund.
- [ ] Yield mô phỏng hay tích hợp thật theo yêu cầu cuộc thi.

Refund được triển khai theo điều kiện thời gian tại B3/B4, với ý nghĩa khách hủy do không sử dụng. Không check-in không chứng minh cơ sở đóng cửa. Thay chính sách refund cần sửa đồng bộ contract, API và Flutter.
