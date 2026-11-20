import 'package:flutter/material.dart';

import '../../app/prepaid_guard_theme.dart';
import 'demo_plan.dart';

class MonthlyOfferCard extends StatelessWidget {
  const MonthlyOfferCard({
    super.key,
    required this.plan,
    required this.subscribed,
    required this.selected,
    required this.onSelect,
    required this.onSubscribe,
  });

  final DemoPlan plan;
  final bool subscribed;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onSubscribe;

  @override
  Widget build(BuildContext context) {
    final type = Theme.of(context).textTheme;
    final discounted = plan.discountPercent > 0;
    final featured = plan.periods == 6;
    return Card(
      clipBehavior: Clip.antiAlias,
      color: selected ? panelRaised : panel,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: selected ? accent : panelOutline),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Semantics(
        selected: selected,
        child: InkWell(
          onTap: onSelect,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _OfferLabel(
                      discounted
                          ? 'Tiết kiệm ${plan.discountPercent}%'
                          : 'Giá chuẩn',
                      highlighted: discounted,
                    ),
                    if (featured) const _OfferLabel('Gợi ý'),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  plan.title,
                  style: type.labelLarge?.copyWith(color: mutedText),
                ),
                Text('Gói ${plan.periods} tháng', style: type.titleLarge),
                if (plan.provider case final provider?)
                  Text(
                    provider,
                    style: type.labelMedium?.copyWith(color: mutedText),
                  ),
                const SizedBox(height: 6),
                Text(
                  plan.description,
                  style: const TextStyle(color: mutedText),
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 14),
                const Text(
                  'Tổng trả trước (demo)',
                  style: TextStyle(color: mutedText),
                ),
                Text(
                  '${formatTokenAmount(plan.total)} $creditUnit',
                  style: type.headlineSmall?.copyWith(
                    color: selected ? accent : brightText,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  '${formatTokenAmount(plan.pricePerPeriod)} $creditUnit/tháng',
                  style: const TextStyle(color: mutedText),
                ),
                const SizedBox(height: 12),
                Text(
                  discounted
                      ? 'Giảm ${formatTokenAmount(plan.savings)} $creditUnit so với mua từng tháng'
                      : '${plan.accessDays} ngày tập theo lịch demo',
                  style: const TextStyle(color: mutedText),
                ),
                if (plan.bonusDaysAfterCheckIn > 0) ...[
                  const SizedBox(height: 6),
                  Text(
                    '+${plan.bonusDaysAfterCheckIn} ngày sau khi duyệt check-in đầu',
                    style: const TextStyle(color: accent),
                  ),
                ],
                const SizedBox(height: 18),
                FilledButton.icon(
                  style: selected
                      ? null
                      : FilledButton.styleFrom(
                          backgroundColor: const Color(0xff20364a),
                          foregroundColor: brightText,
                        ),
                  onPressed: subscribed ? null : onSubscribe,
                  icon: Icon(subscribed ? Icons.check : Icons.arrow_forward),
                  label: Text(subscribed ? 'Đã đăng ký' : 'Đăng ký demo'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OfferLabel extends StatelessWidget {
  const _OfferLabel(this.label, {this.highlighted = false});

  final String label;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: highlighted ? const Color(0xff173b45) : panelRaised,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: highlighted ? accent : brightText,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
