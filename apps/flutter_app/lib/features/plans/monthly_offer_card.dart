import 'package:flutter/material.dart';

import '../../app/prepaid_guard_theme.dart';
import 'demo_plan.dart';

class MonthlyOfferCard extends StatelessWidget {
  const MonthlyOfferCard({
    super.key,
    required this.plan,
    required this.subscribed,
    required this.onSubscribe,
  });

  final DemoPlan plan;
  final bool subscribed;
  final VoidCallback onSubscribe;

  @override
  Widget build(BuildContext context) {
    final type = Theme.of(context).textTheme;
    final discounted = plan.discountPercent > 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              plan.title,
              style: type.labelLarge?.copyWith(color: mutedText),
            ),
            const SizedBox(height: 5),
            Text('Gói ${plan.periods} tháng', style: type.titleLarge),
            const SizedBox(height: 14),
            Text(
              '${formatTokenAmount(plan.pricePerPeriod)} USDC',
              style: type.headlineSmall?.copyWith(
                color: accent,
                fontWeight: FontWeight.w800,
              ),
            ),
            const Text('mỗi tháng', style: TextStyle(color: mutedText)),
            const SizedBox(height: 10),
            Text(
              discounted
                  ? 'Tiết kiệm ${plan.discountPercent}%'
                  : 'Giá chuẩn theo tháng',
              style: TextStyle(
                color: discounted ? accent : mutedText,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              discounted
                  ? 'Giảm ${formatTokenAmount(plan.savings)} USDC'
                  : 'Thời hạn 1 tháng',
              style: const TextStyle(color: mutedText),
            ),
            if (plan.bonusDaysAfterCheckIn > 0) ...[
              const SizedBox(height: 8),
              Text(
                '+${plan.bonusDaysAfterCheckIn} ngày tập khi duyệt check-in đầu',
                style: const TextStyle(color: accent),
              ),
            ],
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            const Text('Tổng tiền gốc', style: TextStyle(color: mutedText)),
            Text(
              '${formatTokenAmount(plan.total)} USDC',
              style: type.titleMedium,
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: subscribed ? null : onSubscribe,
              icon: Icon(subscribed ? Icons.check : Icons.arrow_forward),
              label: Text(subscribed ? 'Đã đăng ký' : 'Đăng ký demo'),
            ),
          ],
        ),
      ),
    );
  }
}
