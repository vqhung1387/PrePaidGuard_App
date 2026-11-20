import 'package:flutter/material.dart';

import '../../app/prepaid_guard_theme.dart';
import '../../shared/widgets/brand_mark.dart';
import 'demo_plan.dart';
import 'monthly_offer_card.dart';
import 'plan_comparison.dart';

enum _PlanFilter {
  all('Tất cả', Icons.grid_view_outlined),
  short('1–6 tháng', Icons.calendar_today_outlined),
  long('12–24 tháng', Icons.card_giftcard_outlined),
  custom('Gói cơ sở', Icons.storefront_outlined);

  const _PlanFilter(this.label, this.icon);

  final String label;
  final IconData icon;
}

enum _PlanSort {
  original('Mặc định'),
  total('Trả trước thấp nhất'),
  duration('Thời hạn ngắn nhất');

  const _PlanSort(this.label);
  final String label;
}

String _searchText(String text) {
  const vietnamese = {
    'a': 'àáảãạăằắẳẵặâầấẩẫậ',
    'e': 'èéẻẽẹêềếểễệ',
    'i': 'ìíỉĩị',
    'o': 'òóỏõọôồốổỗộơờớởỡợ',
    'u': 'ùúủũụưừứửữự',
    'y': 'ỳýỷỹỵ',
    'd': 'đ',
  };
  var normalized = text.toLowerCase().trim();
  for (final entry in vietnamese.entries) {
    normalized = normalized.replaceAll(RegExp('[${entry.value}]'), entry.key);
  }
  return normalized;
}

class PlanCatalog extends StatefulWidget {
  const PlanCatalog({
    super.key,
    required this.plans,
    required this.subscribedPlans,
    required this.onSubscribe,
  });

  final List<DemoPlan> plans;
  final Set<DemoPlan> subscribedPlans;
  final ValueChanged<DemoPlan> onSubscribe;

  @override
  State<PlanCatalog> createState() => _PlanCatalogState();
}

class _PlanCatalogState extends State<PlanCatalog> {
  _PlanFilter _filter = _PlanFilter.all;
  _PlanSort _sort = _PlanSort.original;
  ServiceCategory? _category;
  DemoPlan? _selectedPlan;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _selectPlan(DemoPlan plan) {
    if (_selectedPlan != plan) setState(() => _selectedPlan = plan);
  }

  void _resetFilters() {
    setState(() {
      _search.clear();
      _category = null;
      _filter = _PlanFilter.all;
    });
  }

