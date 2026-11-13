import 'package:flutter/material.dart';

import '../features/community/community_page.dart';
import '../features/merchant/merchant_check_ins.dart';
import '../features/overview/overview_page.dart';
import '../features/plans/demo_plan.dart';
import '../features/plans/plan_catalog.dart';
import '../features/plans/plan_form.dart';
import '../features/subscriptions/demo_membership.dart';
import '../features/subscriptions/membership_card.dart';
import '../shared/widgets/brand_mark.dart';
import 'demo_workspace.dart';
import 'prepaid_guard_theme.dart';

enum _Mode { member, merchant }

enum _Section {
  overview(Icons.dashboard_outlined, 'Tổng quan'),
  plans(Icons.view_list_outlined, 'Gói dịch vụ', 'Gói'),
  memberships(Icons.badge_outlined, 'Hội viên'),
  community(Icons.groups_outlined, 'Bạn tập'),
  checkIns(Icons.fact_check_outlined, 'Check-in'),
  createPlan(Icons.add_business_outlined, 'Tạo gói');

  const _Section(this.icon, this.label, [this.shortLabel]);

  final IconData icon;
  final String label;
  final String? shortLabel;
}

const _memberSections = [
  _Section.overview,
  _Section.plans,
  _Section.memberships,
  _Section.community,
];
const _merchantSections = [_Section.checkIns, _Section.createPlan];

class WorkspaceHome extends StatefulWidget {
  const WorkspaceHome({
    super.key,
    required this.workspace,
    required this.email,
    required this.fromInvite,
    required this.onSignOut,
  });

  final DemoWorkspace workspace;
  final String email;
  final bool fromInvite;
  final VoidCallback onSignOut;

  @override
  State<WorkspaceHome> createState() => _WorkspaceHomeState();
}

class _WorkspaceHomeState extends State<WorkspaceHome> {
  _Mode _mode = _Mode.member;
  late _Section _memberSection = widget.fromInvite
      ? _Section.plans
      : _Section.overview;
  _Section _merchantSection = _Section.checkIns;
  DemoMembership? _selectedMembership;

  void _navigate(_Section section) {
    setState(() {
      if (_mode == _Mode.member) {
        _memberSection = section;
      } else {
        _merchantSection = section;
      }
    });
  }

  void _switchMode(_Mode mode) {
    if (_mode == mode) return;
    setState(() {
      _mode = mode;
      if (mode == _Mode.merchant) _merchantSection = _Section.checkIns;
    });
  }

