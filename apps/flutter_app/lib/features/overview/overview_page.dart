import 'package:flutter/material.dart';

import '../../app/prepaid_guard_theme.dart';
import '../../shared/widgets/brand_mark.dart';
import '../community/invite_link.dart';
import '../subscriptions/demo_membership.dart';
import '../subscriptions/membership_card.dart';

class OverviewPage extends StatelessWidget {
  const OverviewPage({
    super.key,
    required this.memberships,
    required this.selectedMembership,
    required this.onSelectMembership,
    required this.onRequestCheckIn,
    required this.onViewPlans,
    required this.onCommunity,
  });

  final List<DemoMembership> memberships;
  final DemoMembership? selectedMembership;
  final ValueChanged<DemoMembership> onSelectMembership;
  final ValueChanged<DemoMembership> onRequestCheckIn;
  final VoidCallback onViewPlans;
  final VoidCallback onCommunity;

  @override
  Widget build(BuildContext context) {
    final type = Theme.of(context).textTheme;
    final selected = selectedMembership;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (selected == null)
          _ExplorePlansBanner(onViewPlans: onViewPlans)
        else ...[
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 10,
            children: [
              Text('Gói tập của bạn', style: type.headlineLarge),
              OutlinedButton.icon(
                onPressed: onViewPlans,
                icon: const Icon(Icons.add),
                label: const Text('Đăng ký gói tập'),
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
        const SizedBox(height: 20),
        _CommunityCard(onCommunity: onCommunity),
      ],
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
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Gói tập của bạn', style: type.headlineLarge),
                const SizedBox(height: 10),
                const Text(
                  'Chọn gói tập để check-in và theo dõi tiền gốc theo từng kỳ.',
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
