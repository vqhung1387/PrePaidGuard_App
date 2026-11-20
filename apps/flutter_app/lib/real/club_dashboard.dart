import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app/prepaid_guard_theme.dart';
import 'api.dart';
import 'controller.dart';

DateTime _vn(DateTime value) => value.toUtc().add(const Duration(hours: 7));
String _date(DateTime value) => value.toIso8601String().substring(0, 10);
String _clock(int minute) =>
    '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
List<Json> _rows(dynamic value) =>
    (value as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

const _referenceBranches = [
  'Lê Hồng Phong',
  'Điện Biên Phủ',
  'Nguyễn Chí Thanh',
  'Nguyễn Thị Thập',
];

String _branchName(Object? name) =>
    name == 'Lê Hồng Phong · tư liệu 19/11' ? 'Lê Hồng Phong' : name.toString();

int _illustrativeCount(String branch, DateTime day, int hour) {
  const hourly = [
    5,
    3,
    2,
    2,
    4,
    12,
    32,
    47,
    54,
    42,
    35,
    39,
    55,
    51,
    45,
    58,
    76,
    101,
    136,
    142,
    115,
    91,
    52,
    22,
  ];
  final seed = branch.runes.fold<int>(0, (n, r) => (n * 31 + r) % 65521);
  final date = day.year * 10000 + day.month * 100 + day.day;
  final variation = (seed + date * 17 + hour * (date % 17 + 3)) % 23;
  return (hourly[hour] * (77 + seed % 27 + variation) / 100).round();
}

String _classPhoto(String title) {
  final name = title.toLowerCase();
  if (name.contains('dance') || name.contains('zumba'))
    return 'assets/class-dance.jpg';
  if (name.contains('pilates') || name.contains('balance'))
    return 'assets/class-pilates.jpg';
  if (name.contains('phục hồi') || name.contains('opening'))
    return 'assets/class-yoga.jpg';
  if (name.contains('combat') || name.contains('circuit'))
    return 'assets/gym-hero.jpg';
  return 'assets/club-session.jpg';
}

List<Json> _sampleTrainers(Json? club) {
  const rosters = {
    'Lê Hồng Phong': [
      ('Minh Anh', 'Pilates cơ bản · Kiểm soát tư thế'),
      ('Gia Huy', 'Cardio Dance · Sức bền'),
      ('Thảo Nguyên', 'Yoga phục hồi · Giãn cơ'),
    ],
    'Điện Biên Phủ': [
      ('Quốc Bảo', 'Body Combat · Thể lực'),
      ('Bảo Trâm', 'Hatha Yoga · Thăng bằng'),
      ('Hoài An', 'Pilates · Tư thế'),
    ],
    'Nguyễn Chí Thanh': [
      ('Khánh Linh', 'Zumba · Vũ đạo'),
      ('Tuấn Kiệt', 'Circuit Training · Sức mạnh'),
      ('Gia Hân', 'Yoga · Giãn cơ'),
    ],
    'Nguyễn Thị Thập': [
      ('Phương Vy', 'Body Balance · Thăng bằng'),
      ('Minh Khang', 'Cardio · Sức bền'),
      ('Thanh Hà', 'Pilates · Cơ trung tâm'),
    ],
  };
  return [
    for (final (name, specialty)
        in rosters[_branchName(club?['branch'])] ?? const <(String, String)>[])
      {'title': name, 'detail': specialty, 'illustrative': true},
  ];
}

List<Json> _classSchedule(List<Json> entries, Json? club, DateTime date) {
  final published = entries.where((e) => e['kind'] == 'class').toList();
  final index = _referenceBranches.indexOf(_branchName(club?['branch']));
  if (published.isNotEmpty || index < 0) return published;
  const morning = [
    'Hatha Yoga',
    'Pilates cơ bản',
    'Yoga giãn cơ',
    'Body Balance',
  ];
  const afternoon = [
    'Zumba',
    'Cardio Dance',
    'Body Combat',
    'Circuit Training',
  ];
  final slot = (date.weekday + index) % morning.length;
  final offset = index * 15;
  return [
    for (final (title, minute, duration) in [
      (morning[slot], 480 + offset, 60),
      (afternoon[slot], 1050 + offset, 45),
      ('Yoga phục hồi', 1140 + offset, 50),
    ])
      {
        'kind': 'class',
        'title': title,
        'minute': minute,
        'amount': duration,
        'detail': 'Lịch minh họa',
        'illustrative': true,
      },
  ];
}

class _CommunityStat extends StatelessWidget {
  const _CommunityStat(this.value, this.label);
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        '$value',
        style: Theme.of(
          context,
        ).textTheme.headlineSmall?.copyWith(color: accent),
      ),
      Text(label),
    ],
  );
}

