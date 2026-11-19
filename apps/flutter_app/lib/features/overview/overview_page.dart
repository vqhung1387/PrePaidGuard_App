import 'package:flutter/material.dart';

import '../../app/prepaid_guard_theme.dart';
import '../../shared/widgets/brand_mark.dart';
import '../community/invite_link.dart';
import '../plans/demo_plan.dart';
import '../subscriptions/demo_membership.dart';

import '../subscriptions/membership_card.dart';
import '../subscriptions/membership_payout.dart';
import '../training/demo_training.dart';
import '../training/training_page.dart';

class OverviewPage extends StatelessWidget {
  const OverviewPage({
    super.key,
    required this.memberships,
    required this.selectedMembership,
    required this.onSelectMembership,
    required this.onRequestCheckIn,
    required this.onViewPlans,
    required this.onViewMemberships,
    required this.onCommunity,
    required this.trainingGym,
    required this.onTraining,
  });

  final List<DemoMembership> memberships;
  final DemoMembership? selectedMembership;
  final ValueChanged<DemoMembership> onSelectMembership;
  final ValueChanged<DemoMembership> onRequestCheckIn;
  final VoidCallback onViewPlans;
  final VoidCallback onViewMemberships;
  final VoidCallback onCommunity;
  final DemoGym trainingGym;
  final ValueChanged<TrainingView> onTraining;

  @override
  Widget build(BuildContext context) {
    final type = Theme.of(context).textTheme;
    final selected = selectedMembership;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (selected == null) ...[
          _ExplorePlansBanner(onViewPlans: onViewPlans),
        ] else ...[
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 10,
            children: [
              Text(
                selected.plan.category == ServiceCategory.gym
                    ? 'Gói tập của bạn'
                    : 'Gói dịch vụ của bạn',
                style: type.headlineLarge,
              ),
              OutlinedButton.icon(
                onPressed: onViewPlans,
                icon: const Icon(Icons.add),
                label: Text(
                  selected.plan.category == ServiceCategory.gym
                      ? 'Đăng ký gói tập'
                      : 'Đăng ký thêm gói',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (memberships.length > 1) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Chọn gói hội viên',
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<DemoMembership>(
                      isDense: true,
                      isExpanded: true,
                      value: selected,
                      items: [
                        for (final membership in memberships)
                          DropdownMenuItem(
                            value: membership,
                            child: Text(
                              membership.plan.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (membership) {
                        if (membership != null) onSelectMembership(membership);
                      },
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          MembershipCard(
            membership: selected,
            onRequestCheckIn: () => onRequestCheckIn(selected),
          ),
        ],
        const SizedBox(height: 18),
        _MembershipSteps(
          onViewPlans: onViewPlans,
          onViewMemberships: onViewMemberships,
          onViewPayout: () => showMembershipPayout(
            context,
            membership: selected,
            onViewPlans: onViewPlans,
          ),
        ),
        const SizedBox(height: 20),
        _TrainingPreview(gym: trainingGym, onTraining: onTraining),
        const SizedBox(height: 16),
        _CommunityCard(onCommunity: onCommunity),
      ],
    );
  }
}

class _TrainingPreview extends StatelessWidget {
  const _TrainingPreview({required this.gym, required this.onTraining});

  final DemoGym gym;
  final ValueChanged<TrainingView> onTraining;

  @override
  Widget build(BuildContext context) {
    final type = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const AccentIcon(Icons.location_on_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(gym.name, style: type.titleLarge),
                      Text(
                        gym.location,
                        style: const TextStyle(color: mutedText),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '${gym.sampleOccupancy}/${gym.capacity} người lúc ${formatHour(DemoGym.sampleHour)} · Số liệu mô phỏng',
              style: type.titleMedium?.copyWith(color: accent),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final (view, label) in [
                  (TrainingView.facilities, 'Giờ đông & cơ sở'),
                  (TrainingView.classes, 'Lịch lớp'),
                  (TrainingView.coaches, 'Tập với HLV'),
                ])
                  OutlinedButton.icon(
                    onPressed: () => onTraining(view),
                    icon: Icon(view.icon, size: 18),
                    label: Text(label),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ExplorePlansBanner extends StatelessWidget {
  const _ExplorePlansBanner({required this.onViewPlans});

  final VoidCallback onViewPlans;

  @override
  Widget build(BuildContext context) {
    final type = Theme.of(context).textTheme;
    return Card(
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
                  colors: [canvas, Color(0xde080f1c), Color(0x60080f1c)],
                  stops: [0, .55, 1],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'HỘI VIÊN · CHẾ ĐỘ DEMO',
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 10),
                Text('Gói tập của bạn', style: type.headlineLarge),
                const SizedBox(height: 8),
                const Text(
                  'Đăng ký gym, yoga hoặc khóa học. Theo dõi tiền trả trước và từng kỳ giải ngân tại đây.',
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: onViewPlans,
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('Khám phá gói tập'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MembershipSteps extends StatelessWidget {
  const _MembershipSteps({
    required this.onViewPlans,
    required this.onViewMemberships,
    required this.onViewPayout,
  });

  final VoidCallback onViewPlans;
  final VoidCallback onViewMemberships;
  final VoidCallback onViewPayout;

  @override
  Widget build(BuildContext context) {
    final type = Theme.of(context).textTheme;
    final steps = [
      (
        Icons.fitness_center_outlined,
        'Đăng ký dịch vụ',
        'Chọn gói và xem tiền gốc được giữ trong Vault trên mạng thử nghiệm.',
        onViewPlans,
      ),
      (
        Icons.fact_check_outlined,
        'Xác nhận sử dụng',
        'Khách gửi check-in. Trên mạng thử nghiệm, khách tạo QR ký số để cơ sở xác nhận.',
        onViewMemberships,
      ),
      (
        Icons.account_balance_wallet_outlined,
        'Giải ngân theo kỳ',
        'Cơ sở nhận từng phần khi đủ điều kiện. Khách theo dõi tiền gốc còn lại.',
        onViewPayout,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 660 ? 3 : 1;
        final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 10,
          children: [
            for (final (icon, title, detail, onTap) in steps)
              SizedBox(
                width: width,
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: onTap,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AccentIcon(icon, size: 36),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(title, style: type.titleMedium),
                                const SizedBox(height: 4),
                                Text(
                                  detail,
                                  style: const TextStyle(color: mutedText),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.chevron_right,
                            color: accent,
                            size: 18,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _CommunityCard extends StatelessWidget {
  const _CommunityCard({required this.onCommunity});

  final VoidCallback onCommunity;

  @override
  Widget build(BuildContext context) {
    final type = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const AccentIcon(Icons.groups_outlined, size: 36),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Tập cùng bạn bè', style: type.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                TextButton.icon(
                  onPressed: () => showDemoInvite(context),
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: const Text('Giới thiệu bạn tập'),
                ),
                TextButton.icon(
                  onPressed: onCommunity,
                  icon: const Icon(Icons.groups_outlined),
                  label: const Text('Kết nối bạn tập'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
