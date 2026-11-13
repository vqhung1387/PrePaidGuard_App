import 'dart:async';
import 'dart:js_interop';
import 'wallet_port.dart';

@JS('ethereum')
external _Ethereum? get ethereum;
@JS('localStorage')
external _Storage get storage;

extension type _Ethereum(JSObject _) implements JSObject {
  external JSPromise<JSAny?> request(JSObject arguments);
  external void on(JSString event, JSFunction listener);
  external void removeListener(JSString event, JSFunction listener);
}
extension type _Storage(JSObject _) implements JSObject {
  external JSString? getItem(JSString key);
  external void setItem(JSString key, JSString value);
}

WalletPort createWallet() => BrowserWallet();
PendingStore createPendingStore() => BrowserPendingStore();

class BrowserPendingStore implements PendingStore {
  @override
  String? read(String key) {
    try {
      return storage.getItem(key.toJS)?.toDart;
    } catch (_) {
      throw StateError('Không đọc được pending cache.');
    }
  }

  @override
  void write(String key, String value) {
    try {
      storage.setItem(key.toJS, value.toJS);
    } catch (_) {
      throw StateError(
        'Không lưu được giao dịch pending; hãy giữ tx hash trước khi đóng app.',
      );
    }
  }
}

class BrowserWallet implements WalletPort {
  final _changes = StreamController<void>.broadcast();
  _Ethereum? _provider;
  JSFunction? _listener;

  void _listen(_Ethereum provider) {
    if (_provider != null) return;
    _provider = provider;
    final listener = ((JSAny? _) {
      if (!_changes.isClosed) _changes.add(null);
    }).toJS;
    _listener = listener;
    provider.on('accountsChanged'.toJS, listener);
    provider.on('chainChanged'.toJS, listener);
  }

  @override
  Stream<void> get changes => _changes.stream;
  @override
  Future<dynamic> request(
    String method, [
    List<dynamic> params = const [],
  ]) async {
    final provider = ethereum;
    if (provider == null)
      throw StateError(
        'Không tìm thấy ví EIP-1193. Mở bằng trình duyệt có MetaMask/Core tương thích.',
      );
    _listen(provider);
    try {
      final value = await provider
          .request({'method': method, 'params': params}.jsify()! as JSObject)
          .toDart;
      return value.dartify();
    } catch (_) {
      throw StateError(
        'Ví từ chối hoặc không thực hiện được $method. Kiểm tra ví và pending transaction trước khi thử lại.',
      );
    }
  }

  @override
  void dispose() {
    final provider = _provider, listener = _listener;
    if (provider != null && listener != null) {
      provider.removeListener('accountsChanged'.toJS, listener);
      provider.removeListener('chainChanged'.toJS, listener);
    }
    _changes.close();
  }
}
