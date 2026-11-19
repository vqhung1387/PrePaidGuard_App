import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../real/screen.dart';
import 'prepaid_guard_theme.dart';

class PrepaidGuardApp extends StatelessWidget {
  const PrepaidGuardApp({
    super.key,
    this.initialUri,
    this.apiBaseUrl = const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'https://prepaidguard-api.onrender.com',
    ),
  });

  final Uri? initialUri;
  final String apiBaseUrl;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'PrepaidGuard Business',
    debugShowCheckedModeBanner: false,
    locale: const Locale('vi'),
    supportedLocales: const [Locale('vi')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: prepaidGuardTheme(),
    home: RealWorkspaceScreen(
      initialUri: initialUri,
      apiBaseUrl: apiBaseUrl,
      autoConnect: apiBaseUrl.isNotEmpty,
    ),
  );
}
