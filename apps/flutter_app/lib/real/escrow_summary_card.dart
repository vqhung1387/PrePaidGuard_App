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

  BigInt _parseAtomic(Object? value) =>
      BigInt.tryParse(value?.toString() ?? '') ?? BigInt.zero;

  String _sourceLabel(String raw) => switch (raw) {
    'LIVE' => 'LIVE (trực tiếp chuỗi)',
    'PROJECTION' => 'PROJECTION (bản chiếu sự kiện chuỗi)',
    _ => raw,
  };

  @override
  Widget build(BuildContext context) {
    final withPrincipal = subscriptions
        .where((sub) => sub['remaining_principal'] != null)
        .toList();
    if (withPrincipal.isEmpty) return const SizedBox.shrink();

    var initialTotal = BigInt.zero;
    var releasedTotal = BigInt.zero;
    var remainingTotal = BigInt.zero;
    var refundedTotal = BigInt.zero;
    var activeCount = 0;
    DateTime? earliestRefundAt;
    String? earliestRefundRaw;
    BigInt? maxBlock;
    final sources = <String>{};

    for (final sub in withPrincipal) {
      initialTotal += _parseAtomic(sub['initial_principal']);
      releasedTotal += _parseAtomic(sub['principal_released']);
      remainingTotal += _parseAtomic(sub['remaining_principal']);
      refundedTotal += _parseAtomic(sub['principal_refunded']);

      if (sub['status'] == 'ACTIVE') {
        activeCount++;
        final rawRefund = sub['refund_available_at']?.toString();
        if (rawRefund != null && rawRefund.isNotEmpty) {
          final parsed = DateTime.tryParse(rawRefund);
          if (parsed != null &&
              (earliestRefundAt == null || parsed.isBefore(earliestRefundAt))) {
            earliestRefundAt = parsed;
            earliestRefundRaw = rawRefund;
          } else if (earliestRefundRaw == null) {
            earliestRefundRaw = rawRefund;
          }
        }
      }

      final sync = sub['sync'];
      if (sync is Map) {
        final source = sync['source']?.toString();
        if (source != null && source.isNotEmpty) {
          sources.add(_sourceLabel(source));
        }
        final block = BigInt.tryParse(sync['block_number']?.toString() ?? '');
        if (block != null && (maxBlock == null || block > maxBlock)) {
          maxBlock = block;
        }
      }
    }

    final sourceText = sources.isEmpty
        ? _sourceLabel('PROJECTION')
        : sources.join(' + ');
    final theme = Theme.of(context);
    final metrics = [
      ('Tổng gốc đã khóa', '${formatTokenAmount(initialTotal)} mUSDC'),
      ('Tổng đã giải ngân', '${formatTokenAmount(releasedTotal)} mUSDC'),
      ('Đang giữ trong Vault', '${formatTokenAmount(remainingTotal)} mUSDC'),
      ('Tổng đã hoàn gốc', '${formatTokenAmount(refundedTotal)} mUSDC'),
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
                    : 'Không còn gói đang hoạt động trong danh sách này; toàn bộ tiền gốc hiển thị đã giải ngân hoặc hoàn về ví.',
              ),
              const SizedBox(height: 6),
              Text(
                'Nguồn dữ liệu: $sourceText${maxBlock != null ? ' · Block #$maxBlock' : ''} · mUSDC thử nghiệm (Chain ${config['chain_id']}, Yield ${config['yield_mode']})',
                style: theme.textTheme.bodySmall?.copyWith(color: mutedText),
              ),
              if (hasMore || filter != SubscriptionFilter.all) ...[
                const SizedBox(height: 4),
                Text(
                  'Phạm vi cộng: ${withPrincipal.length} đăng ký đang hiển thị (${filter.label}${hasMore ? ', còn trang tiếp' : ''}).',
                  style: theme.textTheme.bodySmall?.copyWith(color: mutedText),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
