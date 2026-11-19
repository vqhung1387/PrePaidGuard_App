import 'package:flutter/material.dart';

import '../../app/prepaid_guard_theme.dart';

class AuthHero extends StatelessWidget {
  const AuthHero({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: compact ? 144 : 506),
        child: Stack(
          alignment: Alignment.bottomLeft,
          children: [
            Positioned.fill(
              child: Image.asset(
                'assets/gym-hero.jpg',
                fit: BoxFit.cover,
                alignment: compact
                    ? const Alignment(0, -.25)
                    : Alignment.centerRight,
                excludeFromSemantics: true,
              ),
            ),
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x08080f1c), Color(0xf2080f1c)],
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(compact ? 18 : 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Quản lý gói trả trước',
                    style: compact
                        ? Theme.of(context).textTheme.titleLarge
                        : Theme.of(context).textTheme.headlineLarge,
                  ),
                  if (!compact) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Tạo gói, đăng ký và theo dõi tiền gốc theo từng kỳ.',
                      style: TextStyle(color: mutedText, height: 1.5),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
