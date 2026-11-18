import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prepaid_guard/app/prepaid_guard_app.dart';
import 'package:prepaid_guard/real/api.dart';
import 'package:prepaid_guard/real/controller.dart';
import 'package:prepaid_guard/real/escrow_summary_card.dart';
import 'package:prepaid_guard/real/screen.dart';
import 'package:prepaid_guard/real/wallet_port.dart';
import 'real_mode_test.dart' as f;

class _UxTestApi extends f.FakeApi {
  bool failDraftCreate = false;
  Json? lastDraftBody;
  final List<Json> customDrafts = [];
  Json? subscriptionDetailOverride;

  @override
  Future<dynamic> request(String method, String path, {Json? body}) async {
    if (method == 'POST' && path == '/api/v1/plan-drafts') {
      if (failDraftCreate) {
        throw ApiFailure(503, 'RPC_UNAVAILABLE', 'Máy chủ tạm bận.');
      }
      lastDraftBody = body;
      final created = {
        'id': 'draft-1',
        'client_reference': '0x${'cc' * 32}',
        'token_address': f.token,
        'state': 'DRAFT',
        ...body!,
        'total_price':
            (BigInt.parse(body['price_per_period'] as String) *
                    BigInt.from(body['total_periods'] as int))
                .toString(),
      };
      customDrafts.insert(0, created);
      return created;
    }
    if (path.startsWith('/api/v1/plan-drafts?')) {
      return {'items': customDrafts, 'next_cursor': null};
    }
    if (path == '/api/v1/subscriptions/1' &&
        subscriptionDetailOverride != null) {
      return subscriptionDetailOverride!;
    }
    return super.request(method, path, body: body);
  }
}

