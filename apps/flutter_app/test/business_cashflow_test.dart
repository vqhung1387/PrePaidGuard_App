import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prepaid_guard/real/controller.dart';
import 'package:prepaid_guard/real/screen.dart';
import 'package:prepaid_guard/real/wallet_port.dart';
import 'real_mode_test.dart' as f;

void main() {
  testWidgets('Merchant can isolate draft and published plans', (tester) async {
    tester.view.physicalSize = const Size(1280, 1140);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = await f.signedIn(api: f.FakeApi()..merchantProfile = true);
    c.drafts = [
      {...f.plan(), 'title': 'Gói tháng', 'state': 'PUBLISHED'},
      {...f.plan(), 'title': 'Gói học', 'state': 'DRAFT'},
    ];
    await tester.pumpWidget(
      MaterialApp(home: RealWorkspaceScreen(controller: c)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cơ sở'));
    await tester.pumpAndSettle();
    for (final filter in ['Bản nháp', 'Đã công bố', 'Tất cả gói']) {
      final chip = find.widgetWithText(ChoiceChip, filter);
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(
        find.text('Bản nháp: Gói học'),
        filter == 'Đã công bố' ? findsNothing : findsOneWidget,
      );
      expect(
        find.text('Gói tháng'),
        filter == 'Bản nháp' ? findsNothing : findsOneWidget,
      );
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Preview shows allocation for each period and wallet login resumes review',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final wallet = f.FakeWallet();
      final c = LiveController(
        api: f.FakeApi(),
        wallet: wallet,
        store: MemoryPendingStore(),
      );
      await c.bootstrap();
      await tester.pumpWidget(
        MaterialApp(home: RealWorkspaceScreen(controller: c)),
      );
      await tester.pumpAndSettle();
      Future<void> tap(Finder target) async {
        await tester.ensureVisible(target);
        await tester.tap(target);
        await tester.pumpAndSettle();
      }

      await tap(find.text('Gói dịch vụ'));
      await tap(find.byTooltip('Kỳ trước'));
      expect(find.text('Kỳ 0/2'), findsOneWidget);
      expect(find.text('0 PG Credit'), findsOneWidget);
      await tap(find.byTooltip('Kỳ tiếp theo'));
      expect(find.text('50 PG Credit'), findsNWidgets(2));
      await tap(find.byTooltip('Kỳ tiếp theo'));
      expect(find.text('Kỳ 2/2'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Kỳ tiếp theo',
              ),
            )
            .onPressed,
        isNull,
      );
      await tap(find.text('Xem gói'));
      await tap(find.text('Kết nối ví để đăng ký'));
      expect(c.loggedIn, isTrue);
      expect(find.text('Tiếp tục ký ví'), findsOneWidget);
      expect(
        find.textContaining('Tổng trả trước: 100 PG Credit'),
        findsOneWidget,
      );
      expect(find.textContaining('Ví thanh toán: 100 mUSDC'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining('1 PG Credit = 1 mUSDC'),
        ),
        findsOneWidget,
      );
      expect(wallet.transactions, isEmpty);
      await tap(find.text('Thử quy trình không dùng token'));
      await tap(find.text('Thử đăng ký'));
      await tap(find.text('Thử xác nhận kỳ đầu'));
      expect(find.textContaining('Gốc còn giữ: 50 PG Credit'), findsOneWidget);
      await tap(find.text('Đóng'));
      expect(wallet.transactions, isEmpty);
      await tap(find.text('Hủy'));
      expect(wallet.transactions, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
