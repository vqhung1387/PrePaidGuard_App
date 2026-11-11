import 'package:flutter/material.dart';

import '../../app/prepaid_guard_theme.dart';
import '../../shared/widgets/brand_mark.dart';
import 'invite_link.dart';

const _profiles = [
  (id: 'an', name: 'Minh An', goal: 'Sức mạnh', schedule: 'Tối thứ 2, 4, 6'),
  (id: 'linh', name: 'Khánh Linh', goal: 'Cardio', schedule: 'Sáng cuối tuần'),
  (id: 'huy', name: 'Quang Huy', goal: 'Sức mạnh', schedule: 'Chiều thứ 3, 5'),
  (id: 'mai', name: 'Thanh Mai', goal: 'Linh hoạt', schedule: 'Sáng thứ 2, 4'),
];

class CommunityPage extends StatefulWidget {
  const CommunityPage({super.key, required this.requests});

  final Set<String> requests;

  @override
  State<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends State<CommunityPage> {
  String _filter = 'Tất cả';

  @override
  Widget build(BuildContext context) {
    final type = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => showDemoInvite(context),
            icon: const Icon(Icons.person_add_alt_1_outlined),
            label: const Text('Giới thiệu bạn tập'),
          ),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final goal in ['Tất cả', 'Sức mạnh', 'Cardio', 'Linh hoạt'])
              ChoiceChip(
                label: Text(goal),
                selected: _filter == goal,
                onSelected: (_) => setState(() => _filter = goal),
              ),
          ],
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth >= 650
                ? (constraints.maxWidth - 16) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                for (final profile in _profiles)
                  if (_filter == 'Tất cả' || profile.goal == _filter)
                    SizedBox(
                      width: width,
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  const AccentIcon(Icons.person_outline),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      profile.name,
                                      style: type.titleMedium,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Text(
                                '${profile.goal} · ${profile.schedule}',
                                style: const TextStyle(color: mutedText),
                              ),
                              const SizedBox(height: 16),
                              if (widget.requests.contains(profile.id)) ...[
                                const Text(
                                  'Đang chờ phản hồi (demo)',
                                  style: TextStyle(color: accent),
                                ),
                                TextButton(
                                  onPressed: () => setState(
                                    () => widget.requests.remove(profile.id),
                                  ),
                                  child: const Text('Hủy lời mời'),
                                ),
                              ] else
                                OutlinedButton.icon(
                                  onPressed: () => setState(
                                    () => widget.requests.add(profile.id),
                                  ),
                                  icon: const Icon(
                                    Icons.person_add_alt_1_outlined,
                                  ),
                                  label: const Text('Gửi lời mời demo'),
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
      ],
    );
  }
}
