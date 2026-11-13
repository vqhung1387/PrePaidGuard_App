import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'api.dart';
import 'ethereum.dart';
import 'wallet.dart';

class LiveController extends ChangeNotifier {
  LiveController({
    required this.api,
    required this.wallet,
    required this.store,
    int Function()? nowSeconds,
    this.expectedChainId = const int.fromEnvironment(
      'CHAIN_ID',
      defaultValue: 43113,
    ),
    this.expectedVault = const String.fromEnvironment('VAULT_ADDRESS'),
    this.expectedDeployment = const String.fromEnvironment('DEPLOYMENT_ID'),
  }) : nowSeconds =
           nowSeconds ??
           (() => DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000) {
    _changes = wallet.changes.listen(
      (_) => invalidate('Ví hoặc network đã đổi; hãy đăng nhập lại.'),
    );
  }
  final ApiPort api;
  final WalletPort wallet;
  final PendingStore store;
  final int Function() nowSeconds;
  final int expectedChainId;
  final String expectedVault, expectedDeployment;
  late final StreamSubscription<void> _changes;
  Json? config, user;
  String? account;
  String notice = '';
  bool busy = false, _disposed = false;
  int _generation = 0;
  List<Json> plans = [],
      drafts = [],
      memberships = [],
      merchantMemberships = [],
      issues = [],
      merchantIssues = [];
  List<Json> pending = [];

  bool get loggedIn => account != null && api.token != null;
  bool get isMerchant => user?['is_merchant'] == true;
  String get _pendingKey =>
      'prepaidguard.pending.${config!['deployment_id']}.$account';
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  void invalidate(String message) {
    _generation++;
    account = null;
    api.token = null;
    user = null;
    memberships = [];
    merchantMemberships = [];
    drafts = [];
    pending = [];
    issues = [];
    merchantIssues = [];
    notice = message;
    _emit();
  }

  Future<T> operation<T>(Future<T> Function() action) async {
    if (busy) throw StateError('Đang có thao tác chờ xử lý.');
    busy = true;
    notice = '';
    _emit();
    try {
      return await action();
    } on ApiFailure catch (error) {
      if (error.status == 401)
        invalidate('Phiên hết hạn; ký SIWE để đăng nhập lại.');
      rethrow;
    } finally {
      busy = false;
      _emit();
    }
  }

  Future<Json> _get(String path) async =>
      Map<String, dynamic>.from(await api.request('GET', path) as Map);
  Future<Json> _post(String path, Json body) async => Map<String, dynamic>.from(
    await api.request('POST', path, body: body) as Map,
  );
  List<Json> _items(Json page) => (page['items'] as List)
      .map((item) => Map<String, dynamic>.from(item as Map))
      .toList();

  Future<void> bootstrap() async {
    final value = await _get('/api/v1/config');
    if (value['chain_id'] != expectedChainId ||
        value['token'] is! Map ||
        value['token']['decimals'] != 6 ||
        value['supported_wallet_kind'] != 'EOA' ||
        value['abi_version'] != 'prepaidguard-1' ||
        !['MOCK', 'DISABLED'].contains(value['yield_mode'])) {
      throw StateError(
        'Network/token/ABI không tương thích client. Kiểm tra CHAIN_ID và deployment.',
      );
    }
    address(value['vault_address']);
    address(value['token']['address']);
    if (expectedVault.isNotEmpty &&
            address(expectedVault) != address(value['vault_address']) ||
        expectedDeployment.isNotEmpty &&
            expectedDeployment != value['deployment_id']) {
      throw StateError(
        'Deployment không khớp bundle đã pin; khóa gửi giao dịch.',
      );
    }
    config = value;
    plans = _items(await _get('/api/v1/plans?limit=100'));
    _emit();
  }

  Future<void> openRegistration(Uri link) async {
    final id = link.queryParameters['plan_id'];
    if (id == null) return;
    if (config == null ||
        link.queryParameters['chain_id'] != config!['chain_id'].toString() ||
        address(link.queryParameters['vault']) !=
            address(config!['vault_address'])) {
      throw const FormatException('QR đăng ký sai network hoặc Vault.');
    }
    final canonicalId = uint(id).toString();
    final selected = await _get('/api/v1/plans/$canonicalId');
    if (selected['plan_id'] != canonicalId ||
        selected['chain_id'] != config!['chain_id'] ||
        address(selected['vault_address']) !=
            address(config!['vault_address'])) {
      throw const FormatException('Plan từ API không khớp QR đăng ký.');
    }
    plans.removeWhere((plan) => plan['plan_id'] == canonicalId);
    plans.insert(0, selected);
    notice =
        'Đã mở gói #$canonicalId từ QR đăng ký. Kiểm tra điều khoản trước khi ký.';
    _emit();
  }

