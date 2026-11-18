import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:prepaid_guard/real/api.dart';
import 'package:prepaid_guard/real/controller.dart';
import 'package:prepaid_guard/real/wallet_port.dart';

import 'real_mode_test.dart' as f;

class PartialFailureApi extends f.FakeApi {
  bool created = false;
  int creations = 0;

  @override
  Future<dynamic> request(String method, String path, {Json? body}) async {
    if (method == 'POST' && path == '/api/v1/merchants') {
      creations++;
      if (created) {
        throw ApiFailure(409, 'MERCHANT_EXISTS', 'Ví này đã có hồ sơ cơ sở.');
      }
      created = true;
      return {'business_name': body!['business_name']};
    }
    if (created && path.startsWith('/api/v1/plans?')) {
      throw ApiFailure(503, 'RPC_UNAVAILABLE', 'Chưa đọc được blockchain.');
    }
    return super.request(method, path, body: body);
  }
}

class DraftResponseApi extends f.FakeApi {
  final response = Completer<Json>();
  final requested = Completer<void>();
  bool catalogUnavailable = false;

  @override
  Future<dynamic> request(String method, String path, {Json? body}) async {
    if (method == 'POST' && path == '/api/v1/plan-drafts') {
      requested.complete();
      return response.future;
    }
    if (catalogUnavailable && path.startsWith('/api/v1/plans?')) {
      throw ApiFailure(503, 'RPC_UNAVAILABLE', 'Chưa đọc được blockchain.');
    }
    return super.request(method, path, body: body);
  }
}

class CatalogApi extends f.FakeApi {
  final selected = <String, dynamic>{
    ...f.plan(),
    'plan_id': '99',
    'title': 'Linked plan',
  };
  bool linkedIsPublished = true;

  @override
  Future<dynamic> request(String method, String path, {Json? body}) async {
    if (path == '/api/v1/plans/99') {
      if (!linkedIsPublished) {
        throw ApiFailure(404, 'NOT_FOUND', 'Gói không còn được công bố.');
      }
      return selected;
    }
    if (path == '/api/v1/plans?limit=20') {
      return {
        'items': [f.plan()],
        'next_cursor': 'next',
      };
    }
    if (path == '/api/v1/plans?limit=20&cursor=next') {
      return {
        'items': [
          {...f.plan(), 'plan_id': '2'},
        ],
        'next_cursor': 'last',
      };
    }
    if (path == '/api/v1/plans?limit=20&cursor=last') {
      return {
        'items': [selected],
        'next_cursor': null,
      };
    }
    return super.request(method, path, body: body);
  }
}

Future<void> waitForPrompt(f.FakeWallet wallet) async {
  for (var tick = 0; tick < 100 && wallet.transactions.isEmpty; tick++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  expect(wallet.transactions, hasLength(1));
}

void main() {
  test('signing in one tab blocks another tab for the same wallet', () async {
    final sharedStore = MemoryPendingStore();
    final walletA = f.FakeWallet()..sendGate = Completer<dynamic>();
    final walletB = f.FakeWallet()..sendGate = Completer<dynamic>();
    final first = await f.signedIn(
      wallet: walletA,
      api: f.FakeApi()..transactionStatus = 'SUBMITTED',
      store: sharedStore,
    );
    final second = await f.signedIn(wallet: walletB, store: sharedStore);
    addTearDown(first.dispose);
    addTearDown(second.dispose);

    final a = first.operation(() => first.subscribe(f.plan()));
    await waitForPrompt(walletA);
    await expectLater(
      second.operation(() => second.subscribe(f.plan())),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('tab khác'),
        ),
      ),
    );
    expect(walletB.transactions, isEmpty);
    expect(sharedStore.values, isEmpty);
    walletA.sendGate!.complete(f.hash);
    await a;
    await expectLater(
      second.operation(() => second.subscribe(f.plan())),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('đang chờ'),
        ),
      ),
    );
    expect(walletB.transactions, isEmpty);
  });

  test(
    'keeps saved merchant status when reloading the catalog fails',
    () async {
      final api = PartialFailureApi();
      final c = await f.signedIn(api: api);
      addTearDown(c.dispose);
      await c.createMerchant('Demo gym');
      expect(api.created, isTrue);
      expect(api.creations, 1);
      expect(c.isMerchant, isTrue);
      expect(c.notice, contains('Đã tạo hồ sơ cơ sở.'));
      expect(c.notice, contains('Chưa tải được dữ liệu mới'));
      await c.createMerchant('Demo gym');
      expect(c.isMerchant, isTrue);
      expect(c.notice, contains('đã có hồ sơ cơ sở'));
    },
  );

  test('discards delayed drafts after switching to another wallet', () async {
    final api = DraftResponseApi()..merchantProfile = true;
    final wallet = f.FakeWallet();
    final c = await f.signedIn(wallet: wallet, api: api);
    addTearDown(c.dispose);
    final inFlight = c.createPlanDraft(f.plan());
    await api.requested.future;
    wallet.account = f.merchant;
    wallet.stream.add(null);
    await Future<void>.delayed(Duration.zero);
    expect(c.loggedIn, isFalse);
    expect(c.drafts, isEmpty);
    final rejected = expectLater(inFlight, throwsStateError);
    api.response.complete({'id': 'previous-wallet-draft', 'state': 'DRAFT'});
    await rejected;
    expect(c.drafts, isEmpty);
    api.owner = f.merchant;
    api.catalogUnavailable = true;
    await expectLater(c.login(), throwsA(isA<ApiFailure>()));
    expect(c.account, f.merchant);
    expect(c.isMerchant, isTrue);
    expect(c.drafts, isEmpty);
  });

  test('keeps linked plan when refreshing or paginating the catalog', () async {
    final api = CatalogApi();
    final c = LiveController(
      api: api,
      wallet: f.FakeWallet(),
      store: MemoryPendingStore(),
    );
    addTearDown(c.dispose);
    await c.bootstrap();
    await c.openRegistration(
      Uri.parse('https://app.example/?real=1&plan_id=99'),
    );
    expect(c.plans.first['plan_id'], '99');
    await c.refresh();
    expect(c.plans.map((plan) => plan['plan_id']), ['99', '1']);
    expect(c.notice, contains('gói #99'));
    await c.loadMorePlans();
    await c.loadMorePlans();
    expect(c.plans.map((plan) => plan['plan_id']), ['99', '1', '2']);
    await c.bootstrap();
    await c.openRegistration(
      Uri.parse('https://app.example/?real=1&plan_id=99'),
    );
    api.linkedIsPublished = false;
    await c.refresh();
    expect(c.plans.map((plan) => plan['plan_id']), ['1']);
    expect(c.notice, contains('không còn được công bố'));
  });

  test(
    'immediately reports reverted transaction and retains the hash',
    () async {
      final api = f.FakeApi()..transactionStatus = 'REVERTED';
      final c = await f.signedIn(api: api);
      addTearDown(c.dispose);
      await expectLater(
        c.operation(() => c.refund('1')),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains(f.hash),
          ),
        ),
      );
      expect(c.pending.single['status'], 'REVERTED');
      expect(c.notice, contains('Giao dịch thất bại'));
    },
  );
}
