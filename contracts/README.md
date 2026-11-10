# Smart contracts

Khung thư mục cho Solidity + OpenZeppelin + Hardhat, chưa khởi tạo project hoặc cài dependencies.

- contracts/: PrepaidVault.sol sau khi chốt nghiệp vụ.
- contracts/interfaces/: IYieldAdapter.sol khi cần adapter.
- contracts/mocks/: MockUSDC.sol và MockYieldAdapter.sol cho môi trường thử nghiệm.
- test/: kiểm thử luồng tiền, chữ ký và các điều kiện biên.
- scripts/: deploy, seed-demo và xuất ABI/địa chỉ vào shared/.

Mạng demo dự kiến: Avalanche Fuji (chain ID 43113). Kiểm chứng cấu hình mạng trước khi deploy. Chưa chọn phiên bản compiler và dependency cụ thể.

Khởi đầu bằng kiểm thử đăng ký → check-in → refund; kiểm tra nonce, deadline, domain EIP-712 và không giải ngân hai lần cho cùng kỳ. Yield mô phỏng cần có token cấp sẵn và được ghi rõ trên UI.
