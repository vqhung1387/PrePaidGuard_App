import 'package:flutter/material.dart';

import '../../app/prepaid_guard_theme.dart';
import 'demo_plan.dart';

class PlanComparison extends StatelessWidget {
  const PlanComparison({
    super.key,
    required this.plans,
    required this.subscribedPlans,
  });

  final List<DemoPlan> plans;
  final Set<DemoPlan> subscribedPlans;

  @override
  Widget build(BuildContext context) {
    final showTable =
        MediaQuery.sizeOf(context).width >= 850 &&
        MediaQuery.textScalerOf(context).scale(14) <= 16;
    return AlertDialog(
      title: const Text('So sánh gói dịch vụ'),
      scrollable: true,
      content: SizedBox(
        width: 780,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Bạn trả trước một lần. Mức mỗi kỳ là phần tiền giải ngân cho nhà cung cấp khi đủ điều kiện.',
              style: TextStyle(color: mutedText),
            ),
            const SizedBox(height: 14),
            if (showTable)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  horizontalMargin: 12,
                  columnSpacing: 16,
                  headingRowColor: WidgetStatePropertyAll(panelRaised),
                  columns: const [
                    DataColumn(label: Text('Gói dịch vụ')),
                    DataColumn(label: Text('Thời hạn')),
                    DataColumn(label: Text('Trả trước'), numeric: true),
                    DataColumn(label: Text('Giải ngân/kỳ'), numeric: true),
                    DataColumn(label: Text('Ưu đãi')),
                    DataColumn(label: Text('Đăng ký')),
                  ],
                  rows: [
                    for (final plan in plans)
                      DataRow(
                        cells: [
                          DataCell(
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 150),
                              child: Tooltip(
                                message: plan.serviceLabel,
                                child: Text(
                                  plan.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ),
                          DataCell(Text('${plan.accessDays} ngày')),
                          DataCell(
                            Text('${formatTokenAmount(plan.total)} $creditUnit'),
                          ),
                          DataCell(
                            Text(
                              '${formatTokenAmount(plan.pricePerPeriod)} $creditUnit',
                            ),
                          ),
                          DataCell(Text(_offerText(plan))),
                          DataCell(
                            _chooseButton(
                              context,
                              plan,
                              subscribedPlans.contains(plan),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              )
            else
              for (final plan in plans)
                _ComparisonRow(
                  plan: plan,
                  subscribed: subscribedPlans.contains(plan),
                ),
            if (plans.any((plan) => plan.bonusDaysAfterCheckIn > 0)) ...[
              const SizedBox(height: 8),
              const Text(
                'Ngày tặng được cộng sau khi cơ sở xác nhận check-in kỳ đầu.',
                style: TextStyle(color: mutedText),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Đóng so sánh'),
        ),
      ],
    );
  }
}

String _offerText(DemoPlan plan) {
  final offers = [
    if (plan.discountPercent > 0) 'Giảm ${plan.discountPercent}%',
    if (plan.bonusDaysAfterCheckIn > 0) '+${plan.bonusDaysAfterCheckIn} ngày',
  ];
  return offers.isEmpty ? '—' : offers.join(' · ');
}

Widget _chooseButton(BuildContext context, DemoPlan plan, bool subscribed) {
  return TextButton(
    onPressed: subscribed ? null : () => Navigator.pop(context, plan),
    child: Text(subscribed ? 'Đã đăng ký' : 'Chọn gói'),
  );
}

class _ComparisonRow extends StatelessWidget {
  const _ComparisonRow({required this.plan, required this.subscribed});

  final DemoPlan plan;
  final bool subscribed;

  @override
  Widget build(BuildContext context) {
    final type = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        color: panelRaised,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(plan.title, style: type.titleMedium),
              Text(plan.serviceLabel, style: const TextStyle(color: mutedText)),
              const SizedBox(height: 4),
              Text(
                'Trả trước ${formatTokenAmount(plan.total)} $creditUnit',
                style: type.titleMedium?.copyWith(color: accent),
              ),
              Text(
                '${plan.accessDays} ngày · ${plan.periods} kỳ',
                style: const TextStyle(color: mutedText),
              ),
              Text(
                'Giải ngân ${formatTokenAmount(plan.pricePerPeriod)} $creditUnit/kỳ',
                style: const TextStyle(color: mutedText),
              ),
              if (plan.discountPercent > 0) ...[
                const SizedBox(height: 4),
                Text(
                  'Tiết kiệm ${plan.discountPercent}% (${formatTokenAmount(plan.savings)} $creditUnit)',
                ),
              ],
              if (plan.bonusDaysAfterCheckIn > 0)
                Text('Tặng ${plan.bonusDaysAfterCheckIn} ngày tập'),
              _chooseButton(context, plan, subscribed),
            ],
          ),
        ),
      ),
    );
  }
}
