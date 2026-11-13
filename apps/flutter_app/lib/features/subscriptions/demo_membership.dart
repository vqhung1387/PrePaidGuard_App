import '../plans/demo_plan.dart';

enum DemoCheckInStatus { ready, awaitingMerchant, confirmed }

class DemoMembership {
  DemoMembership({required this.plan, required this.memberEmail});

  final DemoPlan plan;
  final String memberEmail;
  DemoCheckInStatus _status = DemoCheckInStatus.ready;

  DemoCheckInStatus get status => _status;
  int get releasedPeriods => _status == DemoCheckInStatus.confirmed ? 1 : 0;
  BigInt get released => plan.pricePerPeriod * BigInt.from(releasedPeriods);
  BigInt get remaining => plan.total - released;
  int get earnedBonusDays =>
      _status == DemoCheckInStatus.confirmed ? plan.bonusDaysAfterCheckIn : 0;
  int get accessDays => plan.accessDays + earnedBonusDays;

  bool requestCheckIn() {
    if (_status != DemoCheckInStatus.ready) return false;
    _status = DemoCheckInStatus.awaitingMerchant;
    return true;
  }

  bool confirmCheckIn() {
    if (_status != DemoCheckInStatus.awaitingMerchant) return false;
    _status = DemoCheckInStatus.confirmed;
    return true;
  }
}
