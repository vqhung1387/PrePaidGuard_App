abstract class WalletPort {
  Future<dynamic> request(String method, [List<dynamic> params = const []]);
  Stream<void> get changes;
  void dispose();
}

abstract class PendingStore {
  String? read(String key);
  void write(String key, String value);
}

class MemoryPendingStore implements PendingStore {
  final values = <String, String>{};
  @override
  String? read(String key) => values[key];
  @override
  void write(String key, String value) => values[key] = value;
}
