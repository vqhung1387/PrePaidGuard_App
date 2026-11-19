import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'api.dart';
import 'ethereum.dart';
import 'wallet.dart';

enum SubscriptionFilter {
  all('Tất cả'),
  active('Đang sử dụng', 'ACTIVE'),
  completed('Đã hoàn tất', 'COMPLETED'),
  refunded('Đã hoàn gốc', 'REFUNDED');

  const SubscriptionFilter(this.label, [this.apiValue]);
  final String label;
  final String? apiValue;
}

String formatEligibilityReasons(Object? reasons, {bool forRefund = false}) {
  if (reasons is! List || reasons.isEmpty) {
    return 'chưa đủ điều kiện';
  }
  return reasons
      .map(
        (reason) => switch (reason.toString()) {
          'TOO_EARLY' => 'chưa tới mốc mở kỳ tiếp theo',
          'REFUND_WINDOW_OPEN' =>
            'đã qua hạn check-in và chuyển sang khung hoàn gốc',
          'TERMINAL_STATE' => 'đăng ký đã kết thúc',
          'READY' =>
            forRefund
                ? 'đang trong khung check-in, chưa tới mốc hoàn gốc'
                : 'đã sẵn sàng',
          final other => other,
        },
      )
      .join(', ');
}

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
    _changes = wallet.changes.listen((_) {
      if (loggedIn) {
        invalidate('Ví hoặc network đã đổi; hãy đăng nhập lại.');
      } else {
        _emit();
      }
    });
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
  List<Json> _catalogPlans = [];
  Json? _linkedPlan;
  List<Json> drafts = [],
      memberships = [],
      merchantMemberships = [],
      issues = [],
      merchantIssues = [];
  List<Json> pending = [];
  String? plansCursor;
  bool catalogUnavailable = false;
  String? membershipsCursor, merchantMembershipsCursor, draftsCursor;
  SubscriptionFilter membershipFilter = SubscriptionFilter.all;
  SubscriptionFilter merchantMembershipFilter = SubscriptionFilter.all;
  final Map<String, List<Json>> _memoryPending = {};

  List<Json> get plans {
    final linked = _linkedPlan;
    if (linked == null) return _catalogPlans;
    return [
      linked,
      ..._catalogPlans.where((plan) => plan['plan_id'] != linked['plan_id']),
    ];
  }

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
    membershipsCursor = merchantMembershipsCursor = draftsCursor = null;
    membershipFilter = merchantMembershipFilter = SubscriptionFilter.all;
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

  Future<void> bootstrap({Uri? registration}) async {
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
    _linkedPlan = null;
    try {
      if (registration != null) await openRegistration(registration);
    } finally {
      try {
        final page = await _get('/api/v1/plans?limit=20');
        _catalogPlans = _items(page);
        plansCursor = page['next_cursor'] as String?;
        catalogUnavailable = false;
      } catch (_) {
        if (_linkedPlan == null) {
          config = null;
          rethrow;
        }
        catalogUnavailable = true;
      }
      _emit();
    }
  }

  Future<void> openRegistration(Uri link) async {
    final id = link.queryParameters['plan_id'];
    if (id == null) return;
    final chain = link.queryParameters['chain_id'];
    final vault = link.queryParameters['vault'];
    if (config == null ||
        ((chain != null || vault != null) &&
            (chain != config!['chain_id'].toString() ||
                vault?.toLowerCase() != address(config!['vault_address'])))) {
      throw const FormatException('QR đăng ký sai mạng hoặc Vault.');
    }
    final canonicalId = uint(id).toString();
    _linkedPlan = await _fetchLinkedPlan(canonicalId);
    notice =
        'Đã mở gói #$canonicalId từ QR đăng ký. Kiểm tra điều khoản trước khi ký.';
    _emit();
  }

  Future<Json> _fetchLinkedPlan(String id) async {
    final selected = await _get('/api/v1/plans/$id');
    if (selected['plan_id'] != id ||
        selected['chain_id'] != config!['chain_id'] ||
        address(selected['vault_address']) !=
            address(config!['vault_address'])) {
      throw const FormatException('Gói từ API không khớp liên kết đăng ký.');
    }
    return selected;
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
    final walletAccount = accounts.first;
    final selected = address(walletAccount);
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
      walletAccount,
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
    pending = List<Json>.from(_memoryPending[_pendingKey] ?? []);
    _mergeStoredPending();
  }

  void _mergeStoredPending() {
    final seen = pending.map((item) => item['tx_hash']).toSet();
    for (final item in _memoryPending[_pendingKey] ?? <Json>[]) {
      if (seen.add(item['tx_hash'])) pending.add(item);
    }
    try {
      for (final item in _readStoredPending(_pendingKey)) {
        if (seen.add(item['tx_hash'])) pending.add(item);
      }
    } catch (_) {
      notice =
          'Chưa đọc được giao dịch đang chờ trên thiết bị. Kiểm tra lịch sử trong ví trước khi gửi lại.';
    }
  }

  Future<void> refresh() async {
    if (config == null) return;
    final generation = _generation;
    final planPage = await _refreshWindow(
      (cursor) => _page('/api/v1/plans', limit: 20, cursor: cursor),
      idField: 'plan_id',
      loadedCount: _catalogPlans.length,
    );
    _catalogPlans = _items(planPage);
    plansCursor = planPage['next_cursor'] as String?;
    catalogUnavailable = false;
    final linked = _linkedPlan;
    if (linked != null) {
      final id = linked['plan_id'] as String;
      try {
        _linkedPlan =
            _catalogPlans.where((plan) => plan['plan_id'] == id).firstOrNull ??
            await _fetchLinkedPlan(id);
      } on ApiFailure catch (error) {
        if (error.status != 404) rethrow;
        _linkedPlan = null;
        notice = 'Gói #$id từ liên kết không còn được công bố.';
      }
    }
    if (!loggedIn || generation != _generation) {
      _emit();
      return;
    }
    final key = _pendingKey;
    await assertContext();
    final profile = await _get('/api/v1/me');
    if (!_sameSession(generation, key)) return;
    final memberPage = await _refreshWindow(
      (cursor) => _sameSession(generation, key)
          ? _membershipPage(false, membershipFilter, cursor: cursor)
          : null,
      idField: 'subscription_id',
      loadedCount: memberships.length,
    );
    if (!_sameSession(generation, key)) return;
    Json? draftPage, merchantPage;
    if (profile['is_merchant'] == true) {
      draftPage = await _refreshWindow(
        (cursor) => _sameSession(generation, key)
            ? _page('/api/v1/plan-drafts', limit: 100, cursor: cursor)
            : null,
        idField: 'id',
        loadedCount: drafts.length,
      );
      if (!_sameSession(generation, key)) return;
      merchantPage = await _refreshWindow(
        (cursor) => _sameSession(generation, key)
            ? _membershipPage(true, merchantMembershipFilter, cursor: cursor)
            : null,
        idField: 'subscription_id',
        loadedCount: merchantMemberships.length,
      );
      if (!_sameSession(generation, key)) return;
    }
    user = profile;
    _setMembershipPage(false, memberPage);
    _setMembershipPage(true, merchantPage);
    drafts = draftPage == null ? [] : _items(draftPage);
    draftsCursor = draftPage?['next_cursor'] as String?;
    _mergeStoredPending();
    await refreshPending();
    _emit();
  }

  List<Json> _itemsOrEmpty(dynamic value) => value is List
      ? value.map((v) => Map<String, dynamic>.from(v as Map)).toList()
      : [];

  Future<Json> _refreshWindow(
    Future<Json>? Function(String? cursor) fetch, {
    required String idField,
    required int loadedCount,
  }) async {
    final items = <Json>[];
    final ids = <Object?>{};
    final visited = <String>{};
    Json firstPage = const {};
    String? cursor;
    do {
      final request = fetch(cursor);
      if (request == null) break;
      final page = await request;
      if (cursor == null) firstPage = page;
      items.addAll(_items(page).where((item) => ids.add(item[idField])));
      cursor = page['next_cursor'] as String?;
    } while (items.length < loadedCount &&
        cursor != null &&
        visited.add(cursor));
    return {...firstPage, 'items': items, 'next_cursor': cursor};
  }

  Future<Json> _page(
    String path, {
    required int limit,
    String? cursor,
    String? status,
  }) {
    final query = Uri(
      queryParameters: {
        'limit': '$limit',
        if (status != null) 'status': status,
        if (cursor != null) 'cursor': cursor,
      },
    ).query;
    return _get('$path?$query');
  }

  Future<Json> _membershipPage(
    bool merchant,
    SubscriptionFilter filter, {
    String? cursor,
  }) => _page(
    merchant ? '/api/v1/merchant/subscriptions' : '/api/v1/me/subscriptions',
    limit: 100,
    cursor: cursor,
    status: filter.apiValue,
  );

  void _setMembershipPage(bool merchant, Json? page, {bool append = false}) {
    final items = page == null ? <Json>[] : _items(page);
    final cursor = page?['next_cursor'] as String?;
    final warnings = _itemsOrEmpty(page?['issues']);
    final existing = merchant ? merchantMemberships : memberships;
    if (append) {
      final seen = existing.map((item) => item['subscription_id']).toSet();
      existing.addAll(items.where((item) => seen.add(item['subscription_id'])));
    }
    if (merchant) {
      if (!append) merchantMemberships = items;
      merchantMembershipsCursor = cursor;
      merchantIssues = warnings;
    } else {
      if (!append) memberships = items;
      membershipsCursor = cursor;
      issues = warnings;
    }
  }

  Future<void> filterMemberships(
    bool merchant,
    SubscriptionFilter filter,
  ) async {
    await assertContext();
    final generation = _generation, key = _pendingKey;
    final page = await _membershipPage(merchant, filter);
    if (!_sameSession(generation, key)) return;
    if (merchant) {
      merchantMembershipFilter = filter;
    } else {
      membershipFilter = filter;
    }
    _setMembershipPage(merchant, page);
    _emit();
  }

  Future<void> loadMoreMemberships({required bool merchant}) async {
    final cursor = merchant ? merchantMembershipsCursor : membershipsCursor;
    if (cursor == null) return;
    await assertContext();
    final generation = _generation, key = _pendingKey;
    final filter = merchant ? merchantMembershipFilter : membershipFilter;
    final page = await _membershipPage(merchant, filter, cursor: cursor);
    if (!_sameSession(generation, key)) return;
    _setMembershipPage(merchant, page, append: true);
    _emit();
  }

  Future<void> loadMoreDrafts() async {
    final cursor = draftsCursor;
    if (cursor == null) return;
    await assertContext();
    final generation = _generation, key = _pendingKey;
    final page = await _page('/api/v1/plan-drafts', limit: 100, cursor: cursor);
    if (!_sameSession(generation, key)) return;
    final seen = drafts.map((draft) => draft['id']).toSet();
    drafts.addAll(_items(page).where((draft) => seen.add(draft['id'])));
    draftsCursor = page['next_cursor'] as String?;
    _emit();
  }

  Future<void> loadMorePlans() async {
    final cursor = plansCursor;
    if (cursor == null) return;
    final page = await _get(
      '/api/v1/plans?limit=20&cursor=${Uri.encodeQueryComponent(cursor)}',
    );
    final seen = _catalogPlans.map((plan) => plan['plan_id']).toSet();
    _catalogPlans.addAll(
      _items(page).where((plan) => seen.add(plan['plan_id'])),
    );
    plansCursor = page['next_cursor'] as String?;
    _emit();
  }

  Future<void> createMerchant(String name) async {
    await assertContext();
    final generation = _generation, key = _pendingKey;
    var result = 'Đã tạo hồ sơ cơ sở.';
    try {
      await _post('/api/v1/merchants', {
        'business_name': name,
        'description': '',
        'location_text': null,
      });
    } on ApiFailure catch (error) {
      if (error.status != 409 || error.code != 'MERCHANT_EXISTS') rethrow;
      result = 'Ví này đã có hồ sơ cơ sở.';
    }
    if (!_sameSession(generation, key)) return;
    user = {...?user, 'is_merchant': true};
    notice = result;
    _emit();
    try {
      await refresh();
    } on ApiFailure catch (error) {
      if (!_sameSession(generation, key)) return;
      if (error.status == 401) {
        invalidate('$result Phiên hết hạn, hãy đăng nhập lại.');
        return;
      }
      notice = '$result Chưa tải được dữ liệu mới, hãy làm mới trạng thái.';
      _emit();
    }
  }

  Future<void> publishPlan(Json terms) async {
    await publishDraft(await createPlanDraft(terms));
  }

  Future<Json> createPlanDraft(Json terms) async {
    await assertContext();
    final generation = _generation, key = _pendingKey;
    _mergeStoredPending();
    if (pending.any(
      (item) =>
          item['status'] == 'SUBMITTED' && item['action'] == 'CREATE_PLAN',
    )) {
      throw StateError(
        'Đã có giao dịch tạo gói đang chờ. Kiểm tra hash trước khi gửi lại.',
      );
    }
    final draft = await _post('/api/v1/plan-drafts', terms);
    if (!_sameSession(generation, key)) {
      throw StateError(
        'Bản nháp đã lưu cho ví ban đầu. Hãy chọn lại ví đó để tiếp tục.',
      );
    }
    drafts.insert(0, draft);
    _emit();
    return draft;
  }

  Future<void> publishDraft(Json draft) => _withWalletSigning(() async {
    final sent = await _send(
      'CREATE_PLAN',
      config!['vault_address'],
      encodeCreatePlan(draft),
      {'plan_draft_id': draft['id']},
    );
    await _refreshAfterSend(sent);
  });

  Future<void> _refreshAfterSend(Json item) async {
    _reportReverted(item);
    try {
      await refresh();
    } catch (error) {
      item['last_error'] =
          'Đã gửi giao dịch; chưa cập nhật được: ${formatUserError(error)}';
      if (error is ApiFailure &&
          error.status == 401 &&
          pending.contains(item)) {
        invalidate(
          'Phiên hết hạn; đăng nhập lại. Giao dịch đã gửi: ${item['tx_hash']}.',
        );
        return;
      }
      notice =
          'Đã gửi giao dịch ${item['tx_hash']}; chưa cập nhật được. Kiểm tra hash trước khi gửi lại.';
      _emit();
    }
    _reportReverted(item);
  }

  String _revertedMessage(Json item) =>
      'Giao dịch thất bại trên blockchain. Mã giao dịch: ${item['tx_hash']}.';

  void _reportReverted(Json item) {
    if (item['status'] == 'REVERTED') throw StateError(_revertedMessage(item));
  }

  Future<void> _noPending(String action, Json refs) async {
    _mergeStoredPending();
    final key = _pendingKey;
    for (final item
        in pending
            .where(
              (item) =>
                  item['action'] == action &&
                  jsonEncode(item['refs']) == jsonEncode(refs) &&
                  ['CANCELLED', 'REPLACED'].contains(item['status']),
            )
            .toList()) {
      final status = item['action'] == 'APPROVE'
          ? (await _replaceApproval(
              item,
              item['replacement_tx_hash'],
            ))['original']['status']
          : (await _get('/api/v1/transactions/${item['tx_hash']}'))['status'];
      if (status != item['status']) {
        item['status'] = status;
        _persistForOrigin(key, item);
        _emit();
        throw StateError(
          'Trạng thái giao dịch gốc đã thay đổi; hãy kiểm tra lại trước khi gửi.',
        );
      }
    }
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
    final memory = _memoryPending.putIfAbsent(key, () => []);
    memory.removeWhere((value) => value['tx_hash'] == item['tx_hash']);
    memory.insert(0, item);
    try {
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
      item.remove('storage_warning');
      saved.insert(0, Map<String, dynamic>.from(item));
      store.write(key, jsonEncode(saved.take(50).toList()));
    } catch (_) {
      item['storage_warning'] =
          'Không lưu được giao dịch trên thiết bị. Lưu hash và kiểm tra ví/explorer; nếu tải lại khi API lỗi, ứng dụng có thể không khôi phục được giao dịch.';
      if (loggedIn && _pendingKey == key) notice = item['storage_warning'];
    }
  }

  Future<T> _withWalletSigning<T>(Future<T> Function() action) async {
    if (!loggedIn || config == null) {
      throw StateError('Kết nối API và đăng nhập ví trước.');
    }
    final generation = _generation, key = _pendingKey;
    return store.withSigningLock(key, () async {
      if (!_sameSession(generation, key)) {
        throw StateError('Phiên ví đã đổi. Hãy kiểm tra lại trước khi ký.');
      }
      await assertContext();
      return action();
    });
  }

  Future<Json> _send(String action, String to, String data, Json refs) async {
    await assertContext();
    final originAccount = account!;
    final originKey = _pendingKey;
    final generation = _generation;
    await _noPending(action, refs);
    await assertContext();
    if (!_sameSession(generation, originKey)) {
      throw StateError('Phiên ví đã đổi. Hãy kiểm tra lại trước khi ký.');
    }
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
    if (!_sameSession(generation, originKey)) {
      if (loggedIn && _pendingKey == originKey) _mergeStoredPending();
      notice =
          'Giao dịch đã gửi: ${item['tx_hash']}. Kiểm tra ví/explorer trước khi gửi lại.';
      _emit();
      return item;
    }
    pending.insert(0, item);
    _emit();
    try {
      await _track(item, originKey: originKey, generation: generation);
    } catch (error) {
      item['last_error'] =
          'Đã gửi giao dịch; chưa theo dõi được: ${formatUserError(error)}';
      _persistForOrigin(originKey, item);
      if (error is ApiFailure &&
          error.status == 401 &&
          _sameSession(generation, originKey)) {
        invalidate(
          'Phiên hết hạn; đăng nhập lại. Giao dịch đã gửi: ${item['tx_hash']}.',
        );
      }
      _emit();
    }
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
      } else if (item['sender_nonce'] == null) {
        final tx = await wallet.request('eth_getTransactionByHash', [
          item['tx_hash'],
        ]);
        if (tx != null &&
            tx['hash'].toString().toLowerCase() == item['tx_hash'] &&
            address(tx['from']) == account) {
          item['sender_nonce'] = _rpcUint(tx['nonce']).toString();
        }
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
      item['sender_nonce'] = result['sender_nonce'];
      item['replacement_tx_hash'] = result['replacement_tx_hash'];
    }
    _persistForOrigin(key, item);
    if (_sameSession(session, key)) {
      if (item['status'] == 'REVERTED') notice = _revertedMessage(item);
      _emit();
    }
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
        item['last_error'] = formatUserError(error);
        _persistForOrigin(key, item);
      } catch (error) {
        item['last_error'] = formatUserError(error);
        _persistForOrigin(key, item);
      }
    }
    if (_sameSession(generation, key)) _emit();
  }

  BigInt _rpcUint(dynamic value) => value is String && value.startsWith('0x')
      ? uint(BigInt.parse(value.substring(2), radix: 16).toString())
      : uint(value.toString());

  Future<Json> _replaceApproval(Json item, String hash) async {
    final nonce = item['sender_nonce'];
    if (nonce == null)
      throw StateError('Chưa có nonce gốc; không thể tự xác nhận thay thế.');
    final tx = await wallet.request('eth_getTransactionByHash', [hash]);
    final receipt = await wallet.request('eth_getTransactionReceipt', [hash]);
    if (tx == null || receipt == null)
      throw StateError('Giao dịch thay thế chưa được xác nhận.');
    if (tx['hash'].toString().toLowerCase() != hash ||
        address(tx['from']) != account ||
        _rpcUint(tx['nonce']) != uint(nonce) ||
        tx['blockNumber'] != receipt['blockNumber'] ||
        receipt['transactionHash'].toString().toLowerCase() != hash ||
        address(receipt['from']) != account ||
        tx['to'].toString().toLowerCase() !=
            receipt['to'].toString().toLowerCase() ||
        !['0x0', '0x1'].contains(receipt['status'])) {
      throw StateError('Giao dịch thay thế không khớp ví/nonce/receipt.');
    }
    final height = _rpcUint(await wallet.request('eth_blockNumber'));
    final number = _rpcUint(receipt['blockNumber']);
    final confirmations = config!['confirmations'] as int? ?? 1;
    if (number + BigInt.from(confirmations - 1) > height)
      throw StateError('Chưa đủ xác nhận.');
    final block = await wallet.request('eth_getBlockByNumber', [
      receipt['blockNumber'],
      false,
    ]);
    if (block == null ||
        block['hash'] != receipt['blockHash'] ||
        tx['blockHash'] != receipt['blockHash']) {
      throw StateError('Block giao dịch đã thay đổi; hãy kiểm tra lại.');
    }
    final matches =
        tx['to'].toString().toLowerCase() ==
            config!['token']['address'].toString().toLowerCase() &&
        tx['input'].toString().toLowerCase() ==
            encodeApprove(config!['vault_address'], item['refs']['amount']);
    final cancelled =
        tx['to'].toString().toLowerCase() == account &&
        _rpcUint(tx['value']) == BigInt.zero &&
        tx['input'] == '0x' &&
        receipt['status'] == '0x1';
    return {
      'original': {'status': cancelled ? 'CANCELLED' : 'REPLACED'},
      'replacement': matches
          ? {'status': receipt['status'] == '0x1' ? 'CONFIRMED' : 'REVERTED'}
          : null,
    };
  }

  Future<void> replaceTransaction(
    Json item,
    String replacementHash, {
    String? originalSignedTransaction,
  }) async {
    await assertContext();
    final hash = replacementHash.trim().toLowerCase();
    if (!RegExp(r'^0x[0-9a-f]{64}$').hasMatch(hash) ||
        hash == item['tx_hash'] ||
        item['status'] != 'SUBMITTED') {
      throw const FormatException('Cần hash mới của giao dịch đang pending.');
    }
    final key = _pendingKey, generation = _generation;
    final raw = originalSignedTransaction?.trim();
    if (raw != null &&
        raw.isNotEmpty &&
        (raw.length > 32770 ||
            !RegExp(r'^0x(?:[0-9a-fA-F]{2})+$').hasMatch(raw))) {
      throw const FormatException(
        'Chỉ nhập raw transaction đã ký dạng 0x; không nhập seed/private key.',
      );
    }
    if (item['action'] == 'APPROVE' &&
        item['sender_nonce'] == null &&
        raw != null &&
        raw.isNotEmpty) {
      final proof = await _post('/api/v1/transactions/original-proof', {
        'tx_hash': item['tx_hash'],
        'original_signed_transaction': raw,
      });
      item['sender_nonce'] = uint(proof['sender_nonce']).toString();
      _persistForOrigin(key, item);
      await assertContext();
      if (!_sameSession(generation, key))
        throw StateError('Phiên ví đã đổi; hãy đối chiếu lại.');
    }
    final result = item['action'] == 'APPROVE'
        ? await _replaceApproval(item, hash)
        : await _post('/api/v1/transactions/${item['tx_hash']}/replacement', {
            'tx_hash': hash,
            if (raw != null && raw.isNotEmpty)
              'original_signed_transaction': raw,
          });
    if (item['action'] == 'APPROVE') {
      await assertContext();
      if (!_sameSession(generation, key))
        throw StateError('Phiên ví đã đổi; hãy đối chiếu lại.');
    }
    item['status'] = result['original']['status'];
    item['replacement_tx_hash'] = hash;
    item.remove('last_error');
    _persistForOrigin(key, item);
    Json? replacement;
    if (result['replacement'] != null) {
      replacement = {
        'tx_hash': hash,
        'action': item['action'],
        'refs': item['refs'],
        'status': result['replacement']['status'],
        'sender_nonce': item['sender_nonce'],
      };
      _persistForOrigin(key, replacement);
    }
    if (!_sameSession(generation, key)) return;
    if (replacement != null) {
      pending.removeWhere((value) => value['tx_hash'] == hash);
      pending.insert(0, replacement);
    }
    notice =
        'Đã đối chiếu giao dịch thay thế $hash. Có thể kiểm tra lại thao tác.';
    _emit();
    await _refreshAfterSend(replacement ?? item);
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

  Future<void> subscribe(Json plan) => _withWalletSigning(() async {
    await assertContext();
    await _noPending('SUBSCRIBE', {'plan_id': plan['plan_id']});
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
        throw StateError(
          'Yêu cầu cấp quyền dùng mUSDC đã thất bại. Kiểm tra trạng thái trong ví trước khi thử lại.',
        );
      }
      if (approval['status'] != 'CONFIRMED') {
        notice =
            'Đang chờ ví xác nhận quyền sử dụng mUSDC. Khi mục Giao dịch hiển thị đã xác nhận, bạn có thể tiếp tục đăng ký gói.';
        return;
      }
    }
    final sent = await _send(
      'SUBSCRIBE',
      config!['vault_address'],
      encodeId('subscribe', plan['plan_id']),
      {'plan_id': plan['plan_id']},
    );
    await _refreshAfterSend(sent);
  });

  Future<Json> eligibility(String id) =>
      _get('/api/v1/subscriptions/$id/eligibility');
  Future<Json> detail(String id) => _get('/api/v1/subscriptions/$id');
  Future<(List<Json>, String?)> events(String id, {String? cursor}) async {
    await assertContext();
    final generation = _generation, key = _pendingKey;
    final page = await _page(
      '/api/v1/subscriptions/$id/events',
      limit: 100,
      cursor: cursor,
    );
    if (!_sameSession(generation, key)) {
      throw StateError('Phiên ví đã thay đổi. Mở lại chi tiết đăng ký.');
    }
    return (_items(page), page['next_cursor'] as String?);
  }

  int _chainTime(Json sub, Json eligible) {
    if (sub['chain_id'] != config!['chain_id'] ||
        address(sub['vault_address']) != address(config!['vault_address'])) {
      throw StateError('Subscription sai deployment.');
    }
    final sync = eligible['sync'];
    if (sync is! Map || sync['source'] != 'LIVE') {
      throw StateError('Không có thời gian blockchain LIVE.');
    }
    DateTime? parse(dynamic value) {
      if (value is! String) return null;
      final match = RegExp(
        r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d+)?(Z|[+-](\d{2}):(\d{2}))$',
      ).firstMatch(value);
      if (match == null) return null;
      int part(int i) => int.parse(match.group(i)!);
      final year = part(1), month = part(2), day = part(3);
      final hour = part(4), minute = part(5), second = part(6);
      if (month < 1 ||
          month > 12 ||
          day < 1 ||
          hour > 23 ||
          minute > 59 ||
          second > 59 ||
          (match.group(8) != null && (part(8) > 23 || part(9) > 59))) {
        return null;
      }
      final date = DateTime.utc(year, month, day);
      if (date.year != year || date.month != month || date.day != day)
        return null;
      return DateTime.tryParse(value)?.toUtc();
    }

    final block = parse(sync['block_timestamp']);
    if (block == null) {
      throw StateError('Thời gian blockchain không hợp lệ.');
    }
    final seconds = block.millisecondsSinceEpoch ~/ 1000;
    if (seconds < 0 || seconds > 253402300799) {
      throw StateError('Thời gian blockchain ngoài miền được hỗ trợ.');
    }
    return seconds;
  }

  Future<String> createCheckIn(String id) async {
    await assertContext();
    final sub = await detail(id);
    if (address(sub['subscriber_address']) != account)
      throw StateError('Chỉ subscriber ký mã của mình.');
    final eligible = await eligibility(id);
    if (eligible['can_check_in'] != true)
      throw StateError(
        'Chưa được check-in: ${formatEligibilityReasons(eligible['reasons'])}',
      );
    final message = <String, dynamic>{
      'subscriptionId': id,
      'merchant': sub['merchant_address'],
      'periodIndex': eligible['next_period_index'],
      'nonce': eligible['nonce'],
      'deadline': (_chainTime(sub, eligible) + 900).toString(),
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

  String? validateQrLocally(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return 'Dán JSON mã QR check-in của hội viên.';
    if (value.contains('\u0000')) {
      return 'Dữ liệu không hợp lệ (chứa ký tự NUL).';
    }
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return 'Đây là liên kết web / QR đăng ký gói, không phải mã QR check-in ký số của hội viên.';
    }
    if (config == null) return 'Kết nối API trước khi kiểm tra QR.';
    try {
      final qr = parseQr(value, config!);
      final message = qr['message'] as Map<String, dynamic>;
      if (loggedIn && address(message['merchant']) != account) {
        return 'QR không dành cho ví cơ sở đang đăng nhập.';
      }
      return null;
    } on FormatException catch (error) {
      return error.message;
    } catch (_) {
      return 'Payload QR không đúng định dạng JSON check-in.';
    }
  }

  Future<
    ({
      Json qr,
      Json message,
      Json sub,
      Json eligible,
      BigInt deadline,
      String? expiredError,
      String? eligibilityError,
    })
  >
  _inspectQr(String payload) async {
    await assertContext();
    final qr = parseQr(payload, config!);
    final message = Map<String, dynamic>.from(qr['message'] as Map);
    if (address(message['merchant']) != account) {
      throw StateError('QR không dành cho ví merchant này.');
    }
    final deadline = uint(message['deadline']);
    final sub = await detail(message['subscriptionId']);
    final eligible = await eligibility(message['subscriptionId']);
    final chainTime = _chainTime(sub, eligible);
    final domain = typedData(config!, message)['domain'] as Json;
    if (recoverCheckIn(domain, message, qr['signature']) !=
        address(sub['subscriber_address'])) {
      throw StateError('Chữ ký QR sai subscriber.');
    }
    final expiredError =
        deadline < BigInt.from(chainTime) ||
            deadline > BigInt.from(chainTime + 900)
        ? 'QR hết hạn hoặc deadline quá xa.'
        : null;
    final eligibilityError =
        eligible['can_check_in'] != true ||
            eligible['nonce'] != message['nonce'] ||
            eligible['next_period_index'] != message['periodIndex']
        ? 'QR đã dùng, sai kỳ hoặc chưa đủ điều kiện.'
        : null;
    return (
      qr: qr,
      message: message,
      sub: sub,
      eligible: eligible,
      deadline: deadline,
      expiredError: expiredError,
      eligibilityError: eligibilityError,
    );
  }

  Future<Json> previewCheckInQr(String payload) async {
    final inspected = await _inspectQr(payload);
    final sub = inspected.sub;
    final message = inspected.message;
    final planId = sub['plan_id']?.toString();
    final matchingPlan = plans
        .where((plan) => plan['plan_id']?.toString() == planId)
        .firstOrNull;
    final totalPeriods = sub['total_periods'] is int
        ? sub['total_periods'] as int
        : int.tryParse(sub['total_periods']?.toString() ?? '') ?? 1;
    final initialPrincipal = BigInt.tryParse(
      sub['initial_principal']?.toString() ?? '',
    );
    final releaseAmount =
        matchingPlan?['price_per_period']?.toString() ??
        (initialPrincipal != null && totalPeriods > 0
            ? (initialPrincipal ~/ BigInt.from(totalPeriods)).toString()
            : null);
    final warning =
        inspected.expiredError ??
        (inspected.eligibilityError == null
            ? null
            : '${inspected.eligibilityError} (${formatEligibilityReasons(inspected.eligible['reasons'])})');
    return {
      'subscription_id':
          sub['subscription_id']?.toString() ?? message['subscriptionId'],
      'plan_id': planId ?? '—',
      'subscriber_address': sub['subscriber_address'],
      'period_index': message['periodIndex'],
      'total_periods': sub['total_periods'] ?? '?',
      'nonce': message['nonce'],
      'release_amount': releaseAmount,
      'remaining_principal': sub['remaining_principal'],
      'deadline_iso': DateTime.fromMillisecondsSinceEpoch(
        inspected.deadline.toInt() * 1000,
        isUtc: true,
      ).toIso8601String(),
      'ready': warning == null,
      'warning': warning,
    };
  }

  Future<void> confirmQr(String payload) => _withWalletSigning(() async {
    final inspected = await _inspectQr(payload);
    if (inspected.expiredError != null) {
      throw StateError(inspected.expiredError!);
    }
    if (inspected.eligibilityError != null) {
      throw StateError(inspected.eligibilityError!);
    }
    final message = inspected.message;
    final sent = await _send(
      'CHECK_IN',
      config!['vault_address'],
      encodeCheckIn(message, inspected.qr['signature']),
      {'subscription_id': message['subscriptionId']},
    );
    await _refreshAfterSend(sent);
  });

  Future<void> refund(String id) => _withWalletSigning(() async {
    await assertContext();
    final sub = await detail(id);
    if (address(sub['subscriber_address']) != account)
      throw StateError('Chỉ chủ gói được refund.');
    final eligible = await eligibility(id);
    if (eligible['can_refund'] != true)
      throw StateError(
        'Chưa đủ điều kiện refund: ${formatEligibilityReasons(eligible['reasons'], forRefund: true)}',
      );
    final sent = await _send(
      'REFUND',
      config!['vault_address'],
      encodeId('refund', id),
      {'subscription_id': id},
    );
    await _refreshAfterSend(sent);
  });

  @override
  void dispose() {
    _disposed = true;
    _changes.cancel();
    wallet.dispose();
    api.close();
    super.dispose();
  }
}
