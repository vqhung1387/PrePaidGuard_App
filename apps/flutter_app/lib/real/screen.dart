import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app/prepaid_guard_theme.dart';
import '../features/plans/demo_plan.dart';
import '../shared/widgets/brand_mark.dart';
import 'api.dart';
import 'controller.dart';
import 'subscription_details.dart';
import 'wallet.dart';

class RealWorkspaceScreen extends StatefulWidget {
  const RealWorkspaceScreen({
    super.key,
    required this.onDemo,
    this.controller,
    this.initialUri,
    this.apiBaseUrl,
    this.apiFactory,
    this.walletFactory,
    this.storeFactory,
  });

  final VoidCallback onDemo;
  final LiveController? controller;
  final Uri? initialUri;
  final String? apiBaseUrl;
  final ApiPort Function(String baseUrl)? apiFactory;
  final WalletPort Function()? walletFactory;
  final PendingStore Function()? storeFactory;

  @override
  State<RealWorkspaceScreen> createState() => _RealWorkspaceScreenState();
}

class _RealWorkspaceScreenState extends State<RealWorkspaceScreen> {
  static const _defaultPlanDraft = <String, String>{
    'Tên gói': 'Gym demo',
    'Mô tả': 'Gói thử nghiệm',
    'USDC mỗi kỳ': '50',
    'Số kỳ': '2',
    'Giây mỗi kỳ': '60',
    'Giây ân hạn': '120',
  };
  late final TextEditingController _apiUrl = TextEditingController(
    text: (widget.apiBaseUrl != null && widget.apiBaseUrl!.isNotEmpty)
        ? widget.apiBaseUrl!
        : const String.fromEnvironment(
            'API_BASE_URL',
            defaultValue: 'http://localhost:8000',
          ),
  );
  LiveController? _controller;
  Timer? _poll;
  bool _connecting = false;
  int _modalDepth = 0;
  String _merchantNameDraft = '';
  late Map<String, String> _planFormDraft = Map.of(_defaultPlanDraft);
  String _qrPayloadDraft = '';

