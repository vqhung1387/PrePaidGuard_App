import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:web3dart/web3dart.dart' as eth;
import 'package:wallet/wallet.dart' as wallets;
import 'package:prepaid_guard/real/api.dart';
import 'package:prepaid_guard/real/controller.dart';
import 'package:prepaid_guard/real/ethereum.dart';
import 'package:prepaid_guard/real/wallet_port.dart';

const customer = '0x2222222222222222222222222222222222222222';
const merchant = '0x5555555555555555555555555555555555555555';
const vault = '0x4444444444444444444444444444444444444444';
const token = '0x3333333333333333333333333333333333333333';
final hash = '0x${'aa' * 32}';

Json configuration() => {
  'chain_id': 43113,
  'token': {'address': token, 'decimals': 6},
  'vault_address': vault,
  'supported_wallet_kind': 'EOA',
  'abi_version': 'prepaidguard-1',
  'yield_mode': 'MOCK',
  'deployment_id': 'fixture',
};
Json plan() => {
  'plan_id': '1',
  'chain_id': 43113,
  'vault_address': vault,
  'title': 'Demo',
  'total_price': '100000000',
  'price_per_period': '50000000',
  'total_periods': 2,
  'period_duration_seconds': 10,
  'grace_period_seconds': 20,
};
Json subscription(String owner) => {
  'subscription_id': '1',
  'subscriber_address': owner,
  'merchant_address': merchant,
  'status': 'ACTIVE',
};
Json eligible() => {
  'can_check_in': true,
  'can_refund': true,
  'reasons': ['READY'],
  'next_period_index': '1',
  'nonce': '0',
};

class FakeWallet implements WalletPort {
  String account = customer;
  String chain = '0xa869';
  final calls = <String>[];
  final transactions = <Json>[];
  final stream = StreamController<void>.broadcast();
  String? typedSignature;
  Completer<dynamic>? sendGate;
  @override
  Stream<void> get changes => stream.stream;
  @override
  Future<dynamic> request(
    String method, [
    List<dynamic> params = const [],
  ]) async {
    calls.add(method);
    switch (method) {
      case 'eth_accounts':
      case 'eth_requestAccounts':
        return [account];
      case 'eth_chainId':
        return chain;
      case 'personal_sign':
        return '0x${'11' * 65}';
      case 'eth_signTypedData_v4':
        return typedSignature!;
      case 'eth_call':
        return '0x${BigInt.from(1000000000).toRadixString(16)}';
      case 'eth_sendTransaction':
        transactions.add(Map<String, dynamic>.from(params.first as Map));
        return sendGate == null ? hash : await sendGate!.future;
      case 'eth_getTransactionReceipt':
        return {'status': '0x1'};
      default:
        throw StateError('Unexpected RPC $method');
    }
  }

  @override
  void dispose() {
    stream.close();
  }
}

class FakeApi implements ApiPort {
  @override
  String? token;
  bool merchantProfile = false;
  bool failTracking = false;
  bool canRefund = true;
  String transactionStatus = 'CONFIRMED';
  String owner = customer;
  int checkIns = 0;
  final calls = <String>[];
  @override
  Future<dynamic> request(String method, String path, {Json? body}) async {
    calls.add('$method $path');
    if (path == '/api/v1/config') return configuration();
    if (path == '/api/v1/auth/challenge')
      return {'challenge_id': 'challenge', 'message': 'server SIWE message'};
    if (path == '/api/v1/auth/verify')
      return {
        'access_token': 'fixture-jwt',
        'user': {'wallet_address': owner, 'is_merchant': merchantProfile},
      };
    if (path == '/api/v1/auth/logout') return null;
    if (path == '/api/v1/me')
      return {'wallet_address': owner, 'is_merchant': merchantProfile};
    if (path.startsWith('/api/v1/plans?'))
      return {
        'items': [plan()],
        'next_cursor': null,
      };
    if (path.startsWith('/api/v1/me/subscriptions?'))
      return {
        'items': [],
        'next_cursor': null,
        'issues': [
          {
            'subscription_id': '9',
            'code': 'UNSUPPORTED_TIMESTAMP',
            'message': 'Unsupported history',
          },
        ],
      };
    if (path.startsWith('/api/v1/merchant/subscriptions?'))
      return {
        'items': [],
        'next_cursor': null,
        'issues': [
          {
            'subscription_id': '9',
            'code': 'UNSUPPORTED_TIMESTAMP',
            'message': 'Unsupported merchant history',
          },
        ],
      };
    if (path.startsWith('/api/v1/plan-drafts?'))
      return {'items': [], 'next_cursor': null};
    if (path == '/api/v1/plans/1') return plan();
    if (path.endsWith('/eligibility'))
      return {...eligible(), 'can_refund': canRefund};
    if (path == '/api/v1/subscriptions/1') return subscription(owner);
    if (path == '/api/v1/transactions') {
      if (failTracking)
        throw ApiFailure(503, 'RPC_UNAVAILABLE', 'temporarily unavailable');
      if (body?['action'] == 'CHECK_IN') checkIns++;
      return {
        'status': transactionStatus,
        'explorer_url': 'https://explorer.test/tx/$hash',
      };
    }
    throw StateError('Unexpected API $method $path');
  }

