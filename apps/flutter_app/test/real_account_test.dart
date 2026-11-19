import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prepaid_guard/real/api.dart';
import 'package:prepaid_guard/real/screen.dart';
import 'package:prepaid_guard/app/prepaid_guard_app.dart';
import 'real_mode_test.dart' as f;

Json membership(String mode) => {
  ...f.subscription(f.customer),
  'status': 'REFUNDED',
  'initial_principal': '100000000',
  'principal_released': '50000000',
  'principal_refunded': '50000000',
  'remaining_principal': '0',
  'completed_periods': 1,
  'total_periods': 2,
  'next_release_at': null,
  'refund_available_at': null,
  'sync': {'source': 'PROJECTION', 'block_number': '100'},
  'yield_summary': {
    'mode': mode,
    'estimated_unclaimed': null,
    'paid_subscriber': '200000',
    'paid_merchant': '700000',
    'paid_platform': '100000',
  },
};

class DetailApi extends f.FakeApi {
  DetailApi(this.mode);
  final String mode;
  @override
  Future<dynamic> request(String method, String path, {Json? body}) async {
    if (path == '/api/v1/subscriptions/1') return membership(mode);
    if (path.contains('/events?')) {
      final next = Uri.parse(path).queryParameters['cursor'] == 'history-next';
      return {
        'items': [
          {
            'id': 'refund',
            'event_name': 'REFUNDED',
            'block_timestamp': '2026-11-15T00:00:00Z',
            'explorer_url': 'https://example.test/tx/confirmed',
          },
          if (next)
            {
              'id': 'released',
              'event_name': 'PERIOD_RELEASED',
              'block_timestamp': '2026-11-14T00:00:00Z',
              'explorer_url': 'https://example.test/tx/released',
            },
        ],
        'next_cursor': next ? null : 'history-next',
      };
    }
    return super.request(method, path, body: body);
  }
}

void main() {
  for (final mode in ['MOCK', 'DISABLED']) {
    testWidgets(
      'real detail shows exact API principal and explicitly labelled yield $mode',
      (tester) async {
        final controller = await f.signedIn(api: DetailApi(mode));
        controller.memberships = [membership(mode)];
        await tester.pumpWidget(
          MaterialApp(home: RealWorkspaceScreen(controller: controller)),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Gói của tôi'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Chi tiết / lịch sử'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(find.text('Chi tiết / lịch sử'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Chi tiết / lịch sử'));
        await tester.pumpAndSettle();
        expect(find.text('Đã trả trước: 100 mUSDC'), findsOneWidget);
        expect(find.text('Đã giải ngân: 50 mUSDC'), findsOneWidget);
        expect(find.text('Đã hoàn gốc: 50 mUSDC'), findsOneWidget);
        expect(find.text('Gốc còn lại: 0 mUSDC'), findsOneWidget);
        Finder inDialog(String text) => find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(text),
        );
        if (mode == 'MOCK') {
          expect(
            inDialog('Lợi tức mô phỏng (MOCK) · Token thử nghiệm'),
            findsOneWidget,
          );
          expect(inDialog('Đã trả cho khách: 0,2 mUSDC'), findsOneWidget);
          expect(
            inDialog('Ước tính chưa nhận: Chưa có dữ liệu'),
            findsOneWidget,
          );
        } else {
          expect(inDialog('Lợi tức · Đã tắt (DISABLED)'), findsOneWidget);
          expect(inDialog('Đã trả cho khách: 0,2 mUSDC'), findsNothing);
        }
        expect(find.text('https://example.test/tx/confirmed'), findsOneWidget);
        final loadMore = inDialog('Tải thêm lịch sử');
        await tester.ensureVisible(loadMore);
        await tester.pumpAndSettle();
        await tester.tap(loadMore);
        await tester.pumpAndSettle();
        expect(inDialog('Lịch sử giao dịch · 2 mục'), findsOneWidget);
        expect(find.text('https://example.test/tx/confirmed'), findsOneWidget);
        expect(find.text('https://example.test/tx/released'), findsOneWidget);
        expect(loadMore, findsNothing);
        expect(tester.takeException(), isNull);
        await tester.tap(find.widgetWithText(TextButton, 'Đóng'));
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('business entry never offers a demo login or switch', (
    tester,
  ) async {
    for (final route in ['/', '/?demo=1', '/?real=0&invite=gym-khoi-dong']) {
      await tester.pumpWidget(
        PrepaidGuardApp(
          initialUri: Uri.parse('https://prepaidguard-web.onrender.com$route'),
          apiBaseUrl: '',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Khám phá gói dịch vụ'), findsOneWidget);
      expect(find.byKey(const ValueKey('auth-email')), findsNothing);
      expect(find.text('Về demo'), findsNothing);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
  });
}
