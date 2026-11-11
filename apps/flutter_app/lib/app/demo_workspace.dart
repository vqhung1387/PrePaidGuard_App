import '../features/auth/demo_accounts.dart';
import '../features/plans/demo_plan.dart';
import '../features/plans/gym_offers.dart';
import '../features/subscriptions/demo_membership.dart';

class DemoWorkspace {
  final _gymOffers = buildGymOffers();
  late final samplePlan = _gymOffers.firstWhere((plan) => plan.periods == 3);

  late final _owners = <DemoPlan, String>{
    for (final plan in _gymOffers) plan: DemoAccounts.exampleEmail,
  };
  final _memberships = <String, Map<DemoPlan, DemoMembership>>{};
  final _connections = <String, Set<String>>{};

  List<DemoPlan> get plans => _owners.keys.toList(growable: false);

  void createPlan(String email, DemoPlan plan) {
    _owners[plan] = email;
  }

  Map<DemoPlan, DemoMembership> memberships(String email) =>
      _memberships.putIfAbsent(email, () => {});

  void subscribe(String email, DemoPlan plan) {
    if (!_owners.containsKey(plan)) return;
    memberships(
      email,
    ).putIfAbsent(plan, () => DemoMembership(plan: plan, memberEmail: email));
  }

  Iterable<DemoMembership> pendingCheckIns(String merchantEmail) => _memberships
      .values
      .expand((account) => account.values)
      .where(
        (membership) =>
            _owners[membership.plan] == merchantEmail &&
            membership.status == DemoCheckInStatus.awaitingMerchant,
      );

  bool confirmCheckIn(String merchantEmail, DemoMembership membership) {
    if (_owners[membership.plan] != merchantEmail ||
        _memberships[membership.memberEmail]?[membership.plan] != membership) {
      return false;
    }
    return membership.confirmCheckIn();
  }

  Set<String> connections(String email) =>
      _connections.putIfAbsent(email, () => <String>{});
}
