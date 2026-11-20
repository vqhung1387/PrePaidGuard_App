import 'package:flutter/material.dart';

import '../../app/prepaid_guard_theme.dart';
import '../../shared/widgets/brand_mark.dart';
import '../plans/demo_plan.dart';
import '../subscriptions/demo_membership.dart';
import 'merchant_check_ins.dart';

class MerchantDashboard extends StatelessWidget {
  const MerchantDashboard({
    super.key,
    required this.pending,
    required this.confirmed,
    required this.onConfirm,
    required this.onCreatePlan,
    required this.onHistory,
  });

  final List<DemoMembership> pending;
  final List<DemoMembership> confirmed;
  final void Function(DemoMembership, int) onConfirm;
  final VoidCallback onCreatePlan;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    final type = Theme.of(context).textTheme;
    final ordered = [...pending]
      ..sort((a, b) => a.requestedAt!.compareTo(b.requestedAt!));
    final due = pending.fold(
      BigInt.zero,
      (sum, item) => sum + item.plan.pricePerPeriod,
    );
    final released = confirmed.fold(
      BigInt.zero,
      (sum, item) => sum + item.released,
    );
    final releases = confirmed.fold(
      0,
      (sum, item) => sum + item.releasedPeriods,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Positioned.fill(
                child: Image.asset(
                  'assets/gym-hero.jpg',
                  fit: BoxFit.cover,
                  alignment: Alignment.centerRight,
                  excludeFromSemantics: true,
                ),
              ),
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [canvas, Color(0xf0080f1c), Color(0x9a080f1c)],
                      stops: [0, .54, 1],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'QUẦY LỄ TÂN · DEMO',
                      style: type.labelLarge?.copyWith(
                        color: accent,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text('Check-in của cơ sở', style: type.headlineLarge),
                    const SizedBox(height: 6),
                    Text(
                      pending.isEmpty
                          ? 'Hàng chờ trống. Yêu cầu mới sẽ xuất hiện khi hội viên gửi check-in.'
                          : '${pending.length} yêu cầu cần duyệt, theo thứ tự gửi.',
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        OutlinedButton.icon(
                          onPressed: onCreatePlan,
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Tạo gói dịch vụ'),
                        ),
                        TextButton.icon(
                          onPressed: onHistory,
                          icon: const Icon(Icons.history_outlined, size: 18),
                          label: const Text('Xem lượt đã duyệt'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 780 ? 4 : 2;
            final width = (constraints.maxWidth - 10 * (columns - 1)) / columns;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final (icon, label, value) in [
                  (Icons.schedule_outlined, 'Chờ duyệt', '${pending.length}'),
                  (
                    Icons.lock_clock_outlined,
                    'Chờ giải ngân',
                    '${formatTokenAmount(due)} $creditUnit',
                  ),
                  (Icons.task_alt_outlined, 'Đã duyệt', '$releases'),
                  (
                    Icons.account_balance_wallet_outlined,
                    'Đã giải ngân',
                    '${formatTokenAmount(released)} $creditUnit',
                  ),
                ])
                  SizedBox(
                    width: width,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AccentIcon(icon, size: 28),
                            const SizedBox(height: 7),
                            Text(
                              label,
                              style: type.labelMedium?.copyWith(
                                color: mutedText,
                              ),
                            ),
                            Text(
                              value,
                              style: type.titleLarge?.copyWith(color: accent),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 14),
        MerchantCheckIns(pending: ordered, onConfirm: onConfirm),
      ],
    );
  }
}
