import 'package:flutter/material.dart';

import '../../app/prepaid_guard_theme.dart';
import '../../shared/widgets/brand_mark.dart';
import '../plans/demo_plan.dart';
import 'demo_membership.dart';
import 'membership_activity.dart';

class MembershipCard extends StatelessWidget {
  const MembershipCard({
    super.key,
    required this.membership,
    required this.onRequestCheckIn,
  });

  final DemoMembership membership;
  final VoidCallback onRequestCheckIn;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 700;
        final summary = _MembershipSummary(
          membership: membership,
          onRequestCheckIn: onRequestCheckIn,
          actionFirst: !wide,
        );
        final activity = MembershipActivity(membership: membership);
        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 6, child: summary),
              const SizedBox(width: 16),
              Expanded(flex: 5, child: activity),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [summary, const SizedBox(height: 14), activity],
        );
      },
    );
  }
}

class _MembershipSummary extends StatelessWidget {
  const _MembershipSummary({
    required this.membership,
    required this.onRequestCheckIn,
    required this.actionFirst,
  });

  final DemoMembership membership;
  final VoidCallback onRequestCheckIn;
  final bool actionFirst;

  @override
  Widget build(BuildContext context) {
    final type = Theme.of(context).textTheme;
    final plan = membership.plan;
    final progress =
        'Đã giải ngân ${membership.releasedPeriods}/${plan.periods} kỳ';
    final balance = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Tiền gốc còn lại', style: TextStyle(color: mutedText)),
        const SizedBox(height: 4),
        Text(
          '${formatTokenAmount(membership.remaining)} USDC',
          style: type.headlineLarge?.copyWith(color: accent),
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: membership.releasedPeriods / plan.periods,
            minHeight: 8,
            backgroundColor: panelOutline,
            semanticsLabel: progress,
          ),
        ),
        const SizedBox(height: 8),
        Text(progress, style: const TextStyle(color: mutedText)),
      ],
    );
    final action = _buildAction(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [Color(0xff173b53), panel],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const AccentIcon(Icons.badge_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(plan.title, style: type.titleLarge),
                      Text(
                        '${formatTokenAmount(plan.pricePerPeriod)} USDC mỗi kỳ',
                        style: const TextStyle(color: mutedText),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            actionFirst ? action : balance,
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            actionFirst ? balance : action,
            if (plan.bonusDaysAfterCheckIn > 0) ...[
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Text(
                membership.earnedBonusDays > 0
                    ? 'Đã cộng ${membership.earnedBonusDays} ngày tập'
                    : 'Nhận ${plan.bonusDaysAfterCheckIn} ngày tập sau khi cơ sở xác nhận check-in kỳ đầu',
                style: type.titleMedium?.copyWith(color: accent),
              ),
              const SizedBox(height: 4),
              Text(
                'Tổng thời hạn tập: ${membership.accessDays} ngày (mô phỏng)',
                style: const TextStyle(color: mutedText),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAction(BuildContext context) {
    final type = Theme.of(context).textTheme;
    final (title, detail, statusColor) = switch (membership.status) {
      DemoCheckInStatus.ready => (
        'Sẵn sàng check-in kỳ 1',
        '${formatTokenAmount(membership.plan.pricePerPeriod)} USDC sẽ giải ngân khi cơ sở xác nhận.',
        accent,
      ),
      DemoCheckInStatus.awaitingMerchant => (
        'Đang chờ cơ sở xác nhận',
        'Yêu cầu đã gửi. Số dư vẫn giữ nguyên.',
        const Color(0xfff8cb7d),
      ),
      DemoCheckInStatus.confirmed => (
        'Kỳ 1 đã xác nhận',
        membership.plan.periods == 1
            ? 'Gói đã hoàn tất trong bản mô phỏng.'
            : 'Đã cập nhật số dư. Bản mô phỏng kết thúc sau kỳ đầu.',
        const Color(0xff81e4b2),
      ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          liveRegion: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: type.titleMedium?.copyWith(color: statusColor),
              ),
              const SizedBox(height: 4),
              Text(detail, style: const TextStyle(color: mutedText)),
            ],
          ),
        ),
        if (membership.status == DemoCheckInStatus.ready) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: onRequestCheckIn,
              icon: const Icon(Icons.how_to_reg_outlined),
              label: const Text('Check-in kỳ đầu (demo)'),
            ),
          ),
        ],
      ],
    );
  }
}