  Uri get _entryUri => widget.initialUri ?? Uri.base;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller;
    _controller?.addListener(_changed);
    if (_controller == null &&
        _entryUri.queryParameters.containsKey('plan_id') &&
        _apiUrl.text.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _controller == null && !_connecting) {
          _connect();
        }
      });
    }
    _poll = Timer.periodic(const Duration(seconds: 8), (_) {
      final c = _controller;
      if (c != null &&
          !_connecting &&
          _modalDepth == 0 &&
          c.loggedIn &&
          !c.busy &&
          c.pending.any((item) => item['status'] == 'SUBMITTED')) {
        final submitted = c.pending
            .where((item) => item['status'] == 'SUBMITTED')
            .toList();
        _run(() async {
          await c.refreshPending();
          if (c.loggedIn &&
              submitted.any((item) => item['status'] != 'SUBMITTED')) {
            await c.refresh();
          }
        }, background: true);
      }
    });
  }

  void _changed() {
    if (!(_controller?.loggedIn ?? false)) {
      _merchantNameDraft = '';
      _planFormDraft = Map.of(_defaultPlanDraft);
      _qrPayloadDraft = '';
    }
    if (mounted) setState(() {});
  }

  Future<T> _withModal<T>(Future<T> Function() open) async {
    _modalDepth++;
    try {
      return await open();
    } finally {
      _modalDepth--;
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(content: Text(formatUserError(error))));
  }

  Future<void> _run(
    Future<void> Function() action, {
    bool background = false,
  }) async {
    try {
      final c = _controller;
      if (c == null) {
        await action();
      } else {
        await c.operation(action);
      }
      if (!background && mounted) {
        ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
      }
    } catch (error) {
      if (!background) _showError(error);
    }
  }

  Future<void> _connect() async {
    if (_connecting) return;
    setState(() => _connecting = true);
    try {
      final base = _apiUrl.text.trim();
      final api = widget.apiFactory?.call(base) ?? HttpApi(base);
      final c = LiveController(
        api: api,
        wallet: widget.walletFactory?.call() ?? createWallet(),
        store: widget.storeFactory?.call() ?? createPendingStore(),
      );
      final previous = _controller;
      if (previous?.loggedIn == true) {
        try {
          await previous!.logout();
        } catch (_) {
          /* Local state is still cleared by logout(); continue switching API. */
        }
      }
      if (!mounted) {
        c.dispose();
        return;
      }
      previous?.removeListener(_changed);
      previous?.dispose();
      _controller = c;
      c.addListener(_changed);
      await c.operation(() async {
        await c.bootstrap();
        await c.openRegistration(_entryUri);
      });
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
      }
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  String? _validateRequiredName(String? raw) {
    final trimmed = (raw ?? '').trim();
    if (trimmed.isEmpty) return 'Không được để trống trường này.';
    if (trimmed.length > 120) return 'Tên tối đa 120 ký tự.';
    return null;
  }

  Future<Map<String, String>?> _form(
    String title,
    Map<String, String> fields, {
    String? amountField,
    Map<String, String? Function(String?)> validators = const {},
    Widget Function(Map<String, TextEditingController>)? summaryBuilder,
  }) async {
    final formKey = GlobalKey<FormState>();
    final controllers = {
      for (final entry in fields.entries)
        entry.key: TextEditingController(text: entry.value),
    };
    final result = await _withModal(
      () => showDialog<Map<String, String>>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final entry in controllers.entries)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: TextFormField(
                          controller: entry.value,
                          decoration: InputDecoration(
                            labelText: entry.key,
                            helperText:
                                entry.key == amountField ? tokenAmountHint : null,
                            helperMaxLines: 2,
                            errorMaxLines: 3,
                          ),
                          validator: (value) {
                            if ((value ?? '').contains('\u0000')) {
                              return 'Không được chứa ký tự NUL.';
                            }
                            final custom = validators[entry.key];
                            if (custom != null) return custom(value);
                            if (entry.key == amountField) {
                              return validateTokenAmountInput(value);
                            }
                            return null;
                          },
                          minLines: entry.key == 'Mô tả'
                              ? 2
                              : (entry.key == 'QR payload' ||
                                        entry.key.startsWith('Raw giao dịch')
                                    ? 3
                                    : 1),
                          maxLines: entry.key == 'Mô tả'
                              ? 3
                              : (entry.key == 'QR payload' ||
                                        entry.key.startsWith('Raw giao dịch')
                                    ? 6
                                    : 1),
                        ),
                      ),
                    if (summaryBuilder != null) summaryBuilder(controllers),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () {
                if (!formKey.currentState!.validate()) return;
                Navigator.pop(context, {
                  for (final entry in controllers.entries)
                    entry.key: entry.value.text.trim(),
                });
              },
              child: const Text('Xác nhận'),
            ),
          ],
        ),
      ),
    );
    // Controllers are disposed after the dialog route completes its transition.
    Future<void>.delayed(const Duration(milliseconds: 300), () {
      for (final controller in controllers.values) {
        controller.dispose();
      }
    });
    return result;
  }

  Future<void> _createMerchant() async {
    final fields = await _form(
      'Tạo hồ sơ cơ sở',
      {'Tên cơ sở': _merchantNameDraft},
      validators: {'Tên cơ sở': _validateRequiredName},
    );
    if (fields == null) return;
    _merchantNameDraft = fields['Tên cơ sở']!;
    await _run(() async {
      await _controller!.createMerchant(_merchantNameDraft);
      _merchantNameDraft = '';
    });
  }

  Future<void> _createPlan() async {
    const amountField = 'USDC mỗi kỳ';
    const periodsField = 'Số kỳ';
    const durationField = 'Giây mỗi kỳ';
    const graceField = 'Giây ân hạn';
    final fields = await _form(
      'Tạo gói on-chain',
      _planFormDraft,
      amountField: amountField,
      validators: {
        'Tên gói': _validateRequiredName,
        'Mô tả': (value) => (value ?? '').length > 2000
            ? 'Mô tả tối đa 2000 ký tự.'
            : null,
        periodsField: (value) => parseWholeNumber(value ?? '', max: 120) == null
            ? 'Nhập số kỳ nguyên từ 1 đến 120.'
            : null,
        durationField: (value) =>
            parseWholeNumber(value ?? '', max: 315360000) == null
            ? 'Nhập số giây nguyên dương.'
            : null,
        graceField: (value) =>
            parseWholeNumber(value ?? '', max: 315360000) == null
            ? 'Nhập số giây nguyên dương.'
            : null,
      },
      summaryBuilder: (controllers) => ListenableBuilder(
        listenable: Listenable.merge([
          controllers[amountField]!,
          controllers[periodsField]!,
          controllers[durationField]!,
          controllers[graceField]!,
        ]),
        builder: (context, child) {
          final amount = parseTokenAmount(controllers[amountField]!.text);
          final periods = parseWholeNumber(
            controllers[periodsField]!.text,
            max: 120,
          );
          final duration = parseWholeNumber(
            controllers[durationField]!.text,
            max: 315360000,
          );
          final grace = parseWholeNumber(
            controllers[graceField]!.text,
            max: 315360000,
          );
          final unit = amount == null ? null : formatTokenAmount(amount);
          final total = amount != null && periods != null
              ? formatTokenAmount(amount * BigInt.from(periods))
              : null;
          return Container(
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: panelRaised,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: panelOutline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (total != null && unit != null)
                  Text(
                    'Tổng khóa trả trước: $total mUSDC ($unit mUSDC/kỳ × $periods kỳ)',
                    style: const TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                else if (unit != null)
                  Text('$unit mUSDC/kỳ', style: const TextStyle(color: accent)),
                if (duration != null && grace != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Mở check-in kỳ đầu sau $duration giây; mở hoàn gốc chưa dùng sau thêm $grace giây ân hạn.',
                  ),
                ],
                const SizedBox(height: 4),
                const Text(
                  'Sau khi publish on-chain không sửa được điều khoản. Ví cơ sở sẽ ký giao dịch createPlan và trả gas.',
                  style: TextStyle(color: mutedText),
                ),
              ],
            ),
          );
        },
      ),
    );
    if (fields == null) return;
    _planFormDraft = Map.of(fields);
    await _run(() async {
      final amount = parseTokenAmount(fields[amountField]!);
      final periods = parseWholeNumber(fields[periodsField]!, max: 120);
      final duration = parseWholeNumber(fields[durationField]!, max: 315360000);
      final grace = parseWholeNumber(fields[graceField]!, max: 315360000);
      if (amount == null ||
          periods == null ||
          duration == null ||
          grace == null ||
          fields['Tên gói']!.isEmpty) {
        throw const FormatException(
          'Nhập tên, giá và thời lượng dương; số kỳ 1–120.',
        );
      }
      await _controller!.publishPlan({
        'title': fields['Tên gói'],
        'description': fields['Mô tả'],
        'price_per_period': amount.toString(),
        'total_periods': periods,
        'period_duration_seconds': duration,
        'grace_period_seconds': grace,
      });
      _planFormDraft = Map.of(_defaultPlanDraft);
    });
  }

  Future<bool> _confirm(String title, String message) async =>
      await _withModal<bool?>(
        () => showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: SingleChildScrollView(child: Text(message)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Hủy'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Tiếp tục ký ví'),
              ),
            ],
          ),
        ),
      ) ??
      false;
  Future<void> _qr(
    String title,
    String payload, {
    required String note,
    String copyLabel = 'Sao chép payload',
  }) async {
    if (!mounted) return;
    await _withModal(
      () => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(12),
                    child: QrImageView(
                      data: payload,
                      size: 280,
                      backgroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SelectionArea(child: Text(payload)),
                  const SizedBox(height: 12),
                  Text(note),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Clipboard.setData(ClipboardData(text: payload)),
              child: Text(copyLabel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Đóng'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showQr(Json sub) async => _run(() async {
    final payload = await _controller!.createCheckIn(sub['subscription_id']);
    await _qr(
      'QR check-in ký số',
      payload,
      note:
          'Mã check-in EIP-712 có hạn 15 phút và chỉ giải ngân đúng 1 kỳ. Tạo lại mã không thu hồi mã cũ chưa dùng; contract chỉ tiêu thụ mỗi nonce một lần.',
    );
  });
  Future<void> _importQr() async {
    final c = _controller!;
    final fields = await _form(
      'Nhập QR check-in',
      {'QR payload': _qrPayloadDraft},
      validators: {'QR payload': c.validateQrLocally},
    );
    if (fields == null) return;
    _qrPayloadDraft = fields['QR payload']!;
    Json? preview;
    await _run(() async {
      preview = await c.previewCheckInQr(_qrPayloadDraft);
    });
    final p = preview;
    if (p == null || !mounted) return;
    final amountText = p['release_amount'] != null
        ? '${_money(p['release_amount'])} mUSDC'
        : '—';
    final remainingText = p['remaining_principal'] != null
        ? '${_money(p['remaining_principal'])} mUSDC'
        : '—';
    final warning = p['warning'] as String?;
    final details = [
      'Đăng ký #${p['subscription_id']} (Gói #${p['plan_id']})',
      'Ví hội viên: ${p['subscriber_address']}',
      'Kỳ giải ngân: Kỳ ${p['period_index']}/${p['total_periods']} · Nonce ${p['nonce']}',
      'Số tiền giải ngân kỳ này: $amountText (gốc còn giữ: $remainingText)',
      'Hạn mã QR (UTC): ${p['deadline_iso']}',
      if (warning != null)
        'Cảnh báo: $warning'
      else
        'Trạng thái: Đủ điều kiện — ví cơ sở sẽ ký giao dịch check-in và trả gas.',
    ].join('\n');
    if (!await _confirm('Giải ngân một kỳ', details)) return;
    await _run(() async {
      await c.confirmQr(_qrPayloadDraft);
      _qrPayloadDraft = '';
    });
  }

  Future<void> _showDetail(Json sub) async {
    final id = sub['subscription_id'] as String;
    final c = _controller!;
    SubscriptionDetails? dialog;
    await _run(() async {
      final detail = await c.detail(id);
      final eligibility = await c.eligibility(id);
      final firstPage = await c.events(id);
      dialog = SubscriptionDetails(
        controller: c,
        detail: detail,
        eligibility: eligibility,
        firstPage: firstPage,
      );
    });
    final view = dialog;
    if (view == null || !mounted || !c.loggedIn || _controller != c) return;
    await _withModal(
      () => showDialog<void>(context: context, builder: (_) => view),
    );
  }

  Widget _heading(String value) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 10),
    child: Text(value, style: Theme.of(context).textTheme.titleLarge),
  );
  String _money(dynamic value) =>
      formatTokenAmount(BigInt.parse(value.toString()));

  Widget _membershipFilters(
    LiveController controller, {
    required bool merchant,
  }) {
    final selected = merchant
        ? controller.merchantMembershipFilter
        : controller.membershipFilter;
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final filter in SubscriptionFilter.values)
          ChoiceChip(
            label: Text(filter.label),
            selected: selected == filter,
            onSelected: controller.busy || selected == filter
                ? null
                : (_) => _run(
                    () => controller.filterMemberships(merchant, filter),
                  ),
          ),
      ],
    );
  }

  Widget _loadMore({
    required String label,
    required bool busy,
    required Future<void> Function() load,
  }) {
    return OutlinedButton.icon(
      onPressed: busy ? null : () => _run(load),
      icon: const Icon(Icons.expand_more),
      label: Text(label),
    );
  }

  String _transactionStatus(Object? value) => switch (value) {
    'SUBMITTED' => 'Đang chờ xác nhận',
    'CONFIRMED' => 'Đã xác nhận',
    'REVERTED' => 'Giao dịch thất bại trên chuỗi',
    'REPLACED' => 'Đã được thay thế',
    'CANCELLED' => 'Đã hủy bằng giao dịch thay thế',
    _ => value.toString(),
  };

  Widget _subscription(Json sub, {required bool merchant}) {
    final active = sub['status'] == 'ACTIVE';
    final status = switch (sub['status']) {
      'ACTIVE' => 'Đang sử dụng',
      'COMPLETED' => 'Đã hoàn tất',
      'REFUNDED' => 'Đã hoàn gốc',
      _ => sub['status'].toString(),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Đăng ký #${sub['subscription_id']} · $status',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              'Tiền gốc còn lại trong Vault: ${_money(sub['remaining_principal'])} mUSDC',
            ),
            Text(
              'Đã giải ngân ${sub['completed_periods']}/${sub['total_periods']} kỳ',
            ),
            Text(
              'Kỳ tiếp theo: ${sub['next_release_at'] ?? '—'}\nCó thể yêu cầu hoàn gốc từ: ${sub['refund_available_at'] ?? '—'}',
            ),
            Text(
              'Nguồn: ${sub['sync']['source']} · block ${sub['sync']['block_number']}',
            ),
            const SizedBox(height: 8),
            SubscriptionYield(
              summary: sub['yield_summary'] as Json? ?? const {},
              merchant: merchant,
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton(
                  onPressed: _controller!.busy ? null : () => _showDetail(sub),
                  child: const Text('Chi tiết / lịch sử'),
                ),
                if (active && !merchant)
                  OutlinedButton(
                    onPressed: _controller!.busy ? null : () => _showQr(sub),
                    child: const Text('Tạo QR check-in'),
                  ),
                if (active && !merchant)
                  OutlinedButton(
                    onPressed: _controller!.busy
                        ? null
                        : () async {
                            if (await _confirm(
                              'Hoàn gốc chưa dùng',
                              'Refund theo điều khoản thời gian đã công bố, không chứng minh gym đóng cửa. Gốc còn lại: ${_money(sub['remaining_principal'])} mUSDC.',
                            )) {
                              await _run(
                                () =>
                                    _controller!.refund(sub['subscription_id']),
                              );
                            }
                          },
                    child: const Text('Yêu cầu hoàn gốc'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller,
        connected = c?.config != null,
        logged = c?.loggedIn ?? false,
        busy = (c?.busy ?? false) || _connecting;
    return Scaffold(
      appBar: AppBar(
        title: const BrandMark(),
        actions: [
          TextButton(
            onPressed: busy
                ? null
                : () async {
                    try {
                      if (logged) await c!.logout();
                    } catch (_) {
                      /* Local session is cleared in logout() finally; allow leaving real mode. */
                    } finally {
                      widget.onDemo();
                    }
                  },
            child: const Text('Về demo'),
          ),
        ],
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  'Kết nối API và ví',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  connected
                      ? 'Xem gói đã công bố trên mạng thử nghiệm đang kết nối.'
                      : 'Kết nối API để tải danh sách gói và kiểm tra mạng của Vault.',
                  style: const TextStyle(color: mutedText),
                ),
                const SizedBox(height: 20),
                const Card(
                  child: ListTile(
                    leading: Icon(
                      Icons.account_balance_outlined,
                      color: accent,
                    ),
                    title: Text('Tiền trả trước đi qua Vault'),
                    subtitle: Text(
                      'Khách ký đăng ký để khóa mUSDC thử nghiệm. Cơ sở nhận tiền từng kỳ đủ điều kiện sau khi xác nhận QR ký số của khách. Phần gốc chưa dùng có thể hoàn theo mốc thời gian của gói.',
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          connected ? 'Đã kết nối API' : 'Thiết lập kết nối',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _apiUrl,
                          enabled: !busy && !logged,
                          decoration: const InputDecoration(
                            labelText: 'API URL',
                            hintText: 'http://localhost:8000',
                            prefixIcon: Icon(Icons.dns_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          children: [
                            if (connected && !logged)
                              FilledButton.icon(
                                onPressed: busy
                                    ? null
                                    : () => _run(() => c!.login()),
                                icon: const Icon(
                                  Icons.account_balance_wallet_outlined,
                                ),
                                label: const Text('Kết nối ví / Đăng nhập'),
                              ),
                            if (!connected)
                              FilledButton(
                                onPressed: busy ? null : _connect,
                                child: const Text('Kết nối API'),
                              )
                            else if (!logged)
                              OutlinedButton(
                                onPressed: busy ? null : _connect,
                                child: const Text('Kết nối lại API'),
                              ),
                            if (connected)
                              OutlinedButton(
                                onPressed: busy
                                    ? null
                                    : () => _run(() => c!.refresh()),
                                child: const Text('Làm mới trạng thái'),
                              ),
                            if (logged)
                              TextButton(
                                onPressed: busy
                                    ? null
                                    : () => _run(() => c!.logout()),
                                child: const Text('Đăng xuất ví'),
                              ),
                          ],
                        ),
                        if (connected && !logged && c!.wallet.providers.length > 1) ...[
                          const SizedBox(height: 12),
                          Text(
                            'Chọn ví trình duyệt',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              for (final provider in c.wallet.providers)
                                ChoiceChip(
                                  label: Text(provider.name),
                                  selected:
                                      c.wallet.selectedProviderId ==
                                      provider.id,
                                  onSelected:
                                      busy ||
                                          c.wallet.selectedProviderId ==
                                              provider.id
                                      ? null
                                      : (_) => setState(
                                          () => c.wallet.selectProvider(
                                            provider.id,
                                          ),
                                        ),
                                ),
                            ],
                          ),
                        ],
                        if (busy) ...[
                          const SizedBox(height: 14),
                          const LinearProgressIndicator(),
                        ],
                        if (connected) ...[
                          const SizedBox(height: 12),
                          Text(
                            'Chain ID: ${c!.config!['chain_id']} · Ví: ${logged ? 'Đã đăng nhập' : 'Chưa đăng nhập'}',
                            style: const TextStyle(color: accent),
                          ),
                          ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            title: const Text('Thông tin mạng và Vault'),
                            expandedCrossAxisAlignment:
                                CrossAxisAlignment.stretch,
                            children: [
                              SelectableText(
                                'Deployment: ${c.config!['deployment_id']}\nVault: ${c.config!['vault_address']}\nYield: ${c.config!['yield_mode']}${logged ? '\nVí: ${c.account}' : ''}',
                              ),
                            ],
                          ),
                        ],
                        const Text(
                          'Giao dịch được ký qua ví trình duyệt tương thích EIP-1193.',
                          style: TextStyle(color: mutedText),
                        ),
                      ],
                    ),
                  ),
                ),
                if (c?.notice.isNotEmpty ?? false)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(c!.notice),
                  ),
                if (connected) ...[
                  _heading('Gói đã công bố'),
                  if (c!.plans.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(18),
                        child: Text(
                          'API chưa trả về gói đã công bố trên mạng này.',
                        ),
                      ),
                    ),
                  for (final plan in c.plans)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${plan['title']}',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Trả trước ${_money(plan['total_price'])} mUSDC',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(color: accent),
                              ),
                              Text(
                                'Gói #${plan['plan_id']} · ${plan['total_periods']} kỳ · ${plan['period_duration_seconds']} giây/kỳ · Ân hạn ${plan['grace_period_seconds']} giây',
                                style: const TextStyle(color: mutedText),
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  IconButton(
                                    tooltip: 'QR đăng ký',
                                    onPressed: busy
                                        ? null
                                        : () => _qr(
                                            'QR đăng ký gói',
                                            _entryUri
                                                .replace(
                                                  queryParameters: {
                                                    'real': '1',
                                                    'plan_id': plan['plan_id'],
                                                    'chain_id': c
                                                        .config!['chain_id']
                                                        .toString(),
                                                    'vault': c
                                                        .config!['vault_address'],
                                                  },
                                                )
                                                .toString(),
                                            note:
                                                'Liên kết mở gói #${plan['plan_id']} (${plan['title']} · Trả trước ${_money(plan['total_price'])} mUSDC) trên Chain ${c.config!['chain_id']}. Đây là mã QR đăng ký gói, không phải mã check-in ký số.',
                                            copyLabel: 'Sao chép liên kết',
                                          ),
                                    icon: const Icon(Icons.qr_code),
                                  ),
                                  FilledButton(
                                    onPressed: busy || !logged
                                        ? null
                                        : () async {
                                            if (await _confirm(
                                              'Đăng ký gói',
                                              'Khóa ${_money(plan['total_price'])} mUSDC. Có thể cần ký approve rồi subscribe. Kỳ đầu sau ${plan['period_duration_seconds']} giây; không tự giải ngân.',
                                            )) {
                                              await _run(
                                                () => c.subscribe(plan),
                                              );
                                            }
                                          },
                                    child: const Text('Đăng ký'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
                if (connected && c!.plansCursor != null)
                  OutlinedButton(
                    onPressed: busy
                        ? null
                        : () => _run(() => c.loadMorePlans()),
                    child: const Text('Tải thêm gói'),
                  ),
                if (logged) ...[
                  _heading('Gói của tôi'),
                  _membershipFilters(c!, merchant: false),
                  for (final issue in c.issues)
                    Text(
                      'Cảnh báo gói #${issue['subscription_id']}: ${issue['code']} — ${issue['message']}',
                      style: const TextStyle(color: Colors.orange),
                    ),
                  if (c.memberships.isEmpty)
                    Text(
                      c.membershipFilter == SubscriptionFilter.all
                          ? 'Chưa có subscription đã đồng bộ.'
                          : 'Không có đăng ký khớp trạng thái đã chọn.',
                    ),
                  for (final sub in c.memberships)
                    _subscription(sub, merchant: false),
                  if (c.membershipsCursor != null)
                    _loadMore(
                      label: 'Tải thêm đăng ký của tôi',
                      busy: busy,
                      load: () => c.loadMoreMemberships(merchant: false),
                    ),
                  _heading('Cơ sở'),
                  if (!c.isMerchant)
                    FilledButton(
                      onPressed: busy ? null : _createMerchant,
                      child: const Text('Tạo hồ sơ cơ sở'),
                    ),
                  if (c.isMerchant) ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton(
                          onPressed: busy ? null : _createPlan,
                          child: const Text('Tạo / publish gói'),
                        ),
                        OutlinedButton(
                          onPressed: busy ? null : _importQr,
                          child: const Text('Nhập QR check-in'),
                        ),
                      ],
                    ),
                    const Text(
                      'Nhập/dán payload QR là đường dự phòng hiện tại; chưa tích hợp camera scanner.',
                    ),
                    for (final draft in c.drafts.where(
                      (d) => d['state'] == 'DRAFT',
                    ))
                      ListTile(
                        title: Text('Draft: ${draft['title']}'),
                        subtitle: draft['price_per_period'] == null
                            ? null
                            : Text(
                                '${_money(draft['price_per_period'])} mUSDC/kỳ × ${draft['total_periods']} kỳ · Tổng ${_money(draft['total_price'])} mUSDC\nKỳ ${draft['period_duration_seconds']} giây · Ân hạn ${draft['grace_period_seconds']} giây',
                              ),
                        trailing: TextButton(
                          onPressed: busy
                              ? null
                              : () async {
                                  final summary =
                                      draft['price_per_period'] == null
                                      ? 'Gói: ${draft['title']}\nSau khi publish on-chain không thể sửa điều khoản. Ví cơ sở sẽ ký giao dịch và trả gas.'
                                      : 'Gói: ${draft['title']}\nMỗi kỳ: ${_money(draft['price_per_period'])} mUSDC × ${draft['total_periods']} kỳ = Tổng ${_money(draft['total_price'])} mUSDC\nThời lượng kỳ: ${draft['period_duration_seconds']} giây · Ân hạn hoàn gốc: ${draft['grace_period_seconds']} giây\n\nSau khi publish on-chain không thể sửa điều khoản. Ví cơ sở sẽ ký giao dịch và trả gas.';
                                  if (await _confirm(
                                    'Publish gói lên chuỗi',
                                    summary,
                                  )) {
                                    await _run(() => c.publishDraft(draft));
                                  }
                                },
                          child: const Text('Publish draft'),
                        ),
                      ),
                    if (c.draftsCursor != null)
                      _loadMore(
                        label: 'Tải thêm bản nháp',
                        busy: busy,
                        load: c.loadMoreDrafts,
                      ),
                    _heading('Đăng ký tại cơ sở'),
                    _membershipFilters(c, merchant: true),
                    for (final issue in c.merchantIssues)
                      Text(
                        'Cảnh báo gói #${issue['subscription_id']}: ${issue['code']} — ${issue['message']}',
                        style: const TextStyle(color: Colors.orange),
                      ),
                    for (final sub in c.merchantMemberships)
                      _subscription(sub, merchant: true),
                    if (c.merchantMemberships.isEmpty)
                      const Text('Không có đăng ký tại cơ sở khớp bộ lọc.'),
                    if (c.merchantMembershipsCursor != null)
                      _loadMore(
                        label: 'Tải thêm đăng ký tại cơ sở',
                        busy: busy,
                        load: () => c.loadMoreMemberships(merchant: true),
                      ),
                  ],
                  _heading('Giao dịch của phiên / khôi phục'),
                  const Text(
                    'Hash lưu theo ví + deployment để phục hồi sau reload. JWT chỉ ở bộ nhớ; reload cần ký SIWE lại. Pending không có nghĩa đã thanh toán.',
                  ),
                  for (final item in c.pending)
                    ListTile(
                      title: Text(
                        '${item['action']} · ${_transactionStatus(item['status'])} (${item['status']})',
                      ),
                      subtitle: SelectableText(
                        [
                          'Hash gốc: ${item['tx_hash']}',
                          if (item['replacement_tx_hash'] != null)
                            'Hash thay thế: ${item['replacement_tx_hash']}',
                          if (item['status'] == 'SUBMITTED' &&
                              item['sender_nonce'] == null)
                            'Chưa có nonce gốc. Nếu API chưa có bằng chứng, cần raw giao dịch gốc đã ký để đối chiếu. Thao tác vẫn bị chặn gửi lặp.',
                          if (item['last_error'] != null)
                            '${item['last_error']}',
                          if (item['storage_warning'] != null)
                            '${item['storage_warning']}',
                        ].join('\n'),
                      ),
                      trailing: item['status'] != 'SUBMITTED'
                          ? null
                          : IconButton(
                              tooltip:
                                  'Đối chiếu giao dịch tăng phí hoặc hủy trong ví',
                              onPressed: busy
                                  ? null
                                  : () async {
                                        final fields = await _form(
                                          'Đối chiếu giao dịch thay thế đã xác nhận',
                                          {
                                            'Hash giao dịch mới': '',
                                            if (item['sender_nonce'] == null)
                                              'Raw giao dịch gốc đã ký (không nhập seed/private key)':
                                                  '',
                                          },
                                          validators: {
                                            'Hash giao dịch mới': (value) {
                                              final v = (value ?? '').trim();
                                              if (!RegExp(
                                                r'^0x[0-9a-fA-F]{64}$',
                                              ).hasMatch(v)) {
                                                return 'Nhập hash giao dịch dạng 0x + 64 ký tự hex.';
                                              }
                                              return null;
                                            },
                                            'Raw giao dịch gốc đã ký (không nhập seed/private key)':
                                                (value) {
                                                  final v = (value ?? '')
                                                      .trim();
                                                  if (v.isEmpty) return null;
                                                  if (v.length > 32770 ||
                                                      !RegExp(
                                                        r'^0x(?:[0-9a-fA-F]{2})+$',
                                                      ).hasMatch(v)) {
                                                    return 'Chỉ nhập raw giao dịch đã ký dạng 0x; không nhập seed/private key.';
                                                  }
                                                  return null;
                                                },
                                          },
                                        );
                                      if (fields != null)
                                        await _run(
                                          () => c.replaceTransaction(
                                            item,
                                            fields['Hash giao dịch mới']!,
                                            originalSignedTransaction:
                                                fields['Raw giao dịch gốc đã ký (không nhập seed/private key)'],
                                          ),
                                        );
                                    },
                              icon: const Icon(Icons.find_replace),
                            ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _poll?.cancel();
    _controller?.removeListener(_changed);
    _controller?.dispose();
    _apiUrl.dispose();
    super.dispose();
  }
}
