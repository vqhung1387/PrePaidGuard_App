import 'package:flutter/material.dart';

import '../../app/prepaid_guard_theme.dart';
import '../plans/demo_plan.dart';
import 'demo_membership.dart';

class MembershipActivity extends StatelessWidget {
  const MembershipActivity({super.key, required this.membership});

  final DemoMembership membership;

  @override
  Widget build(BuildContext context) {
    final plan = membership.plan;
    final status = membership.status;
    final type = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Hoạt động gần đây', style: type.titleLarge),
            const SizedBox(height: 8),
            if (membership.earnedBonusDays > 0) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.card_giftcard_outlined,
                  color: accent,
                ),
                title: Text(
                  'Hội viên nhận ${membership.earnedBonusDays} ngày tập thêm',
                ),
                subtitle: Text('Ưu đãi gói ${plan.periods} tháng'),
              ),
              const Divider(height: 1),
            ],
            if (status == DemoCheckInStatus.confirmed) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.check_circle_outline, color: accent),
                title: const Text('Cơ sở xác nhận kỳ đầu'),
                subtitle: Text(
                  'Đã giải ngân ${formatTokenAmount(membership.released)} USDC mô phỏng',
                ),
              ),
              const Divider(height: 1),
            ],
            if (status != DemoCheckInStatus.ready) ...[
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.how_to_reg_outlined, color: mutedText),
                title: Text('Hội viên gửi check-in'),
                subtitle: Text('Kỳ 1'),
              ),
              const Divider(height: 1),
            ],
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.receipt_long_outlined,
                color: mutedText,
              ),
              title: const Text('Hội viên đăng ký gói'),
              subtitle: Text(
                'Tiền gốc ban đầu: ${formatTokenAmount(plan.total)} USDC mô phỏng',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
