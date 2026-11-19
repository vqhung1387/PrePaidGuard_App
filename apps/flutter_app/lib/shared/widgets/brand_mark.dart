import 'package:flutter/material.dart';

import '../../app/prepaid_guard_theme.dart';

class BrandMark extends StatelessWidget {
  const BrandMark({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const AccentIcon(Icons.shield_outlined, size: 34),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            'PrepaidGuard',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
      ],
    );
  }
}

class AccentIcon extends StatelessWidget {
  const AccentIcon(this.icon, {super.key, this.size = 44});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xff173c50),
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: accent, size: size * .53),
    );
  }
}
