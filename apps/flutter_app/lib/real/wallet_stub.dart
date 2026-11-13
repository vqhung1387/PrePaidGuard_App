import 'wallet_port.dart';

WalletPort createWallet() => UnsupportedWallet();
PendingStore createPendingStore() => MemoryPendingStore();

class UnsupportedWallet implements WalletPort {
  @override
  Stream<void> get changes => const Stream.empty();
  @override
  Future<dynamic> request(String method, [List<dynamic> params = const []]) =>
      Future.error(
        StateError('Chế độ ví thật hiện hỗ trợ Flutter Web với ví EIP-1193.'),
      );
  @override
  void dispose() {}
}
