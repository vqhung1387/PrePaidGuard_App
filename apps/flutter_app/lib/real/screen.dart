import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app/prepaid_guard_theme.dart';
import '../features/plans/demo_plan.dart';
import '../shared/widgets/brand_mark.dart';
import 'api.dart';
import 'controller.dart';
import 'escrow_summary_card.dart';
import 'subscription_details.dart';
import 'wallet.dart';

enum _Section {
  catalog('Khám phá', Icons.storefront_outlined),
  memberships('Gói của tôi', Icons.confirmation_number_outlined),
  business('Cơ sở', Icons.business_outlined),
  activity('Giao dịch', Icons.receipt_long_outlined);

  const _Section(this.label, this.icon);
  final String label;
  final IconData icon;
}

class RealWorkspaceScreen extends StatefulWidget {
  const RealWorkspaceScreen({
    super.key,
    this.autoConnect = false,
    this.controller,
    this.initialUri,
    this.apiBaseUrl,
    this.apiFactory,
    this.walletFactory,
    this.storeFactory,
  });

  final bool autoConnect;
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
    'Tên gói': '',
    'Mô tả': '',
    'mUSDC mỗi kỳ': '',
    'Số kỳ': '',
    'Thời lượng mỗi kỳ': '',
    'Thời gian ân hạn': '',
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
  String? _connectionError;
  int _modalDepth = 0;
  _Section _section = _Section.catalog;

