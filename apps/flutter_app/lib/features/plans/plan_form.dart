import 'package:flutter/material.dart';

import '../../app/prepaid_guard_theme.dart';
import '../../shared/widgets/brand_mark.dart';
import 'demo_plan.dart';

class PlanForm extends StatefulWidget {
  const PlanForm({super.key, required this.onCreate});

  final ValueChanged<DemoPlan> onCreate;

  @override
  State<PlanForm> createState() => _PlanFormState();
}

class _PlanFormState extends State<PlanForm> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _price = TextEditingController();
  final _periods = TextEditingController(text: '3');
  final _duration = TextEditingController(text: '30');

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _price.dispose();
    _periods.dispose();
    _duration.dispose();
    super.dispose();
  }

  void _create() {
    if (!_formKey.currentState!.validate()) return;

    widget.onCreate(
      DemoPlan(
        title: _title.text.trim(),
        description: _description.text.trim(),
        pricePerPeriod: parseTokenAmount(_price.text)!,
        periods: parseWholeNumber(_periods.text, max: 120)!,
        daysPerPeriod: parseWholeNumber(_duration.text, max: 3650)!,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final price = parseTokenAmount(_price.text);
    final periods = parseWholeNumber(_periods.text, max: 120);
    final duration = parseWholeNumber(_duration.text, max: 3650);
    final total = price == null || periods == null
        ? '—'
        : '${formatTokenAmount(price * BigInt.from(periods))} USDC thử nghiệm';

    return Form(
      key: _formKey,
      onChanged: () => setState(() {}),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final fields = _buildFields(context);
          final summary = _buildSummary(context, total, periods, duration);
          if (constraints.maxWidth >= 740) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 5, child: fields),
                const SizedBox(width: 20),
                Expanded(flex: 3, child: summary),
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [fields, const SizedBox(height: 16), summary],
          );
        },
      ),
    );
  }

  Widget _buildFields(BuildContext context) {
    final periods = TextFormField(
      controller: _periods,
      keyboardType: TextInputType.number,
      decoration: const InputDecoration(labelText: 'Số kỳ'),
      validator: (value) => parseWholeNumber(value ?? '', max: 120) == null
          ? 'Nhập từ 1 đến 120.'
          : null,
    );
    final duration = TextFormField(
      controller: _duration,
      keyboardType: TextInputType.number,
      decoration: const InputDecoration(labelText: 'Số ngày mỗi kỳ'),
      validator: (value) => parseWholeNumber(value ?? '', max: 3650) == null
          ? 'Nhập từ 1 đến 3650.'
          : null,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Thông tin gói',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _title,
              maxLength: 120,
              decoration: const InputDecoration(
                labelText: 'Tên gói',
                hintText: 'Ví dụ: Gym 3 tháng',
                counterText: '',
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Nhập tên gói.'
                  : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _description,
              maxLength: 2000,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Mô tả (tùy chọn)',
                counterText: '',
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _price,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Giá mỗi kỳ (USDC)'),
              validator: (value) => parseTokenAmount(value ?? '') == null
                  ? 'Nhập giá lớn hơn 0, tối đa 6 chữ số thập phân.'
                  : null,
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) => constraints.maxWidth >= 340
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: periods),
                        const SizedBox(width: 12),
                        Expanded(child: duration),
                      ],
                    )
                  : Column(
                      children: [periods, const SizedBox(height: 16), duration],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummary(
    BuildContext context,
    String total,
    int? periods,
    int? duration,
  ) {
    final theme = Theme.of(context);
    return Card(
      color: panelRaised,
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: AccentIcon(Icons.account_balance_wallet_outlined),
            ),
            const SizedBox(height: 16),
            Text('Tổng tiền gốc', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              total,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: accent,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (periods != null && duration != null) ...[
              const SizedBox(height: 8),
              Text(
                '$periods kỳ · $duration ngày mỗi kỳ',
                style: const TextStyle(color: mutedText),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _create,
              icon: const Icon(Icons.add),
              label: const Text('Tạo gói demo'),
            ),
          ],
        ),
      ),
    );
  }
}
