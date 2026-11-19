import 'package:flutter/material.dart';

import '../../app/prepaid_guard_theme.dart';
import 'demo_training.dart';

class GymTrafficCard extends StatefulWidget {
  const GymTrafficCard({super.key, required this.gym});

  final DemoGym gym;

  @override
  State<GymTrafficCard> createState() => _GymTrafficCardState();
}

class _GymTrafficCardState extends State<GymTrafficCard> {
  int _daysAgo = 0;
  int _hour = DemoGym.sampleHour;

  @override
  Widget build(BuildContext context) {
    final type = Theme.of(context).textTheme;
    final gym = widget.gym;
    final counts = gym.trafficFor(_daysAgo);
    final count = counts[_hour];
    final ratio = count / gym.capacity;
    final (loadLabel, loadColor) = switch ((gym.isOpenAt(_hour), ratio)) {
      (false, _) => ('Đã đóng cửa', mutedText),
      (true, < .45) => ('Thoáng', const Color(0xff81e4b2)),
      (true, < .75) => ('Vừa phải', accent),
      _ => ('Đông', const Color(0xfff8cb7d)),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Hội viên đang tập', style: type.titleLarge),
            Text(
              'Số liệu mô phỏng theo giờ · ${gym.name}',
              style: const TextStyle(color: mutedText),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final (offset, label) in [
                  (0, 'Hôm nay'),
                  (1, 'Hôm qua'),
                  (2, '2 ngày trước'),
                ])
                  ChoiceChip(
                    label: Text(label),
                    showCheckmark: false,
                    selected: _daysAgo == offset,
                    onSelected: (_) => setState(() => _daysAgo = offset),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Wrap(
                spacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '$count / ${gym.capacity} người',
                    style: type.titleLarge,
                  ),
                  Text(
                    '${formatHour(_hour)} · $loadLabel',
                    style: TextStyle(color: loadColor),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final hoursPerRow = constraints.maxWidth >= 720 ? 24 : 12;
                return Column(
                  children: [
                    for (
                      var start = 0;
                      start < counts.length;
                      start += hoursPerRow
                    )
                      _HourChart(
                        firstHour: start,
                        counts: counts.sublist(start, start + hoursPerRow),
                        capacity: gym.capacity,
                        selectedHour: _hour,
                        isOpenAt: gym.isOpenAt,
                        onSelect: (hour) => setState(() => _hour = hour),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            Text(
              'Trong giờ mở cửa, ít đông nhất lúc ${formatHour(_quietHour(gym, counts))}.',
              style: const TextStyle(color: mutedText),
            ),
          ],
        ),
      ),
    );
  }

  int _quietHour(DemoGym gym, List<int> counts) {
    var lowest = gym.opensAt;
    for (var index = lowest + 1; index < gym.closesAt; index++) {
      if (counts[index] < counts[lowest]) lowest = index;
    }
    return lowest;
  }
}

class _HourChart extends StatelessWidget {
  const _HourChart({
    required this.firstHour,
    required this.counts,
    required this.capacity,
    required this.selectedHour,
    required this.isOpenAt,
    required this.onSelect,
  });

  final int firstHour;
  final List<int> counts;
  final int capacity;
  final int selectedHour;
  final bool Function(int) isOpenAt;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final endHour = firstHour + counts.length;
    final style = Theme.of(
      context,
    ).textTheme.labelSmall?.copyWith(color: mutedText);
    final scaler = MediaQuery.textScalerOf(context);
    double labelWidth = 0;
    for (var hour = firstHour; hour <= endHour; hour += 3) {
      final painter = TextPainter(
        text: TextSpan(text: formatHour(hour), style: style),
        textDirection: Directionality.of(context),
        textScaler: scaler,
      )..layout();
      if (painter.width > labelWidth) labelWidth = painter.width;
      painter.dispose();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth < labelWidth * 2 + 16
            ? labelWidth * 2 + 16
            : constraints.maxWidth;
        final divisions = [
          4,
          2,
          1,
        ].firstWhere((n) => labelWidth * (n + 1) + 8 * n <= width);
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: width,
            child: Column(
              children: [
                Row(
                  children: [
                    for (final (index, count) in counts.indexed)
                      Expanded(
                        child: _hourBar(context, firstHour + index, count),
                      ),
                  ],
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (
                        var hour = firstHour;
                        hour <= endHour;
                        hour += counts.length ~/ divisions
                      )
                        Text(formatHour(hour), style: style),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _hourBar(BuildContext context, int hour, int count) {
    final selected = hour == selectedHour;
    final open = isOpenAt(hour);
    final label = open
        ? '${formatHour(hour)} · $count người'
        : '${formatHour(hour)} · Đã đóng cửa';
    return Semantics(
      label: label,
      selected: selected,
      button: true,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: InkWell(
          key: ValueKey('traffic-hour-$hour'),
          onTap: () => onSelect(hour),
          borderRadius: BorderRadius.circular(5),
          child: SizedBox(
            height: 98,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  height: 4 + 86 * count / capacity,
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(4),
                    ),
                    color: selected
                        ? accent
                        : open
                        ? const Color(0xff337389)
                        : panelOutline,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