  void _openSection(_Section section) {
    if (_section != section) setState(() => _section = section);
  }

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
        (widget.autoConnect ||
            _entryUri.queryParameters.containsKey('plan_id')) &&
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
    setState(() {
      _connecting = true;
      _connectionError = null;
    });
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
      await c.operation(() => c.bootstrap(registration: _entryUri));
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
      }
    } catch (error) {
      if (_controller?.config == null) {
        _connectionError = formatUserError(error);
      } else {
        _showError(error);
      }
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
    Map<String, String> fieldHints = const {},
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
                          autovalidateMode: entry.key == amountField
                              ? AutovalidateMode.onUserInteraction
                              : AutovalidateMode.disabled,
                          decoration: InputDecoration(
                            labelText: entry.key,
                            helperText: entry.key == amountField
                                ? tokenAmountHint
                                : fieldHints[entry.key],
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
    const amountField = 'mUSDC mỗi kỳ';
    const periodsField = 'Số kỳ';
    const durationField = 'Thời lượng mỗi kỳ';
    const graceField = 'Thời gian ân hạn';
    const durationHint =
        'Ví dụ: 30 ngày, 12 giờ, 45 phút. Số đứng riêng tính theo ngày.';
    String? validateDuration(String? value) =>
        _durationSeconds(value ?? '') == null
        ? 'Nhập thời lượng dương, tối đa 3650 ngày.'
        : null;
    final fields = await _form(
      'Tạo gói dịch vụ',
      _planFormDraft,
      amountField: amountField,
      fieldHints: {durationField: durationHint, graceField: durationHint},
      validators: {
        'Tên gói': _validateRequiredName,
        'Mô tả': (value) =>
            (value ?? '').length > 2000 ? 'Mô tả tối đa 2000 ký tự.' : null,
        periodsField: (value) => parseWholeNumber(value ?? '', max: 120) == null
            ? 'Nhập số kỳ nguyên từ 1 đến 120.'
            : null,
        durationField: validateDuration,
        graceField: validateDuration,
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
          final duration = _durationSeconds(controllers[durationField]!.text);
          final grace = _durationSeconds(controllers[graceField]!.text);
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
                    'Check-in kỳ đầu sau ${_duration(duration)}. Sau thêm ${_duration(grace)} ân hạn, khách có thể yêu cầu hoàn gốc chưa dùng.',
                  ),
                ],
                const SizedBox(height: 4),
                const Text(
                  'Sau khi công bố, điều khoản của gói được cố định. Ví cơ sở xác nhận giao dịch và trả phí mạng.',
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
      final duration = _durationSeconds(fields[durationField]!);
      final grace = _durationSeconds(fields[graceField]!);
      if (amount == null ||
          periods == null ||
          duration == null ||
          grace == null ||
          fields['Tên gói']!.isEmpty) {
        throw const FormatException(
          'Nhập tên, giá, thời lượng và số kỳ hợp lệ.',
        );
      }
      final c = _controller!;
      final draft = await c.createPlanDraft({
        'title': fields['Tên gói'],
        'description': fields['Mô tả'],
        'price_per_period': amount.toString(),
        'total_periods': periods,
        'period_duration_seconds': duration,
        'grace_period_seconds': grace,
      });
      _planFormDraft = Map.of(_defaultPlanDraft);
      await c.publishDraft(draft);
    });
  }

  Future<bool> _confirm(
    String title,
    String message, {
    String confirmLabel = 'Tiếp tục ký ví',
  }) async =>
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
                child: Text(confirmLabel),
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
    final completed = int.tryParse(sub['completed_periods'].toString());
    final periods = int.tryParse(sub['total_periods'].toString());
    final status = switch (sub['status']) {
      'ACTIVE' => 'Đang sử dụng',
      'COMPLETED' => 'Đã hoàn tất',
      'REFUNDED' => 'Đã hoàn gốc',
      _ => sub['status'].toString(),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _planName(
                _controller!.plans
                        .where((plan) => plan['plan_id'] == sub['plan_id'])
                        .firstOrNull ??
                    sub,
              ),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'Đăng ký #${sub['subscription_id']} · $status',
              style: const TextStyle(color: mutedText),
            ),
            const SizedBox(height: 10),
            Text(
              'Tiền gốc còn lại trong Vault: ${_money(sub['remaining_principal'])} mUSDC',
            ),
            Text(
              'Đã giải ngân ${sub['completed_periods']}/${sub['total_periods']} kỳ',
            ),
            if (completed != null &&
                periods != null &&
                periods > 0 &&
                completed >= 0 &&
                completed <= periods)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(
                  value: completed / periods,
                  semanticsLabel: 'Tiến độ giải ngân',
                  borderRadius: const BorderRadius.all(Radius.circular(6)),
                ),
              ),
            if (active)
              Text(
                'Kỳ tiếp theo: ${_date(sub['next_release_at'])}\nCó thể yêu cầu hoàn gốc từ: ${_date(sub['refund_available_at'])}',
              ),
            const SizedBox(height: 8),
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
                              'Yêu cầu hoàn phần tiền gốc chưa dùng khi tới mốc theo điều khoản của gói. Gốc còn lại: ${_money(sub['remaining_principal'])} mUSDC.',
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

  List<Widget> _businessSection(LiveController c, bool busy) => [
    _sectionHeader(
      c.isMerchant ? 'Vận hành cơ sở' : 'Cơ sở của bạn',
      description: c.isMerchant
          ? 'Công bố gói, xác nhận check-in và theo dõi khoản giải ngân.'
          : null,
    ),
    if (!c.isMerchant)
      _emptyState(
        Icons.business_outlined,
        'Mở hồ sơ cơ sở',
        'Tạo hồ sơ bằng ví hiện tại để khách hàng thấy tên cơ sở trên các gói.',
        action: FilledButton(
          onPressed: busy ? null : _createMerchant,
          child: const Text('Tạo hồ sơ cơ sở'),
        ),
      ),
    if (c.isMerchant) ...[
      Card(
        color: panelRaised,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tiếp nhận hội viên',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              const Text(
                'Dán mã QR hội viên gửi để kiểm tra kỳ và số tiền trước khi xác nhận.',
                style: TextStyle(color: mutedText),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: busy ? null : _importQr,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Nhập QR check-in'),
                  ),
                  OutlinedButton.icon(
                    onPressed: busy ? null : _createPlan,
                    icon: const Icon(Icons.add),
                    label: const Text('Tạo gói dịch vụ'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      _heading('Gói của cơ sở'),
      if (c.drafts.isEmpty)
        const Text(
          'Gói đã lưu và gói đã công bố sẽ xuất hiện ở đây.',
          style: TextStyle(color: mutedText),
        ),
      for (final plan in c.drafts.where((plan) => plan['state'] == 'PUBLISHED'))
        ListTile(
          leading: const Icon(Icons.storefront_outlined, color: accent),
          title: Text(_planName(plan)),
          subtitle: Text(
            'Đã công bố · ${_money(plan['total_price'])} mUSDC trả trước',
          ),
        ),
      for (final draft in c.drafts.where((d) => d['state'] == 'DRAFT'))
        ListTile(
          title: Text('Bản nháp: ${draft['title']}'),
          subtitle: draft['price_per_period'] == null
              ? null
              : Text(
                  '${_money(draft['price_per_period'])} mUSDC/kỳ × ${draft['total_periods']} kỳ · Tổng ${_money(draft['total_price'])} mUSDC\nKỳ ${draft['period_duration_seconds']} giây · Ân hạn ${draft['grace_period_seconds']} giây',
                ),
          trailing: TextButton(
            onPressed: busy
                ? null
                : () async {
                    final summary = draft['price_per_period'] == null
                        ? 'Gói: ${draft['title']}\nSau khi công bố, điều khoản của gói được cố định. Ví cơ sở xác nhận giao dịch và trả phí mạng.'
                        : 'Gói: ${draft['title']}\nMỗi kỳ: ${_money(draft['price_per_period'])} mUSDC × ${draft['total_periods']} kỳ = Tổng ${_money(draft['total_price'])} mUSDC\nThời lượng kỳ: ${draft['period_duration_seconds']} giây · Ân hạn hoàn gốc: ${draft['grace_period_seconds']} giây\n\nSau khi công bố, điều khoản của gói được cố định. Ví cơ sở xác nhận giao dịch và trả phí mạng.';
                    if (await _confirm('Kiểm tra và công bố gói', summary)) {
                      await _run(() => c.publishDraft(draft));
                    }
                  },
            child: const Text('Công bố bản nháp'),
          ),
        ),
      if (c.draftsCursor != null)
        _loadMore(
          label: 'Tải thêm gói của cơ sở',
          busy: busy,
          load: c.loadMoreDrafts,
        ),
      _heading('Đăng ký tại cơ sở'),
      _membershipFilters(c, merchant: true),
      EscrowSummaryCard(
        subscriptions: c.merchantMemberships,
        config: c.config!,
        filter: c.merchantMembershipFilter,
        hasMore: c.merchantMembershipsCursor != null,
        merchant: true,
      ),
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
  ];

  String _shortWallet(String address) => address.length > 13
      ? '${address.substring(0, 6)}…${address.substring(address.length - 4)}'
      : address;

  int? _durationSeconds(String value) {
    const secondsPerUnit = {'ngày': 86400, 'giờ': 3600, 'phút': 60, 'giây': 1};
    final match = RegExp(
      r'^([0-9]+)(?:\s*(ngày|giờ|phút|giây))?$',
    ).firstMatch(value.trim().toLowerCase());
    if (match == null) return null;
    final unit = secondsPerUnit[match[2] ?? 'ngày']!;
    final count = parseWholeNumber(match[1]!, max: 315360000 ~/ unit);
    return count == null ? null : count * unit;
  }

  String _duration(Object? raw) {
    final seconds = int.tryParse(raw.toString());
    if (seconds == null) return 'Chưa có thời lượng';
    for (final (size, unit) in [(86400, 'ngày'), (3600, 'giờ'), (60, 'phút')]) {
      if (seconds > 0 && seconds % size == 0) return '${seconds ~/ size} $unit';
    }
    return '$seconds giây';
  }

  String _date(Object? raw) {
    final date = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
    if (date == null) return '—';
    final localizations = MaterialLocalizations.of(context);
    return '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(date), alwaysUse24HourFormat: true)} · ${localizations.formatCompactDate(date)}';
  }

  String _planName(Json plan) {
    final id = plan['plan_id'];
    final title = plan['title']?.toString().trim();
    return title == null || title.isEmpty || title == 'Plan #$id'
        ? (id == null ? 'Gói dịch vụ' : 'Gói #$id')
        : title;
  }

  String _providerName(Json plan) {
    final merchant = plan['merchant'] as Map?;
    final name = merchant?['business_name']?.toString().trim();
    return name == null || name.isEmpty
        ? 'Cơ sở · ${_shortWallet(plan['merchant_address']?.toString() ?? '—')}'
        : name;
  }

  Future<void> _login(LiveController c) async {
    final providers = c.wallet.providers;
    if (providers.length > 1) {
      final selected = await _withModal(
        () => showDialog<String>(
          context: context,
          builder: (context) => SimpleDialog(
            title: const Text('Chọn ví trình duyệt'),
            children: [
              for (final provider in providers)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, provider.id),
                  child: Text(provider.name),
                ),
            ],
          ),
        ),
      );
      if (selected == null || !mounted || _controller != c) return;
      c.wallet.selectProvider(selected);
    }
    await _run(c.login);
  }

  Future<void> _accountDetails(LiveController c) => _withModal(
    () => showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Tài khoản'),
        content: SizedBox(
          width: 480,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (c.loggedIn) ...[
                const Text('Địa chỉ ví'),
                SelectableText(c.account ?? '—'),
                const SizedBox(height: 16),
              ],
              const Text(
                'mUSDC trên môi trường hiện tại là token thử nghiệm.',
                style: TextStyle(color: mutedText),
              ),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Thông tin mạng và Vault'),
                expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SelectableText(
                    'Mạng: ${c.config!['chain_name'] ?? c.config!['chain_id']}'
                    '\nChain ID: ${c.config!['chain_id']}'
                    '\nVault: ${c.config!['vault_address']}'
                    '\nDeployment: ${c.config!['deployment_id']}',
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          if (c.loggedIn)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                unawaited(_run(c.logout));
              },
              child: const Text('Đăng xuất ví'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng'),
          ),
        ],
      ),
    ),
  );

  Widget _sectionHeader(String title, {String? description}) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineMedium),
        if (description != null) ...[
          const SizedBox(height: 6),
          Text(description, style: const TextStyle(color: mutedText)),
        ],
      ],
    ),
  );

  Widget _emptyState(
    IconData icon,
    String title,
    String description, {
    Widget? action,
  }) => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AccentIcon(icon),
          const SizedBox(height: 14),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(description, style: const TextStyle(color: mutedText)),
          if (action != null) ...[const SizedBox(height: 16), action],
        ],
      ),
    ),
  );

  Widget _catalogHero() => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 680;
      return ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          children: [
            if (wide)
              Positioned.fill(
                child: Image.asset(
                  'assets/gym-hero.jpg',
                  fit: BoxFit.cover,
                  alignment: Alignment.centerRight,
                  excludeFromSemantics: true,
                ),
              ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: wide ? null : panelRaised,
                  gradient: wide
                      ? const LinearGradient(
                          colors: [
                            Color(0xff102436),
                            Color(0xf2102436),
                            Color(0x40102436),
                          ],
                          stops: [0, .49, 1],
                        )
                      : null,
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(wide ? 36 : 22),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 510),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AccentIcon(Icons.shield_outlined),
                    const SizedBox(height: 14),
                    Text(
                      'Khám phá gói dịch vụ',
                      style: Theme.of(
                        context,
                      ).textTheme.headlineLarge?.copyWith(color: brightText),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Xem giá trả trước, thời hạn và điều kiện hoàn gốc trước khi đăng ký. Cơ sở nhận tiền theo từng kỳ đã xác nhận sử dụng.',
                      style: TextStyle(color: Color(0xffc4d3e1), height: 1.5),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    },
  );

  Future<void> _reviewPlan(LiveController c, Json plan) async {
    final logged = c.loggedIn;
    final account = c.account;
    final location = (plan['merchant'] as Map?)?['location_text']
        ?.toString()
        .trim();
    final terms = <String>[
      _providerName(plan),
      if (location != null && location.isNotEmpty) location,
      if ((plan['description']?.toString().trim() ?? '').isNotEmpty)
        plan['description'].toString().trim(),
      'Tổng trả trước: ${_money(plan['total_price'])} mUSDC',
      'Mỗi kỳ: ${_money(plan['price_per_period'])} mUSDC · ${plan['total_periods']} kỳ',
      'Mỗi kỳ kéo dài ${_duration(plan['period_duration_seconds'])}. Kỳ đầu mở sau thời lượng này kể từ lúc đăng ký.',
      'Cơ sở nhận tiền sau khi xác nhận bạn đã sử dụng dịch vụ. Bạn có thể yêu cầu hoàn phần gốc chưa dùng khi kết thúc ${_duration(plan['grace_period_seconds'])} ân hạn của kỳ tiếp theo.',
      'Thanh toán bằng mUSDC thử nghiệm. Ví có thể yêu cầu cấp quyền sử dụng token trước khi ký đăng ký.',
    ];
    final confirmed = await _confirm(
      'Đăng ký ${_planName(plan)}',
      terms.join('\n\n'),
      confirmLabel: logged ? 'Tiếp tục ký ví' : 'Kết nối ví để đăng ký',
    );
    if (!confirmed || !mounted || _controller != c || c.account != account) {
      return;
    }
    if (logged) {
      await _run(() => c.subscribe(plan));
    } else {
      await _login(c);
    }
  }

  Widget _planCard(LiveController c, Json plan, bool busy) {
    final theme = Theme.of(context);
    final description = plan['description']?.toString().trim() ?? '';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const AccentIcon(Icons.storefront_outlined, size: 34),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _providerName(plan),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: mutedText,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(_planName(plan), style: theme.textTheme.titleLarge),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                description,
                style: const TextStyle(color: mutedText),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Divider(height: 1),
            ),
            const Text('Tổng trả trước', style: TextStyle(color: mutedText)),
            const SizedBox(height: 4),
            Text(
              '${_money(plan['total_price'])} mUSDC',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: accent,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${_money(plan['price_per_period'])} mUSDC/kỳ  ·  ${plan['total_periods']} kỳ',
            ),
            Text(
              '${_duration(plan['period_duration_seconds'])}/kỳ  ·  Ân hạn ${_duration(plan['grace_period_seconds'])}',
              style: const TextStyle(color: mutedText),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: busy ? null : () => _reviewPlan(c, plan),
                    child: Text(c.loggedIn ? 'Đăng ký' : 'Xem gói'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.outlined(
                  tooltip: 'QR đăng ký',
                  onPressed: busy
                      ? null
                      : () => _qr(
                          'QR đăng ký gói',
                          _entryUri
                              .replace(
                                queryParameters: {
                                  'plan_id': plan['plan_id'].toString(),
                                  'chain_id': c.config!['chain_id'].toString(),
                                  'vault': c.config!['vault_address']
                                      .toString(),
                                },
                                fragment: '',
                              )
                              .toString(),
                          note:
                              'Chia sẻ gói ${_planName(plan)} để khách xem điều khoản và đăng ký.',
                          copyLabel: 'Sao chép liên kết',
                        ),
                  icon: const Icon(Icons.qr_code),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _catalog(LiveController? c, bool busy) => [
    _catalogHero(),
    _heading('Gói đã công bố'),
    if (c?.config == null)
      _emptyState(
        Icons.storefront_outlined,
        _connecting ? 'Đang tải danh mục' : 'Chưa thể tải danh mục',
        _connecting
            ? 'Danh sách gói sẽ xuất hiện khi tải xong.'
            : 'Thử tải lại để xem các gói đang mở đăng ký.',
        action: _connecting
            ? null
            : FilledButton(
                onPressed: busy ? null : _connect,
                child: Text(widget.autoConnect ? 'Tải lại' : 'Kết nối API'),
              ),
      )
    else if (c!.plans.isEmpty)
      _emptyState(
        Icons.storefront_outlined,
        'Chưa có gói mở đăng ký',
        'Các gói sẽ xuất hiện tại đây sau khi cơ sở công bố.',
      )
    else ...[
      if (c.catalogUnavailable)
        _emptyState(
          Icons.storefront_outlined,
          'Chưa thể tải các gói khác',
          'Bạn vẫn có thể xem gói từ liên kết đăng ký.',
          action: FilledButton(
            onPressed: busy ? null : () => _run(c.refresh),
            child: const Text('Tải lại danh mục'),
          ),
        ),
      LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 730;
          final width = wide
              ? (constraints.maxWidth - 16) / 2
              : constraints.maxWidth;
          return Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              for (final plan in c.plans)
                SizedBox(width: width, child: _planCard(c, plan, busy)),
            ],
          );
        },
      ),
      if (c.plansCursor != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: _loadMore(
            label: 'Tải thêm gói',
            busy: busy,
            load: c.loadMorePlans,
          ),
        ),
    ],
  ];

  List<Widget> _memberArea(LiveController c, bool busy) => [
    _sectionHeader(
      'Đăng ký của bạn',
      description: 'Xem lịch kỳ, số tiền còn giữ và mã check-in của từng gói.',
    ),
    if (c.memberships.isNotEmpty ||
        c.membershipFilter != SubscriptionFilter.all)
      _membershipFilters(c, merchant: false),
    EscrowSummaryCard(
      subscriptions: c.memberships,
      config: c.config!,
      filter: c.membershipFilter,
      hasMore: c.membershipsCursor != null,
    ),
    for (final issue in c.issues)
      Text(
        'Đăng ký #${issue['subscription_id']}: ${issue['message']}',
        style: const TextStyle(color: Colors.orange),
      ),
    if (c.memberships.isEmpty)
      _emptyState(
        Icons.confirmation_number_outlined,
        c.membershipFilter == SubscriptionFilter.all
            ? 'Bạn chưa có gói đã đăng ký'
            : 'Không có đăng ký khớp bộ lọc',
        'Bạn có thể xem các gói đang mở trong danh mục.',
        action: FilledButton(
          onPressed: () => _openSection(_Section.catalog),
          child: const Text('Xem danh mục'),
        ),
      ),
    for (final sub in c.memberships) _subscription(sub, merchant: false),
    if (c.membershipsCursor != null)
      _loadMore(
        label: 'Tải thêm đăng ký của tôi',
        busy: busy,
        load: () => c.loadMoreMemberships(merchant: false),
      ),
  ];

  String _transactionAction(Object? value) => switch (value) {
    'APPROVE' => 'Cấp quyền sử dụng token',
    'CREATE_PLAN' => 'Công bố gói',
    'SUBSCRIBE' => 'Đăng ký gói',
    'CHECK_IN' => 'Giải ngân kỳ',
    'REFUND' => 'Hoàn tiền gốc',
    _ => 'Giao dịch',
  };

  Future<void> _reconcile(LiveController c, Json item) async {
    const hashLabel = 'Hash giao dịch mới';
    const originalLabel =
        'Raw giao dịch gốc đã ký (không nhập seed/private key)';
    final fields = await _form(
      'Đối chiếu giao dịch thay thế đã xác nhận',
      {hashLabel: '', if (item['sender_nonce'] == null) originalLabel: ''},
      validators: {
        hashLabel: (value) =>
            RegExp(r'^0x[0-9a-fA-F]{64}$').hasMatch((value ?? '').trim())
            ? null
            : 'Nhập hash giao dịch dạng 0x + 64 ký tự hex.',
        originalLabel: (value) {
          final raw = (value ?? '').trim();
          if (raw.isEmpty) return null;
          if (raw.length > 32770 ||
              !RegExp(r'^0x(?:[0-9a-fA-F]{2})+$').hasMatch(raw)) {
            return 'Chỉ nhập raw giao dịch đã ký dạng 0x; không nhập seed/private key.';
          }
          return null;
        },
      },
    );
    if (fields == null || !mounted || _controller != c) return;
    await _run(
      () => c.replaceTransaction(
        item,
        fields[hashLabel]!,
        originalSignedTransaction: fields[originalLabel],
      ),
    );
  }

  List<Widget> _activity(LiveController c, bool busy) => [
    _sectionHeader(
      'Giao dịch của bạn',
      description: 'Theo dõi các thao tác đã gửi từ ứng dụng bằng ví này.',
    ),
    if (c.pending.isEmpty)
      _emptyState(
        Icons.receipt_long_outlined,
        'Chưa có giao dịch để theo dõi',
        'Sau khi bạn gửi giao dịch, trạng thái xác nhận sẽ hiển thị tại đây.',
      ),
    for (final item in c.pending)
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExpansionTile(
                key: ValueKey(item['tx_hash']),
                title: Text(_transactionAction(item['action'])),
                subtitle: Text(_transactionStatus(item['status'])),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SelectableText(
                    [
                      'Hash gốc: ${item['tx_hash']}',
                      if (item['replacement_tx_hash'] != null)
                        'Hash thay thế: ${item['replacement_tx_hash']}',
                      if (item['status'] == 'SUBMITTED' &&
                          item['sender_nonce'] == null)
                        'Thiếu nonce gốc. Có thể cần giao dịch gốc đã ký để xác minh; ứng dụng vẫn chặn gửi lặp.',
                      if (item['last_error'] != null) '${item['last_error']}',
                      if (item['storage_warning'] != null)
                        '${item['storage_warning']}',
                    ].join('\n'),
                  ),
                ],
              ),
              if (item['status'] == 'SUBMITTED')
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
                  child: TextButton(
                    onPressed: busy ? null : () => _reconcile(c, item),
                    child: const Text(
                      'Đối chiếu giao dịch tăng phí hoặc hủy trong ví',
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
  ];

  List<Widget> _currentSection(LiveController? c, bool busy) {
    if (_section == _Section.catalog) return _catalog(c, busy);
    if (c?.config == null) {
      return [
        _sectionHeader(_section.label),
        _emptyState(
          _section.icon,
          _connecting ? 'Đang tải dữ liệu' : 'Chưa thể tải dữ liệu',
          'Kết nối với dịch vụ để tiếp tục.',
          action: _connecting
              ? null
              : FilledButton(
                  onPressed: busy ? null : _connect,
                  child: const Text('Tải lại'),
                ),
        ),
      ];
    }
    if (!c!.loggedIn) {
      final description = switch (_section) {
        _Section.memberships =>
          'Dùng ví đã đăng ký để xem các gói và mã check-in của bạn.',
        _Section.business =>
          'Kết nối ví cơ sở để công bố gói, tiếp nhận check-in và theo dõi tiền nhận theo kỳ.',
        _ => 'Kết nối ví đã gửi giao dịch để xem trạng thái xác nhận.',
      };
      return [
        _sectionHeader(_section.label),
        _emptyState(
          _section.icon,
          'Đăng nhập để tiếp tục',
          description,
          action: FilledButton(
            onPressed: busy ? null : () => _login(c),
            child: const Text('Kết nối ví'),
          ),
        ),
      ];
    }
    return switch (_section) {
      _Section.business => _businessSection(c, busy),
      _Section.memberships => _memberArea(c, busy),
      _Section.activity => _activity(c, busy),
      _Section.catalog => _catalog(c, busy),
    };
  }

  Widget _navigation() => DecoratedBox(
    decoration: const BoxDecoration(
      color: panel,
      border: Border(bottom: BorderSide(color: panelOutline)),
    ),
    child: Align(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1160),
        child: SizedBox(
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            child: Wrap(
              spacing: 4,
              runSpacing: 2,
              children: [
                for (final section in _Section.values)
                  Semantics(
                    selected: _section == section,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        backgroundColor: _section == section ? canvas : null,
                        foregroundColor: _section == section
                            ? accent
                            : mutedText,
                        minimumSize: const Size(0, 44),
                      ),
                      onPressed: () => _openSection(section),
                      child: Text(section.label),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final connected = c?.config != null;
    final logged = c?.loggedIn ?? false;
    final busy = (c?.busy ?? false) || _connecting;
    final compact =
        MediaQuery.sizeOf(context).width < 480 ||
        MediaQuery.textScalerOf(context).scale(14) > 20;
    return Scaffold(
      appBar: AppBar(
        title: const BrandMark(),
        actions: [
          if (connected && !logged)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: compact
                  ? IconButton(
                      tooltip: 'Kết nối ví / Đăng nhập',
                      onPressed: busy ? null : () => _login(c!),
                      icon: const Icon(Icons.account_balance_wallet_outlined),
                    )
                  : FilledButton.icon(
                      onPressed: busy ? null : () => _login(c!),
                      icon: const Icon(Icons.account_balance_wallet_outlined),
                      label: const Text('Kết nối ví / Đăng nhập'),
                    ),
            ),
          if (connected)
            IconButton(
              tooltip: 'Làm mới trạng thái',
              onPressed: busy ? null : () => _run(c!.refresh),
              icon: const Icon(Icons.refresh),
            ),
          if (connected)
            IconButton(
              tooltip: logged ? 'Tài khoản ví' : 'Thông tin thanh toán',
              onPressed: () => _accountDetails(c!),
              icon: Icon(
                logged ? Icons.account_circle_outlined : Icons.info_outline,
              ),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _navigation(),
            SizedBox(
              height: 2,
              child: busy ? const LinearProgressIndicator() : null,
            ),
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1160),
                  child: ListView(
                    key: ValueKey(_section),
                    padding: EdgeInsets.fromLTRB(
                      compact ? 14 : 24,
                      18,
                      compact ? 14 : 24,
                      32,
                    ),
                    children: [
                      if (!widget.autoConnect &&
                          widget.controller == null &&
                          !connected)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: TextField(
                            controller: _apiUrl,
                            enabled: !busy,
                            decoration: const InputDecoration(
                              labelText: 'API URL',
                            ),
                          ),
                        ),
                      if (_connectionError case final message?)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Semantics(
                            liveRegion: true,
                            child: Text(
                              message,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        ),
                      if (c != null && c.notice.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Semantics(
                            liveRegion: true,
                            child: Text(c.notice),
                          ),
                        ),
                      ..._currentSection(c, busy),
                      if (connected && _section == _Section.catalog)
                        const Padding(
                          padding: EdgeInsets.only(top: 18),
                          child: Text(
                            'Các khoản hiển thị bằng mUSDC trên mạng thử nghiệm.',
                            style: TextStyle(color: mutedText),
                          ),
                        ),
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

  @override
  void dispose() {
    _poll?.cancel();
    _controller?.removeListener(_changed);
    _controller?.dispose();
    _apiUrl.dispose();
    super.dispose();
  }
}
