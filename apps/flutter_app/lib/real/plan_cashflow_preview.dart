import 'package:flutter/material.dart';

import '../app/prepaid_guard_theme.dart';
import '../features/plans/demo_plan.dart';

/// Illustrates the published terms. The selected period never submits a transaction.
class PlanCashflowPreview extends StatefulWidget {
  const PlanCashflowPreview({
    super.key,
    required this.periods,
    required this.unit,
  });

  final int periods;
  final BigInt unit;

  @override
  State<PlanCashflowPreview> createState() => _PlanCashflowPreviewState();
}

class _PlanCashflowPreviewState extends State<PlanCashflowPreview> {
  int _period = 1;

  @override
  Widget build(BuildContext context) {
    final current = _period.clamp(0, widget.periods);
    final released = widget.unit * BigInt.from(current);
    final held = widget.unit * BigInt.from(widget.periods - current);
    final theme = Theme.of(context).textTheme;

    const ink = Color(0xff103a46);
    Widget amount(String label, BigInt value, Color color) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.bodySmall?.copyWith(color: mutedText)),
        Text(
          '${formatTokenAmount(value)} $creditUnit',
          style: theme.titleMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xffedf6f7),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Dòng tiền theo kỳ',
            style: theme.titleLarge?.copyWith(color: ink),
          ),
          const SizedBox(height: 4),
          Text(
            'Mỗi kỳ xác nhận giải ngân ${formatTokenAmount(widget.unit)} $creditUnit.',
            style: theme.bodyMedium?.copyWith(color: mutedText),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    'Kỳ $current/${widget.periods}',
                    style: theme.titleMedium,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Kỳ trước',
                onPressed: current == 0
                    ? null
                    : () => setState(() => _period = current - 1),
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                tooltip: 'Kỳ tiếp theo',
                onPressed: current == widget.periods
                    ? null
                    : () => setState(() => _period = current + 1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: current / widget.periods,
              minHeight: 10,
              color: accent,
              backgroundColor: const Color(0xffc8dce1),
              semanticsLabel: 'Tỷ lệ dự kiến giải ngân',
              semanticsValue: '${(100 * current / widget.periods).round()}%',
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 24,
            runSpacing: 8,
            children: [
              amount('Dự kiến cơ sở nhận', released, accent),
              amount('Còn giữ cho khách', held, ink),
            ],
          ),
        ],
      ),
    );
  }
}
