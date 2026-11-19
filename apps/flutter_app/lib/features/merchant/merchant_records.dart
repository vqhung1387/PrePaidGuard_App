import 'package:flutter/material.dart';

import '../../app/prepaid_guard_theme.dart';
import '../../shared/widgets/brand_mark.dart';
import '../plans/demo_plan.dart';
import '../subscriptions/demo_membership.dart';

String formatMerchantTime(BuildContext context, DateTime time) {
  final localizations = MaterialLocalizations.of(context);
  final date = localizations.formatShortDate(time);
  final hour = localizations.formatTimeOfDay(
    TimeOfDay.fromDateTime(time),
    alwaysUse24HourFormat: true,
  );
  return '$date · $hour';
}

class MerchantHistory extends StatefulWidget {
  const MerchantHistory({super.key, required this.items});

  final List<DemoMembership> items;

  @override
  State<MerchantHistory> createState() => _MerchantHistoryState();
}

class _MerchantHistoryState extends State<MerchantHistory> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final results = [
      for (final item in widget.items)
        if (item.memberEmail.toLowerCase().contains(_query) ||
            item.plan.title.toLowerCase().contains(_query))
          for (final release in item.releases) (item, release),
    ]..sort((a, b) => b.$2.confirmedAt.compareTo(a.$2.confirmedAt));
    if (widget.items.isEmpty) {
      return const Card(
        child: ListTile(
          contentPadding: EdgeInsets.all(16),
          leading: AccentIcon(Icons.history_outlined),
          title: Text('Chưa có lượt đã duyệt'),
          subtitle: Text(
            'Sau khi xác nhận check-in, lượt duyệt sẽ xuất hiện ở đây.',
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          onChanged: (value) =>
              setState(() => _query = value.trim().toLowerCase()),
          decoration: const InputDecoration(
            labelText: 'Tìm theo email hoặc tên gói',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 14),
        if (results.isEmpty)
          const Text('Không tìm thấy lượt đã duyệt phù hợp.'),
        for (final (item, release) in results)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              child: ListTile(
                contentPadding: const EdgeInsets.all(16),
                leading: const AccentIcon(Icons.task_alt_outlined, size: 34),
                title: Text(item.plan.title),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.memberEmail),
                    Text(
                      'Kỳ ${release.period} · ${formatMerchantTime(context, release.confirmedAt)}',
                    ),
                    Text(
                      '${formatTokenAmount(release.amount)} USDC đã giải ngân',
                      style: const TextStyle(color: accent),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class MerchantPlans extends StatelessWidget {
  const MerchantPlans({
    super.key,
    required this.plans,
    required this.memberships,
    required this.onCreatePlan,
  });

  final List<DemoPlan> plans;
  final List<DemoMembership> memberships;
  final VoidCallback onCreatePlan;

  @override
  Widget build(BuildContext context) {
    final byPlan = <DemoPlan, List<DemoMembership>>{};
    for (final membership in memberships) {
      (byPlan[membership.plan] ??= []).add(membership);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: onCreatePlan,
            icon: const Icon(Icons.add),
            label: const Text('Tạo gói dịch vụ'),
          ),
        ),
        const SizedBox(height: 14),
        if (plans.isEmpty)
          const Card(
            child: ListTile(
              title: Text('Cơ sở chưa có gói'),
              subtitle: Text('Tạo gói đầu tiên để hội viên có thể đăng ký.'),
            ),
          ),
        for (final plan in plans)
          _PlanRecord(plan: plan, memberships: byPlan[plan] ?? const []),
      ],
    );
  }
}

class _PlanRecord extends StatelessWidget {
  const _PlanRecord({required this.plan, required this.memberships});

  final DemoPlan plan;
  final List<DemoMembership> memberships;

  @override
  Widget build(BuildContext context) {
    final type = Theme.of(context).textTheme;
    final pending = memberships
        .where((item) => item.status == DemoCheckInStatus.awaitingMerchant)
        .length;
    final released = memberships.fold(
      BigInt.zero,
      (sum, item) => sum + item.released,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const AccentIcon(Icons.fitness_center_outlined, size: 36),
                  const SizedBox(width: 10),
                  Expanded(child: Text(plan.title, style: type.titleLarge)),
                ],
              ),
              const SizedBox(height: 8),
              Text(plan.serviceLabel, style: const TextStyle(color: mutedText)),
              Text(
                '${plan.periods} kỳ × ${plan.daysPerPeriod} ngày · ${formatTokenAmount(plan.pricePerPeriod)} USDC/kỳ',
              ),
              Text(
                'Tổng trả trước mỗi lượt: ${formatTokenAmount(plan.total)} USDC',
                style: const TextStyle(color: mutedText),
              ),
              const Divider(height: 22),
              Wrap(
                spacing: 14,
                runSpacing: 6,
                children: [
                  Text('${memberships.length} lượt đăng ký'),
                  Text('$pending check-in chờ duyệt'),
                  Text(
                    '${formatTokenAmount(released)} USDC đã giải ngân',
                    style: const TextStyle(color: accent),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
