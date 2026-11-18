import 'package:flutter/material.dart';

import '../app/prepaid_guard_theme.dart';
import '../features/plans/demo_plan.dart';
import 'api.dart';
import 'controller.dart';

class EscrowSummaryCard extends StatelessWidget {
  const EscrowSummaryCard({
    super.key,
    required this.subscriptions,
    required this.config,
    required this.filter,
    required this.hasMore,
    this.merchant = false,
  });

  final List<Json> subscriptions;
  final Json config;
  final SubscriptionFilter filter;
  final bool hasMore;
  final bool merchant;

  static const _principalFields = [
    'initial_principal',
    'principal_released',
    'remaining_principal',
    'principal_refunded',
  ];

  static BigInt? _parseAtomic(Object? value) {
    final amount = BigInt.tryParse(value?.toString() ?? '');
    return amount != null && !amount.isNegative ? amount : null;
  }

  String _sourceLabel(String raw) => switch (raw) {
    'LIVE' => 'LIVE (trực tiếp chuỗi)',
    'PROJECTION' => 'PROJECTION (bản chiếu sự kiện chuỗi)',
    _ => raw,
  };

  @override
  Widget build(BuildContext context) {
    if (subscriptions.isEmpty) return const SizedBox.shrink();
    final totals = List.filled(_principalFields.length, BigInt.zero);
    var validCount = 0;
    var activeCount = 0;
    DateTime? earliestRefundAt;
    String? earliestRefundRaw;
    BigInt? maxBlock;
    final sources = <String>{};

    for (final sub in subscriptions) {
      final amounts = _principalFields
          .map((key) => _parseAtomic(sub[key]))
          .toList();
      if (amounts.contains(null) ||
          amounts[0] != amounts[1]! + amounts[2]! + amounts[3]!) {
        continue;
      }
      validCount++;
      for (var index = 0; index < totals.length; index++) {
        totals[index] += amounts[index]!;
      }

      if (sub['status'] == 'ACTIVE') {
        activeCount++;
        final rawRefund = sub['refund_available_at']?.toString();
        if (rawRefund != null && rawRefund.isNotEmpty) {
          final parsed = DateTime.tryParse(rawRefund);
          if (parsed != null &&
              (earliestRefundAt == null || parsed.isBefore(earliestRefundAt))) {
            earliestRefundAt = parsed;
            earliestRefundRaw = rawRefund;
          }
        }
      }

      final sync = sub['sync'];
      final source = sync is Map ? sync['source']?.toString() : null;
      sources.add(
        source == null || source.isEmpty ? 'Chưa rõ' : _sourceLabel(source),
      );
      if (sync is Map) {
        final block = BigInt.tryParse(sync['block_number']?.toString() ?? '');
        if (block != null && (maxBlock == null || block > maxBlock)) {
          maxBlock = block;
        }
      }
    }

    if (validCount == 0) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text('Chưa đủ dữ liệu đối chiếu để tóm tắt tiền gốc.'),
      );
    }
    final sourceText = sources.join(' + ');
    final theme = Theme.of(context);
    final metrics = [
      ('Tổng gốc đã khóa', '${formatTokenAmount(totals[0])} mUSDC'),
      ('Tổng đã giải ngân', '${formatTokenAmount(totals[1])} mUSDC'),
      ('Đang giữ trong Vault', '${formatTokenAmount(totals[2])} mUSDC'),
      ('Tổng đã hoàn gốc', '${formatTokenAmount(totals[3])} mUSDC'),
    ];

    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 8),
      child: Card(
        color: panelRaised,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                merchant
                    ? 'Tóm tắt dòng tiền cơ sở (dữ liệu thật)'
                    : 'Tóm tắt tiền gốc và hoàn tiền (dữ liệu thật)',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final wideText =
                      MediaQuery.textScalerOf(context).scale(14) > 18;
                  final columns = constraints.maxWidth >= 720 && !wideText
                      ? 4
                      : (constraints.maxWidth >= 420 && !wideText ? 2 : 1);
                  final itemWidth =
                      (constraints.maxWidth - 10 * (columns - 1)) / columns;
                  return Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final (label, value) in metrics)
                        SizedBox(
                          width: itemWidth,
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: panel,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: panelOutline),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  label,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: mutedText,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  value,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: accent,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              Text(
                activeCount > 0
                    ? '$activeCount gói đang hoạt động${earliestRefundRaw != null ? ' · Mốc hoàn gốc sớm nhất: $earliestRefundRaw' : ''}. Hoàn gốc chỉ mở khi tới mốc của từng gói; không tự giải ngân.'
                    : 'Các đăng ký được cộng ở trên đều đã kết thúc.',
              ),
              const SizedBox(height: 6),
              Text(
                'Nguồn dữ liệu: $sourceText${maxBlock != null ? ' · Block #$maxBlock' : ''} · mUSDC thử nghiệm (Chain ${config['chain_id']}, Yield ${config['yield_mode']})',
                style: theme.textTheme.bodySmall?.copyWith(color: mutedText),
              ),
              if (hasMore || filter != SubscriptionFilter.all) ...[
                const SizedBox(height: 4),
                Text(
                  'Phạm vi cộng: $validCount đăng ký đang hiển thị (${filter.label}${hasMore ? ', còn trang tiếp' : ''}).',
                  style: theme.textTheme.bodySmall?.copyWith(color: mutedText),
                ),
              ],
              if (validCount != subscriptions.length)
                Text(
                  'Bỏ qua ${subscriptions.length - validCount} đăng ký có dữ liệu tiền gốc thiếu hoặc không khớp.',
                  style: theme.textTheme.bodySmall?.copyWith(color: mutedText),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