  int _chain(dynamic value) => value is int
      ? value
      : int.parse((value as String).replaceFirst('0x', ''), radix: 16);
  Future<void> assertContext() async {
    if (!loggedIn || config == null)
      throw StateError('Kết nối API và đăng nhập ví trước.');
    final accounts = await wallet.request('eth_accounts') as List;
    final chain = _chain(await wallet.request('eth_chainId'));
    if (accounts.isEmpty ||
        address(accounts.first) != account ||
        chain != config!['chain_id']) {
      invalidate('Ví hoặc network đã đổi; hãy đăng nhập lại.');
      throw StateError(notice);
    }
  }

  Future<void> login() async {
    if (config == null) throw StateError('Kết nối API trước.');
    final accounts = await wallet.request('eth_requestAccounts') as List;
    if (accounts.isEmpty) throw StateError('Ví chưa cấp tài khoản.');
    final selected = address(accounts.first);
    final chain = _chain(await wallet.request('eth_chainId'));
    if (chain != config!['chain_id'])
      throw StateError(
        'Đổi ví sang chain ${config!['chain_id']} trước khi đăng nhập.',
      );
    final challenge = await _post('/api/v1/auth/challenge', {
      'wallet_address': selected,
      'chain_id': chain,
    });
    final message = challenge['message'] as String;
    final signature = await wallet.request('personal_sign', [
      '0x${utf8.encode(message).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}',
      selected,
    ]);
    final result = await _post('/api/v1/auth/verify', {
      'challenge_id': challenge['challenge_id'],
      'signature': signature,
    });
    if (address(result['user']['wallet_address']) != selected)
      throw StateError('Phiên API trả sai ví.');
    api.token = result['access_token'] as String;
    _generation++;
    account = selected;
    user = Map<String, dynamic>.from(result['user'] as Map);
    await assertContext();
    _restorePending();
    await refresh();
  }

  Future<void> logout() async {
    try {
      if (api.token != null) await api.request('POST', '/api/v1/auth/logout');
    } finally {
      invalidate('Đã đăng xuất. Giao dịch đã gửi vẫn tồn tại trên blockchain.');
    }
  }

  List<Json> _readStoredPending(String key) {
    final raw = store.read(key);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list
        .take(50)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .where(
          (item) =>
              RegExp(
                r'^0x[0-9a-fA-F]{64}$',
              ).hasMatch(item['tx_hash'].toString()) &&
              [
                'APPROVE',
                'CREATE_PLAN',
                'SUBSCRIBE',
                'CHECK_IN',
                'REFUND',
              ].contains(item['action']),
        )
        .toList();
  }

  void _restorePending() {
    try {
      pending = _readStoredPending(_pendingKey);
    } catch (_) {
      notice =
          'Không đọc được pending cache. Kiểm tra lịch sử ví/explorer trước khi gửi lại.';
    }
  }

  void _mergeStoredPending() {
    try {
      final stored = _readStoredPending(_pendingKey);
      final seen = pending.map((item) => item['tx_hash']).toSet();
      for (final item in stored) {
        if (seen.add(item['tx_hash'])) pending.add(item);
      }
      if (pending.length > 50) pending = pending.take(50).toList();
    } catch (_) {
      /* Preserve in-memory pending entries if cache read fails. */
    }
  }

  Future<void> refresh() async {
    if (config == null) return;
    plans = _items(await _get('/api/v1/plans?limit=100'));
    if (!loggedIn) {
      _emit();
      return;
    }
    await assertContext();
    user = await _get('/api/v1/me');
    final page = await _get('/api/v1/me/subscriptions?limit=100');
    memberships = _items(page);
    issues = _itemsOrEmpty(page['issues']);
    if (isMerchant) {
      drafts = _items(await _get('/api/v1/plan-drafts?limit=100'));
      final merchantPage = await _get(
        '/api/v1/merchant/subscriptions?limit=100',
      );
      merchantMemberships = _items(merchantPage);
      merchantIssues = _itemsOrEmpty(merchantPage['issues']);
    } else {
      drafts = [];
      merchantMemberships = [];
      merchantIssues = [];
    }
    _mergeStoredPending();
    await refreshPending();
    _emit();
  }

  List<Json> _itemsOrEmpty(dynamic value) => value is List
      ? value.map((v) => Map<String, dynamic>.from(v as Map)).toList()
      : [];
  Future<void> createMerchant(String name) async {
    await assertContext();
    await _post('/api/v1/merchants', {
      'business_name': name,
      'description': '',
      'location_text': null,
    });
    await refresh();
  }

