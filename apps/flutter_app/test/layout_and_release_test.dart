import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prepaid_guard/app/demo_workspace.dart';
import 'package:prepaid_guard/app/prepaid_guard_theme.dart';

import 'package:prepaid_guard/features/plans/demo_plan.dart';
import 'package:prepaid_guard/features/plans/plan_catalog.dart';
import 'package:prepaid_guard/features/plans/plan_comparison.dart';
import 'package:prepaid_guard/features/subscriptions/demo_membership.dart';
import 'package:prepaid_guard/features/subscriptions/membership_card.dart';
import 'package:prepaid_guard/features/merchant/merchant_dashboard.dart';
import 'package:prepaid_guard/features/training/demo_training.dart';
import 'package:prepaid_guard/features/training/training_page.dart';
import 'package:prepaid_guard/real/screen.dart';
import 'real_mode_test.dart' as f;

void main() {
  test(
    'review: 128 generated release sequences preserve principal and reject stale approval',
    () {
      final rng = Random(1115);
      for (var run = 0; run < 128; run++) {
        final periods = 1 + rng.nextInt(120);
        final price =
            (BigInt.one << rng.nextInt(80)) +
            BigInt.from(1 + rng.nextInt(1000000));
        final workspace = DemoWorkspace();
        final plan = DemoPlan(
          title: 'Generated',
          description: '',
          pricePerPeriod: price,
          periods: periods,
          daysPerPeriod: 30,
          bonusDaysAfterCheckIn: 7,
        );
        workspace.createPlan('merchant', plan);
        workspace.subscribe('subscriber', plan);
        final member = workspace.memberships('subscriber')[plan]!;
        expect(
          workspace.confirmCheckIn('outsider', member, period: 1),
          isFalse,
        );
        for (var period = 1; period <= periods; period++) {
          expect(member.requestCheckIn(), isTrue);
          expect(member.requestCheckIn(), isFalse);
          expect(
            workspace.confirmCheckIn('merchant', member, period: period + 1),
            isFalse,
          );
          expect(
            workspace.confirmCheckIn('merchant', member, period: period),
            isTrue,
          );
          expect(
            workspace.confirmCheckIn('merchant', member, period: period),
            isFalse,
          );
          expect(member.remaining + member.released, plan.total);
          expect(member.remaining, greaterThanOrEqualTo(BigInt.zero));
          expect(member.releasedPeriods, period);
          expect(member.earnedBonusDays, 7);
        }
        expect(member.status, DemoCheckInStatus.confirmed);
        expect(member.requestCheckIn(), isFalse);
        expect(member.remaining, BigInt.zero);
        expect(workspace.memberships('outsider'), isEmpty);
      }
    },
  );

  for (final width in [320.0, 390.0, 800.0]) {
    for (final scale in [1.0, 1.5, 2.0]) {
      for (final page in [
        'catalog',
        'member',
        'merchant',
        'training',
        'comparison',
        'real',
      ]) {
        testWidgets('review layout $page width=$width scale=$scale', (
          tester,
        ) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final workspace = DemoWorkspace();
          final plan = workspace.samplePlan;
          workspace.subscribe('subscriber', plan);
          final membership = workspace.memberships('subscriber')[plan]!;
          membership.requestCheckIn();
          Widget child;
          switch (page) {
            case 'catalog':
              child = PlanCatalog(
                plans: workspace.plans,
                subscribedPlans: {plan},
                onSubscribe: (_) {},
              );
            case 'member':
              child = MembershipCard(
                membership: membership,
                onRequestCheckIn: () {},
              );
            case 'merchant':
              child = MerchantDashboard(
                pending: [membership],
                confirmed: [],
                onConfirm: (_, _) {},
                onCreatePlan: () {},
                onHistory: () {},
              );
            case 'training':
              child = TrainingPage(
                view: TrainingView.facilities,
                onViewChanged: (_) {},
                gym: demoGyms.first,
                onGymChanged: (_) {},
                bookings: DemoTrainingBookings(),
              );
            case 'comparison':
              child = PlanComparison(
                plans: workspace.plans,
                subscribedPlans: {plan},
              );
            default:
              child = RealWorkspaceScreen(
                controller: await f.signedIn(),
                onDemo: () {},
              );
          }
          await tester.pumpWidget(
            MaterialApp(
              theme: prepaidGuardTheme(),
              locale: const Locale('vi'),
              supportedLocales: const [Locale('vi')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              builder: (context, widget) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: widget!,
              ),
              home: page == 'real'
                  ? child
                  : Scaffold(
                      body: SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: child,
                      ),
                    ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
        });
      }
    }
  }
}