Future<void> _tapScroll(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    250,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Real plan form preserves inputs on error, keeps multiline description, rejects NUL and shows pre-sign summary',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 960);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final api = _UxTestApi()
        ..owner = f.merchant
        ..merchantProfile = true
        ..failDraftCreate = true;
      final wallet = f.FakeWallet()..account = f.merchant;
      final controller = await f.signedIn(wallet: wallet, api: api);

      await tester.pumpWidget(
        MaterialApp(
          home: RealWorkspaceScreen(controller: controller, onDemo: () {}),
        ),
      );
      await tester.pumpAndSettle();

      await _tapScroll(tester, find.text('Tạo / publish gói'));
      expect(
        find.text('Tổng khóa trả trước: 100 mUSDC (50 mUSDC/kỳ × 2 kỳ)'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Mở check-in kỳ đầu sau 60 giây'),
        findsOneWidget,
      );

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Tên gói'),
        'Gói Yoga\u0000lỗi',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'USDC mỗi kỳ'),
        '1.000',
      );
      await tester.tap(find.text('Xác nhận'));
      await tester.pumpAndSettle();
      expect(find.text('Không được chứa ký tự NUL.'), findsOneWidget);
      expect(find.textContaining('Không dùng dấu hàng nghìn'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Tên gói'),
        'Gói Yoga Chuyên Sâu',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Mô tả'),
        'Buổi sáng\nBuổi tối',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'USDC mỗi kỳ'),
        '25',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Số kỳ'),
        '4',
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Không dùng dấu hàng nghìn'), findsNothing);
      expect(
        find.text('Tổng khóa trả trước: 100 mUSDC (25 mUSDC/kỳ × 4 kỳ)'),
        findsOneWidget,
      );

      await tester.tap(find.text('Xác nhận'));
      await tester.pumpAndSettle();
      expect(wallet.transactions, isEmpty);

      // Reopen form after API failure -> inputs are preserved.
      await _tapScroll(tester, find.text('Tạo / publish gói'));
      expect(find.text('Gói Yoga Chuyên Sâu'), findsOneWidget);
      expect(find.text('Buổi sáng\nBuổi tối'), findsOneWidget);
      expect(find.text('25'), findsOneWidget);

      api.failDraftCreate = false;
      await tester.tap(find.text('Xác nhận'));
      await tester.pumpAndSettle();
      expect(api.lastDraftBody!['description'], 'Buổi sáng\nBuổi tối');
      expect(api.lastDraftBody!['price_per_period'], '25000000');
      expect(wallet.transactions.length, 1);

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Draft row displays terms and requires confirmation before wallet tx',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 960);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final api = _UxTestApi()
        ..owner = f.merchant
        ..merchantProfile = true
        ..customDrafts.add({
          'id': 'draft-9',
          'client_reference': '0x${'dd' * 32}',
          'token_address': f.token,
          'title': 'Gói Draft Kiểm Tra',
          'description': '',
          'price_per_period': '15000000',
          'total_periods': 3,
          'period_duration_seconds': 60,
          'grace_period_seconds': 180,
          'total_price': '45000000',
          'state': 'DRAFT',
        });
      final wallet = f.FakeWallet()..account = f.merchant;
      final controller = await f.signedIn(wallet: wallet, api: api);

      await tester.pumpWidget(
        MaterialApp(
          home: RealWorkspaceScreen(controller: controller, onDemo: () {}),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Draft: Gói Draft Kiểm Tra'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Draft: Gói Draft Kiểm Tra'), findsOneWidget);
      expect(
        find.textContaining('15 mUSDC/kỳ × 3 kỳ · Tổng 45 mUSDC'),
        findsOneWidget,
      );

      await _tapScroll(tester, find.text('Publish draft'));
      expect(find.text('Publish gói lên chuỗi'), findsOneWidget);
      expect(
        find.textContaining('Mỗi kỳ: 15 mUSDC × 3 kỳ = Tổng 45 mUSDC'),
        findsOneWidget,
      );
      expect(wallet.transactions, isEmpty);

      await tester.tap(find.text('Hủy'));
      await tester.pumpAndSettle();
      expect(wallet.transactions, isEmpty);

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Registration QR copy avoids check-in 15-min text and import QR previews details before signing',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 960);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fixture =
          jsonDecode(
                File('../../shared/check-in.fixture.json').readAsStringSync(),
              )
              as Json;
      final signer = fixture['signer'].toString().toLowerCase();
      final payload = jsonEncode({
        'version': 1,
        'kind': 'PREPAIDGUARD_CHECK_IN',
        'chainId': 43113,
        'verifyingContract': f.vault,
        'message': fixture['message'],
        'signature': fixture['signature'],
      });

      final api = _UxTestApi()
        ..owner = f.merchant
        ..merchantProfile = true
        ..subscriptionDetailOverride = {
          ...f.subscription(signer),
          'plan_id': '1',
          'initial_principal': '100000000',
          'remaining_principal': '100000000',
          'total_periods': 2,
          'completed_periods': 0,
        };
      final wallet = f.FakeWallet()..account = f.merchant;
      final controller = LiveController(
        api: api,
        wallet: wallet,
        store: MemoryPendingStore(),
        nowSeconds: () => int.parse(fixture['message']['deadline']) - 100,
      );
      await controller.bootstrap();
      await controller.login();

      await tester.pumpWidget(
        MaterialApp(
          home: RealWorkspaceScreen(controller: controller, onDemo: () {}),
        ),
      );
      await tester.pumpAndSettle();

      await _tapScroll(tester, find.byTooltip('QR đăng ký'));
      expect(find.text('QR đăng ký gói'), findsOneWidget);
      expect(
        find.textContaining('Đây là mã QR đăng ký gói, không phải mã check-in ký số.'),
        findsOneWidget,
      );
      expect(find.textContaining('15 phút'), findsNothing);
      await tester.tap(find.text('Đóng'));
      await tester.pumpAndSettle();

      // Reject registration link inline in Import Check-in QR.
      await _tapScroll(tester, find.text('Nhập QR check-in'));
      await tester.enterText(
        find.widgetWithText(TextFormField, 'QR payload'),
        'https://prepaidguard-web.onrender.com/?real=1&plan_id=1',
      );
      await tester.tap(find.text('Xác nhận'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Đây là liên kết web / QR đăng ký gói'),
        findsOneWidget,
      );
      expect(wallet.transactions, isEmpty);

      // Valid QR opens pre-sign confirmation showing subscriber, period, and amount.
      await tester.enterText(
        find.widgetWithText(TextFormField, 'QR payload'),
        payload,
      );
      await tester.tap(find.text('Xác nhận'));
      await tester.pumpAndSettle();
      expect(find.text('Giải ngân một kỳ'), findsOneWidget);
      expect(find.textContaining('Đăng ký #1 (Gói #1)'), findsOneWidget);
      expect(find.textContaining('Ví hội viên: $signer'), findsOneWidget);
      expect(find.textContaining('Kỳ giải ngân: Kỳ 1/2 · Nonce 0'), findsOneWidget);
      expect(
        find.textContaining('Số tiền giải ngân kỳ này: 50 mUSDC'),
        findsOneWidget,
      );
      expect(wallet.transactions, isEmpty);

      // Cancel preserves QR draft on reopen; confirming sends 1 tx and clears it.
      await tester.tap(find.text('Hủy'));
      await tester.pumpAndSettle();
      expect(wallet.transactions, isEmpty);

      await _tapScroll(tester, find.text('Nhập QR check-in'));
      expect(find.text(payload), findsOneWidget);
      await tester.tap(find.text('Xác nhận'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tiếp tục ký ví'));
      await tester.pumpAndSettle();
      expect(wallet.transactions.length, 1);

      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'HttpApi omits Content-Type on GET and maps 502 HTML, 429 Retry-After, ClientException and TimeoutException cleanly',
    () async {
      final getHeaders = <String, String>{};
      final postHeaders = <String, String>{};
      var mode = '200';
      final client = MockClient((request) async {
        if (request.method == 'GET') {
          getHeaders.addAll(request.headers);
        } else {
          postHeaders.addAll(request.headers);
        }
        switch (mode) {
          case '502':
            return http.Response('<html><body>502 Bad Gateway</body></html>', 502);
          case '429':
            return http.Response.bytes(
              utf8.encode(
                jsonEncode({
                  'error': {
                    'code': 'RATE_LIMITED',
                    'message': 'Quá nhiều yêu cầu.',
                  },
                }),
              ),
              429,
              headers: {
                'content-type': 'application/json; charset=utf-8',
                'retry-after': '300',
              },
            );
          case 'client':
            throw http.ClientException('Failed to fetch');
          case 'timeout':
            throw TimeoutException('timed out');
          default:
            return http.Response(jsonEncode({'ok': true}), 200);
        }
      });

      final api = HttpApi('https://api.example.com', client: client);
      addTearDown(api.close);
      await api.request('GET', '/api/v1/config');
      expect(getHeaders.containsKey('Content-Type'), isFalse);
      await api.request('POST', '/api/v1/auth/challenge', body: {'a': 1});
      expect(postHeaders['Content-Type'], startsWith('application/json'));

      mode = '502';
      await expectLater(
        api.request('GET', '/api/v1/config'),
        throwsA(
          isA<ApiFailure>()
              .having((e) => e.status, 'status', 502)
              .having((e) => e.message, 'message', contains('HTTP 502')),
        ),
      );

      mode = '429';
      await expectLater(
        api.request('GET', '/api/v1/config'),
        throwsA(
          isA<ApiFailure>()
              .having((e) => e.status, 'status', 429)
              .having((e) => e.message, 'message', contains('300 giây')),
        ),
      );

      mode = 'client';
      await expectLater(
        api.request('GET', '/api/v1/config'),
        throwsA(
          isA<ApiFailure>()
              .having((e) => e.code, 'code', 'NETWORK_ERROR')
              .having((e) => e.message, 'message', contains('Không kết nối được')),
        ),
      );

      mode = 'timeout';
      await expectLater(
        api.request('POST', '/api/v1/auth/challenge', body: {'a': 1}),
        throwsA(
          isA<ApiFailure>()
              .having((e) => e.code, 'code', 'NETWORK_TIMEOUT')
              .having((e) => e.message, 'message', contains('15 giây')),
        ),
      );
    },
  );

  testWidgets('Config can arrive after the normal request deadline', (
    tester,
  ) async {
    final api = HttpApi(
      'https://api.example.com',
      client: MockClient((_) async {
        await Future<void>.delayed(const Duration(seconds: 20));
        return http.Response('{"ok": true}', 200);
      }),
    );
    addTearDown(api.close);

    final config = expectLater(
      api.request('GET', '/api/v1/config'),
      completion({'ok': true}),
    );
    final login = expectLater(
      api.request('POST', '/api/v1/auth/challenge', body: {'a': 1}),
      throwsA(isA<ApiFailure>().having((e) => e.code, 'code', 'NETWORK_TIMEOUT')),
    );
    await tester.pump(const Duration(seconds: 15));
    await login;
    await tester.pump(const Duration(seconds: 5));
    await config;
  });

  test('Wallet error and eligibility reason classifiers output clear Vietnamese', () {
    expect(
      classifyWalletError(code: 4001, method: 'personal_sign'),
      contains('Bạn đã từ chối'),
    );
    expect(
      classifyWalletError(code: 4100, method: 'eth_requestAccounts'),
      contains('Ví đang khóa'),
    );
    expect(
      classifyWalletError(code: -32002, method: 'eth_requestAccounts'),
      contains('chờ xác nhận'),
    );
    expect(
      classifyWalletError(code: 4902, method: 'wallet_switchEthereumChain'),
      contains('chưa được thêm'),
    );
    expect(
      classifyWalletError(
        message: 'insufficient funds for gas * price + value',
        method: 'eth_sendTransaction',
      ),
      contains('Không đủ AVAX'),
    );
    expect(
      formatEligibilityReasons(['TOO_EARLY']),
      'chưa tới mốc mở kỳ tiếp theo',
    );
    expect(
      formatEligibilityReasons(['REFUND_WINDOW_OPEN']),
      contains('khung hoàn gốc'),
    );
    expect(
      formatEligibilityReasons(['READY'], forRefund: true),
      contains('chưa tới mốc hoàn gốc'),
    );
    expect(formatUserError(StateError('Thông báo sạch')), 'Thông báo sạch');
    expect(
      formatUserError(ApiFailure(422, 'VALIDATION_ERROR', 'Sai dữ liệu')),
      'Sai dữ liệu',
    );
  });

  testWidgets(
    'Stale SnackBar clears after retry success and multi-provider wallet selector switches provider',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 960);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      var failConfig = true;
      final client = MockClient((request) async {
        if (request.url.path == '/api/v1/config') {
          if (failConfig) {
            return http.Response('<html>502 Bad Gateway</html>', 502);
          }
          return http.Response(jsonEncode(f.configuration()), 200);
        }
        if (request.url.path == '/api/v1/plans') {
          return http.Response(
            jsonEncode({'items': [f.plan()], 'next_cursor': null}),
            200,
          );
        }
        return http.Response('{}', 404);
      });

      final multiWallet = _MultiProviderWallet();
      await tester.pumpWidget(
        MaterialApp(
          home: RealWorkspaceScreen(
            apiFactory: (base) => HttpApi(base, client: client),
            walletFactory: () => multiWallet,
            storeFactory: MemoryPendingStore.new,
            onDemo: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Kết nối API'));
      await tester.pumpAndSettle();
      expect(find.textContaining('HTTP 502'), findsOneWidget);
      expect(find.textContaining('Bad state:'), findsNothing);
      expect(find.textContaining('INVALID_RESPONSE:'), findsNothing);

      failConfig = false;
      await tester.tap(find.text('Kết nối API'));
      await tester.pumpAndSettle();
      expect(find.textContaining('HTTP 502'), findsNothing);
      expect(find.text('Chọn ví trình duyệt'), findsOneWidget);
      expect(find.text('Core'), findsOneWidget);
      expect(find.text('MetaMask'), findsOneWidget);

      await tester.tap(find.text('MetaMask'));
      await tester.pumpAndSettle();
      expect(multiWallet.selectedProviderId, 'mm');

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Demo invite link stays in Demo even when API_BASE_URL is pinned, and plan_id deep-link auto-connects',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 960);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        PrepaidGuardApp(
          initialUri: Uri.parse(
            'https://prepaidguard-web.onrender.com/?invite=gym-khoi-dong',
          ),
          apiBaseUrl: 'https://prepaidguard-api.onrender.com',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Bản demo. Hãy dùng email và mật khẩu giả.'), findsOneWidget);
      expect(find.text('Kết nối API và ví'), findsNothing);

      final api = f.FakeApi();
      await tester.pumpWidget(
        MaterialApp(
          home: RealWorkspaceScreen(
            initialUri: Uri.parse(
              'https://prepaidguard-web.onrender.com/?real=1&plan_id=1&chain_id=43113&vault=${f.vault}',
            ),
            apiBaseUrl: 'https://prepaidguard-api.onrender.com',
            apiFactory: (_) => api,
            walletFactory: f.FakeWallet.new,
            storeFactory: MemoryPendingStore.new,
            onDemo: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Đã kết nối API'), findsOneWidget);
      expect(find.textContaining('Đã mở gói #1 từ QR đăng ký'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'EscrowSummaryCard computes exact principal sums, cites source/block, and fits 320px at 2.0x scale',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final subs = [
        {
          ...f.subscription(f.customer),
          'subscription_id': '1',
          'status': 'ACTIVE',
          'initial_principal': '3000000',
          'principal_released': '1000000',
          'remaining_principal': '2000000',
          'principal_refunded': '0',
          'refund_available_at': '2026-11-18T12:00:00Z',
          'sync': {'source': 'PROJECTION', 'block_number': '105'},
        },
        {
          ...f.subscription(f.customer),
          'subscription_id': '2',
          'status': 'REFUNDED',
          'initial_principal': '3000000',
          'principal_released': '0',
          'remaining_principal': '0',
          'principal_refunded': '3000000',
          'refund_available_at': '2026-11-18T10:00:00Z',
          'sync': {'source': 'PROJECTION', 'block_number': '112'},
        },
        {
          ...f.subscription(f.customer),
          'subscription_id': '3',
          'status': 'ACTIVE',
          'initial_principal': '999000000',
          'remaining_principal': '999000000',
          'principal_released': '0',
          'principal_refunded': null,
          'refund_available_at': '2026-11-17T12:00:00Z',
        },
      ];

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, widget) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2.0)),
            child: widget!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: EscrowSummaryCard(
                subscriptions: subs,
                config: f.configuration(),
                filter: SubscriptionFilter.active,
                hasMore: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Tổng gốc đã khóa'), findsOneWidget);
      expect(find.text('6 mUSDC'), findsOneWidget);
      expect(find.text('1 mUSDC'), findsOneWidget);
      expect(find.text('2 mUSDC'), findsOneWidget);
      expect(find.text('3 mUSDC'), findsOneWidget);
      expect(find.textContaining('Bỏ qua 1 đăng ký'), findsOneWidget);
      expect(
        find.textContaining('1 gói đang hoạt động · Mốc hoàn gốc sớm nhất: 2026-11-18T12:00:00Z'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'Nguồn dữ liệu: PROJECTION (bản chiếu sự kiện chuỗi) · Block #112',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('2 đăng ký đang hiển thị (Đang sử dụng, còn trang tiếp)'),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox());
    },
  );
}

class _MultiProviderWallet extends f.FakeWallet {
  String _selected = 'core';

  @override
  List<WalletProviderInfo> get providers => const [
    WalletProviderInfo(id: 'core', name: 'Core', rdns: 'app.core.extension'),
    WalletProviderInfo(id: 'mm', name: 'MetaMask', rdns: 'io.metamask'),
  ];

  @override
  String? get selectedProviderId => _selected;

  @override
  void selectProvider(String id) {
    _selected = id;
  }
}