enum ClubView {
  classes,
  trainers,
  notices,
  account,
  buddies,
  referral,
  publish,
}

class ClubDashboard extends StatefulWidget {
  const ClubDashboard({
    super.key,
    required this.controller,
    required this.login,
    required this.entry,
  });
  final LiveController? controller;
  final Future<void> Function() login;
  final Uri entry;
  @override
  State<ClubDashboard> createState() => ClubDashboardState();
}

class ClubDashboardState extends State<ClubDashboard> {
  List<Json> clubs = [
    for (final name in _referenceBranches) {'branch': name},
  ];
  Json? selected;
  DateTime day = DateUtils.dateOnly(_vn(DateTime.now()));
  List<Json> daily = [], today = [];
  bool loading = false;
  String? error;
  int request = 0;
  Timer? _refreshTimer;
  bool followToday = true;
  final hours = ScrollController(
    initialScrollOffset: (_vn(DateTime.now()).hour - 3).clamp(0, 23) * 37.0,
  );
  @override
  void dispose() {
    _refreshTimer?.cancel();
    hours.dispose();
    super.dispose();
  }

  LiveController? get c => widget.controller;
  bool get connected => c?.config != null;
  late bool wasConnected;
  @override
  void initState() {
    super.initState();
    selected = clubs.first;
    wasConnected = connected;
    if (connected) _load();
    _refreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted ||
          !connected ||
          loading ||
          ModalRoute.of(context)?.isCurrent != true)
        return;
      if (followToday) day = DateUtils.dateOnly(_vn(DateTime.now()));
      _load(background: true);
    });
  }

  @override
  void didUpdateWidget(ClubDashboard old) {
    super.didUpdateWidget(old);
    if (wasConnected != connected || old.controller != c) {
      wasConnected = connected;
      _load();
    }
  }

  Future<void> _load({bool background = false}) async {
    final ticket = ++request, api = c?.api;
    if (!connected || api == null) {
      setState(() {
        final previousName = _branchName(selected?['branch']);
        clubs = [
          for (final name in _referenceBranches) {'branch': name},
        ];
        selected =
            clubs.where((b) => b['branch'] == previousName).firstOrNull ??
            clubs.first;
        daily = [];
        today = [];
        error = null;
        loading = false;
      });
      return;
    }
    final target = day, previous = selected;
    setState(() {
      loading = true;
      error = null;
      if (!background) {
        daily = [];
        today = [];
      }
    });
    try {
      final branches = _rows(await api.request('GET', '/api/v1/clubs'));
      final known = branches.map((b) => _branchName(b['branch'])).toSet();
      for (final name in _referenceBranches.where(
        (name) => !known.contains(name),
      )) {
        branches.add({'branch': name});
      }
      final club =
          branches
              .where(
                (b) =>
                    b['merchant_id'] == previous?['merchant_id'] &&
                    b['branch'] == previous?['branch'],
              )
              .firstOrNull ??
          branches.firstOrNull;
      Future<List<Json>> board(DateTime date) async =>
          club == null || club['merchant_id'] == null
          ? []
          : _rows(
              await api.request(
                'GET',
                Uri(
                  path: '/api/v1/clubs/${club['merchant_id']}/board',
                  queryParameters: {
                    'branch': club['branch'].toString(),
                    'day': _date(date),
                  },
                ).toString(),
              ),
            );
      final current = _vn(DateTime.now());
      final records = await board(target);
      final todays = DateUtils.isSameDay(current, target)
          ? records
          : await board(current);
      if (!mounted || ticket != request) return;
      setState(() {
        clubs = branches;
        selected = club;
        daily = records;
        today = todays;
      });
    } catch (e) {
      if (mounted && ticket == request)
        setState(() => error = formatUserError(e));
    } finally {
      if (mounted && ticket == request) setState(() => loading = false);
    }
  }

  Future<void> refreshDirectory() => _load();
  List<Json> get availableBranches => clubs;
  String branchLabel(Json branch) => _branchName(branch['branch']);
  Future<void> selectBranch(Json branch) async {
    selected = branch;
    await _load();
  }

  Future<void> open(ClubView view) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ClubPage(
          view: view,
          c: c,
          branch: selected,
          login: widget.login,
          entry: widget.entry,
        ),
      ),
    );
    if (mounted && view == ClubView.publish) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final now = _vn(DateTime.now());
    final recorded = {
      for (final e in daily.where((e) => e['kind'] == 'attendance'))
        (e['minute'] as int) ~/ 60: e['amount'] as int,
    };
    final name = _branchName(selected?['branch']);
    final counts = {
      if (_referenceBranches.contains(name) && error == null)
        for (var hour = 0; hour < 24; hour++)
          hour: _illustrativeCount(name, day, hour),
      ...recorded,
    };
    final maximum = counts.values.fold<int>(1, (v, n) => v > n ? v : n);
    final classes = error == null && (!loading || today.isNotEmpty)
        ? _classSchedule(today, selected, now)
        : <Json>[];
    final current = DateUtils.isSameDay(day, now) ? counts[now.hour] : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Số hội viên đang tập',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (current != null)
                      Text(
                        '$current người${recorded.containsKey(now.hour) ? '' : ' · minh họa'}',
                        style: const TextStyle(
                          color: accent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                if (clubs.isNotEmpty)
                  DropdownButtonFormField<int>(
                    initialValue: clubs.indexOf(selected!),
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Chi nhánh'),
                    items: [
                      for (final (i, b) in clubs.indexed)
                        DropdownMenuItem(
                          value: i,
                          child: Text(
                            _branchName(b['branch']),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (i) {
                      if (i != null) {
                        selected = clubs[i];
                        _load();
                      }
                    },
                  ),
                if (loading)
                  const LinearProgressIndicator(
                    semanticsLabel: 'Đang tải số liệu chi nhánh',
                  ),
                if (error != null)
                  TextButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Tải lại dữ liệu chi nhánh'),
                  )
                else if (clubs.isEmpty && !loading)
                  const Text('Chưa có chi nhánh công bố số liệu.'),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  controller: hours,
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (var h = 0; h < 24; h++)
                        SizedBox(
                          width: 37,
                          child: Tooltip(
                            triggerMode: TooltipTriggerMode.tap,
                            message:
                                '$h giờ: ${counts[h]?.toString() ?? "chưa có số liệu"}${counts[h] != null && !recorded.containsKey(h)
                                    ? ', minh họa'
                                    : recorded.containsKey(h)
                                    ? ', đã ghi nhận'
                                    : ''}',
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Text(
                                  counts[h]?.toString() ?? '–',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: mutedText,
                                  ),
                                ),
                                Container(
                                  width: 23,
                                  height: counts[h] == null
                                      ? 2
                                      : 2 + 68 * counts[h]! / maximum,
                                  decoration: BoxDecoration(
                                    color: counts[h] == null
                                        ? panelOutline
                                        : !recorded.containsKey(h)
                                        ? const Color(0xff87cce1)
                                        : (DateUtils.isSameDay(day, now) &&
                                                  h == now.hour
                                              ? Colors.deepOrange
                                              : cyan),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                                Text(
                                  '${h}h',
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final h in [0, 8, 16])
                      TextButton(
                        onPressed: () {
                          if (hours.hasClients)
                            hours.animateTo(
                              (h * 37.0).clamp(
                                0.0,
                                hours.position.maxScrollExtent,
                              ),
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOut,
                            );
                        },
                        child: Text('${h}–${h + 8}h'),
                      ),
                  ],
                ),
                Wrap(
                  spacing: 5,
                  children: [
                    for (var ago = 0; ago < 7; ago++)
                      Builder(
                        builder: (_) {
                          final date = DateUtils.dateOnly(
                            now,
                          ).subtract(Duration(days: ago));
                          return ChoiceChip(
                            label: Text(
                              ago == 0
                                  ? 'Hôm nay'
                                  : '${date.day}/${date.month}',
                            ),
                            selected: DateUtils.isSameDay(date, day),
                            onSelected: (_) {
                              followToday = ago == 0;
                              day = date;
                              _load();
                            },
                          );
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            'Lớp học hôm nay',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          subtitle: classes.isEmpty
              ? null
              : Text(
                  '${classes.length} lớp · ${_branchName(selected?['branch'])}${classes.first['illustrative'] == true ? ' · Lịch minh họa' : ''}',
                ),
          trailing: const Text('Xem tất cả', style: TextStyle(color: accent)),
          onTap: () => open(ClubView.classes),
        ),
        if (classes.isEmpty)
          Card(
            child: ListTile(
              leading: const Icon(Icons.event_note, color: accent),
              title: Text(
                loading
                    ? 'Đang tải lịch lớp'
                    : error != null
                    ? 'Lịch lớp chưa tải được'
                    : 'Chưa có lịch lớp được công bố hôm nay',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => open(ClubView.classes),
            ),
          )
        else
          SizedBox(
            height: 150,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: classes.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (_, i) => SizedBox(
                width: 220,
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => open(ClubView.classes),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: Image.asset(
                            _classPhoto(classes[i]['title']),
                            fit: BoxFit.cover,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(
                            '${classes[i]['title']}\n${_clock(classes[i]['minute'])} · ${classes[i]['amount']} phút',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class ClubPage extends StatefulWidget {
  const ClubPage({
    super.key,
    required this.view,
    required this.c,
    required this.branch,
    required this.login,
    required this.entry,
  });
  final ClubView view;
  final LiveController? c;
  final Json? branch;
  final Uri entry;
  final Future<void> Function() login;
  @override
  State<ClubPage> createState() => _ClubPageState();
}

class _ClubPageState extends State<ClubPage> {
  static const titles = [
    'Lớp học hôm nay',
    'Huấn luyện viên',
    'Thông báo',
    'Tài khoản',
    'Kết nối bạn tập',
    'Giới thiệu bạn',
    'Cập nhật chi nhánh',
  ];
  late final code = TextEditingController(
    text: widget.entry.queryParameters['buddy'] ?? '',
  );
  late final name = TextEditingController(
    text: widget.c?.user?['display_name']?.toString() ?? '',
  );
  late final branch = TextEditingController(
    text: widget.branch?['branch']?.toString() ?? '',
  );
  final title = TextEditingController(),
      detail = TextEditingController(),
      amount = TextEditingController();
  DateTime day = DateUtils.dateOnly(_vn(DateTime.now()));
  TimeOfDay time = TimeOfDay(hour: _vn(DateTime.now()).hour, minute: 0);
  String kind = 'class', message = '', invite = '';
  bool busy = false;
  List<Json> items = [];
  int generation = 0;
  String? owner;
  LiveController? get c => widget.c;
  Uri share(Map<String, String> params) {
    final local = ['localhost', '127.0.0.1', '::1'].contains(widget.entry.host);
    final base = local
        ? Uri.parse(
            const String.fromEnvironment(
              'PUBLIC_APP_URL',
              defaultValue: 'https://prepaidguard-web.onrender.com',
            ),
          )
        : widget.entry;
    return base.replace(queryParameters: params, fragment: '');
  }

  @override
  void initState() {
    super.initState();
    owner = c?.account;
    c?.addListener(_changed);
    _read();
  }

  void _changed() {
    if (!mounted) return;
    if (owner != c?.account) {
      owner = c?.account;
      invite = '';
      code.clear();
      name.text = c?.user?['display_name']?.toString() ?? '';
      _read();
    } else {
      setState(() {});
    }
  }

  @override
  void dispose() {
    c?.removeListener(_changed);
    for (final t in [code, name, branch, title, detail, amount]) {
      t.dispose();
    }
    super.dispose();
  }

  Future<void> _read() async {
    final token = ++generation;
    var records = <Json>[];
    final view = widget.view;
    setState(() {
      message = '';
      items = [];
      busy = true;
    });
    try {
      if (view == ClubView.notices && c?.config != null) {
        records = _rows(await c!.api.request('GET', '/api/v1/club-notices'));
      }
      if (view == ClubView.buddies && c?.loggedIn == true) {
        records = _rows(await c!.api.request('GET', '/api/v1/me/buddies'));
      }
      if (view == ClubView.trainers || view == ClubView.classes) {
        var club = widget.branch;
        if (club == null && c?.config != null) {
          club = _rows(
            await c!.api.request('GET', '/api/v1/clubs'),
          ).firstOrNull;
        }
        if (club != null && club['merchant_id'] != null && c?.config != null) {
          final path = Uri(
            path: '/api/v1/clubs/${club['merchant_id']}/board',
            queryParameters: {
              'day': _date(day),
              'branch': club['branch'].toString(),
            },
          );
          records = _rows(await c!.api.request('GET', path.toString()))
              .where(
                (e) =>
                    e['kind'] ==
                    (view == ClubView.classes ? 'class' : 'trainer'),
              )
              .toList();
        }
        if (view == ClubView.classes) {
          records = _classSchedule(records, club, day);
        } else if (records.isEmpty) {
          records = _sampleTrainers(club);
        }
      }
      if (mounted && generation == token) setState(() => items = records);
    } catch (e) {
      if (mounted && generation == token)
        setState(() => message = formatUserError(e));
    } finally {
      if (mounted && generation == token) setState(() => busy = false);
    }
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      message = '';
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => message = formatUserError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget field(TextEditingController tc, String label, {int? limit}) =>
      TextField(
        controller: tc,
        maxLength: limit,
        decoration: InputDecoration(labelText: label),
      );
  Widget button(String label, Future<void> Function() action) => FilledButton(
    onPressed: busy ? null : () => run(action),
    child: Text(label),
  );
  Future<void> copy(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) setState(() => message = 'Đã sao chép.');
  }

  String get seenKey => 'club.seen.${c?.account ?? "guest"}';
  bool seen(String id) =>
      (c?.store.read(seenKey) ?? '').split(',').contains(id);
  Future<void> openNotice(Json n) async {
    final all =
        (c?.store.read(seenKey) ?? '')
            .split(',')
            .where((v) => v.isNotEmpty)
            .toSet()
          ..add(n['id'].toString());
    c?.store.write(
      seenKey,
      all.skip(all.length > 200 ? all.length - 200 : 0).join(','),
    );
    setState(() {});
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(n['title']),
        content: Text(n['detail']),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.view, signed = c?.loggedIn == true;
    final login = button('Kết nối ví', widget.login);
    final widgets = <Widget>[];
    if (v == ClubView.referral) {
      final link = share({
        'ref': signed ? c!.user!['id']?.toString() ?? 'member' : 'club',
      }).toString();
      widgets.addAll([
        const Icon(Icons.person_add_alt_1, size: 56, color: cyan),
        const Text('Mời bạn khám phá các gói dịch vụ tại PrepaidGuard.'),
        SelectableText(link),
        button('Sao chép liên kết giới thiệu', () => copy(link)),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '7 ngày qua · Minh họa',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 14),
                const Wrap(
                  spacing: 24,
                  runSpacing: 10,
                  children: [
                    _CommunityStat(18, 'Lượt mở liên kết'),
                    _CommunityStat(6, 'Bạn đã đăng ký'),
                    _CommunityStat(2, 'Bạn đã chọn gói'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ]);
    } else if (v == ClubView.account) {
      widgets.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 26),
          decoration: BoxDecoration(
            color: const Color(0xff0088b2),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            children: [
              const CircleAvatar(
                backgroundColor: Colors.white,
                radius: 34,
                child: Icon(Icons.person_outline, color: accent, size: 36),
              ),
              const SizedBox(height: 10),
              Text(
                signed ? (c?.user?['display_name'] ?? 'Hội viên') : 'Khách',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      );
      if (!signed)
        widgets.add(login);
      else
        widgets.addAll([
          Card(
            child: ListTile(
              leading: const Icon(
                Icons.account_balance_wallet_outlined,
                color: accent,
              ),
              title: const Text('Ví thanh toán'),
              subtitle: SelectableText(c!.account!),
            ),
          ),

          field(name, 'Tên hiển thị', limit: 80),
          button('Lưu thông tin cá nhân', () async {
            await c!.api.request(
              'PATCH',
              '/api/v1/me',
              body: {'display_name': name.text.trim()},
            );
            await c!.refresh();
            if (mounted) setState(() => message = 'Đã lưu tên hiển thị.');
          }),
          OutlinedButton.icon(
            onPressed: busy ? null : () => run(c!.logout),
            icon: const Icon(Icons.logout),
            label: const Text('Đăng xuất'),
          ),
        ]);
    } else if (v == ClubView.buddies) {
      if (!signed)
        widgets.addAll([
          const Text('Kết nối ví để tạo lời mời riêng và xem bạn tập của bạn.'),
          login,
        ]);
      else {
        widgets.addAll([
          button('Tạo mã mời bạn tập', () async {
            final result = await c!.api.request(
              'POST',
              '/api/v1/me/buddy-invites',
            );
            if (mounted) setState(() => invite = result['code']);
          }),
          if (invite.isNotEmpty) ...[
            SelectableText(invite),
            button('Sao chép mã mời', () => copy(invite)),
          ],
          field(code, 'Mã mời từ bạn tập', limit: 64),
          button('Chấp nhận lời mời', () async {
            await c!.api.request(
              'POST',
              '/api/v1/me/buddies',
              body: {'code': code.text.trim()},
            );
            if (!mounted) return;
            code.clear();
            await _read();
          }),
          Text(
            busy || message.isNotEmpty
                ? 'Bạn tập của tôi'
                : 'Bạn tập của tôi (${items.length})',
          ),
          if (items.isEmpty) const Text('Chưa có kết nối.'),
          for (final e in items)
            ListTile(
              leading: const Icon(Icons.person),
              title: Text(e['display_name'] ?? 'Hội viên'),
            ),
        ]);
      }
      widgets.add(
        Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text(
                  '3 hồ sơ bạn tập · Minh họa',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              for (final (initial, person, routine) in [
                ('MA', 'Minh Anh', 'Yoga · 07:00 · Thứ 2 và thứ 4'),
                ('QH', 'Quang Huy', 'Tập sức mạnh · 18:00 · Thứ 3 và thứ 5'),
                ('HL', 'Hà Linh', 'Pilates · 09:00 · Cuối tuần'),
              ])
                ListTile(
                  leading: CircleAvatar(child: Text(initial)),
                  title: Text(person),
                  subtitle: Text(routine),
                ),
            ],
          ),
        ),
      );
    } else if (v == ClubView.publish) {
      if (c?.isMerchant != true)
        widgets.add(const Text('Cần đăng nhập bằng tài khoản cơ sở.'));
      else
        widgets.addAll([
          field(branch, 'Tên chi nhánh', limit: 100),
          DropdownButtonFormField<String>(
            initialValue: kind,
            items: [
              for (final (k, l) in [
                ('class', 'Lớp học'),
                ('trainer', 'Huấn luyện viên'),
                ('attendance', 'Số người đang tập'),
                ('notice', 'Thông báo công khai'),
              ])
                DropdownMenuItem(value: k, child: Text(l)),
            ],
            onChanged: (k) {
              if (k != null)
                setState(() {
                  kind = k;
                  amount.clear();
                });
            },
          ),
          if (kind != 'attendance')
            field(
              title,
              kind == 'trainer' ? 'Tên huấn luyện viên' : 'Tiêu đề',
              limit: 120,
            ),
          if (kind != 'attendance') field(detail, 'Chi tiết', limit: 500),
          if (kind == 'class' || kind == 'attendance') ...[
            TextButton(
              onPressed: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: day,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                );
                if (d != null && mounted) setState(() => day = d);
              },
              child: Text('Ngày ${_date(day)}'),
            ),
            TextButton(
              onPressed: () async {
                final t = await showTimePicker(
                  context: context,
                  initialTime: time,
                );
                if (t != null && mounted) setState(() => time = t);
              },
              child: Text('Giờ ${time.format(context)}'),
            ),
            field(
              amount,
              kind == 'class' ? 'Thời lượng (phút)' : 'Số hội viên đang tập',
            ),
          ],
          button('Công bố', () async {
            final n = int.tryParse(amount.text.trim());
            if (branch.text.trim().isEmpty ||
                (kind != 'attendance' && title.text.trim().isEmpty) ||
                ((kind == 'class' || kind == 'attendance') &&
                    (n == null || n < (kind == 'class' ? 1 : 0))))
              throw const FormatException(
                'Kiểm tra tên chi nhánh, tiêu đề và số lượng.',
              );
            await c!.api.request(
              'POST',
              '/api/v1/merchant/club-entries',
              body: {
                'branch': branch.text.trim(),
                'kind': kind,
                'title': title.text.trim(),
                'detail': detail.text.trim(),
                'day': _date(day),
                'minute': time.hour * 60 + time.minute,
                'amount': n ?? 0,
              },
            );
            if (mounted) {
              title.clear();
              detail.clear();
              amount.clear();
              setState(() => message = 'Đã công bố tại chi nhánh.');
            }
          }),
        ]);
    } else {
      if (widget.branch != null && v != ClubView.notices)
        widgets.add(
          Text(
            _branchName(widget.branch!['branch']),
            style: Theme.of(context).textTheme.titleLarge,
          ),
        );
      if (v == ClubView.classes)
        widgets.add(
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              IconButton(
                tooltip: 'Ngày trước',
                onPressed: busy
                    ? null
                    : () {
                        day = day.subtract(const Duration(days: 1));
                        _read();
                      },
                icon: const Icon(Icons.chevron_left),
              ),
              TextButton(
                onPressed: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: day,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (d != null && mounted) {
                    day = d;
                    _read();
                  }
                },
                child: Text('Lịch ngày ${_date(day)}'),
              ),
              IconButton(
                tooltip: 'Ngày sau',
                onPressed: busy
                    ? null
                    : () {
                        day = day.add(const Duration(days: 1));
                        _read();
                      },
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        );
      if (items.isEmpty && !busy && message.isEmpty)
        widgets.add(
          Text(
            c?.config == null
                ? 'Vui lòng kết nối dịch vụ để tải dữ liệu.'
                : switch (v) {
                    ClubView.notices => 'Chưa có thông báo công khai.',
                    ClubView.classes =>
                      'Chi nhánh chưa công bố lớp học cho ngày này.',
                    _ => 'Chưa có hồ sơ huấn luyện viên được công bố.',
                  },
          ),
        );
      if (v == ClubView.trainers &&
          items.firstOrNull?['illustrative'] == true) {
        widgets.add(Text('Hồ sơ minh họa · ${items.length} huấn luyện viên'));
      }
      for (final e in items)
        widgets.add(
          Card(
            child: v == ClubView.notices
                ? ListTile(
                    leading: const Icon(
                      Icons.notifications_outlined,
                      color: cyan,
                    ),
                    title: Text(e['title']),
                    subtitle: Text(
                      '${_branchName(e['branch'])} · ${_date(_vn(DateTime.parse(e['created'])))}',
                    ),
                    trailing: seen(e['id'])
                        ? null
                        : const Icon(
                            Icons.circle,
                            size: 10,
                            color: Colors.deepOrange,
                          ),
                    onTap: () => openNotice(e),
                  )
                : ListTile(
                    leading: v == ClubView.classes
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.asset(
                              _classPhoto(e['title']),
                              excludeFromSemantics: true,
                              width: 74,
                              height: 54,
                              fit: BoxFit.cover,
                            ),
                          )
                        : const Icon(Icons.sports, color: cyan),
                    title: Text(e['title']),
                    subtitle: Text(
                      [
                        if (v == ClubView.classes)
                          '${_clock(e['minute'])} · ${e['amount']} phút',
                        if (e['detail'].toString().isNotEmpty) e['detail'],
                      ].join('\n'),
                    ),
                  ),
          ),
        );
      widgets.add(
        TextButton.icon(
          onPressed: busy ? null : _read,
          icon: const Icon(Icons.refresh),
          label: const Text('Làm mới'),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Quay lại',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(titles[v.index]),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (busy) const LinearProgressIndicator(),
              for (final w in widgets)
                Padding(padding: const EdgeInsets.only(bottom: 12), child: w),
              if (message.isNotEmpty)
                Semantics(liveRegion: true, child: Text(message)),
            ],
          ),
        ),
      ),
    );
  }
}