  void _addPlan(DemoPlan plan) {
    widget.workspace.createPlan(widget.email, plan);
    _navigate(_Section.checkIns);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Đã tạo gói ${plan.title}.'),
        action: SnackBarAction(
          label: 'Xem gói',
          onPressed: () => setState(() {
            _mode = _Mode.member;
            _memberSection = _Section.plans;
          }),
        ),
      ),
    );
  }

  void _subscribe(DemoPlan plan) {
    widget.workspace.subscribe(widget.email, plan);
    _selectedMembership = widget.workspace.memberships(widget.email)[plan];
    _navigate(_Section.overview);
  }

  void _requestCheckIn(DemoMembership membership) {
    if (!membership.requestCheckIn()) return;
    setState(() => _selectedMembership = membership);
  }

  void _confirmCheckIn(DemoMembership membership) {
    if (!widget.workspace.confirmCheckIn(widget.email, membership)) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Đã cập nhật giải ngân mô phỏng.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 960;
    final memberMode = _mode == _Mode.member;
    final section = memberMode ? _memberSection : _merchantSection;
    final destinations = memberMode ? _memberSections : _merchantSections;
    final memberships = widget.workspace.memberships(widget.email);
    final (title, description) = switch (section) {
      _Section.overview => ('Tổng quan', ''),
      _Section.plans => (
        'Đăng ký gói tập',
        widget.fromInvite
            ? 'Bạn được mời thử gói Gym Khởi Động.'
            : 'Chọn gói theo tháng và xem tổng tiền trước khi xác nhận.',
      ),
      _Section.memberships => (
        'Thẻ hội viên',
        'Check-in và xem lịch sử giải ngân theo kỳ.',
      ),
      _Section.community => (
        'Kết nối bạn tập',
        'Chọn mục tiêu để tìm hồ sơ mẫu có lịch tập phù hợp.',
      ),
      _Section.checkIns => (
        'Check-in của cơ sở',
        'Xem yêu cầu của hội viên và số tiền dự kiến giải ngân.',
      ),
      _Section.createPlan => (
        'Tạo gói dịch vụ',
        'Đặt giá và thời hạn để hội viên xem trước khi đăng ký.',
      ),
    };

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 68,
        title: const BrandMark(),
        actions: [
          PopupMenuButton<_Mode>(
            tooltip: 'Chuyển chế độ',
            initialValue: _mode,
            onSelected: _switchMode,
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _Mode.member,
                child: Text('Chế độ Hội viên'),
              ),
              PopupMenuItem(value: _Mode.merchant, child: Text('Chế độ Cơ sở')),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    memberMode ? 'Hội viên demo' : 'Cơ sở demo',
                    style: const TextStyle(color: accent, fontSize: 12),
                  ),
                  const Icon(Icons.expand_more, color: accent, size: 18),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: 'Đăng xuất',
            onPressed: widget.onSignOut,
            icon: const Icon(Icons.logout_outlined),
          ),
          const SizedBox(width: 12),
        ],
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: destinations.indexOf(section),
              onDestinationSelected: (index) => _navigate(destinations[index]),
              destinations: [
                for (final item in destinations)
                  NavigationDestination(
                    icon: Icon(item.icon),
                    selectedIcon: Icon(item.icon, color: accent),
                    label: item.shortLabel ?? item.label,
                  ),
              ],
            ),
      body: SafeArea(
        child: Row(
          children: [
            if (wide) ...[
              NavigationRail(
                extended: true,
                minExtendedWidth: 176,
                useIndicator: true,
                selectedIndex: destinations.indexOf(section),
                onDestinationSelected: (index) =>
                    _navigate(destinations[index]),
                destinations: [
                  for (final item in destinations)
                    NavigationRailDestination(
                      icon: Icon(item.icon),
                      label: Text(item.label),
                    ),
                ],
              ),
              const VerticalDivider(width: 1, color: panelOutline),
            ],
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1120),
                  child: ListView(
                    key: PageStorageKey(section),
                    padding: EdgeInsets.fromLTRB(
                      wide ? 32 : 18,
                      24,
                      wide ? 32 : 18,
                      32,
                    ),
                    children: [
                      if (section != _Section.overview) ...[
                        Text(
                          title,
                          style: Theme.of(context).textTheme.headlineLarge,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          description,
                          style: const TextStyle(color: mutedText),
                        ),
                        const SizedBox(height: 22),
                      ],
                      switch (section) {
                        _Section.overview => OverviewPage(
                          memberships: memberships.values.toList(),
                          selectedMembership:
                              _selectedMembership ??
                              memberships.values.firstOrNull,
                          onSelectMembership: (membership) =>
                              setState(() => _selectedMembership = membership),
                          onRequestCheckIn: _requestCheckIn,
                          onViewPlans: () => _navigate(_Section.plans),
                          onCommunity: () => _navigate(_Section.community),
                        ),
                        _Section.plans => PlanCatalog(
                          plans: widget.workspace.plans,
                          subscribedPlans: memberships.keys.toSet(),
                          onSubscribe: _subscribe,
                        ),
                        _Section.memberships => _buildMemberships(
                          memberships.values,
                        ),
                        _Section.community => CommunityPage(
                          requests: widget.workspace.connections(widget.email),
                        ),
                        _Section.checkIns => MerchantCheckIns(
                          pending: widget.workspace
                              .pendingCheckIns(widget.email)
                              .toList(),
                          onConfirm: _confirmCheckIn,
                        ),
                        _Section.createPlan => PlanForm(onCreate: _addPlan),
                      },
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemberships(Iterable<DemoMembership> memberships) {
    if (memberships.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Chưa có thẻ hội viên. Hãy đăng ký một gói.'),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => _navigate(_Section.plans),
                child: const Text('Xem gói dịch vụ'),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        for (final membership in memberships)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: MembershipCard(
              membership: membership,
              onRequestCheckIn: () => _requestCheckIn(membership),
            ),
          ),
      ],
    );
  }
}