  Future<void> _confirmSubscription(BuildContext context, DemoPlan plan) async {
    if (widget.subscribedPlans.contains(plan)) return;
    _selectPlan(plan);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text('Đăng ký ${plan.title}?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(plan.serviceLabel),
            const SizedBox(height: 8),
            if (plan.monthlyListPrice != null) ...[
              Text(
                '${plan.periods} tháng × ${formatTokenAmount(plan.pricePerPeriod)} $creditUnit',
              ),
              if (plan.discountPercent > 0)
                Text(
                  'Tiết kiệm ${formatTokenAmount(plan.savings)} $creditUnit so với mua từng tháng.',
                ),
              if (plan.bonusDaysAfterCheckIn > 0) ...[
                const SizedBox(height: 8),
                Text(
                  'Tặng ${plan.bonusDaysAfterCheckIn} ngày tập sau khi cơ sở xác nhận check-in kỳ đầu.',
                ),
              ],
              const SizedBox(height: 12),
            ],
            Card(
              color: panelRaised,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  'Tổng tiền gốc mô phỏng: ${formatTokenAmount(plan.total)} $creditUnit',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${plan.accessDays} ngày dịch vụ · ${plan.periods} kỳ, mỗi kỳ ${plan.daysPerPeriod} ngày',
            ),
            const Divider(height: 24),
            const Text('Trả trước một lần khi đăng ký'),
            Text(
              'Giải ngân cho cơ sở: ${formatTokenAmount(plan.pricePerPeriod)} $creditUnit mỗi kỳ đủ điều kiện.',
            ),
            const SizedBox(height: 8),
            const Text(
              'Bản demo dùng số dư mô phỏng. Trên mạng thử nghiệm, giải ngân và hoàn gốc tuân theo các mốc thời gian của gói.',
            ),
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
    if (context.mounted && confirmed == true) widget.onSubscribe(plan);
  }

  Future<void> _comparePlans(BuildContext context, List<DemoPlan> plans) async {
    final chosen = await showDialog<DemoPlan>(
      context: context,
      builder: (context) =>
          PlanComparison(plans: plans, subscribedPlans: widget.subscribedPlans),
    );
    if (context.mounted && chosen != null) {
      await _confirmSubscription(context, chosen);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.plans.isEmpty) {
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

    final scoped = widget.plans.where(
      (plan) => _category == null || plan.category == _category,
    );
    final categories = {for (final plan in widget.plans) plan.category};
    final scopedMonthly = scoped.where((plan) => plan.monthlyListPrice != null);
    final filters = [
      _PlanFilter.all,
      if (scopedMonthly.any((plan) => plan.periods < 12)) _PlanFilter.short,
      if (scopedMonthly.any((plan) => plan.periods >= 12)) _PlanFilter.long,
      if (scopedMonthly.isNotEmpty &&
          scoped.any((plan) => plan.monthlyListPrice == null))
        _PlanFilter.custom,
    ];
    final filter = filters.contains(_filter) ? _filter : _PlanFilter.all;
    final query = _searchText(_search.text);
    final matches = scoped.where(
      (plan) =>
          query.isEmpty ||
          _searchText('${plan.title} ${plan.serviceLabel}').contains(query),
    );
    final visible = matches
        .where(
          (plan) => switch (filter) {
            _PlanFilter.all => true,
            _PlanFilter.short =>
              plan.monthlyListPrice != null && plan.periods < 12,
            _PlanFilter.long =>
              plan.monthlyListPrice != null && plan.periods >= 12,
            _PlanFilter.custom => plan.monthlyListPrice == null,
          },
        )
        .toList();
    if (_sort != _PlanSort.original) {
      visible.sort((a, b) {
        final order = _sort == _PlanSort.total
            ? a.total.compareTo(b.total)
            : a.accessDays.compareTo(b.accessDays);
        return order == 0 ? a.title.compareTo(b.title) : order;
      });
    }
    final monthly = visible
        .where((plan) => plan.monthlyListPrice != null)
        .toList();
    final standard = monthly.where((plan) => plan.periods < 12);
    final longTerm = monthly.where((plan) => plan.periods >= 12);
    final custom = visible.where((plan) => plan.monthlyListPrice == null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const ValueKey('service-search'),
          controller: _search,
          textInputAction: TextInputAction.search,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Tìm tên gói hoặc nhà cung cấp',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Xóa tìm kiếm',
                    onPressed: () => setState(_search.clear),
                    icon: const Icon(Icons.close),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final option in [
              null,
              ...ServiceCategory.values.where(categories.contains),
            ])
              ChoiceChip(
                selected: _category == option,
                label: Text(option?.label ?? 'Mọi dịch vụ'),
                onSelected: (_) => setState(() {
                  _category = option;
                  _filter = _PlanFilter.all;
                }),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (filters.length > 1) ...[
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final option in filters)
                ChoiceChip(
                  avatar: Icon(option.icon, size: 17),
                  label: Text(option.label),
                  selected: filter == option,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _filter = option),
                ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        Wrap(
          spacing: 12,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Semantics(
              liveRegion: true,
              child: Text(
                '${visible.length} gói phù hợp',
                style: const TextStyle(color: mutedText),
              ),
            ),
            if (visible.length > 1)
              TextButton.icon(
                onPressed: () => _comparePlans(context, visible),
                icon: const Icon(Icons.compare_arrows_outlined),
                label: const Text('So sánh các gói'),
              ),
            if (visible.length > 1)
              PopupMenuButton<_PlanSort>(
                tooltip: 'Sắp xếp gói',
                initialValue: _sort,
                onSelected: (sort) => setState(() => _sort = sort),
                itemBuilder: (context) => [
                  for (final sort in _PlanSort.values)
                    PopupMenuItem(value: sort, child: Text(sort.label)),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 12,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.sort, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        _sort == _PlanSort.original ? 'Sắp xếp' : _sort.label,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (visible.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: AccentIcon(Icons.search_off_outlined),
                    title: Text('Không tìm thấy gói phù hợp'),
                    subtitle: Text(
                      'Đổi từ khóa hoặc bỏ bộ lọc để xem thêm gói.',
                    ),
                  ),
                  TextButton(
                    onPressed: _resetFilters,
                    child: const Text('Bỏ bộ lọc'),
                  ),
                ],
              ),
            ),
          ),
        if (_sort != _PlanSort.original && visible.isNotEmpty) ...[
          _buildGrid([
            for (final plan in visible)
              plan.monthlyListPrice == null
                  ? _planCard(context, plan)
                  : _monthlyCard(context, plan),
          ], allowThreeColumns: true),
          const SizedBox(height: 24),
        ],
        if (_sort == _PlanSort.original && standard.isNotEmpty) ...[
          _buildGrid([
            for (final plan in standard) _monthlyCard(context, plan),
          ], allowThreeColumns: true),
          const SizedBox(height: 24),
        ],
        if (_sort == _PlanSort.original && longTerm.isNotEmpty) ...[
          Text(
            'Gói dài hạn có ngày tập tặng',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          _buildGrid([
            for (final plan in longTerm) _monthlyCard(context, plan),
          ]),
          const SizedBox(height: 24),
        ],
        if (_sort == _PlanSort.original && custom.isNotEmpty) ...[
          Text(
            'Gói theo kỳ của nhà cung cấp',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 14),
          _buildGrid([for (final plan in custom) _planCard(context, plan)]),
          const SizedBox(height: 24),
        ],
        if (monthly.isNotEmpty) const _PromotionPolicy(),
      ],
    );
  }

  Widget _monthlyCard(BuildContext context, DemoPlan plan) {
    return MonthlyOfferCard(
      plan: plan,
      subscribed: widget.subscribedPlans.contains(plan),
      selected: _selectedPlan == plan,
      onSelect: () => _selectPlan(plan),
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
        final effectiveColumns = cards.length < columns
            ? cards.length
            : columns;
        final width =
            (constraints.maxWidth - 16 * (effectiveColumns - 1)) /
            effectiveColumns;
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
    final subscribed = widget.subscribedPlans.contains(plan);
    final selected = _selectedPlan == plan;
    final type = Theme.of(context).textTheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      color: selected ? panelRaised : panel,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: selected ? accent : panelOutline),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Semantics(
        selected: selected,
        child: InkWell(
          onTap: () => _selectPlan(plan),
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
                const SizedBox(height: 4),
                Text(plan.serviceLabel, style: const TextStyle(color: accent)),
                if (plan.description.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    plan.description,
                    style: const TextStyle(color: mutedText),
                  ),
                ],
                const SizedBox(height: 18),
                Text(
                  'Tổng trả trước (demo)',
                  style: type.labelLarge?.copyWith(color: mutedText),
                ),
                Text(
                  '${formatTokenAmount(plan.total)} $creditUnit',
                  style: type.headlineSmall?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Giải ngân ${formatTokenAmount(plan.pricePerPeriod)} $creditUnit mỗi kỳ đủ điều kiện',
                ),
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
            'Giảm giá áp dụng tự động. Mức tiết kiệm được tính bằng cách so với mua lẻ gói 1 tháng cùng số tháng.',
          ),
          SizedBox(height: 8),
          Text(
            'Gói đủ điều kiện được cộng ngày tập một lần, sau khi cơ sở xác nhận check-in kỳ đầu.',
          ),
          SizedBox(height: 8),
          Text(
            'Demo tính 30 ngày mỗi tháng. Ngày tặng cộng vào thời hạn tập. Tiền gốc giải ngân theo số kỳ đã mua.',
          ),
        ],
      ),
    );
  }
}