  Future<void> publishPlan(Json terms) async {
    await assertContext();
    final draft = await _post('/api/v1/plan-drafts', terms);
    drafts.insert(0, draft);
    _emit();
    await publishDraft(draft);
  }

  Future<void> publishDraft(Json draft) async {
    await _send(
      'CREATE_PLAN',
      config!['vault_address'],
      encodeCreatePlan(draft),
      {'plan_draft_id': draft['id']},
    );
    await refresh();
  }

  Future<void> _noPending(String action, Json refs) async {
    if (pending.any(
      (item) =>
          item['status'] == 'SUBMITTED' &&
          item['action'] == action &&
          jsonEncode(item['refs']) == jsonEncode(refs),
    )) {
      throw StateError(
        'Đã có giao dịch cùng thao tác đang chờ. Hãy refresh/đối chiếu hash trước khi gửi lại.',
      );
    }
  }

  bool _sameSession(int generation, String key) =>
      !_disposed && _generation == generation && loggedIn && _pendingKey == key;

  void _persistForOrigin(String key, Json item) {
    // Only transaction metadata is persisted; never JWT/private keys.
    List<Json> saved = [];
    final raw = store.read(key);
    if (raw != null) {
      try {
        saved = (jsonDecode(raw) as List)
            .map((value) => Map<String, dynamic>.from(value as Map))
            .toList();
      } catch (_) {
        /* Preserve the new broadcast hash even if old cache is corrupt. */
      }
    }
    saved.removeWhere((value) => value['tx_hash'] == item['tx_hash']);
    saved.insert(0, Map<String, dynamic>.from(item));
    store.write(key, jsonEncode(saved.take(50).toList()));
  }

  Future<Json> _send(String action, String to, String data, Json refs) async {
    await assertContext();
    await _noPending(action, refs);
    final originAccount = account!;
    final originKey = _pendingKey;
    final generation = _generation;
    final hash = await wallet.request('eth_sendTransaction', [
      {'from': originAccount, 'to': address(to), 'data': data, 'value': '0x0'},
    ]);
    if (hash is! String || !RegExp(r'^0x[0-9a-fA-F]{64}$').hasMatch(hash)) {
      throw StateError('Ví không trả tx hash hợp lệ. Kiểm tra ví trước retry.');
    }
    final item = <String, dynamic>{
      'tx_hash': hash.toLowerCase(),
      'action': action,
      'refs': refs,
      'status': 'SUBMITTED',
    };
    // A wallet/network event can invalidate the session while its prompt is open.
    // The hash still belongs to the initiating wallet/deployment, not the new UI.
    _persistForOrigin(originKey, item);
    if (!_sameSession(generation, originKey)) return item;
    pending.insert(0, item);
    _emit();
    await _track(item, originKey: originKey, generation: generation);
    return item;
  }

  Future<void> _track(Json item, {String? originKey, int? generation}) async {
    final key = originKey ?? _pendingKey;
    final session = generation ?? _generation;
    if (!_sameSession(session, key)) return;
    if (item['action'] == 'APPROVE') {
      final receipt = await wallet.request('eth_getTransactionReceipt', [
        item['tx_hash'],
      ]);
      if (receipt != null) {
        item['status'] = receipt['status'] == '0x1' ? 'CONFIRMED' : 'REVERTED';
      }
    } else {
      final result = await _post('/api/v1/transactions', {
        'tx_hash': item['tx_hash'],
        'action': item['action'],
        ...Map<String, dynamic>.from(item['refs'] as Map),
      });
      item['status'] = result['status'];
      item.remove('last_error');
      item['explorer_url'] = result['explorer_url'];
    }
    _persistForOrigin(key, item);
    if (_sameSession(session, key)) _emit();
  }

  Future<void> refreshPending() async {
    if (!loggedIn) return;
    final key = _pendingKey, generation = _generation;
    for (final item
        in pending.where((item) => item['status'] == 'SUBMITTED').toList()) {
      if (!_sameSession(generation, key)) break;
      try {
        await _track(item, originKey: key, generation: generation);
      } on ApiFailure catch (error) {
        if (error.status == 401) rethrow;
        item['last_error'] = error.toString();
        _persistForOrigin(key, item);
      } catch (error) {
        item['last_error'] = error.toString();
        _persistForOrigin(key, item);
      }
    }
    if (_sameSession(generation, key)) _emit();
  }

  Future<BigInt> _tokenRead(String data) async {
    final result =
        await wallet.request('eth_call', [
              {'to': config!['token']['address'], 'data': data},
              'latest',
            ])
            as String;
    return BigInt.parse(result.replaceFirst('0x', ''), radix: 16);
  }

