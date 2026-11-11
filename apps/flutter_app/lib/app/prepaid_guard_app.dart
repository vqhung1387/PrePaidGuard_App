import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../features/auth/auth_screen.dart';
import '../features/auth/demo_accounts.dart';
import '../features/community/invite_link.dart';
import 'demo_workspace.dart';
import 'prepaid_guard_theme.dart';
import 'workspace_home.dart';

class PrepaidGuardApp extends StatefulWidget {
  const PrepaidGuardApp({super.key});

  @override
  State<PrepaidGuardApp> createState() => _PrepaidGuardAppState();
}

class _PrepaidGuardAppState extends State<PrepaidGuardApp> {
  final _accounts = DemoAccounts();
  final _workspace = DemoWorkspace();
  final _fromInvite = isDemoInvite(Uri.base);
  String? _email;

  @override
  Widget build(BuildContext context) {
    final email = _email;
    return MaterialApp(
      title: 'PrepaidGuard',
      debugShowCheckedModeBanner: false,
      locale: const Locale('vi'),
      supportedLocales: const [Locale('vi')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: prepaidGuardTheme(),
      home: email == null
          ? AuthScreen(
              accounts: _accounts,
              onSignedIn: (email) => setState(() => _email = email),
            )
          : WorkspaceHome(
              key: ValueKey(email),
              workspace: _workspace,
              email: email,
              fromInvite: _fromInvite,
              onSignOut: () => setState(() => _email = null),
            ),
    );
  }
}
