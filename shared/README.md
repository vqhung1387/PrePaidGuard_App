# Dữ liệu tích hợp dùng chung

- abi/: ABI xuất tự động từ contract build đã kiểm chứng.
- deployments/: địa chỉ contract theo chain ID và network.
- check-in.schema.json: chỉ tạo sau khi chốt kiểu và tên trường; không đưa schema giả vào tích hợp.

Thông điệp check-in dự kiến chứa subscriptionId, merchant, kỳ, nonce và deadline. Domain EIP-712 chứa name, version, chainId, verifyingContract. Flutter và Solidity phải thống nhất hoàn toàn tên trường, kiểu dữ liệu và thứ tự. JSON Schema chỉ mô tả payload, không thay thế định nghĩa EIP-712.

Chưa có ABI, deployment hoặc schema vì contract chưa được triển khai.