  Future<void> subscribe(Json plan) async {
    await assertContext();
    final amount = uint(plan['total_price']);
    if (await _tokenRead(encodeBalance(account!)) < amount)
      throw StateError('Không đủ mUSDC thử nghiệm.');
    if (await _tokenRead(encodeAllowance(account!, config!['vault_address'])) <
        amount) {
      final approval = await _send(
        'APPROVE',
        config!['token']['address'],
        encodeApprove(config!['vault_address'], amount.toString()),
        {'amount': amount.toString()},
      );
      if (approval['status'] == 'REVERTED') {
        throw StateError('Approve đã revert; kiểm tra ví và token.');
      }
      if (approval['status'] != 'CONFIRMED') {
        notice = 'Approve đang chờ. Refresh, rồi bấm đăng ký khi đã confirmed.';
        return;
      }
    }
    await _send(
      'SUBSCRIBE',
      config!['vault_address'],
      encodeId('subscribe', plan['plan_id']),
      {'plan_id': plan['plan_id']},
    );
    await refresh();
  }

  Future<Json> eligibility(String id) =>
      _get('/api/v1/subscriptions/$id/eligibility');
  Future<Json> detail(String id) => _get('/api/v1/subscriptions/$id');
  Future<List<Json>> events(String id) async =>
      _items(await _get('/api/v1/subscriptions/$id/events?limit=100'));
  Future<String> createCheckIn(String id) async {
    await assertContext();
    final sub = await detail(id);
    if (address(sub['subscriber_address']) != account)
      throw StateError('Chỉ subscriber ký mã của mình.');
    final eligible = await eligibility(id);
    if (eligible['can_check_in'] != true)
      throw StateError('Chưa được check-in: ${eligible['reasons']}');
    final message = <String, dynamic>{
      'subscriptionId': id,
      'merchant': sub['merchant_address'],
      'periodIndex': eligible['next_period_index'],
      'nonce': eligible['nonce'],
      'deadline': (nowSeconds() + 900).toString(),
    };
    final typed = typedData(config!, message);
    final signature =
        await wallet.request('eth_signTypedData_v4', [
              account,
              jsonEncode(typed),
            ])
            as String;
    if (recoverCheckIn(
          Map<String, dynamic>.from(typed['domain']),
          message,
          signature,
        ) !=
        account)
      throw StateError('Ví trả chữ ký không khớp subscriber.');
    return jsonEncode({
      'version': 1,
      'kind': 'PREPAIDGUARD_CHECK_IN',
      'chainId': config!['chain_id'],
      'verifyingContract': config!['vault_address'],
      'message': message,
      'signature': signature,
    });
  }

  Future<void> confirmQr(String payload) async {
    await assertContext();
    final qr = parseQr(payload, config!);
    final message = Map<String, dynamic>.from(qr['message'] as Map);
    if (address(message['merchant']) != account)
      throw StateError('QR không dành cho ví merchant này.');
    final deadline = uint(message['deadline']);
    if (deadline < BigInt.from(nowSeconds()) ||
        deadline > BigInt.from(nowSeconds() + 900))
      throw StateError('QR hết hạn hoặc deadline quá xa.');
    final sub = await detail(message['subscriptionId']);
    final eligible = await eligibility(message['subscriptionId']);
    if (eligible['can_check_in'] != true ||
        eligible['nonce'] != message['nonce'] ||
        eligible['next_period_index'] != message['periodIndex']) {
      throw StateError('QR đã dùng, sai kỳ hoặc chưa đủ điều kiện.');
    }
    final domain = typedData(config!, message)['domain'] as Json;
    if (recoverCheckIn(domain, message, qr['signature']) !=
        address(sub['subscriber_address']))
      throw StateError('Chữ ký QR sai subscriber.');
    await _send(
      'CHECK_IN',
      config!['vault_address'],
      encodeCheckIn(message, qr['signature']),
      {'subscription_id': message['subscriptionId']},
    );
    await refresh();
  }

  Future<void> refund(String id) async {
    await assertContext();
    final sub = await detail(id);
    if (address(sub['subscriber_address']) != account)
      throw StateError('Chỉ chủ gói được refund.');
    final eligible = await eligibility(id);
    if (eligible['can_refund'] != true)
      throw StateError('Chưa đủ điều kiện refund: ${eligible['reasons']}');
    await _send('REFUND', config!['vault_address'], encodeId('refund', id), {
      'subscription_id': id,
    });
    await refresh();
  }

  @override
  void dispose() {
    _disposed = true;
    _changes.cancel();
    wallet.dispose();
    api.close();
    super.dispose();
  }
}
