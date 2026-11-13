import 'package:flutter/material.dart';

import '../../app/prepaid_guard_theme.dart';
import '../../shared/widgets/brand_mark.dart';
import 'demo_plan.dart';
import 'monthly_offer_card.dart';

class PlanCatalog extends StatelessWidget {
  const PlanCatalog({
    super.key,
    required this.plans,
    required this.subscribedPlans,
    required this.onSubscribe,
  });

  final List<DemoPlan> plans;
  final Set<DemoPlan> subscribedPlans;
  final ValueChanged<DemoPlan> onSubscribe;

  Future<void> _confirmSubscription(BuildContext context, DemoPlan plan) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text('Đăng ký ${plan.title}?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (plan.monthlyListPrice != null) ...[
              Text(
                '${plan.periods} tháng × ${formatTokenAmount(plan.pricePerPeriod)} USDC',
              ),
              if (plan.discountPercent > 0)
                Text(
                  'Tiết kiệm ${formatTokenAmount(plan.savings)} USDC so với mua từng tháng.',
                ),
              if (plan.bonusDaysAfterCheckIn > 0) ...[
                const SizedBox(height: 8),
                Text(
                  'Tặng ${plan.bonusDaysAfterCheckIn} ngày tập sau khi cơ sở xác nhận check-in kỳ đầu.',
                ),
              ],
              const SizedBox(height: 12),
            ],
            Text(
              'Tổng tiền gốc mô phỏng: ${formatTokenAmount(plan.total)} USDC',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text('Thao tác này chỉ đăng ký trong bản demo.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Quay lại'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xác nhận demo'),
          ),
        ],
      ),
    );
    if (context.mounted && confirmed == true) onSubscribe(plan);
  }

  @override
  Widget build(BuildContext context) {
    if (plans.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Row(
            children: [
              AccentIcon(Icons.inventory_2_outlined),
              SizedBox(width: 16),
              Expanded(child: Text('Chưa có gói. Tạo gói trong mục Cơ sở.')),
            ],
          ),
        ),
      );
    }

    final monthly = plans.where((plan) => plan.monthlyListPrice != null);
    final standard = monthly.where((plan) => plan.bonusDaysAfterCheckIn == 0);
    final bonusOffers = monthly.where((plan) => plan.bonusDaysAfterCheckIn > 0);
    final custom = plans.where((plan) => plan.monthlyListPrice == null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (monthly.isNotEmpty) ...[
          const Text(
            'Giá bằng USDC thử nghiệm. Mức tiết kiệm so với mua từng tháng, mỗi tháng tính 30 ngày trong demo.',
            style: TextStyle(color: mutedText),
          ),
          const SizedBox(height: 16),
          if (standard.isNotEmpty)
            _buildGrid([
              for (final plan in standard) _monthlyCard(context, plan),
            ], allowThreeColumns: true),
          if (bonusOffers.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(
              'Gói dài hạn có ngày tập tặng',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            _buildGrid([
              for (final plan in bonusOffers) _monthlyCard(context, plan),
            ]),
            const SizedBox(height: 12),
            const _PromotionPolicy(),
          ],
        ],
        if (custom.isNotEmpty) ...[
          if (monthly.isNotEmpty) const SizedBox(height: 24),
          Text(
            'Gói do cơ sở tạo',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 14),
          _buildGrid([for (final plan in custom) _planCard(context, plan)]),
        ],
      ],
    );
  }

  Widget _monthlyCard(BuildContext context, DemoPlan plan) {
    return MonthlyOfferCard(
      plan: plan,
      subscribed: subscribedPlans.contains(plan),
      onSubscribe: () => _confirmSubscription(context, plan),
    );
  }

  Widget _buildGrid(List<Widget> cards, {bool allowThreeColumns = false}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = switch (constraints.maxWidth) {
          >= 760 when allowThreeColumns => 3,
          >= 520 => 2,
          _ => 1,
        };
        final width = (constraints.maxWidth - 16 * (columns - 1)) / columns;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            for (final card in cards) SizedBox(width: width, child: card),
          ],
        );
      },
    );
  }

  Widget _planCard(BuildContext context, DemoPlan plan) {
    final subscribed = subscribedPlans.contains(plan);
    final type = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: AccentIcon(Icons.storefront_outlined),
            ),
            const SizedBox(height: 16),
            Text(plan.title, style: type.titleLarge),
            if (plan.description.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(plan.description, style: const TextStyle(color: mutedText)),
            ],
            const SizedBox(height: 18),
            Text(
              'Tổng tiền gốc',
              style: type.labelLarge?.copyWith(color: mutedText),
            ),
            Text(
              '${formatTokenAmount(plan.total)} USDC',
              style: type.headlineSmall?.copyWith(
                color: accent,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text('${formatTokenAmount(plan.pricePerPeriod)} USDC mỗi kỳ'),
            Text(
              '${plan.periods} kỳ · ${plan.daysPerPeriod} ngày mỗi kỳ',
              style: const TextStyle(color: mutedText),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: subscribed
                  ? null
                  : () => _confirmSubscription(context, plan),
              icon: Icon(subscribed ? Icons.check : Icons.arrow_forward),
              label: Text(subscribed ? 'Đã đăng ký' : 'Đăng ký demo'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PromotionPolicy extends StatelessWidget {
  const _PromotionPolicy();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: ExpansionTile(
        key: PageStorageKey('promotion-policy'),
        leading: Icon(Icons.card_giftcard_outlined, color: accent),
        title: Text('Điều kiện áp dụng ưu đãi'),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        childrenPadding: EdgeInsets.fromLTRB(20, 0, 20, 18),
        children: [
          Text(
            'Giảm giá theo thời hạn được áp dụng tự động và hiển thị trước khi xác nhận.',
          ),
          SizedBox(height: 8),
          Text(
            'Gói đủ điều kiện được cộng ngày tập một lần, sau khi cơ sở xác nhận check-in kỳ đầu.',
          ),
          SizedBox(height: 8),
          Text(
            'Ngày tặng cộng vào thời hạn tập. Tiền gốc giải ngân theo số kỳ đã mua.',
          ),
        ],
      ),
    );
  }
}
