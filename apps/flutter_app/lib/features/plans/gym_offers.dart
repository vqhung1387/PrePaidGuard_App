import 'demo_plan.dart';

List<DemoPlan> buildGymOffers() {
  final monthlyListPrice = BigInt.from(16000000);
  const tiers = [
    (1, 0, 'Gym Linh Hoạt', 0),
    (3, 10, 'Gym Khởi Động', 0),
    (6, 20, 'Gym Bền Bỉ', 0),
    (12, 25, 'Gym Cả Năm', 7),
    (24, 35, 'Gym Hai Năm', 15),
  ];

  return [
    for (final (months, discount, title, bonusDays) in tiers)
      DemoPlan(
        title: title,
        description: '',
        pricePerPeriod:
            monthlyListPrice * BigInt.from(100 - discount) ~/ BigInt.from(100),
        periods: months,
        daysPerPeriod: 30,
        monthlyListPrice: monthlyListPrice,
        bonusDaysAfterCheckIn: bonusDays,
      ),
  ];
}
