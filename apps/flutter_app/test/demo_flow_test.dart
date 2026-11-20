import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prepaid_guard/app/prepaid_guard_theme.dart';
import 'package:prepaid_guard/app/demo_workspace.dart';
import 'support/demo_test_app.dart';
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
      final offers = workspace.plans
          .where((plan) => plan.monthlyListPrice != null)
          .toList();
      expect(workspace.plans.map((plan) => plan.category).toSet(), {
        ServiceCategory.gym,
        ServiceCategory.yoga,
        ServiceCategory.course,
      });
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
        expect(
          workspace.confirmCheckIn(customer, membership, period: 1),
          isFalse,
        );
        expect(
          workspace.confirmCheckIn(
            DemoAccounts.exampleEmail,
            membership,
            period: 1,
          ),
          isTrue,
        );
        expect(
          workspace.confirmCheckIn(
            DemoAccounts.exampleEmail,
            membership,
            period: 1,
          ),
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
    expect(parseTokenAmount('0.001'), BigInt.from(1000));
    expect(parseTokenAmount('0,001'), BigInt.from(1000));
    expect(parseTokenAmount('1,0010'), BigInt.from(1001000));
    expect(parseTokenAmount('1000'), BigInt.from(1000000000));
    expect(parseTokenAmount('  2500,5  '), BigInt.from(2500500000));
    expect(parseTokenAmount('0.0000001'), isNull);
    expect(parseTokenAmount('1e3'), isNull);
    expect(parseTokenAmount('0'), isNull);
    for (final ambiguous in [
      '1.000',
      '10.000',
      '100.000',
      '1,000',
      '1.000.000',
      '1.234,56',
      '1 000',
    ]) {
      expect(parseTokenAmount(ambiguous), isNull, reason: ambiguous);
      expect(
        validateTokenAmountInput(ambiguous),
        isNotNull,
        reason: ambiguous,
      );
    }
    expect(
      validateTokenAmountInput('1.000'),
      contains('Không dùng dấu hàng nghìn'),
    );
    expect(validateTokenAmountInput('0.1234567'), contains('6 chữ số'));
    expect(validateTokenAmountInput('1000'), isNull);
    expect(formatTokenAmount(BigInt.parse('1234000001')), '1.234,000001');
  });

  test('Only the plan owner can confirm a pending check-in once', () {
    final workspace = DemoWorkspace();
    final plan = workspace.samplePlan;
    const customer = 'customer@example.com';
    workspace.subscribe(customer, plan);
    final membership = workspace.memberships(customer)[plan]!;
    expect(
      workspace.confirmCheckIn(
        DemoAccounts.exampleEmail,
        membership,
        period: 1,
      ),
      isFalse,
    );
    expect(membership.requestCheckIn(), isTrue);
    expect(membership.requestCheckIn(), isFalse);
    expect(membership.remaining, plan.total);
    expect(workspace.pendingCheckIns(customer), isEmpty);
    expect(workspace.confirmCheckIn(customer, membership, period: 1), isFalse);
    expect(
      workspace.confirmCheckIn(
        DemoAccounts.exampleEmail,
        membership,
        period: 1,
      ),
      isTrue,
    );
    expect(
      workspace.confirmCheckIn(
        DemoAccounts.exampleEmail,
        membership,
        period: 1,
      ),
      isFalse,
    );
    expect(membership.remaining + membership.released, plan.total);
    for (var period = 2; period <= plan.periods; period++) {
      expect(membership.requestCheckIn(), isTrue);
      expect(
        workspace.confirmCheckIn(
          DemoAccounts.exampleEmail,
          membership,
          period: period - 1,
        ),
        isFalse,
      );
      expect(
        workspace.confirmCheckIn(
          DemoAccounts.exampleEmail,
          membership,
          period: period,
        ),
        isTrue,
      );
    }
    expect(membership.releases.map((release) => release.period), [1, 2, 3]);
    expect(membership.remaining, BigInt.zero);
    expect(membership.released, plan.total);
    expect(membership.requestCheckIn(), isFalse);
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

    await tester.pumpWidget(const DemoTestApp());
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
    await tester.tap(find.text('Quản lý gói'));
    await tester.pumpAndSettle();
    expect(find.text('Gói của cơ sở (9)'), findsOneWidget);
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
    await tester.enterText(fields.at(2), '1.000');
    await tester.pumpAndSettle();
    expect(find.textContaining('Không dùng dấu hàng nghìn'), findsOneWidget);
    await tester.enterText(fields.at(2), '12,345678');
    await tester.pumpAndSettle();
    expect(find.textContaining('Không dùng dấu hàng nghìn'), findsNothing);
    expect(find.text('37,037034 PG Credit thử nghiệm'), findsOneWidget);

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
    expect(find.text('37,037034 PG Credit'), findsOneWidget);
    expect(find.text('Đã giải ngân 0/3 kỳ'), findsOneWidget);

    await tester.tap(find.text('Check-in kỳ đầu (demo)'));
    await tester.pumpAndSettle();
    expect(find.text('Đang chờ cơ sở xác nhận'), findsOneWidget);
    expect(find.text('37,037034 PG Credit'), findsOneWidget);
    await _switchMode(tester, 'Chế độ Cơ sở');
    expect(find.text('12,345678 PG Credit'), findsOneWidget);
    expect(
      find.text('Kỳ 1 · 12,345678 PG Credit dự kiến giải ngân'),
      findsOneWidget,
    );
    final queueSearch = find.widgetWithText(
      TextField,
      'Tìm theo email hoặc tên gói',
    );
    await tester.enterText(queueSearch, 'no-match@example.com');
    await tester.pumpAndSettle();
    expect(find.text('Không tìm thấy yêu cầu phù hợp.'), findsOneWidget);
    expect(find.text('Duyệt check-in'), findsNothing);
    await tester.enterText(queueSearch, 'GYM 3');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Duyệt check-in'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Xác nhận kỳ demo'));
    await tester.pumpAndSettle();
    expect(find.text('Duyệt check-in'), findsNothing);
    expect(find.text('12,345678 PG Credit'), findsOneWidget);
    await tester.tap(find.text('Lịch sử'));
    await tester.pumpAndSettle();
    expect(find.text('12,345678 PG Credit đã giải ngân'), findsOneWidget);
    await tester.tap(find.text('Quản lý gói'));
    await tester.pumpAndSettle();
    final managedPlan = find.ancestor(
      of: find.text('Gym 3 tháng'),
      matching: find.byType(Card),
    );
    expect(
      find.descendant(of: managedPlan, matching: find.text('1 lượt đăng ký')),
      findsOneWidget,
    );
    await _switchMode(tester, 'Chế độ Hội viên');
    expect(find.text('Gói tập của bạn'), findsOneWidget);
    expect(find.text('24,691356 PG Credit'), findsOneWidget);
    expect(find.text('Đã giải ngân 1/3 kỳ'), findsOneWidget);
    expect(find.text('Cơ sở xác nhận kỳ đầu'), findsOneWidget);
    expect(find.text('Check-in kỳ đầu (demo)'), findsNothing);
    expect(find.text('Check-in kỳ 2 (demo)'), findsOneWidget);
    await tester.tap(find.text('Xem từng kỳ giải ngân'));
    await tester.pumpAndSettle();
    expect(find.text('Kỳ 2 · 12,345678 PG Credit'), findsOneWidget);
    expect(find.text('1/3 kỳ đã giải ngân · PG Credit mô phỏng'), findsOneWidget);
    expect(find.text('Chờ hoàn thành các kỳ trước'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Đóng'));
    await tester.pumpAndSettle();

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

    final comparePlans = find.text('So sánh các gói');
    await tester.ensureVisible(comparePlans);
    await tester.pumpAndSettle();
    final courseFilter = find.widgetWithText(ChoiceChip, 'Khóa học');
    await tester.ensureVisible(courseFilter);
    await tester.pumpAndSettle();
    await tester.tap(courseFilter);
    await tester.pumpAndSettle();
    expect(find.text('Tiếng Anh giao tiếp'), findsOneWidget);
    expect(find.text('Excel thực hành'), findsOneWidget);
    expect(find.text('Thiết kế UI với Figma'), findsOneWidget);
    final sortPlans = find.byTooltip('Sắp xếp gói');
    await tester.ensureVisible(sortPlans);
    await tester.pumpAndSettle();
    await tester.tap(sortPlans);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trả trước thấp nhất'));
    await tester.pumpAndSettle();
    final excelPosition = tester.getTopLeft(find.text('Excel thực hành'));
    final englishPosition = tester.getTopLeft(find.text('Tiếng Anh giao tiếp'));
    expect(excelPosition.dy, lessThanOrEqualTo(englishPosition.dy));
    if (excelPosition.dy == englishPosition.dy) {
      expect(excelPosition.dx, lessThan(englishPosition.dx));
    }
    await tester.tap(sortPlans);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mặc định'));
    await tester.pumpAndSettle();
    final serviceSearch = find.byKey(const ValueKey('service-search'));
    await tester.ensureVisible(serviceSearch);
    await tester.pumpAndSettle();
    await tester.enterText(serviceSearch, 'thiet ke');
    await tester.pumpAndSettle();
    expect(find.text('1 gói phù hợp'), findsOneWidget);
    expect(find.text('Thiết kế UI với Figma'), findsOneWidget);
    expect(find.text('Excel thực hành'), findsNothing);
    await tester.enterText(serviceSearch, 'datalab');
    await tester.pumpAndSettle();
    expect(find.text('Excel thực hành'), findsOneWidget);
    await tester.enterText(serviceSearch, 'no match');
    await tester.pumpAndSettle();
    expect(find.text('Không tìm thấy gói phù hợp'), findsOneWidget);
    await tester.tap(find.byTooltip('Xóa tìm kiếm'));
    await tester.pumpAndSettle();
    expect(find.text('3 gói phù hợp'), findsOneWidget);
    expect(find.text('Gói 3 tháng'), findsNothing);
    await tester.ensureVisible(comparePlans);
    await tester.pumpAndSettle();
    await tester.tap(comparePlans);
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(AlertDialog, 'So sánh gói dịch vụ'),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(DataTable),
        matching: find.text('Excel thực hành'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(DataTable),
        matching: find.text('32 PG Credit'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Đóng so sánh'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Mọi dịch vụ'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(comparePlans);
    await tester.pumpAndSettle();
    await tester.tap(comparePlans);
    await tester.pumpAndSettle();
    expect(find.byType(DataTable), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(DataTable),
        matching: find.text('249,6 PG Credit'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Đóng so sánh'));
    await tester.pumpAndSettle();
    final longTermFilter = find.widgetWithText(ChoiceChip, '12–24 tháng');
    await tester.ensureVisible(longTermFilter);
    await tester.pumpAndSettle();
    await tester.tap(longTermFilter);
    await tester.pumpAndSettle();
    expect(find.text('Gói 3 tháng'), findsNothing);

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
    expect(find.text('Tổng tiền gốc mô phỏng: 249,6 PG Credit'), findsOneWidget);
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
    expect(find.text('239,2 PG Credit'), findsOneWidget);
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

    await tester.pumpWidget(const DemoTestApp());
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

    final checkInShortcut = find.text('Xác nhận sử dụng');
    await tester.ensureVisible(checkInShortcut);
    await tester.pumpAndSettle();
    await tester.tap(checkInShortcut);
    await tester.pumpAndSettle();
    expect(
      find.text('Bạn cần đăng ký một gói dịch vụ trước khi gửi check-in.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Tổng quan'));
    await tester.pumpAndSettle();
    final payoutShortcut = find.text('Giải ngân theo kỳ');
    await tester.ensureVisible(payoutShortcut);
    await tester.pumpAndSettle();
    await tester.tap(payoutShortcut);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AlertDialog, 'Xem gói dịch vụ'), findsOneWidget);
    await tester.tap(find.text('Đóng'));
    await tester.pumpAndSettle();
    final plansShortcut = find.text('Đăng ký dịch vụ');
    await tester.ensureVisible(plansShortcut);
    await tester.pumpAndSettle();
    await tester.tap(plansShortcut);
    await tester.pumpAndSettle();
    await tester.tap(find.text('So sánh các gói'));
    await tester.pumpAndSettle();
    expect(find.text('Trả trước 16 PG Credit'), findsOneWidget);
    expect(find.byType(DataTable), findsNothing);
    final firstComparedPlan = find.ancestor(
      of: find.text('Trả trước 16 PG Credit'),
      matching: find.byType(Card),
    );
    final chooseComparedPlan = find.descendant(
      of: firstComparedPlan,
      matching: find.text('Chọn gói'),
    );
    await tester.ensureVisible(chooseComparedPlan);
    await tester.pumpAndSettle();
    await tester.tap(chooseComparedPlan);
    await tester.pumpAndSettle();
    expect(find.text('Tổng tiền gốc mô phỏng: 16 PG Credit'), findsOneWidget);
    await tester.tap(find.text('Quay lại'));
    await tester.pumpAndSettle();
    final threeMonthOffer = find.ancestor(
      of: find.text('Gói 3 tháng'),
      matching: find.byType(Card),
    );
    final sixMonthOffer = find.ancestor(
      of: find.text('Gói 6 tháng'),
      matching: find.byType(Card),
    );
    Color outline(Finder card) =>
        (tester.widget<Card>(card).shape! as RoundedRectangleBorder).side.color;
    expect(outline(sixMonthOffer), panelOutline);
    final sixMonthTitle = find.text('Gói 6 tháng');
    await tester.ensureVisible(sixMonthTitle);
    await tester.pumpAndSettle();
    await tester.tap(sixMonthTitle);
    await tester.pumpAndSettle();
    expect(outline(sixMonthOffer), accent);
    expect(find.byType(AlertDialog), findsNothing);
    final threeMonthTitle = find.text('Gói 3 tháng');
    await tester.ensureVisible(threeMonthTitle);
    await tester.pumpAndSettle();
    await tester.tap(threeMonthTitle);
    await tester.pumpAndSettle();
    expect(outline(threeMonthOffer), accent);
    expect(outline(sixMonthOffer), panelOutline);
    final subscribe = find.descendant(
      of: threeMonthOffer,
      matching: find.text('Đăng ký demo'),
    );
    await tester.ensureVisible(subscribe);
    await tester.pumpAndSettle();
    await tester.tap(subscribe);
    await tester.pumpAndSettle();
    expect(find.text('3 tháng × 14,4 PG Credit'), findsOneWidget);
    expect(find.text('Tổng tiền gốc mô phỏng: 43,2 PG Credit'), findsOneWidget);
    await tester.tap(find.text('Xác nhận demo'));
    await tester.pumpAndSettle();
    final checkIn = find.text('Check-in kỳ đầu (demo)');
    final balance = find.text('Tiền gốc còn lại');
    expect(checkIn, findsOneWidget);
    expect(find.text('43,2 PG Credit'), findsOneWidget);
    expect(
      tester.getTopLeft(checkIn).dy,
      lessThan(tester.getTopLeft(balance).dy),
    );
    final browseAgain = find.text('Đăng ký gói tập');
    await tester.ensureVisible(browseAgain);
    await tester.pumpAndSettle();
    await tester.tap(browseAgain);
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
