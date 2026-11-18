import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/demo_test_app.dart';
import 'package:prepaid_guard/features/auth/demo_accounts.dart';
import 'package:prepaid_guard/features/training/demo_training.dart';

void main() {
  test('Training bookings reject past and overlapping slots across gyms', () {
    final day = DateTime(2026, 11, 15);
    final bookings = DemoTrainingBookings();
    final morning = demoGyms.first.schedule(day, personal: false).first;
    final otherGym = demoGyms[1].schedule(day, personal: false).first;
    final coach = demoGyms.first.schedule(day, personal: true).first;

    expect(bookings.add(morning, morning.startsAt), isFalse);
    expect(bookings.add(morning, day), isTrue);
    expect(bookings.add(morning, day), isFalse);
    expect(bookings.add(otherGym, day), isFalse);
    expect(bookings.add(coach, day), isTrue);
    expect(bookings.slots, [morning, coach]);
    bookings.remove(morning);
    expect(bookings.add(otherGym, day), isTrue);
  });

  testWidgets('Browse a gym, book a class, and cancel on mobile', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Future<void> tapVisible(Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    await tester.pumpWidget(const DemoTestApp());
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('auth-email')),
      DemoAccounts.exampleEmail,
    );
    await tester.enterText(
      find.byKey(const ValueKey('auth-password')),
      DemoAccounts.examplePassword,
    );
    await tapVisible(find.widgetWithText(FilledButton, 'Đăng nhập'));
    await tapVisible(find.text('Giờ đông & cơ sở'));
    expect(find.text('39 / 80 người'), findsOneWidget);
    expect(find.text('00:00'), findsOneWidget);
    expect(find.text('24:00'), findsOneWidget);
    await tapVisible(find.byKey(const ValueKey('traffic-hour-18')));
    expect(find.text('68 / 80 người'), findsOneWidget);
    await tapVisible(find.byKey(const ValueKey('traffic-hour-23')));
    expect(find.text('23:00 · Đã đóng cửa'), findsOneWidget);
    expect(find.text('0 / 80 người'), findsOneWidget);
    await tapVisible(find.byKey(const ValueKey('traffic-hour-13')));
    await tapVisible(find.text('Hôm qua'));
    expect(find.text('33 / 80 người'), findsOneWidget);
    await tapVisible(find.widgetWithText(ListTile, 'PrepaidGuard Riverside'));
    expect(find.text('28 / 65 người'), findsOneWidget);
    await tapVisible(find.widgetWithText(ChoiceChip, 'Lớp học'));
    expect(find.text('Mobility Flow'), findsOneWidget);
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    await tapVisible(find.text('${tomorrow.day}/${tomorrow.month}'));
    final classCard = find.ancestor(
      of: find.text('Mobility Flow'),
      matching: find.byType(Card),
    );
    await tapVisible(
      find.descendant(of: classCard, matching: find.text('Chọn giờ này')),
    );
    await tapVisible(find.text('Đặt lịch demo'));
    expect(find.text('Đã đặt'), findsOneWidget);
    await tapVisible(find.widgetWithText(ChoiceChip, 'Huấn luyện viên'));
    expect(find.text('Minh Trần'), findsOneWidget);
    await tapVisible(find.widgetWithText(ChoiceChip, 'Lịch của tôi'));
    expect(find.text('Mobility Flow'), findsOneWidget);
    await tapVisible(find.text('Hủy lịch demo'));
    expect(find.text('Mobility Flow'), findsNothing);
  });
}
