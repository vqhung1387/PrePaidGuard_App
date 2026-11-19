# Dữ liệu tích hợp dùng chung

- abi/: ABI thật xuất từ PrepaidVault, MockUSDC và MockYieldAdapter bằng npm run export trong contracts/.
- deployments/: manifest do script deploy xuất sau receipt thành công. local.json phụ thuộc node hiện tại và được gitignore. fuji.json được tạo sau khi deploy trên Fuji.
- check-in.types.json: tên, thứ tự và kiểu fields EIP-712 CheckIn.
- check-in.schema.json: cấu trúc QR. Client còn cần kiểm max payload 4096 bytes, uint256 <= 2^256-1, domain, nonce, thời hạn và chữ ký.
- check-in.fixture.json: vector test cố định gồm domain separator, struct hash, digest, signature và signer. Địa chỉ Vault trong vector là placeholder phục vụ test.

Thông điệp check-in gồm subscriptionId, merchant, periodIndex, nonce và deadline theo đúng thứ tự. Domain EIP-712 chứa name=PrepaidGuard, version=1, chainId, verifyingContract. Flutter và Solidity dùng cùng định nghĩa field/type/order. Chữ ký phải được đối chiếu bằng typed-data encoder.

Backend test đối chiếu ABI xuất trước RPC và kiểm vector chữ ký do TypeScript tạo bằng eth-account của Python. Khi đổi contract hoặc typed-data fields, chạy export, test backend và contract, rồi commit bộ shared cùng thay đổi.

Xem [bàn giao Solidity](../docs/solidity-handoff.md).
