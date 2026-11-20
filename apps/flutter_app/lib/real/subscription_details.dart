import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/prepaid_guard_theme.dart';
import '../features/plans/demo_plan.dart';
import 'api.dart';
import 'controller.dart';

String formatTestnetAmount(Object? value) {
  final amount = BigInt.tryParse(value.toString());
  return amount == null
      ? 'Chưa có dữ liệu'
      : '${formatTokenAmount(amount)} $creditUnit';
}

class SubscriptionYield extends StatelessWidget {
  const SubscriptionYield({
    super.key,
    required this.summary,
    this.expanded = false,
    this.merchant = false,
  });

  final Json summary;
  final bool expanded;
  final bool merchant;

  @override
  Widget build(BuildContext context) {
    final mode = summary['mode'];
    if (mode == 'DISABLED') return const Text('Lợi tức · Đã tắt (DISABLED)');
    if (mode != 'MOCK') return const Text('Lợi tức · Chưa có dữ liệu');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Lợi tức mô phỏng (MOCK) · Token thử nghiệm',
          style: TextStyle(color: accent),
        ),
        Text(
          'Ước tính chưa nhận: ${formatTestnetAmount(summary['estimated_unclaimed'])}',
        ),
        if (expanded || !merchant)
          Text(
            'Đã trả cho khách: ${formatTestnetAmount(summary['paid_subscriber'])}',
          ),
        if (expanded || merchant)
          Text(
            'Đã trả cho cơ sở: ${formatTestnetAmount(summary['paid_merchant'])}',
          ),
        if (expanded)
          Text(
            'Đã trả nền tảng: ${formatTestnetAmount(summary['paid_platform'])}',
          ),
      ],
    );
  }
}

class SubscriptionDetails extends StatefulWidget {
  const SubscriptionDetails({
    super.key,
    required this.controller,
    required this.detail,
    required this.eligibility,
    required this.firstPage,
  });

  final LiveController controller;
  final Json detail;
  final Json eligibility;
  final (List<Json>, String?) firstPage;

  @override
  State<SubscriptionDetails> createState() => _SubscriptionDetailsState();
}

class _SubscriptionDetailsState extends State<SubscriptionDetails> {
  late final _events = [...widget.firstPage.$1];
  late String? _cursor = widget.firstPage.$2;
  bool _loading = false;
  String? _error;

  Future<void> _loadMore() async {
    if (_cursor == null || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final (items, next) = await widget.controller.operation(
        () => widget.controller.events(
          widget.detail['subscription_id'] as String,
          cursor: _cursor,
        ),
      );
      if (!mounted) return;
      final ids = _events.map((event) => event['id']).toSet();
      setState(() {
        _events.addAll(items.where((item) => ids.add(item['id'])));
        _cursor = next;
      });
    } catch (error) {
      if (mounted) setState(() => _error = formatUserError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = widget.detail;
    final eligibility = widget.eligibility;
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => AlertDialog(
        scrollable: true,
        title: Text('Đăng ký #${detail['subscription_id']}'),
        content: !widget.controller.loggedIn
            ? const Text('Phiên ví đã thay đổi. Đăng nhập lại để xem chi tiết.')
            : SizedBox(
                width: 680,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (label, field) in [
                      ('Đã trả trước', 'initial_principal'),
                      ('Đã giải ngân', 'principal_released'),
                      ('Đã hoàn gốc', 'principal_refunded'),
                      ('Gốc còn lại', 'remaining_principal'),
                    ])
                      Text('$label: ${formatTestnetAmount(detail[field])}'),
                    Text(
                      'Đã giải ngân ${detail['completed_periods']}/${detail['total_periods']} kỳ',
                    ),
                    const Divider(),
                    Text(
                      'Có thể check-in: ${eligibility['can_check_in'] == true ? 'Có' : 'Chưa'}',
                    ),
                    Text(
                      'Có thể hoàn gốc: ${eligibility['can_refund'] == true ? 'Có' : 'Chưa'}',
                    ),
                    Text('Kỳ tiếp: ${detail['next_release_at'] ?? '—'}'),
                    Text(
                      'Mốc hoàn gốc: ${detail['refund_available_at'] ?? '—'}',
                    ),
                    const Divider(),
                    SubscriptionYield(
                      summary: detail['yield_summary'] as Json? ?? const {},
                      expanded: true,
                    ),
                    const Divider(),
                    Text('Lịch sử giao dịch · ${_events.length} mục'),
                    if (_events.isEmpty)
                      const Text('Chưa có giao dịch được đồng bộ.'),
                    for (final event in _events)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          '${event['event_name']} · ${event['block_timestamp']}',
                        ),
                        subtitle: SelectableText(
                          event['explorer_url'] as String,
                        ),
                        trailing: IconButton(
                          tooltip: 'Sao chép liên kết giao dịch',
                          onPressed: () => Clipboard.setData(
                            ClipboardData(
                              text: event['explorer_url'] as String,
                            ),
                          ),
                          icon: const Icon(Icons.copy),
                        ),
                      ),
                    if (_error case final error?)
                      Text(
                        error,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    if (_cursor != null)
                      OutlinedButton(
                        onPressed: _loading ? null : _loadMore,
                        child: Text(
                          _loading ? 'Đang tải lịch sử…' : 'Tải thêm lịch sử',
                        ),
                      ),
                  ],
                ),
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }
}
