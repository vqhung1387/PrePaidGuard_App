import 'package:flutter/material.dart';

import '../../app/prepaid_guard_theme.dart';
import '../../shared/widgets/brand_mark.dart';
import 'auth_hero.dart';
import 'demo_accounts.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    required this.accounts,
    required this.onSignedIn,
  });

  final DemoAccounts accounts;
  final ValueChanged<String> onSignedIn;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  static final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _registering = false;
  bool _hidePassword = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  void _switchMode() {
    final email = _email.text;
    _formKey.currentState?.reset();
    _email.text = email;
    _password.clear();
    _confirmation.clear();
    setState(() {
      _registering = !_registering;
      _hidePassword = true;
      _error = null;
    });
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final email = _email.text.trim().toLowerCase();
    final error = _registering
        ? widget.accounts.register(email, _password.text)
        : widget.accounts.signIn(email, _password.text);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    widget.onSignedIn(email);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            final form = _buildForm(context);
            return Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: wide ? 32 : 18,
                  vertical: 24,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: wide ? 1120 : 456),
                  child: wide
                      ? Row(
                          children: [
                            const Expanded(child: AuthHero()),
                            const SizedBox(width: 24),
                            SizedBox(width: 410, child: form),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const AuthHero(compact: true),
                            const SizedBox(height: 14),
                            form,
                          ],
                        ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final theme = Theme.of(context);
    final title = _registering ? 'Tạo tài khoản' : 'Đăng nhập';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          onChanged: () {
            if (_error != null) setState(() => _error = null);
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const BrandMark(),
              const SizedBox(height: 20),
              Text(title, style: theme.textTheme.headlineMedium),
              const SizedBox(height: 8),
              const Text(
                'Bản demo. Hãy dùng email và mật khẩu giả.',
                style: TextStyle(color: mutedText),
              ),
              const SizedBox(height: 24),
              TextFormField(
                key: const ValueKey('auth-email'),
                controller: _email,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.mail_outline),
                ),
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                textInputAction: TextInputAction.next,
                validator: (value) =>
                    _emailPattern.hasMatch(value?.trim() ?? '')
                    ? null
                    : 'Nhập email đúng định dạng.',
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('auth-password'),
                controller: _password,
                obscureText: _hidePassword,
                enableSuggestions: false,
                autocorrect: false,
                textInputAction: _registering
                    ? TextInputAction.next
                    : TextInputAction.done,
                onFieldSubmitted: _registering ? null : (_) => _submit(),
                decoration: InputDecoration(
                  labelText: 'Mật khẩu',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    tooltip: _hidePassword ? 'Hiện mật khẩu' : 'Ẩn mật khẩu',
                    onPressed: () =>
                        setState(() => _hidePassword = !_hidePassword),
                    icon: Icon(
                      _hidePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                validator: (value) => (value?.length ?? 0) >= 8
                    ? null
                    : 'Nhập mật khẩu ít nhất 8 ký tự.',
              ),
              if (_registering) ...[
                const SizedBox(height: 16),
                TextFormField(
                  key: const ValueKey('auth-confirmation'),
                  controller: _confirmation,
                  obscureText: _hidePassword,
                  enableSuggestions: false,
                  autocorrect: false,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(
                    labelText: 'Xác nhận mật khẩu',
                  ),
                  validator: (value) => value == _password.text
                      ? null
                      : 'Hai mật khẩu chưa khớp.',
                ),
              ],
              if (_error case final error?) ...[
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    error,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton(onPressed: _submit, child: Text(title)),
              TextButton(
                onPressed: _switchMode,
                child: Text(
                  _registering
                      ? 'Đã có tài khoản? Đăng nhập'
                      : 'Chưa có tài khoản? Đăng ký',
                ),
              ),
              if (!_registering) ...[
                const Divider(height: 24),
                const SelectableText(
                  'Tài khoản thử: ${DemoAccounts.exampleEmail}\nMật khẩu: ${DemoAccounts.examplePassword}',
                  style: TextStyle(color: mutedText, height: 1.5),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
