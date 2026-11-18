import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'wallet_port.dart';

@JS('ethereum')
external _Ethereum? get ethereum;
@JS('localStorage')
external _Storage get storage;
@JS('window')
external JSObject? get _window;

@JS('Event')
extension type _Event._(JSObject _) implements JSObject {
  external factory _Event(JSString type);
}

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

class _DiscoveredProvider {
  _DiscoveredProvider({
    required this.info,
    required this.provider,
    required this.fromEip6963,
  });

  final WalletProviderInfo info;
  final _Ethereum provider;
  final bool fromEip6963;
}

class BrowserWallet extends WalletPort {
  BrowserWallet() {
    _discoverProviders();
  }

  final _changes = StreamController<void>.broadcast();
  final List<_DiscoveredProvider> _discovered = [];
  String? _selectedId;
  _Ethereum? _provider;
  JSFunction? _listener;
  JSFunction? _announceListener;

  void _discoverProviders() {
    final win = _window;
    if (win != null) {
      try {
        final listener = ((JSAny? event) {
          _onAnnounce(event);
        }).toJS;
        _announceListener = listener;
        win.callMethod(
          'addEventListener'.toJS,
          'eip6963:announceProvider'.toJS,
          listener,
        );
        win.callMethod(
          'dispatchEvent'.toJS,
          _Event('eip6963:requestProvider'.toJS),
        );
      } catch (_) {
        /* Ignore in headless stubs without CustomEvent/EventTarget support. */
      }
    }
    _syncLegacyProviders();
  }

  void _onAnnounce(JSAny? event) {
    if (event == null || !event.isA<JSObject>()) return;
    final detail = (event as JSObject).getProperty('detail'.toJS);
    if (detail == null || !detail.isA<JSObject>()) return;
    final detailObj = detail as JSObject;
    final infoAny = detailObj.getProperty('info'.toJS);
    final providerAny = detailObj.getProperty('provider'.toJS);
    if (infoAny == null ||
        !infoAny.isA<JSObject>() ||
        providerAny == null ||
        !providerAny.isA<JSObject>()) {
      return;
    }
    final info = infoAny as JSObject;
    final providerObj = providerAny as JSObject;
    final uuid = _readString(info, 'uuid');
    final name = _readString(info, 'name');
    final rdns = _readString(info, 'rdns') ?? '';
    final id = (uuid != null && uuid.isNotEmpty)
        ? uuid
        : (rdns.isNotEmpty ? rdns : 'eip6963-${_discovered.length}');
    final label = (name != null && name.isNotEmpty)
        ? name
        : _inferLabel(providerObj, fallback: 'Ví trình duyệt');
    _addProvider(
      _DiscoveredProvider(
        info: WalletProviderInfo(id: id, name: label, rdns: rdns),
        provider: providerObj as _Ethereum,
        fromEip6963: true,
      ),
    );
  }

  void _syncLegacyProviders() {
    final root = ethereum;
    if (root == null) return;
    final rawProviders = root.getProperty('providers'.toJS);
    if (rawProviders != null && rawProviders.isA<JSArray>()) {
      final list = (rawProviders as JSArray).toDart;
      for (var i = 0; i < list.length; i++) {
        final item = list[i];
        if (item != null && item.isA<JSObject>()) {
          final obj = item as JSObject;
          _addProvider(
            _DiscoveredProvider(
              info: WalletProviderInfo(
                id: 'legacy-$i',
                name: _inferLabel(obj, fallback: 'Ví #${i + 1}'),
              ),
              provider: obj as _Ethereum,
              fromEip6963: false,
            ),
          );
        }
      }
    } else {
      _addProvider(
        _DiscoveredProvider(
          info: WalletProviderInfo(
            id: 'legacy-default',
            name: _inferLabel(root, fallback: 'Ví trình duyệt'),
          ),
          provider: root,
          fromEip6963: false,
        ),
      );
    }
  }

  void _addProvider(_DiscoveredProvider entry) {
    final sameProviderIndex = _discovered.indexWhere(
      (existing) => existing.provider == entry.provider,
    );
    if (sameProviderIndex >= 0) {
      if (entry.fromEip6963 && !_discovered[sameProviderIndex].fromEip6963) {
        final wasSelected =
            _selectedId == _discovered[sameProviderIndex].info.id;
        _discovered[sameProviderIndex] = entry;
        if (wasSelected) _selectedId = entry.info.id;
        if (_provider == null && !_changes.isClosed) _changes.add(null);
      }
      return;
    }
    final sameIdIndex = _discovered.indexWhere(
      (existing) => existing.info.id == entry.info.id,
    );
    if (sameIdIndex >= 0) {
      _discovered[sameIdIndex] = entry;
    } else {
      _discovered.add(entry);
      if (_provider == null && !_changes.isClosed) _changes.add(null);
    }
    _selectedId ??= entry.info.id;
  }

