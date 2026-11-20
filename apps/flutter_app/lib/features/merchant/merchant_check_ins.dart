import 'package:flutter/material.dart';

import '../../app/prepaid_guard_theme.dart';
import '../../shared/widgets/brand_mark.dart';
import '../plans/demo_plan.dart';
import '../subscriptions/demo_membership.dart';
import 'merchant_records.dart';

class MerchantCheckIns extends StatefulWidget {
  const MerchantCheckIns({
    super.key,
    required this.pending,
    required this.onConfirm,
  });

  final List<DemoMembership> pending;
  final void Function(DemoMembership, int) onConfirm;

  @override
  State<MerchantCheckIns> createState() => _MerchantCheckInsState();
}

class _MerchantCheckInsState extends State<MerchantCheckIns> {
  String _query = '';

  Future<void> _review(BuildContext context, DemoMembership membership) async {
    final period = membership.nextPeriod;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Xác nhận check-in kỳ $period'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(membership.plan.title),
            Text(membership.memberEmail),
            const SizedBox(height: 12),
            Text(
              'Giải ngân kỳ này: ${formatTokenAmount(membership.plan.pricePerPeriod)} $creditUnit',
            ),
            Text(
              'Gốc còn lại sau duyệt: ${formatTokenAmount(membership.remaining - membership.plan.pricePerPeriod)} $creditUnit',
            ),
            const SizedBox(height: 12),
            const Text('Số tiền mô phỏng trong phiên demo.'),
          ],
        ),
        scrollable: true,
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
    if (context.mounted && approved == true)
      widget.onConfirm(membership, period);
  }

  @override
  Widget build(BuildContext context) {
    final type = Theme.of(context).textTheme;
    final pending = widget.pending;
    final matches = pending
        .where(
          (membership) =>
              membership.plan.title.toLowerCase().contains(_query) ||
              membership.memberEmail.toLowerCase().contains(_query),
        )
        .toList();
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
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.inbox_outlined, color: mutedText),
                title: Text('Chưa có yêu cầu đang chờ'),
                subtitle: Text(
                  'Từ chế độ Hội viên, đăng ký gói của cơ sở và gửi check-in kỳ đầu để thử quy trình duyệt.',
                ),
              ),
            if (pending.isNotEmpty) ...[
              TextField(
                onChanged: (value) =>
                    setState(() => _query = value.trim().toLowerCase()),
                decoration: const InputDecoration(
                  labelText: 'Tìm theo email hoặc tên gói',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                matches.isEmpty
                    ? 'Không tìm thấy yêu cầu phù hợp.'
                    : 'Hiển thị ${matches.length}/${pending.length} yêu cầu',
                style: const TextStyle(color: mutedText),
              ),
            ],
            for (final membership in matches) ...[
              const Divider(),
              Text(membership.plan.title, style: type.titleMedium),
              Text(
                membership.memberEmail,
                style: const TextStyle(color: mutedText),
              ),
              Text(
                'Gửi lúc ${formatMerchantTime(context, membership.requestedAt!)}',
                style: const TextStyle(color: mutedText),
              ),
              const SizedBox(height: 6),
              Text(
                'Kỳ ${membership.nextPeriod} · ${formatTokenAmount(membership.plan.pricePerPeriod)} $creditUnit dự kiến giải ngân',
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
