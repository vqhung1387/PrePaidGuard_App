import '../plans/demo_plan.dart';

enum DemoCheckInStatus { ready, awaitingMerchant, confirmed }

class DemoRelease {
  const DemoRelease({
    required this.period,
    required this.amount,
    required this.confirmedAt,
  });

  final int period;
  final BigInt amount;
  final DateTime confirmedAt;
}

class DemoMembership {
  DemoMembership({required this.plan, required this.memberEmail});

  final DemoPlan plan;
  final String memberEmail;
  DateTime? _requestedAt;
  final _releases = <DemoRelease>[];

  DemoCheckInStatus get status {
    if (_requestedAt != null) return DemoCheckInStatus.awaitingMerchant;
    if (releasedPeriods == plan.periods) return DemoCheckInStatus.confirmed;
    return DemoCheckInStatus.ready;
  }

  DateTime? get requestedAt => _requestedAt;
  List<DemoRelease> get releases => List.unmodifiable(_releases);
  int get releasedPeriods => _releases.length;
  int get nextPeriod => releasedPeriods + 1;
  BigInt get released => plan.pricePerPeriod * BigInt.from(releasedPeriods);
  BigInt get remaining => plan.total - released;
  int get earnedBonusDays =>
      _releases.isNotEmpty ? plan.bonusDaysAfterCheckIn : 0;
  int get accessDays => plan.accessDays + earnedBonusDays;

  bool requestCheckIn() {
    if (status != DemoCheckInStatus.ready) return false;
    _requestedAt = DateTime.now();
    return true;
  }

  bool confirmCheckIn({required int period}) {
    if (status != DemoCheckInStatus.awaitingMerchant || period != nextPeriod) {
      return false;
    }
    _releases.add(
      DemoRelease(
        period: period,
        amount: plan.pricePerPeriod,
        confirmedAt: DateTime.now(),
      ),
    );
    _requestedAt = null;
    return true;
  }
}
