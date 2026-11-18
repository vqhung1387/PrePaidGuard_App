class WalletProviderInfo {
  const WalletProviderInfo({
    required this.id,
    required this.name,
    this.rdns = '',
  });

  final String id;
  final String name;
  final String rdns;
}

String classifyWalletError({
  int? code,
  String? message,
  required String method,
}) {
  final lower = (message ?? '').toLowerCase();
  if (code == 4001 ||
      lower.contains('user rejected') ||
      lower.contains('user denied')) {
    return 'Bạn đã từ chối yêu cầu trong ví ($method). Dữ liệu đã nhập vẫn được giữ để thử lại.';
  }
  if (code == 4100 ||
      lower.contains('locked') ||
      lower.contains('unauthorized')) {
    return 'Ví đang khóa hoặc chưa cấp quyền tài khoản. Hãy mở khóa MetaMask/Core rồi thử lại.';
  }
  if (code == -32002 || lower.contains('already pending')) {
    return 'Đang có yêu cầu chờ xác nhận sẵn trong tiện ích ví. Hãy mở biểu tượng ví trên trình duyệt.';
  }
  if (code == 4902 || lower.contains('unrecognized chain')) {
    return 'Mạng yêu cầu chưa được thêm vào ví. Hãy thêm mạng thử nghiệm rồi thử lại.';
  }
  if (lower.contains('insufficient funds') ||
      lower.contains('gas required exceeds allowance') ||
      lower.contains('intrinsic gas too low')) {
    return 'Không đủ AVAX trên mạng thử nghiệm để trả phí gas giao dịch.';
  }
  if (method == 'personal_sign') {
    final details = code == null ? '' : ' (mã ví $code)';
    return 'Ví chưa trả chữ ký đăng nhập$details. Mở tiện ích ví để xem có thông báo lỗi không.';
  }
  return 'Ví không thực hiện được $method. Kiểm tra ví và giao dịch đang chờ trước khi thử lại.';
}

abstract class WalletPort {
  Future<dynamic> request(String method, [List<dynamic> params = const []]);
  Stream<void> get changes;
  List<WalletProviderInfo> get providers => const [];
  String? get selectedProviderId => null;
  void selectProvider(String id) {}
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
