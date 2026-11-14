import 'package:flutter/material.dart';

import '../../app/prepaid_guard_theme.dart';
import '../../shared/widgets/brand_mark.dart';
import 'demo_training.dart';
import 'gym_traffic_card.dart';

enum TrainingView {
  facilities('Cơ sở', Icons.location_on_outlined),
  classes('Lớp học', Icons.calendar_month_outlined),
  coaches('Huấn luyện viên', Icons.sports_outlined),
  bookings('Lịch của tôi', Icons.event_available_outlined);

  const TrainingView(this.label, this.icon);
  final String label;
  final IconData icon;
}

class TrainingPage extends StatefulWidget {
  const TrainingPage({
    super.key,
    required this.view,
    required this.onViewChanged,
    required this.gym,
    required this.onGymChanged,
    required this.bookings,
  });

  final TrainingView view;
  final ValueChanged<TrainingView> onViewChanged;
  final DemoGym gym;
  final ValueChanged<DemoGym> onGymChanged;
  final DemoTrainingBookings bookings;

  @override
  State<TrainingPage> createState() => _TrainingPageState();
}

class _TrainingPageState extends State<TrainingPage> {
  int _dayOffset = 0;

  Future<void> _book(TrainingSlot slot) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xác nhận đặt lịch demo'),
        content: Text(
          '${slot.title}\n${slot.gym.name}\n${_when(context, slot)}\n\n'
          'Lịch được lưu trong phiên demo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Quay lại'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Đặt lịch demo'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    final saved = widget.bookings.add(slot, DateTime.now());
    final openBookings = widget.onViewChanged;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          saved ? 'Đã lưu lịch demo.' : 'Khung giờ đã qua hoặc trùng lịch.',
        ),
        action: saved
            ? SnackBarAction(
                label: 'Xem lịch',
                onPressed: () => openBookings(TrainingView.bookings),
              )
            : null,
      ),
    );
  }

  static String _when(BuildContext context, TrainingSlot slot) {
    final local = MaterialLocalizations.of(context);
    final time = local.formatTimeOfDay(
      TimeOfDay.fromDateTime(slot.startsAt),
      alwaysUse24HourFormat: true,
    );
    return '$time · ${slot.startsAt.day}/${slot.startsAt.month} · ${slot.duration.inMinutes} phút';
  }

  @override
  Widget build(BuildContext context) {
    final gym = widget.gym;
    final view = widget.view;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (view != TrainingView.bookings) ...[
          _TrainingBanner(gym: gym),
          const SizedBox(height: 16),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final option in TrainingView.values)
              ChoiceChip(
                avatar: Icon(option.icon, size: 17),
                label: Text(option.label),
                selected: view == option,
                showCheckmark: false,
                onSelected: (_) {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  widget.onViewChanged(option);
                },
              ),
          ],
        ),
        const SizedBox(height: 14),
        if (view != TrainingView.bookings) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: DropdownButtonFormField<DemoGym>(
                key: ValueKey(gym.name),
                initialValue: gym,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Cơ sở đang xem',
                  prefixIcon: Icon(Icons.location_on_outlined),
                ),
                items: [
                  for (final item in demoGyms)
                    DropdownMenuItem(value: item, child: Text(item.name)),
                ],
                onChanged: (item) {
                  if (item != null) widget.onGymChanged(item);
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        switch (view) {
          TrainingView.facilities => _facilities(context),
          TrainingView.classes => _schedule(context, personal: false),
          TrainingView.coaches => _schedule(context, personal: true),
          TrainingView.bookings => _savedSchedule(context),
        },
      ],
    );
  }

  Widget _facilities(BuildContext context) {
    final type = Theme.of(context).textTheme;
    final sites = Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Danh sách cơ sở', style: type.titleLarge),
            for (final item in demoGyms)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: AccentIcon(Icons.apartment_outlined, size: 34),
                selected: widget.gym == item,
                title: Text(item.name),
                subtitle: Text('${item.location} · ${item.hours}'),
                trailing: Icon(
                  widget.gym == item ? Icons.check_circle : Icons.chevron_right,
                  color: widget.gym == item ? accent : mutedText,
                ),
                onTap: () => widget.onGymChanged(item),
              ),
          ],
        ),
      ),
    );
    final traffic = GymTrafficCard(
      key: ValueKey(widget.gym.name),
      gym: widget.gym,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 740) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [traffic, const SizedBox(height: 14), sites],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3, child: traffic),
            const SizedBox(width: 16),
            Expanded(flex: 2, child: sites),
          ],
        );
      },
    );
  }

  Widget _schedule(BuildContext context, {required bool personal}) {
    final now = DateTime.now();
    final days = [
      for (var index = 0; index < 7; index++)
        DateTime(now.year, now.month, now.day + index),
    ];
    final gym = widget.gym;
    final type = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (personal) ...[
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.all(14),
              leading: const AccentIcon(Icons.sports_outlined),
              title: Text(gym.coach, style: type.titleLarge),
              subtitle: Text(
                '${gym.specialty}\nBuổi 1:1 · 45 phút · Hồ sơ mẫu',
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final (index, day) in days.indexed)
              ChoiceChip(
                label: Text(index == 0 ? 'Hôm nay' : '${day.day}/${day.month}'),
                selected: index == _dayOffset,
                showCheckmark: false,
                onSelected: (_) => setState(() => _dayOffset = index),
              ),
          ],
        ),
        const SizedBox(height: 14),
        for (final slot in gym.schedule(days[_dayOffset], personal: personal))
          _slotCard(context, slot, now: now),
      ],
    );
  }

  Widget _savedSchedule(BuildContext context) {
    final now = DateTime.now();
    final slots = widget.bookings.slots;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (slots.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Text(
                'Chưa có lịch. Chọn lớp học hoặc khung giờ tập 1:1 để đặt thử.',
              ),
            ),
          ),
        for (final slot in slots)
          _slotCard(context, slot, now: now, saved: true),
      ],
    );
  }

  Widget _slotCard(
    BuildContext context,
    TrainingSlot slot, {
    required DateTime now,
    bool saved = false,
  }) {
    final alreadyBooked = widget.bookings.contains(slot);
    final past = !slot.startsAt.isAfter(now);
    final conflicting = !alreadyBooked && widget.bookings.overlaps(slot);
    final type = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _when(context, slot),
                style: type.labelLarge?.copyWith(color: accent),
              ),
              const SizedBox(height: 5),
              Text(slot.title, style: type.titleLarge),
              Text(
                '${slot.gym.name} · ${slot.personal ? 'Tập 1:1 với ${slot.gym.coach}' : 'Lớp nhóm'}',
                style: const TextStyle(color: mutedText),
              ),
              const SizedBox(height: 10),
              if (saved)
                OutlinedButton(
                  onPressed: past
                      ? null
                      : () => setState(() => widget.bookings.remove(slot)),
                  child: Text(past ? 'Đã qua giờ bắt đầu' : 'Hủy lịch demo'),
                )
              else
                FilledButton(
                  onPressed: past || alreadyBooked || conflicting
                      ? null
                      : () => _book(slot),
                  child: Text(
                    alreadyBooked
                        ? 'Đã đặt'
                        : past
                        ? 'Đã qua giờ bắt đầu'
                        : conflicting
                        ? 'Trùng lịch đã đặt'
                        : 'Chọn giờ này',
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrainingBanner extends StatelessWidget {
  const _TrainingBanner({required this.gym});

  final DemoGym gym;

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
                  colors: [canvas, Color(0xec080f1c), Color(0x88080f1c)],
                  stops: [0, .50, 1],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AccentIcon(Icons.fitness_center_outlined, size: 38),
                const SizedBox(height: 12),
                Text(gym.name, style: type.headlineMedium),
                const SizedBox(height: 6),
                Text('${gym.location} · ${gym.hours}'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
