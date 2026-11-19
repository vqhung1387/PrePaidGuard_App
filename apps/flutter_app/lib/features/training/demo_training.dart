class DemoGym {
  const DemoGym({
    required this.name,
    required this.area,
    required this.city,
    required this.opensAt,
    required this.closesAt,
    required this.capacity,
    required this.traffic,
    required this.coach,
    required this.specialty,
    required this.groupClasses,
  });

  final String name;
  final String area;
  final String city;
  final int opensAt;
  final int closesAt;
  final int capacity;
  final List<int> traffic;
  final String coach;
  final String specialty;
  final List<String> groupClasses;

  String get location => '$area, $city';
  String get hours => '${formatHour(opensAt)}–${formatHour(closesAt)}';
  static const sampleHour = 13;
  int get sampleOccupancy => traffic[sampleHour - opensAt];

  bool isOpenAt(int hour) => hour >= opensAt && hour < closesAt;

  List<int> trafficFor(int daysAgo) => [
    for (var hour = 0; hour < 24; hour++)
      if (isOpenAt(hour))
        (traffic[hour - opensAt] - daysAgo * (3 + (hour - opensAt) % 4)).clamp(
          0,
          capacity,
        )
      else
        0,
  ];

  List<TrainingSlot> schedule(DateTime day, {required bool personal}) {
    final slots = personal
        ? [(9, 0, specialty, 45), (16, 30, specialty, 45)]
        : [(8, 0, groupClasses.first, 60), (18, 30, groupClasses.last, 45)];
    return [
      for (final (hour, minute, title, duration) in slots)
        TrainingSlot(
          gym: this,
          title: title,
          startsAt: DateTime(day.year, day.month, day.day, hour, minute),
          duration: Duration(minutes: duration),
          personal: personal,
        ),
    ];
  }
}

String formatHour(int hour) => '${hour.toString().padLeft(2, '0')}:00';

const demoGyms = [
  DemoGym(
    name: 'PrepaidGuard Central',
    area: 'Quận 3',
    city: 'TP. HCM',
    opensAt: 6,
    closesAt: 22,
    capacity: 80,
    traffic: [23, 25, 42, 43, 50, 52, 46, 39, 33, 36, 45, 57, 68, 64, 48, 25],
    coach: 'Linh Nguyễn',
    specialty: 'Sức mạnh & kỹ thuật tạ',
    groupClasses: ['Vinyasa Yoga', 'Zumba'],
  ),
  DemoGym(
    name: 'PrepaidGuard Riverside',
    area: 'Quận 7',
    city: 'TP. HCM',
    opensAt: 6,
    closesAt: 22,
    capacity: 65,
    traffic: [14, 21, 25, 31, 34, 37, 33, 28, 24, 30, 38, 44, 54, 47, 33, 17],
    coach: 'Minh Trần',
    specialty: 'Thể lực & vận động chức năng',
    groupClasses: ['Mobility Flow', 'HIIT Circuit'],
  ),
  DemoGym(
    name: 'PrepaidGuard West',
    area: 'Cầu Giấy',
    city: 'Hà Nội',
    opensAt: 6,
    closesAt: 22,
    capacity: 65,
    traffic: [25, 29, 40, 42, 47, 53, 56, 51, 43, 42, 49, 56, 61, 59, 44, 30],
    coach: 'An Lê',
    specialty: 'Kỹ thuật tập cho người mới',
    groupClasses: ['Pilates cơ bản', 'Dance Cardio'],
  ),
];

class TrainingSlot {
  const TrainingSlot({
    required this.gym,
    required this.title,
    required this.startsAt,
    required this.duration,
    required this.personal,
  });

  final DemoGym gym;
  final String title;
  final DateTime startsAt;
  final Duration duration;
  final bool personal;

  DateTime get endsAt => startsAt.add(duration);
  String get id => '${gym.name}|${startsAt.toIso8601String()}|$personal';
}

class DemoTrainingBookings {
  final _slots = <String, TrainingSlot>{};

  List<TrainingSlot> get slots =>
      _slots.values.toList()..sort((a, b) => a.startsAt.compareTo(b.startsAt));

  bool contains(TrainingSlot slot) => _slots.containsKey(slot.id);

  bool overlaps(TrainingSlot slot) => _slots.values.any(
    (existing) =>
        slot.startsAt.isBefore(existing.endsAt) &&
        existing.startsAt.isBefore(slot.endsAt),
  );

  bool add(TrainingSlot slot, DateTime now) {
    if (!slot.startsAt.isAfter(now) || overlaps(slot)) return false;
    _slots[slot.id] = slot;
    return true;
  }

  void remove(TrainingSlot slot) => _slots.remove(slot.id);
}
