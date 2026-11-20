import 'package:flutter/material.dart';

import '../../app/prepaid_guard_theme.dart';
import '../plans/demo_plan.dart';
import 'demo_membership.dart';

Future<void> showMembershipPayout(
  BuildContext context, {
  required DemoMembership? membership,
  VoidCallback? onViewPlans,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      scrollable: true,
      title: const Text('Giải ngân theo kỳ'),
      content: membership == null
          ? const Text(
              'Bạn chưa có gói dịch vụ. Sau khi đăng ký, bạn có thể xem tiến độ và tiền gốc còn lại ở đây.',
            )
          : _PayoutSchedule(membership: membership),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Đóng'),
        ),
        if (membership == null && onViewPlans != null)
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              onViewPlans();
            },
            child: const Text('Xem gói dịch vụ'),
          ),
      ],
    ),
  );
}

class _PayoutSchedule extends StatelessWidget {
  const _PayoutSchedule({required this.membership});

  final DemoMembership membership;

  @override
  Widget build(BuildContext context) {
    final plan = membership.plan;
    final releases = membership.releases;
    final completed = releases.length;
    final awaiting = membership.status == DemoCheckInStatus.awaitingMerchant;
    final type = Theme.of(context).textTheme;
    final locale = MaterialLocalizations.of(context);
    return SizedBox(
      width: 440,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(plan.title, style: type.titleMedium),
          Text(plan.serviceLabel, style: const TextStyle(color: mutedText)),
          const SizedBox(height: 14),
          for (final (label, amount) in [
            ('Tổng trả trước', plan.total),
            ('Đã giải ngân', membership.released),
            ('Tiền gốc còn lại', membership.remaining),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 12,
                children: [
                  Text(label),
                  Text(
                    '${formatTokenAmount(amount)} $creditUnit',
                    style: type.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: completed / plan.periods,
            semanticsLabel: '$completed/${plan.periods} kỳ đã giải ngân',
          ),
          const SizedBox(height: 10),
          Text(
            '$completed/${plan.periods} kỳ đã giải ngân · $creditUnit mô phỏng',
            style: const TextStyle(color: mutedText),
          ),
          const SizedBox(height: 10),
          for (var period = 1; period <= plan.periods; period++) ...[
            const Divider(height: 1),
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: Icon(
                period <= completed
                    ? Icons.check_circle_outline
                    : period == membership.nextPeriod
                    ? Icons.schedule_outlined
                    : Icons.lock_outline,
                color: period <= completed ? accent : mutedText,
              ),
              title: Text(
                'Kỳ $period · ${formatTokenAmount(plan.pricePerPeriod)} $creditUnit',
              ),
              subtitle: Text(
                period <= completed
                    ? 'Đã giải ngân · ${locale.formatShortDate(releases[period - 1].confirmedAt)}'
                    : period == membership.nextPeriod
                    ? (awaiting ? 'Đang chờ cơ sở duyệt' : 'Sẵn sàng check-in')
                    : 'Chờ hoàn thành các kỳ trước',
              ),
            ),
          ],
        ],
      ),
    );
  }
}