  String? _readString(JSObject obj, String key) {
    final value = obj.getProperty(key.toJS);
    return value != null && value.isA<JSString>()
        ? (value as JSString).toDart
        : null;
  }

  bool _readBool(JSObject obj, String key) {
    final value = obj.getProperty(key.toJS);
    return value != null && value.isA<JSBoolean>() && (value as JSBoolean).toDart;
  }

  String _inferLabel(JSObject provider, {required String fallback}) {
    if (_readBool(provider, 'isCoreWallet') ||
        _readBool(provider, 'isAvalanche')) {
      return 'Core';
    }
    if (_readBool(provider, 'isMetaMask')) return 'MetaMask';
    return fallback;
  }

  @override
  List<WalletProviderInfo> get providers =>
      _discovered.map((entry) => entry.info).toList(growable: false);

  @override
  String? get selectedProviderId => _selectedId;

  @override
  void selectProvider(String id) {
    final match = _discovered.where((entry) => entry.info.id == id).firstOrNull;
    if (match == null || _selectedId == id) return;
    _selectedId = id;
    _detachProviderListener();
    if (!_changes.isClosed) _changes.add(null);
  }

  _Ethereum? _activeProvider() {
    if (_discovered.isEmpty) _syncLegacyProviders();
    if (_selectedId != null) {
      final selected = _discovered
          .where((entry) => entry.info.id == _selectedId)
          .firstOrNull;
      if (selected != null) return selected.provider;
    }
    return _discovered.isNotEmpty ? _discovered.first.provider : ethereum;
  }

  void _listen(_Ethereum provider) {
    if (_provider == provider) return;
    _detachProviderListener();
    _provider = provider;
    final listener = ((JSAny? _) {
      if (!_changes.isClosed) _changes.add(null);
    }).toJS;
    _listener = listener;
    try {
      provider.on('accountsChanged'.toJS, listener);
      provider.on('chainChanged'.toJS, listener);
    } catch (_) {
      /* Ignore providers without event emitters. */
    }
  }

  void _detachProviderListener() {
    final provider = _provider, listener = _listener;
    if (provider != null && listener != null) {
      try {
        provider.removeListener('accountsChanged'.toJS, listener);
        provider.removeListener('chainChanged'.toJS, listener);
      } catch (_) {
        /* Ignore cleanup errors on stale provider handles. */
      }
    }
    _provider = null;
    _listener = null;
  }

  (int?, String?) _extractJsError(Object error) {
    try {
      final any = error as JSAny?;
      if (any != null && any.isA<JSObject>()) {
        final obj = any as JSObject;
        int? code;
        String? message;
        final rawCode = obj.getProperty('code'.toJS);
        if (rawCode != null && rawCode.isA<JSNumber>()) {
          code = (rawCode as JSNumber).toDartInt;
        }
        final rawMessage = obj.getProperty('message'.toJS);
        if (rawMessage != null && rawMessage.isA<JSString>()) {
          message = (rawMessage as JSString).toDart;
        }
        final nested =
            obj.getProperty('error'.toJS) ?? obj.getProperty('cause'.toJS);
        if (nested != null && nested.isA<JSObject>()) {
          final nestedObj = nested as JSObject;
          if (code == null) {
            final nestedCode = nestedObj.getProperty('code'.toJS);
            if (nestedCode != null && nestedCode.isA<JSNumber>()) {
              code = (nestedCode as JSNumber).toDartInt;
            }
          }
          if (message == null || message.isEmpty) {
            final nestedMsg = nestedObj.getProperty('message'.toJS);
            if (nestedMsg != null && nestedMsg.isA<JSString>()) {
              message = (nestedMsg as JSString).toDart;
            }
          }
        }
        return (code, message ?? error.toString());
      }
    } catch (_) {
      /* Fallback to Dart toString when error is not a JS interop object. */
    }
    return (null, error.toString());
  }

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<dynamic> request(
    String method, [
    List<dynamic> params = const [],
  ]) async {
    final provider = _activeProvider();
    if (provider == null) {
      throw StateError(
        'Không tìm thấy ví EIP-1193. Mở bằng trình duyệt có MetaMask/Core tương thích.',
      );
    }
    _listen(provider);
    try {
      final value = await provider
          .request({'method': method, 'params': params}.jsify()! as JSObject)
          .toDart;
      return value.dartify();
    } catch (error) {
      final (code, message) = _extractJsError(error);
      throw StateError(
        classifyWalletError(code: code, message: message, method: method),
      );
    }
  }

  @override
  void dispose() {
    _detachProviderListener();
    final win = _window, announce = _announceListener;
    if (win != null && announce != null) {
      try {
        win.callMethod(
          'removeEventListener'.toJS,
          'eip6963:announceProvider'.toJS,
          announce,
        );
      } catch (_) {
        /* Ignore cleanup errors. */
      }
    }
    _announceListener = null;
    _changes.close();
  }
}
