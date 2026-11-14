import 'demo_plan.dart';

List<DemoPlan> buildGymOffers() {
  final monthlyListPrice = BigInt.from(16000000);
  const tiers = [
    (1, 0, 'Gym Linh Hoạt', 'Thử phòng tập và lịch tập trong một tháng.', 0),
    (3, 10, 'Gym Khởi Động', 'Tạo thói quen tập luyện đều đặn.', 0),
    (6, 20, 'Gym Bền Bỉ', 'Dành cho một mục tiêu tập luyện dài hơi.', 0),
    (12, 25, 'Gym Cả Năm', 'Duy trì lịch tập suốt một năm.', 7),
    (24, 35, 'Gym Hai Năm', 'Chi phí bình quân thấp nhất trong các gói.', 15),
  ];

  return [
    for (final (months, discount, title, description, bonusDays) in tiers)
      DemoPlan(
        title: title,
        description: description,
        pricePerPeriod:
            monthlyListPrice * BigInt.from(100 - discount) ~/ BigInt.from(100),
        periods: months,
        daysPerPeriod: 30,
        monthlyListPrice: monthlyListPrice,
        bonusDaysAfterCheckIn: bonusDays,
        provider: 'PrepaidGuard Gym',
      ),
  ];
}
