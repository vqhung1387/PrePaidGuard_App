import '../features/auth/demo_accounts.dart';
import '../features/plans/demo_plan.dart';
import '../features/plans/gym_offers.dart';
import '../features/subscriptions/demo_membership.dart';
import '../features/training/demo_training.dart';

class DemoWorkspace {
  final _gymOffers = buildGymOffers();
  late final samplePlan = _gymOffers.firstWhere((plan) => plan.periods == 3);

  late final _owners = <DemoPlan, String>{
    for (final plan in _gymOffers) plan: DemoAccounts.exampleEmail,
    DemoPlan(
      title: 'Yoga nền tảng',
      description: 'Thực hành tư thế, nhịp thở và độ linh hoạt theo từng kỳ.',
      category: ServiceCategory.yoga,
      provider: 'An Yoga Studio',
      pricePerPeriod: BigInt.from(18000000),
      periods: 3,
      daysPerPeriod: 30,
    ): DemoAccounts.exampleEmail,
    DemoPlan(
      title: 'Tiếng Anh giao tiếp',
      description: 'Luyện phản xạ nói theo chủ đề trong sáu kỳ học.',
      category: ServiceCategory.course,
      provider: 'SpeakLab',
      pricePerPeriod: BigInt.from(24000000),
      periods: 6,
      daysPerPeriod: 30,
    ): DemoAccounts.exampleEmail,
    DemoPlan(
      title: 'Excel thực hành',
      description:
          'Làm sạch dữ liệu, dùng hàm tra cứu và lập báo cáo với PivotTable.',
      category: ServiceCategory.course,
      provider: 'DataLab',
      pricePerPeriod: BigInt.from(16000000),
      periods: 2,
      daysPerPeriod: 30,
    ): DemoAccounts.exampleEmail,
    DemoPlan(
      title: 'Thiết kế UI với Figma',
      description:
          'Thiết kế giao diện, xây bộ thành phần và tạo bản mẫu tương tác.',
      category: ServiceCategory.course,
      provider: 'DesignLab',
      pricePerPeriod: BigInt.from(22000000),
      periods: 4,
      daysPerPeriod: 30,
    ): DemoAccounts.exampleEmail,
  };
  final _memberships = <String, Map<DemoPlan, DemoMembership>>{};
  final _connections = <String, Set<String>>{};
  final _training = <String, DemoTrainingBookings>{};

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

  Iterable<DemoPlan> merchantPlans(String merchantEmail) => _owners.entries
      .where((entry) => entry.value == merchantEmail)
      .map((entry) => entry.key);

  Iterable<DemoMembership> merchantMemberships(String merchantEmail) =>
      _memberships.values
          .expand((account) => account.values)
          .where((membership) => _owners[membership.plan] == merchantEmail);

  Iterable<DemoMembership> pendingCheckIns(String merchantEmail) =>
      merchantMemberships(merchantEmail).where(
        (membership) => membership.status == DemoCheckInStatus.awaitingMerchant,
      );

  bool confirmCheckIn(
    String merchantEmail,
    DemoMembership membership, {
    required int period,
  }) {
    if (_owners[membership.plan] != merchantEmail ||
        _memberships[membership.memberEmail]?[membership.plan] != membership) {
      return false;
    }
    return membership.confirmCheckIn(period: period);
  }

  Set<String> connections(String email) =>
      _connections.putIfAbsent(email, () => <String>{});

  DemoTrainingBookings trainingBookings(String email) =>
      _training.putIfAbsent(email, DemoTrainingBookings.new);
}
