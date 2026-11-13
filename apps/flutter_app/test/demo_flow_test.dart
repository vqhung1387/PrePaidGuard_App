import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prepaid_guard/app/demo_workspace.dart';
import 'package:prepaid_guard/app/prepaid_guard_app.dart';
import 'package:prepaid_guard/features/auth/demo_accounts.dart';
import 'package:prepaid_guard/features/community/invite_link.dart';
import 'package:prepaid_guard/features/plans/demo_plan.dart';

Future<void> _switchMode(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('Chuyển chế độ'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  test(
    'Monthly offers calculate exact prices and savings from the one-month rate',
    () {
      final workspace = DemoWorkspace();
      final offers = workspace.plans;
      expect(offers.map((plan) => plan.periods), [1, 3, 6, 12, 24]);
      expect(offers.map((plan) => plan.discountPercent), [0, 10, 20, 25, 35]);
      expect(offers.map((plan) => formatTokenAmount(plan.total)), [
        '16',
        '43,2',
        '76,8',
        '144',
        '249,6',
      ]);
      expect(offers.map((plan) => formatTokenAmount(plan.savings)), [
        '0',
        '4,8',
        '19,2',
        '48',
        '134,4',
      ]);
      expect(offers.every((plan) => plan.daysPerPeriod == 30), isTrue);
      expect(workspace.samplePlan, same(offers[1]));
    },
  );

  test(
    'Long-term bonuses are awarded once, only after merchant confirmation',
    () {
      final workspace = DemoWorkspace();
      const customer = 'customer@example.com';
      for (final plan in workspace.plans.where((plan) => plan.periods >= 12)) {
        final expectedBonus = plan.periods == 12 ? 7 : 15;
        workspace.subscribe(customer, plan);
        final membership = workspace.memberships(customer)[plan]!;
        expect(membership.earnedBonusDays, 0);
        expect(membership.requestCheckIn(), isTrue);
        expect(membership.accessDays, plan.periods * 30);
        expect(membership.earnedBonusDays, 0);
        expect(workspace.confirmCheckIn(customer, membership), isFalse);
        expect(
          workspace.confirmCheckIn(DemoAccounts.exampleEmail, membership),
          isTrue,
        );
        expect(
          workspace.confirmCheckIn(DemoAccounts.exampleEmail, membership),
          isFalse,
        );
        expect(membership.earnedBonusDays, expectedBonus);
        expect(membership.accessDays, plan.periods * 30 + expectedBonus);
        expect(membership.released, plan.pricePerPeriod);
        expect(membership.remaining, plan.total - plan.pricePerPeriod);
      }
    },
  );

  test('Token amounts retain six decimals without rounding', () {
    expect(parseTokenAmount('12,345678'), BigInt.from(12345678));
    expect(parseTokenAmount('0.000001'), BigInt.one);
    expect(parseTokenAmount('0.0000001'), isNull);
    expect(parseTokenAmount('1e3'), isNull);
    expect(parseTokenAmount('0'), isNull);
    expect(formatTokenAmount(BigInt.parse('1234000001')), '1.234,000001');
  });

  test('Only the plan owner can confirm a pending check-in once', () {
    final workspace = DemoWorkspace();
    final plan = workspace.samplePlan;
    const customer = 'customer@example.com';
    workspace.subscribe(customer, plan);
    final membership = workspace.memberships(customer)[plan]!;
    expect(
      workspace.confirmCheckIn(DemoAccounts.exampleEmail, membership),
      isFalse,
    );
    expect(membership.requestCheckIn(), isTrue);
    expect(membership.requestCheckIn(), isFalse);
    expect(membership.remaining, plan.total);
    expect(workspace.pendingCheckIns(customer), isEmpty);
    expect(workspace.confirmCheckIn(customer, membership), isFalse);
    expect(
      workspace.confirmCheckIn(DemoAccounts.exampleEmail, membership),
      isTrue,
    );
    expect(
      workspace.confirmCheckIn(DemoAccounts.exampleEmail, membership),
      isFalse,
    );
    expect(membership.remaining + membership.released, plan.total);
  });

  test('Invitation links identify only the built-in demo plan', () {
    final link = demoInviteLink(Uri.parse('http://localhost:8080/#/'));
    expect(link.toString(), 'http://localhost:8080/?invite=gym-khoi-dong');
    expect(isDemoInvite(link), isTrue);
    expect(
      isDemoInvite(Uri.parse('http://localhost:8080/?invite=other')),
      isFalse,
    );
  });

  testWidgets('Create, subscribe, and release one period after check-in', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const PrepaidGuardApp());
    await tester.pumpAndSettle();
    expect(find.text('Tạo gói demo'), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('auth-email')),
      DemoAccounts.exampleEmail,
    );
    await tester.enterText(
      find.byKey(const ValueKey('auth-password')),
      DemoAccounts.examplePassword,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
    await tester.pumpAndSettle();
    expect(find.text('Gói tập của bạn'), findsOneWidget);
    await _switchMode(tester, 'Chế độ Cơ sở');
    expect(find.text('Check-in của cơ sở'), findsOneWidget);
    expect(find.text('Bạn tập'), findsNothing);
    await tester.tap(find.text('Tạo gói'));
    await tester.pumpAndSettle();
    final create = find.text('Tạo gói demo');
    await tester.ensureVisible(create);
    await tester.tap(create);
    await tester.pumpAndSettle();
    expect(find.text('Nhập tên gói.'), findsOneWidget);

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Gym 3 tháng');
    await tester.enterText(fields.at(2), '12,345678');
    await tester.pumpAndSettle();
    expect(find.text('37,037034 USDC thử nghiệm'), findsOneWidget);

    await tester.ensureVisible(create);
    await tester.tap(create);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Xem gói'));
    await tester.pumpAndSettle();
    final createdPlan = find.ancestor(
      of: find.text('Gym 3 tháng'),
      matching: find.byType(Card),
    );
    final customSubscribe = find.descendant(
      of: createdPlan,
      matching: find.text('Đăng ký demo'),
    );
    await tester.ensureVisible(customSubscribe);
    await tester.pumpAndSettle();
    await tester.tap(customSubscribe);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Xác nhận demo'));
    await tester.pumpAndSettle();

    expect(find.text('Gói tập của bạn'), findsOneWidget);
    expect(find.text('Gym 3 tháng'), findsOneWidget);
    expect(find.text('37,037034 USDC'), findsOneWidget);
    expect(find.text('Đã giải ngân 0/3 kỳ'), findsOneWidget);

    await tester.tap(find.text('Check-in kỳ đầu (demo)'));
    await tester.pumpAndSettle();
    expect(find.text('Đang chờ cơ sở xác nhận'), findsOneWidget);
    expect(find.text('37,037034 USDC'), findsOneWidget);
    await _switchMode(tester, 'Chế độ Cơ sở');
    expect(
      find.text('Kỳ 1 · 12,345678 USDC dự kiến giải ngân'),
      findsOneWidget,
    );
    await tester.tap(find.text('Duyệt check-in'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Xác nhận kỳ demo'));
    await tester.pumpAndSettle();
    expect(find.text('Duyệt check-in'), findsNothing);
    await _switchMode(tester, 'Chế độ Hội viên');
    expect(find.text('Gói tập của bạn'), findsOneWidget);
    expect(find.text('24,691356 USDC'), findsOneWidget);
    expect(find.text('Đã giải ngân 1/3 kỳ'), findsOneWidget);
    expect(find.text('Cơ sở xác nhận kỳ đầu'), findsOneWidget);
    expect(find.text('Check-in kỳ đầu (demo)'), findsNothing);

    await tester.tap(find.text('Bạn tập'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Cardio'));
    await tester.pumpAndSettle();
    expect(find.text('Khánh Linh'), findsOneWidget);
    expect(find.text('Minh An'), findsNothing);
    await tester.tap(find.text('Gửi lời mời demo'));
    await tester.pumpAndSettle();
    expect(find.text('Đang chờ phản hồi (demo)'), findsOneWidget);
    await tester.tap(find.text('Hủy lời mời'));
    await tester.pumpAndSettle();
    expect(find.text('Gửi lời mời demo'), findsOneWidget);
    await tester.tap(find.text('Giới thiệu bạn tập'));
    await tester.pumpAndSettle();
    expect(find.text('Rủ bạn cùng tập'), findsOneWidget);
    expect(find.text('Sao chép liên kết'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gói dịch vụ'));
    await tester.pumpAndSettle();

    final twoYearOffer = find.ancestor(
      of: find.text('Gói 24 tháng'),
      matching: find.byType(Card),
    );
    expect(
      find.descendant(of: twoYearOffer, matching: find.text('Tiết kiệm 35%')),
      findsOneWidget,
    );
    final subscribe = find.descendant(
      of: twoYearOffer,
      matching: find.text('Đăng ký demo'),
    );
    await tester.ensureVisible(subscribe);
    await tester.pumpAndSettle();
    await tester.tap(subscribe);
    await tester.pumpAndSettle();
    expect(find.text('Tổng tiền gốc mô phỏng: 249,6 USDC'), findsOneWidget);
    expect(
      find.text('Tặng 15 ngày tập sau khi cơ sở xác nhận check-in kỳ đầu.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Xác nhận demo'));
    await tester.pumpAndSettle();
    expect(find.text('Tổng thời hạn tập: 720 ngày (mô phỏng)'), findsOneWidget);
    await tester.tap(find.text('Check-in kỳ đầu (demo)'));
    await tester.pumpAndSettle();
    expect(find.text('Đã cộng 15 ngày tập'), findsNothing);
    await _switchMode(tester, 'Chế độ Cơ sở');
    await tester.tap(find.text('Duyệt check-in'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Xác nhận kỳ demo'));
    await tester.pumpAndSettle();
    await _switchMode(tester, 'Chế độ Hội viên');
    expect(find.text('239,2 USDC'), findsOneWidget);
    expect(find.text('Đã giải ngân 1/24 kỳ'), findsOneWidget);
    expect(find.text('Tổng thời hạn tập: 735 ngày (mô phỏng)'), findsOneWidget);
    expect(find.text('Hội viên nhận 15 ngày tập thêm'), findsOneWidget);
  });

  testWidgets('Register, sign out, and sign back in during a demo session', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const PrepaidGuardApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chưa có tài khoản? Đăng ký'));
    await tester.pumpAndSettle();

    final email = find.byKey(const ValueKey('auth-email'));
    final password = find.byKey(const ValueKey('auth-password'));
    final confirmation = find.byKey(const ValueKey('auth-confirmation'));
    final register = find.widgetWithText(FilledButton, 'Tạo tài khoản');
    await tester.enterText(email, 'tester@example.com');
    await tester.enterText(password, 'tester123');
    await tester.enterText(confirmation, 'different');
    await tester.ensureVisible(register);
    await tester.tap(register);
    await tester.pumpAndSettle();
    expect(find.text('Hai mật khẩu chưa khớp.'), findsOneWidget);

    await tester.enterText(confirmation, 'tester123');
    await tester.ensureVisible(register);
    await tester.tap(register);
    await tester.pumpAndSettle();
    expect(find.text('Gói tập của bạn'), findsOneWidget);

    await tester.tap(find.byTooltip('Đăng xuất'));
    await tester.pumpAndSettle();
    final signIn = find.widgetWithText(FilledButton, 'Đăng nhập');
    expect(signIn, findsOneWidget);
    await tester.enterText(email, 'TESTER@example.com');
    await tester.enterText(password, 'wrong123');
    await tester.ensureVisible(signIn);
    await tester.tap(signIn);
    await tester.pumpAndSettle();
    expect(find.text('Email hoặc mật khẩu demo chưa đúng.'), findsOneWidget);

    await tester.enterText(password, 'tester123');
    await tester.ensureVisible(signIn);
    await tester.tap(signIn);
    await tester.pumpAndSettle();
    expect(find.text('Gói tập của bạn'), findsOneWidget);

    await tester.tap(find.text('Khám phá gói tập'));
    await tester.pumpAndSettle();
    final threeMonthOffer = find.ancestor(
      of: find.text('Gói 3 tháng'),
      matching: find.byType(Card),
    );
    final subscribe = find.descendant(
      of: threeMonthOffer,
      matching: find.text('Đăng ký demo'),
    );
    await tester.ensureVisible(subscribe);
    await tester.pumpAndSettle();
    await tester.tap(subscribe);
    await tester.pumpAndSettle();
    expect(find.text('3 tháng × 14,4 USDC'), findsOneWidget);
    expect(find.text('Tổng tiền gốc mô phỏng: 43,2 USDC'), findsOneWidget);
    await tester.tap(find.text('Xác nhận demo'));
    await tester.pumpAndSettle();
    final checkIn = find.text('Check-in kỳ đầu (demo)');
    final balance = find.text('Tiền gốc còn lại');
    expect(checkIn, findsOneWidget);
    expect(find.text('43,2 USDC'), findsOneWidget);
    expect(
      tester.getTopLeft(checkIn).dy,
      lessThan(tester.getTopLeft(balance).dy),
    );
    await tester.tap(find.text('Đăng ký gói tập'));
    await tester.pumpAndSettle();
    final enrolled = find.descendant(
      of: threeMonthOffer,
      matching: find.text('Đã đăng ký'),
    );
    expect(enrolled, findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.ancestor(
              of: enrolled,
              matching: find.byWidgetPredicate(
                (widget) => widget is FilledButton,
              ),
            ),
          )
          .onPressed,
      isNull,
    );
  });
}
