import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/prepaid_guard_theme.dart';

const demoInviteCode = 'gym-khoi-dong';

bool isDemoInvite(Uri uri) => uri.queryParameters['invite'] == demoInviteCode;

Uri demoInviteLink(Uri page) =>
    page.removeFragment().replace(queryParameters: {'invite': demoInviteCode});

Future<void> showDemoInvite(BuildContext context) {
  final link = demoInviteLink(Uri.base).toString();
  return Navigator.of(
    context,
  ).push<void>(MaterialPageRoute(builder: (_) => _ReferralPage(link: link)));
}

class _ReferralPage extends StatelessWidget {
  const _ReferralPage({required this.link});

  final String link;

  Future<void> _copy(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await Clipboard.setData(ClipboardData(text: link));
      if (!context.mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Đã sao chép liên kết gói mẫu.')),
      );
    } on PlatformException {
      if (!context.mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Hãy chọn và sao chép liên kết bên trên.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final type = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Giới thiệu bạn tập')),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 780),
            child: ListView(
              padding: const EdgeInsets.all(18),
              children: [
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Image.asset(
                          'assets/gym-referral.jpg',
                          fit: BoxFit.cover,
                          alignment: const Alignment(1, -.8),
                          excludeFromSemantics: true,
                        ),
                      ),
                      const Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomLeft,
                              end: Alignment.topRight,
                              colors: [
                                canvas,
                                Color(0xaa080f1c),
                                Color(0x18080f1c),
                              ],
                            ),
                          ),
                        ),
                      ),
                      ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 260),
                        child: Align(
                          alignment: Alignment.bottomLeft,
                          child: Padding(
                            padding: const EdgeInsets.all(22),
                            child: Text(
                              'Rủ bạn cùng tập',
                              style: type.headlineLarge,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Chia sẻ gói Gym Khởi Động',
                          style: type.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Bạn bè mở liên kết và đăng nhập để xem gói tập mẫu.',
                          style: TextStyle(color: mutedText),
                        ),
                        const SizedBox(height: 18),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: canvas,
                            border: Border.all(color: panelOutline),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: SelectableText(link),
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: () => _copy(context),
                          icon: const Icon(Icons.copy_outlined),
                          label: const Text('Sao chép liên kết'),
                        ),
                        if (Uri.base.host == 'localhost' ||
                            Uri.base.host == '127.0.0.1') ...[
                          const SizedBox(height: 12),
                          const Text(
                            'Liên kết localhost chỉ mở trên máy đang chạy bản demo.',
                            style: TextStyle(color: mutedText),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