  @override
  void close() {}
}

Future<LiveController> signedIn({
  FakeWallet? wallet,
  FakeApi? api,
  MemoryPendingStore? store,
  int Function()? now,
}) async {
  final w = wallet ?? FakeWallet(), a = api ?? FakeApi();
  final c = LiveController(
    api: a,
    wallet: w,
    store: store ?? MemoryPendingStore(),
    nowSeconds: now,
  );
  await c.bootstrap();
  await c.login();
  return c;
}

void main() {
  test(
    'HTTP sends DTO directly with bearer and normalizes error envelope',
    () async {
      final client = MockClient((request) async {
        expect(
          request.url.toString(),
          'http://localhost:8000/api/v1/transactions',
        );
        expect(request.headers['Authorization'], 'Bearer jwt');
        expect(jsonDecode(request.body), {
          'action': 'REFUND',
          'subscription_id': '1',
        });
        return http.Response(
          jsonEncode({
            'error': {
              'code': 'UNSUPPORTED_TIMESTAMP',
              'message': 'History unsupported',
            },
          }),
          409,
        );
      });
      final api = HttpApi('http://localhost:8000', client: client)
        ..token = 'jwt';
      await expectLater(
        api.request(
          'POST',
          '/api/v1/transactions',
          body: {'action': 'REFUND', 'subscription_id': '1'},
        ),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.code,
            'code',
            'UNSUPPORTED_TIMESTAMP',
          ),
        ),
      );
      api.close();
    },
  );
  test('HTTP refuses plaintext remote origins and credential URLs', () {
    expect(() => HttpApi('http://example.com'), throwsArgumentError);
    expect(() => HttpApi('https://user:pass@example.com'), throwsArgumentError);
  });
  test('Dart EIP-712 digest and recovery match exported TypeScript vector', () {
    final fixture =
        jsonDecode(
              File('../../shared/check-in.fixture.json').readAsStringSync(),
            )
            as Json;
    final digest = checkInDigest(
      Map<String, dynamic>.from(fixture['domain']),
      Map<String, dynamic>.from(fixture['message']),
    );
    expect('0x${eth.bytesToHex(digest)}', fixture['digest']);
    expect(
      recoverCheckIn(
        Map<String, dynamic>.from(fixture['domain']),
        Map<String, dynamic>.from(fixture['message']),
        fixture['signature'],
      ),
      fixture['signer'].toString().toLowerCase(),
    );
  });
  test(
    'ABI calldata matches the compiled contract ABI, including dynamic CheckIn bytes',
    () {
      final artifact = File(
        '../../shared/abi/PrepaidVault.json',
      ).readAsStringSync();
      final abi = eth.ContractAbi.fromJson(artifact, 'PrepaidVault');
      final fixture =
          jsonDecode(
                File('../../shared/check-in.fixture.json').readAsStringSync(),
              )
              as Json;
      final message = Map<String, dynamic>.from(fixture['message']);
      final encoded = abi.functions
          .firstWhere((f) => f.name == 'checkInWithSignature')
          .encodeCall([
            [
              uint(message['subscriptionId']),
              wallets.EthereumAddress.fromHex(message['merchant']),
              uint(message['periodIndex']),
              uint(message['nonce']),
              uint(message['deadline']),
            ],
            eth.hexToBytes(fixture['signature']),
          ]);
      expect(
        encodeCheckIn(message, fixture['signature']),
        '0x${eth.bytesToHex(encoded)}',
      );
      final draft = {
        'client_reference': '0x${'cc' * 32}',
        'token_address': token,
        'price_per_period': '50000000',
        'total_periods': 2,
        'period_duration_seconds': 10,
        'grace_period_seconds': 20,
      };
      final create = abi.functions
          .firstWhere((f) => f.name == 'createPlan')
          .encodeCall([
            eth.hexToBytes(draft['client_reference'] as String),
            wallets.EthereumAddress.fromHex(token),
            BigInt.from(50000000),
            BigInt.two,
            BigInt.from(10),
            BigInt.from(20),
          ]);
      expect(encodeCreatePlan(draft), '0x${eth.bytesToHex(create)}');
    },
  );
  test('QR rejects wrong deployment, oversized payload and malformed uint', () {
    final fixture =
        jsonDecode(
              File('../../shared/check-in.fixture.json').readAsStringSync(),
            )
            as Json;
    final qr = {
      'version': 1,
      'kind': 'PREPAIDGUARD_CHECK_IN',
      'chainId': 43113,
      'verifyingContract': vault,
      'message': fixture['message'],
      'signature': fixture['signature'],
    };
    expect(parseQr(jsonEncode(qr), configuration())['version'], 1);
    expect(
      () => parseQr(jsonEncode({...qr, 'chainId': 1}), configuration()),
      throwsFormatException,
    );
    expect(() => parseQr('x' * 4097, configuration()), throwsFormatException);
    expect(() => uint('-1'), throwsFormatException);
    expect(() => uint((BigInt.one << 256).toString()), throwsFormatException);
  });
  test('wrong network and pinned deployment block login/transaction', () async {
    final w = FakeWallet()..chain = '0x1';
    final c = LiveController(
      api: FakeApi(),
      wallet: w,
      store: MemoryPendingStore(),
    );
    await c.bootstrap();
    await expectLater(c.login(), throwsStateError);
    expect(w.transactions, isEmpty);
    c.dispose();
    final pinned = LiveController(
      api: FakeApi(),
      wallet: FakeWallet(),
      store: MemoryPendingStore(),
      expectedVault: token,
    );
    await expectLater(pinned.bootstrap(), throwsStateError);
    pinned.dispose();
  });
  test(
    'subscriber login, real transaction tracking, issue warnings and logout',
    () async {
      final w = FakeWallet(), a = FakeApi();
      final c = await signedIn(wallet: w, api: a);
      expect(c.loggedIn, isTrue);
      expect(c.issues.single['code'], 'UNSUPPORTED_TIMESTAMP');
      await c.subscribe(plan());
      expect(w.transactions.single['to'], vault);
      expect(w.transactions.single['data'], encodeId('subscribe', '1'));
      expect(c.pending.single['status'], 'CONFIRMED');
      await c.logout();
      expect(c.loggedIn, isFalse);
      expect(a.token, isNull);
      c.dispose();
    },
  );
  test(
    'wallet changes invalidate the server session before financial action',
    () async {
      final w = FakeWallet(), c = await signedIn(wallet: w);
      w.account = merchant;
      await expectLater(c.subscribe(plan()), throwsStateError);
      expect(c.loggedIn, isFalse);
      expect(w.transactions, isEmpty);
      c.dispose();
    },
  );
  test(
    'broadcast hash survives API outage and restores without double broadcasting',
    () async {
      final store = MemoryPendingStore(), w = FakeWallet(), a = FakeApi();
      final c = await signedIn(wallet: w, api: a, store: store);
      a.failTracking = true;
      await expectLater(c.subscribe(plan()), throwsA(isA<ApiFailure>()));
      expect(w.transactions.length, 1);
      expect(store.values.values.single, contains(hash));
      c.dispose();
      final nextWallet = FakeWallet(),
          nextApi = FakeApi()..transactionStatus = 'SUBMITTED';
      final restored = await signedIn(
        wallet: nextWallet,
        api: nextApi,
        store: store,
      );
      expect(restored.pending.single['tx_hash'], hash);
      await expectLater(restored.subscribe(plan()), throwsStateError);
      expect(nextWallet.transactions, isEmpty);
      restored.dispose();
    },
  );
  test(
    'create signed QR and merchant confirms only the exact current subscriber nonce',
    () async {
      final fixture =
          jsonDecode(
                File('../../shared/check-in.fixture.json').readAsStringSync(),
              )
              as Json;
      final signingWallet = FakeWallet()
        ..account = fixture['signer'].toString().toLowerCase()
        ..typedSignature = fixture['signature'];
      final api = FakeApi()..owner = signingWallet.account;
      final subscriber = await signedIn(
        wallet: signingWallet,
        api: api,
        now: () => int.parse(fixture['message']['deadline']) - 900,
      );
      final payload = await subscriber.createCheckIn('1');
      expect(jsonDecode(payload)['message'], fixture['message']);
      subscriber.dispose();
      final merchantWallet = FakeWallet()..account = merchant;
      final merchantApi = FakeApi()
        ..owner = merchant
        ..merchantProfile = true;
      // The API session belongs to merchant, but subscription owner remains fixture signer.
      final merchantController = await signedIn(
        wallet: merchantWallet,
        api: merchantApi,
        now: () => int.parse(fixture['message']['deadline']) - 100,
      );
      merchantApi.owner = fixture['signer'].toString().toLowerCase();
      await merchantController.confirmQr(payload);
      expect(merchantApi.checkIns, 1);
      expect(
        merchantWallet.transactions.single['data'],
        encodeCheckIn(
          Map<String, dynamic>.from(fixture['message']),
          fixture['signature'],
        ),
      );
      merchantController.dispose();
    },
  );
  test(
    'delayed wallet broadcast persists hash under initiating wallet after account change',
    () async {
      final store = MemoryPendingStore(),
          wallet = FakeWallet(),
          api = FakeApi();
      final c = await signedIn(wallet: wallet, api: api, store: store);
      final gate = Completer<dynamic>();
      wallet.sendGate = gate;
      final sending = c.subscribe(plan());
      while (wallet.transactions.isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      wallet.account = merchant;
      wallet.stream.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(c.loggedIn, isFalse);
      gate.complete(hash);
      await sending;
      expect(c.pending, isEmpty);
      expect(
        store.values.keys.single,
        'prepaidguard.pending.fixture.$customer',
      );
      expect(store.values.values.single, contains(hash));
      expect(
        api.calls.where((call) => call == 'POST /api/v1/transactions'),
        isEmpty,
      );
      c.dispose();
      final restored = await signedIn(
        wallet: FakeWallet(),
        api: FakeApi()..transactionStatus = 'SUBMITTED',
        store: store,
      );
      expect(restored.pending.single['tx_hash'], hash);
      restored.dispose();
    },
  );

  test(
    'delayed wallet broadcast survives chain change without tracking under invalid session',
    () async {
      final store = MemoryPendingStore(),
          wallet = FakeWallet(),
          api = FakeApi();
      final c = await signedIn(wallet: wallet, api: api, store: store);
      final gate = Completer<dynamic>();
      wallet.sendGate = gate;
      final sending = c.subscribe(plan());
      while (wallet.transactions.isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      wallet.chain = '0x1';
      wallet.stream.add(null);
      await Future<void>.delayed(Duration.zero);
      gate.complete(hash);
      await sending;
      expect(c.loggedIn, isFalse);
      expect(
        store.values.keys.single,
        'prepaidguard.pending.fixture.$customer',
      );
      expect(
        api.calls.where((call) => call == 'POST /api/v1/transactions'),
        isEmpty,
      );
      c.dispose();
    },
  );
  test(
    'registration links bind plan, chain and Vault before showing target plan',
    () async {
      final c = LiveController(
        api: FakeApi(),
        wallet: FakeWallet(),
        store: MemoryPendingStore(),
      );
      await c.bootstrap();
      await c.openRegistration(
        Uri.parse('https://app.example/?plan_id=1&chain_id=43113&vault=$vault'),
      );
      expect(c.notice, contains('gói #1'));
      await expectLater(
        c.openRegistration(
          Uri.parse('https://app.example/?plan_id=1&chain_id=1&vault=$vault'),
        ),
        throwsFormatException,
      );
      c.dispose();
    },
  );

  test(
    'refund enforces live owner and eligibility before broadcasting',
    () async {
      final wallet = FakeWallet(), api = FakeApi();
      final c = await signedIn(wallet: wallet, api: api);
      api.canRefund = false;
      await expectLater(c.refund('1'), throwsStateError);
      expect(wallet.transactions, isEmpty);
      api.canRefund = true;
      await c.refund('1');
      expect(wallet.transactions.single['data'], encodeId('refund', '1'));
      expect(c.pending.single['status'], 'CONFIRMED');
      c.dispose();
    },
  );

  test(
    'merchant and subscriber projection issues are tracked separately and delayed hash merges on refresh',
    () async {
      final store = MemoryPendingStore(), wallet = FakeWallet(), api = FakeApi();
      api.merchantProfile = true;
      final c = await signedIn(wallet: wallet, api: api, store: store);
      expect(c.issues.single['subscription_id'], '9');
      expect(c.merchantIssues.single['subscription_id'], '9');

      final gate = Completer<dynamic>();
      wallet.sendGate = gate;
      final sending = c.subscribe(plan());
      while (wallet.transactions.isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      wallet.account = merchant;
      wallet.stream.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(c.loggedIn, isFalse);

      // Re-login to original wallet before the delayed tx hash arrives.
      wallet.account = customer;
      await c.login();
      expect(c.pending, isEmpty);

      gate.complete(hash);
      await sending;
      await c.refresh();
      expect(c.pending.single['tx_hash'], hash);
      c.dispose();
    },
  );
}
