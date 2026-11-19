import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:prepaid_guard/app/demo_workspace.dart';
import 'package:prepaid_guard/app/prepaid_guard_theme.dart';
import 'package:prepaid_guard/app/workspace_home.dart';
import 'package:prepaid_guard/features/auth/auth_screen.dart';
import 'package:prepaid_guard/features/auth/demo_accounts.dart';

class DemoTestApp extends StatefulWidget {
  const DemoTestApp({super.key});

  @override
  State<DemoTestApp> createState() => _DemoTestAppState();
}

class _DemoTestAppState extends State<DemoTestApp> {
  final _accounts = DemoAccounts();
  final _workspace = DemoWorkspace();
  String? _email;

  @override
  Widget build(BuildContext context) {
    final email = _email;
    return MaterialApp(
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
              fromInvite: false,
              onSignOut: () => setState(() => _email = null),
              onReal: () {},
            ),
    );
  }
}
