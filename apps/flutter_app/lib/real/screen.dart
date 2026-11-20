import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app/prepaid_guard_theme.dart';
import '../features/plans/demo_plan.dart';
import '../shared/widgets/brand_mark.dart';
import 'api.dart';
import 'club_dashboard.dart';
import 'controller.dart';
import 'plan_cashflow_preview.dart';
import 'escrow_summary_card.dart';
import 'subscription_details.dart';
import 'wallet.dart';

enum _Section {
  catalog('Trang chủ', Icons.home_outlined),
  shop('Gói dịch vụ', Icons.sell_outlined),
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
    '$creditUnit mỗi kỳ': '',
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

  String? _planStateFilter;
  bool _pendingOnly = false;
  String? _catalogMerchant;
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
      _planStateFilter = null;
      _pendingOnly = false;
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
    const amountField = '$creditUnit mỗi kỳ';
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
                    'Tổng khóa trả trước: $total $creditUnit ($unit $creditUnit/kỳ × $periods kỳ)',
                    style: const TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                else if (unit != null)
                  Text(
                    '$unit $creditUnit/kỳ',
                    style: const TextStyle(color: accent),
                  ),
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
        ? '${_money(p['release_amount'])} $creditUnit'
        : '—';
    final remainingText = p['remaining_principal'] != null
        ? '${_money(p['remaining_principal'])} $creditUnit'
        : '—';
    final warning = p['warning'] as String?;
    final details = [
      'Đăng ký #${p['subscription_id']} (Gói ${p['plan_id']})',
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
              'Tiền gốc còn lại trong Vault: ${_money(sub['remaining_principal'])} $creditUnit',
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
                              'Yêu cầu hoàn phần tiền gốc chưa dùng khi tới mốc theo điều khoản của gói. Gốc còn lại: ${_money(sub['remaining_principal'])} $creditUnit.',
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

  Future<void> _reviewDraft(LiveController c, Json draft) async {
    final terms = [
      'Gói: ${draft['title']}',
      if (draft['price_per_period'] != null) ...[
        'Mỗi kỳ: ${_money(draft['price_per_period'])} $creditUnit × ${draft['total_periods']} kỳ = Tổng ${_money(draft['total_price'])} $creditUnit',
        'Thời lượng kỳ: ${_duration(draft['period_duration_seconds'])} · Ân hạn hoàn gốc: ${_duration(draft['grace_period_seconds'])}',
      ],
      'Sau khi công bố, điều khoản của gói được cố định. Ví cơ sở xác nhận giao dịch và trả phí mạng.',
    ];
    final account = c.account;
    if (await _confirm('Kiểm tra và công bố gói', terms.join('\n\n')) &&
        mounted &&
        _controller == c &&
        c.account == account) {
      await _run(() => c.publishDraft(draft));
    }
  }

  List<Widget> _businessSection(LiveController c, bool busy) => [
    if (c.isMerchant)
      ListTile(
        leading: const Icon(Icons.event_note),
        title: const Text('Cập nhật chi nhánh'),
        subtitle: const Text(
          'Lịch lớp, huấn luyện viên, số hội viên và thông báo',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _clubPage(ClubView.publish),
      ),
    if (!c.isMerchant) _sectionHeader('Cơ sở của bạn'),
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
      _serviceBanner(
        title: 'Vận hành cơ sở',
        description:
            'Tiếp nhận hội viên, xác nhận lượt sử dụng và theo dõi các khoản thanh toán theo kỳ.',
        image: 'assets/gym-referral.jpg',
        action: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: accent,
              ),
              onPressed: busy ? null : _importQr,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Nhập QR check-in'),
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Color(0xffafddec)),
              ),
              onPressed: busy ? null : _createPlan,
              icon: const Icon(Icons.add),
              label: const Text('Tạo gói dịch vụ'),
            ),
          ],
        ),
      ),
      _heading('Gói của cơ sở'),
      if (c.drafts.isNotEmpty || _planStateFilter != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final (state, label) in <(String?, String)>[
                (null, 'Tất cả gói'),
                ('DRAFT', 'Bản nháp'),
                ('PUBLISHED', 'Đã công bố'),
              ])
                ChoiceChip(
                  label: Text(label),
                  selected: _planStateFilter == state,
                  onSelected: (_) => setState(() => _planStateFilter = state),
                ),
            ],
          ),
        ),
      if (c.drafts.isEmpty)
        const Text(
          'Gói đã lưu và gói đã công bố sẽ xuất hiện ở đây.',
          style: TextStyle(color: mutedText),
        )
      else if (_planStateFilter != null &&
          !c.drafts.any((item) => item['state'] == _planStateFilter))
        Text(
          c.draftsCursor != null
              ? 'Chưa có gói khớp trong phần đã tải.'
              : 'Chưa có gói ở trạng thái đã chọn.',
          style: const TextStyle(color: mutedText),
        ),
      for (final draft in c.drafts.where(
        (item) => _planStateFilter == null || item['state'] == _planStateFilter,
      ))
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      AccentIcon(
                        draft['state'] == 'DRAFT'
                            ? Icons.edit_note
                            : Icons.storefront_outlined,
                        size: 38,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          draft['state'] == 'DRAFT'
                              ? 'Bản nháp: ${draft['title']}'
                              : _planName(draft),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                  if (draft['price_per_period'] != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      '${_money(draft['price_per_period'])} $creditUnit/kỳ × ${draft['total_periods']} kỳ · Tổng ${_money(draft['total_price'])} $creditUnit',
                    ),
                    Text(
                      'Mỗi kỳ ${_duration(draft['period_duration_seconds'])} · Ân hạn ${_duration(draft['grace_period_seconds'])}',
                      style: const TextStyle(color: mutedText),
                    ),
                  ],
                  if (draft['state'] == 'DRAFT')
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: busy ? null : () => _reviewDraft(c, draft),
                        icon: const Icon(Icons.publish_outlined),
                        label: const Text('Công bố bản nháp'),
                      ),
                    )
                  else if (draft['state'] == 'PUBLISHED')
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Đang mở đăng ký',
                        style: TextStyle(color: accent),
                      ),
                    ),
                ],
              ),
            ),
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
          style: const TextStyle(color: Color(0xff895008)),
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
    return title == null ||
            title.isEmpty ||
            (title == 'Plan #$id' || title == 'Gói #$id')
        ? (id == null ? 'Gói dịch vụ' : 'Gói $id')
        : title;
  }

  String _providerName(Json plan) {
    final merchant = plan['merchant'] as Map?;
    final name = merchant?['business_name']?.toString().trim();
    return name == null || name.isEmpty ? 'Cơ sở cung cấp dịch vụ' : name;
  }

  Future<bool> _login(LiveController c) async {
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
      if (selected == null || !mounted || _controller != c) return false;
      c.wallet.selectProvider(selected);
    }
    var completed = false;
    await _run(() async {
      await c.login();
      completed = true;
    });
    return completed && c.loggedIn;
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
                'Tín dụng PrepaidGuard được hiển thị bằng $creditUnit. Trên mạng thử nghiệm, $testnetCreditRate.',
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
    color: const Color(0xffeaf8fd),
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

  Widget _serviceBanner({
    required String title,
    required String description,
    required String image,
    Widget? action,
  }) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 680;
      return ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: SizedBox(
          width: double.infinity,
          child: Stack(
            children: [
              Positioned.fill(
                child: ColoredBox(
                  color: const Color(0xff094864),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FractionallySizedBox(
                      widthFactor: wide ? .56 : 1,
                      heightFactor: 1,
                      child: Image.asset(
                        image,
                        fit: BoxFit.cover,
                        alignment: const Alignment(.35, -.15),
                        excludeFromSemantics: true,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xff094864),
                        wide
                            ? const Color(0xff094864)
                            : const Color(0xe6094864),
                        wide
                            ? const Color(0x06094864)
                            : const Color(0x99094864),
                      ],
                      stops: [0, wide ? .43 : .30, 1],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: wide ? 42 : 22,
                  vertical: wide ? 37 : 26,
                ),
                child: SizedBox(
                  width: wide ? constraints.maxWidth * .45 : double.infinity,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 42,
                        height: 4,
                        color: const Color(0xff65dcff),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        title,
                        style: Theme.of(context).textTheme.headlineLarge
                            ?.copyWith(
                              color: Colors.white,
                              height: 1.12,
                              fontSize: wide ? 42 : 31,
                            ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        description,
                        style: const TextStyle(
                          color: Color(0xffeffbff),
                          height: 1.5,
                        ),
                      ),
                      if (action != null) ...[
                        const SizedBox(height: 16),
                        action,
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
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
    final description = plan['description']?.toString().trim() ?? '';
    final confirmed =
        await _withModal<bool?>(
          () => showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              scrollable: true,
              title: Text('Đăng ký ${_planName(plan)}'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _providerName(plan),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (location != null && location.isNotEmpty) Text(location),
                    if (description.isNotEmpty)
                      Text(
                        description,
                        style: const TextStyle(color: mutedText),
                      ),
                    const SizedBox(height: 16),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: panelRaised,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Tổng trả trước: ${_money(plan['total_price'])} $creditUnit',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Mỗi kỳ: ${_money(plan['price_per_period'])} $creditUnit · ${plan['total_periods']} kỳ',
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Lịch thanh toán',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      'Mỗi kỳ kéo dài ${_duration(plan['period_duration_seconds'])}. Kỳ đầu mở sau thời lượng này kể từ lúc đăng ký. Cơ sở nhận tiền sau khi xác nhận bạn đã sử dụng dịch vụ.',
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Điều kiện hoàn tiền',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      'Bạn có thể yêu cầu hoàn phần gốc chưa dùng khi kết thúc ${_duration(plan['grace_period_seconds'])} ân hạn của kỳ tiếp theo.',
                    ),
                    const Divider(height: 26),
                    Text(
                      'Ví thanh toán: ${_money(plan['total_price'])} mUSDC trên mạng thử nghiệm ($testnetCreditRate). Ví có thể yêu cầu cấp quyền sử dụng mUSDC trước khi đăng ký.',
                      style: const TextStyle(color: mutedText),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.play_circle_outline),
                      label: const Text('Thử quy trình không dùng token'),
                      onPressed: () {
                        final total = BigInt.parse(
                          plan['total_price'].toString(),
                        );
                        final unit = BigInt.parse(
                          plan['price_per_period'].toString(),
                        );
                        var step = 0;
                        showDialog<void>(
                          context: context,
                          builder: (dialog) => StatefulBuilder(
                            builder: (_, update) => AlertDialog(
                              title: const Text('Thử quy trình đăng ký'),
                              content: Text(
                                [
                                  'Mô phỏng trên máy. Thử đăng ký gói ${formatTokenAmount(total)} PG Credit.',
                                  'Đã đăng ký mô phỏng. Thử xác nhận sử dụng dịch vụ kỳ đầu.',
                                  'Kết quả mô phỏng kỳ đầu\nCơ sở nhận: ${formatTokenAmount(unit)} PG Credit\nGốc còn giữ: ${formatTokenAmount(total - unit)} PG Credit',
                                ][step],
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(dialog),
                                  child: const Text('Đóng'),
                                ),
                                if (step < 2)
                                  FilledButton(
                                    onPressed: () => update(() => step++),
                                    child: Text(
                                      step == 0
                                          ? 'Thử đăng ký'
                                          : 'Thử xác nhận kỳ đầu',
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    if (logged && account != null)
                      TextButton.icon(
                        icon: const Icon(Icons.copy),
                        label: const Text('Sao chép địa chỉ nhận mUSDC thử'),
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: account));
                          if (context.mounted)
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Đã sao chép địa chỉ ví Fuji.'),
                              ),
                            );
                        },
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Hủy'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(
                    logged ? 'Tiếp tục ký ví' : 'Kết nối ví để đăng ký',
                  ),
                ),
              ],
            ),
          ),
        ) ??
        false;
    if (!confirmed || !mounted || _controller != c || c.account != account) {
      return;
    }
    if (logged) {
      await _run(() => c.subscribe(plan));
    } else if (await _login(c) &&
        mounted &&
        _controller == c &&
        (_section == _Section.catalog || _section == _Section.shop)) {
      final refreshed = c.plans
          .where((item) => item['plan_id'] == plan['plan_id'])
          .firstOrNull;
      if (refreshed == null) {
        _showError(
          StateError(
            'Gói vừa chọn chưa có trong danh mục mới. Hãy mở lại gói trước khi đăng ký.',
          ),
        );
      } else {
        await _reviewPlan(c, refreshed);
      }
    }
  }

  Widget _trainingIdeas() {
    const offers = [
      (
        title: 'Gym linh hoạt',
        periods: 3,
        price: 40,
        photo: 'assets/gym-referral.jpg',
      ),
      (
        title: 'Yoga chuyên sâu',
        periods: 6,
        price: 35,
        photo: 'assets/club-session.jpg',
      ),
    ];
    return LayoutBuilder(
      builder: (context, box) => Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final offer in offers)
            SizedBox(
              width: box.maxWidth >= 640
                  ? (box.maxWidth - 12) / 2
                  : box.maxWidth,
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(
                      offer.photo,
                      width: 64,
                      height: 56,
                      fit: BoxFit.cover,
                    ),
                  ),
                  title: Text(offer.title),
                  subtitle: Text(
                    '${offer.periods} tháng · ${offer.periods * offer.price} $creditUnit',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      scrollable: true,
                      title: Text(offer.title),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Gói tham khảo · ${offer.periods} kỳ, mỗi kỳ một tháng. Tổng trả trước dự kiến ${offer.periods * offer.price} $creditUnit.',
                          ),
                          const SizedBox(height: 12),
                          PlanCashflowPreview(
                            periods: offer.periods,
                            unit: parseTokenAmount(offer.price.toString())!,
                          ),
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Đóng'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _planCard(LiveController c, Json plan, bool busy) {
    final theme = Theme.of(context);
    final description = plan['description']?.toString().trim() ?? '';
    final overview = Container(
      alignment: Alignment.bottomLeft,
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 16),
      constraints: const BoxConstraints(minHeight: 118),
      decoration: const BoxDecoration(
        color: Color(0xff103442),
        image: DecorationImage(
          image: AssetImage('assets/gym-hero.jpg'),
          fit: BoxFit.cover,
          alignment: Alignment.centerRight,
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xeb12323f),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _planName(plan),
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '${plan['total_periods']} kỳ · ${_duration(plan['period_duration_seconds'])}/kỳ',
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
    final pricing = Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 14),
          if (description.isNotEmpty) ...[
            Text(description),
            const SizedBox(height: 8),
          ],
          if ((plan['merchant'] as Map?)?['business_name'] != null)
            Text(_providerName(plan), style: theme.textTheme.labelMedium),
          const Text('Tổng trả trước', style: TextStyle(color: mutedText)),
          Text(
            '${_money(plan['total_price'])} $creditUnit',
            style: theme.textTheme.headlineMedium?.copyWith(color: accent),
          ),
          Text(
            '${_money(plan['price_per_period'])} $creditUnit/kỳ · Ân hạn ${_duration(plan['grace_period_seconds'])}',
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
                                'vault': c.config!['vault_address'].toString(),
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
    );
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [overview, pricing],
    );
    final count = int.tryParse(plan['total_periods'].toString());
    final unit = BigInt.tryParse(plan['price_per_period'].toString());
    final total = BigInt.tryParse(plan['total_price'].toString());
    final preview =
        count != null &&
            count > 0 &&
            unit != null &&
            unit > BigInt.zero &&
            total == unit * BigInt.from(count)
        ? PlanCashflowPreview(
            key: ValueKey(plan['plan_id']),
            periods: count,
            unit: unit,
          )
        : null;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, box) {
          if (preview == null) return info;
          if (box.maxWidth >= 720) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: info),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 16, 16, 16),
                    child: preview,
                  ),
                ),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_section != _Section.catalog ||
                  _entryUri.queryParameters.containsKey('plan_id'))
                info,
              Padding(padding: const EdgeInsets.all(12), child: preview),
              if (_section == _Section.catalog &&
                  !_entryUri.queryParameters.containsKey('plan_id'))
                info,
            ],
          );
        },
      ),
    );
  }

  Future<void> _homeCheckIn(LiveController? c) async {
    _openSection(_Section.memberships);
    if (c == null || c.config == null || c.busy) return;
    if (!c.loggedIn) await _login(c);
  }

  String? _merchantKey(Json plan) =>
      plan['merchant_address']?.toString().toLowerCase();

  Future<void> _chooseClub(LiveController c) async {
    final dashboard = _clubKey.currentState;
    if (dashboard == null) return;
    if (dashboard.loading && dashboard.availableBranches.isEmpty) {
      await dashboard.refreshDirectory();
      if (!mounted || !dashboard.mounted) return;
    }
    final providers = <String, Json>{};
    for (final plan in c.plans) {
      final name = (plan['merchant'] as Map?)?['business_name']
          ?.toString()
          .trim();
      final key = _merchantKey(plan);
      if (key != null && name != null && name.isNotEmpty) providers[key] = plan;
    }
    final branches = dashboard.availableBranches;
    final choice = await _withModal(
      () => showModalBottomSheet<({Json? branch, String? provider})>(
        context: context,
        showDragHandle: true,
        useSafeArea: true,
        builder: (context) => ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: [
            Text(
              'Chọn chi nhánh',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            for (final branch in branches)
              ListTile(
                leading: const Icon(Icons.location_on_outlined, color: accent),
                title: Text(dashboard.branchLabel(branch)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () =>
                    Navigator.pop(context, (branch: branch, provider: null)),
              ),
            if (branches.isEmpty)
              const ListTile(title: Text('Chưa tải được danh sách chi nhánh.')),
            if (providers.isNotEmpty) ...[
              const Divider(),
              Text(
                'Gói theo nhà cung cấp',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              for (final entry in providers.entries)
                ListTile(
                  title: Text(_providerName(entry.value)),
                  leading: const Icon(Icons.storefront_outlined),
                  onTap: () => Navigator.pop(context, (
                    branch: null,
                    provider: entry.key,
                  )),
                ),
            ],
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice.branch case final branch?) {
      if (dashboard.mounted) {
        await dashboard.selectBranch(branch);
        if (dashboard.mounted)
          await Scrollable.ensureVisible(
            dashboard.context,
            duration: const Duration(milliseconds: 250),
          );
      }
    } else {
      setState(() => _catalogMerchant = choice.provider);
      _openSection(_Section.shop);
    }
  }

  final _clubKey = GlobalKey<ClubDashboardState>();
  Future<void> _clubLogin() async {
    if (_controller?.config == null) await _connect();
    final c = _controller;
    if (mounted && c?.config != null && !c!.loggedIn) await _login(c);
  }

  Future<void> _clubPage(ClubView view) async {
    final dashboard = _clubKey.currentState;
    if (dashboard != null) {
      await dashboard.open(view);
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ClubPage(
          view: view,
          c: _controller,
          branch: null,
          login: _clubLogin,
          entry: _entryUri,
        ),
      ),
    );
  }

  Widget _catalogCover(LiveController? c, bool busy) => LayoutBuilder(
    builder: (context, box) {
      final wide = box.maxWidth >= 800;
      final member = c?.loggedIn == true;
      final title = member
          ? 'Thẻ hội viên của bạn'
          : 'Thẻ hội viên PrepaidGuard';
      final tools = [
        (
          Icons.stars_rounded,
          'Thành viên',
          () => _openSection(_Section.memberships),
        ),
        (
          Icons.sports_rounded,
          'Huấn luyện viên',
          () => _clubPage(ClubView.trainers),
        ),
        (Icons.event_available, 'Lớp học', () => _clubPage(ClubView.classes)),
      ];
      final picture = Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/club-session.jpg',
            fit: BoxFit.cover,
            alignment: wide
                ? const Alignment(0, .55)
                : const Alignment(.15, .10),
            excludeFromSemantics: true,
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.transparent,
                  Color(0x99094459),
                ],
                stops: [0, .60, 1],
              ),
            ),
          ),
          Positioned(
            top: 12,
            left: 14,
            right: 14,
            child: Row(
              children: [
                IconButton.filledTonal(
                  tooltip: 'Tài khoản',
                  style: IconButton.styleFrom(backgroundColor: Colors.white),
                  onPressed: () => _clubPage(ClubView.account),
                  icon: const Icon(Icons.person_outline),
                ),
                const Spacer(),
                IconButton.filledTonal(
                  tooltip: 'Thông báo',
                  style: IconButton.styleFrom(backgroundColor: Colors.white),
                  onPressed: () => _clubPage(ClubView.notices),
                  icon: const Icon(Icons.notifications_none),
                ),
              ],
            ),
          ),
          Positioned(
            left: 14,
            right: 14,
            bottom: wide ? 18 : 32,
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 5,
              children: [
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: accent,
                  ),
                  onPressed: () => _clubPage(ClubView.referral),
                  icon: const Icon(Icons.person_add_alt, size: 18),
                  label: const Text('Giới thiệu bạn'),
                ),
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: accent,
                  ),
                  onPressed: () => _clubPage(ClubView.buddies),
                  icon: const Icon(Icons.group_outlined, size: 18),
                  label: const Text('Kết nối bạn tập'),
                ),
              ],
            ),
          ),
        ],
      );
      final pass = Material(
        color: panel,
        elevation: 4,
        shadowColor: const Color(0x291c5369),
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: 245,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    backgroundColor: const Color(0xff007fa6),
                  ),
                  onPressed: busy ? null : () => _homeCheckIn(c),
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Check-in'),
                ),
              ),
            ],
          ),
        ),
      );
      final tiles = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (icon, label, action) in tools)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Material(
                  color: panel,
                  borderRadius: BorderRadius.circular(14),
                  elevation: 2,
                  shadowColor: const Color(0x2216546b),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: action,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 3,
                        vertical: 12,
                      ),
                      child: Column(
                        children: [
                          Icon(icon, size: 32, color: cyan),
                          const SizedBox(height: 5),
                          Text(
                            label,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
      if (wide) {
        return Row(
          children: [
            Expanded(
              flex: 6,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(height: 254, child: picture),
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [pass, const SizedBox(height: 14), tiles],
              ),
            ),
          ],
        );
      }
      final photoHeight = (box.maxWidth * .85).clamp(220.0, 350.0);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              SizedBox(
                height: photoHeight,
                width: double.infinity,
                child: picture,
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(18, photoHeight - 19, 18, 0),
                child: SizedBox(width: double.infinity, child: pass),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 18, 14, 2),
            child: tiles,
          ),
        ],
      );
    },
  );

  Widget _figure(String label, String value, IconData icon) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    child: Column(
      children: [
        Icon(icon, color: cyan, size: 25),
        const SizedBox(height: 6),
        Text(value, style: Theme.of(context).textTheme.titleLarge),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(color: mutedText),
        ),
      ],
    ),
  );

  Widget _shopHeader(LiveController? c) {
    final loaded = c?.config != null && !c!.catalogUnavailable;
    final providers = c?.plans
        .map((p) => p['merchant_address']?.toString().toLowerCase())
        .whereType<String>()
        .toSet();
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xff007da9), Color(0xff004458)],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Khám phá gói dịch vụ',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Row(
                children: [
                  Expanded(
                    child: _figure(
                      'Gói đã tải',
                      loaded ? '${c.plans.length}' : '—',
                      Icons.sell_outlined,
                    ),
                  ),
                  const SizedBox(height: 48, child: VerticalDivider(width: 1)),
                  Expanded(
                    child: _figure(
                      'Cơ sở trong danh sách',
                      loaded ? '${providers!.length}' : '—',
                      Icons.storefront_outlined,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _catalog(LiveController? c, bool busy) => [
    if (_section == _Section.shop)
      _shopHeader(c)
    else if (_entryUri.queryParameters.containsKey('plan_id'))
      _sectionHeader('Khám phá gói dịch vụ')
    else ...[
      _catalogCover(c, busy),
      if (_entryUri.queryParameters['ref']?.isNotEmpty == true)
        const ListTile(
          leading: Icon(Icons.person_add_alt, color: accent),
          title: Text('Bạn được mời khám phá PrepaidGuard'),
          subtitle: Text('Chọn cơ sở hoặc xem gói dịch vụ để bắt đầu.'),
        ),

      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          children: [
            TextButton(
              onPressed: () => _openSection(_Section.shop),
              child: const Text('Khám phá gói dịch vụ'),
            ),
            if (c?.config != null)
              TextButton(
                onPressed: () => _chooseClub(c!),
                child: const Text('Tìm cơ sở'),
              ),
          ],
        ),
      ),
      ClubDashboard(
        key: _clubKey,
        controller: c,
        login: _clubLogin,
        entry: _entryUri,
      ),
    ],
    if (_section == _Section.shop && _catalogMerchant != null)
      Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Chip(
                avatar: const Icon(Icons.storefront_outlined, size: 18),
                label: Text(
                  c?.plans
                          .where((p) => _merchantKey(p) == _catalogMerchant)
                          .map(_providerName)
                          .firstOrNull ??
                      'Cơ sở đã chọn',
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _catalogMerchant = null),
                child: const Text('Hiện tất cả cơ sở'),
              ),
            ],
          ),
        ),
      ),
    _heading('Gói đang mở đăng ký'),
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
          final wide = constraints.maxWidth >= 730 && c.plans.length > 1;
          final width = wide
              ? (constraints.maxWidth - 16) / 2
              : constraints.maxWidth;
          return Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              if (_section == _Section.shop &&
                  _catalogMerchant != null &&
                  !c.plans.any((p) => _merchantKey(p) == _catalogMerchant))
                const Text('Chưa có gói của cơ sở này trong danh sách đã tải.'),
              for (final plan in c.plans.where(
                (p) =>
                    _section != _Section.shop ||
                    _catalogMerchant == null ||
                    _merchantKey(p) == _catalogMerchant,
              ))
                SizedBox(
                  key: ValueKey(plan['plan_id']),
                  width: width,
                  child: _planCard(c, plan, busy),
                ),
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
    if (c?.config != null) ...[
      const Padding(
        padding: EdgeInsets.only(top: 12),
        child: Text(
          'Các khoản hiển thị bằng $creditUnit. Trên mạng thử nghiệm, $testnetCreditRate.',
          style: TextStyle(color: mutedText),
        ),
      ),
    ],
    if (_catalogMerchant == null) ...[
      _heading('Gói tập tham khảo'),
      _trainingIdeas(),
    ],
    if (c?.config != null) ...[
      _heading('Hướng dẫn sử dụng gói'),
      LayoutBuilder(
        builder: (context, box) {
          final width = box.maxWidth >= 660
              ? (box.maxWidth - 12) / 2
              : box.maxWidth;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final (title, image, icon, body) in [
                (
                  'Check-in tại cơ sở',
                  'assets/gym-referral.jpg',
                  Icons.qr_code_scanner,
                  'Trong Gói của tôi, chọn gói đang sử dụng và bấm Tạo QR check-in khi kỳ đủ điều kiện. Kiểm tra nội dung trước khi ký trong ví. Xuất trình mã cho cơ sở xác nhận lượt sử dụng.',
                ),
                (
                  'Xem điều kiện hoàn tiền',
                  'assets/gym-hero.jpg',
                  Icons.account_balance_wallet_outlined,
                  'Mở gói đã đăng ký để xem tiền gốc còn lại và mốc có thể yêu cầu hoàn. Sau thời gian ân hạn của kỳ chưa sử dụng, chọn Yêu cầu hoàn gốc và kiểm tra số tiền trước khi ký trong ví.',
                ),
              ])
                SizedBox(
                  width: width,
                  child: Card(
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () async {
                        final open = await _confirm(
                          title,
                          body,
                          confirmLabel: 'Mở gói của tôi',
                        );
                        if (open && mounted) _openSection(_Section.memberships);
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AspectRatio(
                            aspectRatio: 2.6,
                            child: Image.asset(
                              image,
                              fit: BoxFit.cover,
                              excludeFromSemantics: true,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Icon(icon, color: accent),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    title,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                ),
                                const Icon(
                                  Icons.arrow_forward,
                                  size: 18,
                                  color: accent,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
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
        style: const TextStyle(color: Color(0xff895008)),
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
    Card(
      child: Row(
        children: [
          Expanded(
            child: _figure(
              'Giao dịch đã gửi',
              '${c.pending.length}',
              Icons.receipt_long_outlined,
            ),
          ),
          const SizedBox(height: 48, child: VerticalDivider(width: 1)),
          Expanded(
            child: _figure(
              'Chờ xác nhận',
              '${c.pending.where((i) => i['status'] == 'SUBMITTED').length}',
              Icons.schedule,
            ),
          ),
        ],
      ),
    ),
    Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Wrap(
        spacing: 8,
        children: [
          for (final pending in [false, true])
            ChoiceChip(
              label: Text(pending ? 'Đang chờ' : 'Tất cả'),
              selected: _pendingOnly == pending,
              onSelected: (_) => setState(() => _pendingOnly = pending),
            ),
        ],
      ),
    ),
    if (_pendingOnly && !c.pending.any((i) => i['status'] == 'SUBMITTED'))
      _emptyState(
        Icons.task_alt,
        'Không có giao dịch đang chờ',
        'Chọn Tất cả để xem lịch sử giao dịch của ví.',
      )
    else if (c.pending.isEmpty)
      _emptyState(
        Icons.receipt_long_outlined,
        'Chưa có giao dịch để theo dõi',
        'Sau khi bạn gửi giao dịch, trạng thái xác nhận sẽ hiển thị tại đây.',
      ),
    for (final item in c.pending.where(
      (item) => !_pendingOnly || item['status'] == 'SUBMITTED',
    ))
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
    if (_section == _Section.catalog || _section == _Section.shop)
      return _catalog(c, busy);
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
      if (_section == _Section.business) {
        return [
          _sectionHeader('Cơ sở của bạn'),
          _serviceBanner(
            title: 'Đăng nhập để tiếp tục',
            description: description,
            image: 'assets/gym-referral.jpg',
            action: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: accent,
              ),
              onPressed: busy ? null : () => _login(c),
              icon: const Icon(Icons.account_balance_wallet_outlined),
              label: const Text('Kết nối ví'),
            ),
          ),
        ];
      }
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
      _Section.catalog || _Section.shop => _catalog(c, busy),
    };
  }

  Widget _navigation({required bool mobile}) {
    final tabs = [
      for (final section in _Section.values)
        Semantics(
          selected: section == _section,
          child: TextButton(
            style: TextButton.styleFrom(
              foregroundColor: section == _section ? accent : mutedText,
              backgroundColor: section == _section && !mobile
                  ? panelRaised
                  : null,
              minimumSize: const Size(0, 44),
              padding: EdgeInsets.symmetric(
                horizontal: mobile ? 3 : 14,
                vertical: 6,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => _openSection(section),
            child: mobile
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 22,
                        height: 3,
                        decoration: BoxDecoration(
                          color: section == _section
                              ? cyan
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Icon(section.icon, size: 21),
                      const SizedBox(height: 3),
                      Text(
                        section.label,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(section.icon, size: 18),
                      const SizedBox(width: 8),
                      Text(section.label),
                    ],
                  ),
          ),
        ),
    ];
    return Material(
      color: panel,
      child: SafeArea(
        top: false,
        bottom: mobile,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: mobile ? 4 : 10,
            vertical: 5,
          ),
          child: mobile
              ? Row(children: [for (final tab in tabs) Expanded(child: tab)])
              : Wrap(spacing: 4, children: tabs),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final connected = c?.config != null;
    final logged = c?.loggedIn ?? false;
    final busy = (c?.busy ?? false) || _connecting;
    final compact =
        MediaQuery.sizeOf(context).width < 480 ||
        MediaQuery.textScalerOf(context).scale(14) > 20;
    final width = MediaQuery.sizeOf(context).width;
    final photoHeader =
        width < 680 &&
        _section == _Section.catalog &&
        !_entryUri.queryParameters.containsKey('plan_id');
    return Scaffold(
      bottomNavigationBar: _navigation(mobile: true),
      appBar: photoHeader
          ? null
          : AppBar(
              title: const BrandMark(),
              actions: [
                if (connected && !logged)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: compact
                        ? IconButton(
                            tooltip: 'Kết nối ví / Đăng nhập',
                            onPressed: busy ? null : () => _login(c!),
                            icon: const Icon(
                              Icons.account_balance_wallet_outlined,
                            ),
                          )
                        : FilledButton.icon(
                            onPressed: busy ? null : () => _login(c!),
                            icon: const Icon(
                              Icons.account_balance_wallet_outlined,
                            ),
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
                      logged
                          ? Icons.account_circle_outlined
                          : Icons.info_outline,
                    ),
                  ),
                const SizedBox(width: 4),
              ],
            ),
      body: SafeArea(
        child: Column(
          children: [
            if (_connecting)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 5),
                child: Text('Đang kết nối dịch vụ và tải danh sách gói…'),
              ),
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
                      photoHeader
                          ? 0
                          : compact
                          ? 14
                          : 24,
                      photoHeader ? 0 : 18,
                      photoHeader
                          ? 0
                          : compact
                          ? 14
                          : 24,
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
                      for (final (index, item) in _currentSection(
                        c,
                        busy,
                      ).indexed)
                        if (photoHeader && index != 0)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: item,
                          )
                        else
                          item,
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
