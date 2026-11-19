import 'package:flutter/material.dart';

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
    const ink = Color(0xff143f35);
    const lime = Color(0xffc7eaa6);
    Widget amount(String label, BigInt value, Color color) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Color(0xffd7e6de))),
        Text(
          '${formatTokenAmount(value)} mUSDC',
          style: theme.titleLarge?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ink,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Dòng tiền theo kỳ',
              style: theme.titleLarge?.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 4),
            const Text(
              'Ước tính khi các kỳ đã chọn đều được xác nhận sử dụng.',
              style: TextStyle(color: Color(0xffd7e6de)),
            ),
            const SizedBox(height: 14),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                IconButton.outlined(
                  tooltip: 'Kỳ trước',
                  onPressed: current == 0
                      ? null
                      : () => setState(() => _period = current - 1),
                  style: IconButton.styleFrom(
                    foregroundColor: Colors.white,
                    disabledForegroundColor: Colors.white38,
                  ),
                  icon: const Icon(Icons.remove),
                ),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    'Kỳ $current/${widget.periods}',
                    style: theme.titleMedium?.copyWith(color: Colors.white),
                  ),
                ),
                IconButton.outlined(
                  tooltip: 'Kỳ tiếp theo',
                  onPressed: current == widget.periods
                      ? null
                      : () => setState(() => _period = current + 1),
                  style: IconButton.styleFrom(
                    foregroundColor: Colors.white,
                    disabledForegroundColor: Colors.white38,
                  ),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: 14),
            LinearProgressIndicator(
              value: current / widget.periods,
              color: lime,
              backgroundColor: const Color(0xff698c7e),
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
              semanticsLabel: 'Tỷ lệ tiền đã chuyển theo ước tính',
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 24,
              runSpacing: 10,
              children: [
                amount('Cơ sở đã nhận', released, lime),
                amount('Còn giữ cho khách', held, Colors.white),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
