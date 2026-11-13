import 'package:flutter/material.dart';

import '../../app/prepaid_guard_theme.dart';
import '../../shared/widgets/brand_mark.dart';
import '../plans/demo_plan.dart';
import '../subscriptions/demo_membership.dart';

class MerchantCheckIns extends StatelessWidget {
  const MerchantCheckIns({
    super.key,
    required this.pending,
    required this.onConfirm,
  });

  final List<DemoMembership> pending;
  final ValueChanged<DemoMembership> onConfirm;

  Future<void> _review(BuildContext context, DemoMembership membership) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xác nhận check-in kỳ đầu'),
        content: Text(
          '${membership.plan.title}\n'
          'Gốc sẽ giải ngân: ${formatTokenAmount(membership.plan.pricePerPeriod)} USDC demo.\n\n'
          'Thao tác chỉ cập nhật dữ liệu trong phiên.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Quay lại'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xác nhận kỳ demo'),
          ),
        ],
      ),
    );
    if (context.mounted && approved == true) onConfirm(membership);
  }

  @override
  Widget build(BuildContext context) {
    final type = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const AccentIcon(Icons.fact_check_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Yêu cầu check-in', style: type.titleLarge),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (pending.isEmpty)
              const Text(
                'Chưa có yêu cầu đang chờ cho gói của cơ sở này.',
                style: TextStyle(color: mutedText),
              ),
            for (final membership in pending) ...[
              const Divider(),
              Text(membership.plan.title, style: type.titleMedium),
              Text(
                membership.memberEmail,
                style: const TextStyle(color: mutedText),
              ),
              const SizedBox(height: 6),
              Text(
                'Kỳ 1 · ${formatTokenAmount(membership.plan.pricePerPeriod)} USDC dự kiến giải ngân',
                style: const TextStyle(color: accent),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton(
                  onPressed: () => _review(context, membership),
                  child: const Text('Duyệt check-in'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
