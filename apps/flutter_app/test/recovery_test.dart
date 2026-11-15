import 'package:flutter_test/flutter_test.dart';
import 'package:prepaid_guard/real/api.dart';
import 'package:prepaid_guard/real/controller.dart';
import 'package:prepaid_guard/real/wallet_port.dart';
import 'package:prepaid_guard/real/ethereum.dart';
import 'real_mode_test.dart' as f;

final replacementHash = '0x' + 'bb' * 32;
final blockHash = '0x' + 'ee' * 32;

class RecoveryApi extends f.FakeApi {
  bool expired = false;
  bool speedup = false;
  bool reorg = false;
  @override
  Future<dynamic> request(String method, String path, {Json? body}) async {
    if (expired && (path == '/api/v1/transactions' || path == '/api/v1/me')) {
      throw ApiFailure(401, 'TOKEN_EXPIRED', 'Expired');
    }
    if (path.endsWith('/replacement')) {
      return {
        'original': {'status': speedup ? 'REPLACED' : 'CANCELLED'},
        'replacement': speedup ? {'status': 'CONFIRMED'} : null,
      };
    }
    if (path.startsWith('/api/v1/transactions/')) {
      return {
        'status': reorg ? 'SUBMITTED' : (speedup ? 'REPLACED' : 'CANCELLED'),
      };
    }
    final value = await super.request(method, path, body: body);
    if (path == '/api/v1/transactions')
      return {...value as Json, 'sender_nonce': '1'};
    return value;
  }
}

class CatalogApi extends f.FakeApi {
  @override
  Future<dynamic> request(String method, String path, {Json? body}) async {
    if (path.startsWith('/api/v1/plans?')) {
      expect(path, contains('limit=20'));
      return path.contains('cursor=')
          ? {
              'items': [
                f.plan(),
                {...f.plan(), 'plan_id': '2'},
              ],
              'next_cursor': null,
            }
          : {
              'items': [f.plan()],
              'next_cursor': 'cursor +/&',
            };
    }
    return super.request(method, path, body: body);
  }
}

class ApprovalWallet extends f.FakeWallet {
  String fault = '';
  @override
  Future<dynamic> request(
    String method, [
    List<dynamic> params = const [],
  ]) async {
    if (method == 'eth_call') {
      final data = (params.first as Map)['data'] as String;
      return data == encodeAllowance(f.customer, f.vault)
          ? '0x0'
          : '0x3b9aca00';
    }
    if (method == 'eth_getTransactionByHash') {
      if (params.first == f.hash)
        return {'hash': f.hash, 'from': account, 'nonce': '0x1'};
      return {
        'hash': replacementHash,
        'from': fault == 'sender' ? f.merchant : account,
        'to': account,
        'nonce': fault == 'nonce' ? '0x2' : '0x1',
        'value': '0x0',
        'input': '0x',
        'blockNumber': '0x2',
        'blockHash': blockHash,
      };
    }
    if (method == 'eth_getTransactionReceipt') {
      if (params.first == f.hash || fault == 'pending') return null;
      return {
        'transactionHash': replacementHash,
        'from': account,
        'to': account,
        'status': '0x1',
        'blockNumber': '0x2',
        'blockHash': blockHash,
      };
    }
    if (method == 'eth_blockNumber') return fault == 'height' ? '0x1' : '0x10';
    if (method == 'eth_getBlockByNumber')
      return {'hash': fault == 'reorg' ? '0x00' : blockHash};
    return super.request(method, params);
  }
}

void main() {
  test(
    'cancelled transaction is revalidated before retry after a reorg',
    () async {
      final api = RecoveryApi()..transactionStatus = 'SUBMITTED';
      final wallet = f.FakeWallet();
      final c = await f.signedIn(api: api, wallet: wallet);
      addTearDown(c.dispose);
      await c.subscribe(f.plan());
      await c.replaceTransaction(c.pending.single, replacementHash);
      api.reorg = true;
      await expectLater(c.subscribe(f.plan()), throwsStateError);
      expect(wallet.transactions.length, 1);
      expect(c.pending.single['status'], 'SUBMITTED');
    },
  );
  test('catalog loads small pages and deduplicates cursor results', () async {
    final c = LiveController(
      api: CatalogApi(),
      wallet: f.FakeWallet(),
      store: MemoryPendingStore(),
    );
    addTearDown(c.dispose);
    await c.bootstrap();
    expect(c.plansCursor, 'cursor +/&');
    await c.loadMorePlans();
    expect(c.plans.map((p) => p['plan_id']), ['1', '2']);
    expect(c.plansCursor, isNull);
  });

  for (final speedup in [false, true]) {
    test(
      'confirmed replacement is recorded without sending another transaction: $speedup',
      () async {
        final api = RecoveryApi()
          ..transactionStatus = 'SUBMITTED'
          ..speedup = speedup;
        final wallet = f.FakeWallet(), store = MemoryPendingStore();
        final c = await f.signedIn(api: api, wallet: wallet, store: store);
        addTearDown(c.dispose);
        await c.subscribe(f.plan());
        expect(c.pending.single['sender_nonce'], '1');
        await c.replaceTransaction(c.pending.single, replacementHash);
        expect(wallet.transactions.length, 1);
        expect(
          c.pending.where((p) => p['tx_hash'] == f.hash).single['status'],
          speedup ? 'REPLACED' : 'CANCELLED',
        );
        if (speedup) expect(c.pending.first['status'], 'CONFIRMED');
        expect(store.values.values.single, contains(replacementHash));
      },
    );
  }

  test(
    'expired JWT after broadcast preserves hash and requires login immediately',
    () async {
      final api = RecoveryApi(),
          wallet = f.FakeWallet(),
          store = MemoryPendingStore();
      final c = await f.signedIn(api: api, wallet: wallet, store: store);
      addTearDown(c.dispose);
      api.expired = true;
      await c.operation(() => c.subscribe(f.plan()));
      expect(c.loggedIn, isFalse);
      expect(api.token, isNull);
      expect(wallet.transactions.length, 1);
      expect(store.values.values.single, contains(f.hash));
      api.expired = false;
      api.transactionStatus = 'SUBMITTED';
      await c.login();
      await expectLater(c.subscribe(f.plan()), throwsStateError);
      expect(wallet.transactions.length, 1);
    },
  );

  test(
    'approval cancellation with confirmed nonce proof unblocks retry',
    () async {
      final wallet = ApprovalWallet(),
          c = await f.signedIn(wallet: ApprovalWallet());
      c.dispose();
      final live = await f.signedIn(wallet: wallet);
      addTearDown(live.dispose);
      await live.subscribe(f.plan());
      expect(live.pending.single['action'], 'APPROVE');
      expect(live.pending.single['sender_nonce'], '1');
      await live.replaceTransaction(live.pending.single, replacementHash);
      expect(live.pending.single['status'], 'CANCELLED');
      await live.subscribe(f.plan());
      expect(wallet.transactions.length, 2);
    },
  );

  for (final fault in ['sender', 'nonce', 'pending', 'height', 'reorg']) {
    test(
      'approval recovery rejects $fault and keeps duplicate-send guard',
      () async {
        final wallet = ApprovalWallet()..fault = fault;
        final c = await f.signedIn(wallet: wallet);
        addTearDown(c.dispose);
        await c.subscribe(f.plan());
        await expectLater(
          c.replaceTransaction(c.pending.single, replacementHash),
          throwsStateError,
        );
        expect(c.pending.single['status'], 'SUBMITTED');
        await expectLater(c.subscribe(f.plan()), throwsStateError);
        expect(wallet.transactions.length, 1);
      },
    );
  }
}
