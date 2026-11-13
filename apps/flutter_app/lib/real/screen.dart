import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../features/plans/demo_plan.dart';
import 'api.dart';
import 'controller.dart';
import 'wallet.dart';

class RealWorkspaceScreen extends StatefulWidget {
  const RealWorkspaceScreen({super.key, required this.onDemo, this.controller});
  final VoidCallback onDemo;
  final LiveController? controller;
  @override
  State<RealWorkspaceScreen> createState() => _RealWorkspaceScreenState();
}

class _RealWorkspaceScreenState extends State<RealWorkspaceScreen> {
  final _apiUrl = TextEditingController(
    text: const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://localhost:8000',
    ),
  );
  LiveController? _controller;
  Timer? _poll;
  bool _connecting = false;
  int _modalDepth = 0;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller;
    _controller?.addListener(_changed);
    _poll = Timer.periodic(const Duration(seconds: 8), (_) {
      final c = _controller;
      if (c != null &&
          !_connecting &&
          _modalDepth == 0 &&
          c.loggedIn &&
          !c.busy &&
          c.pending.any((item) => item['status'] == 'SUBMITTED')) {
        _run(() => c.refresh());
      }
    });
  }

  void _changed() {
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
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      final c = _controller;
      if (c == null) {
        await action();
      } else {
        await c.operation(action);
      }
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _connect() async {
    if (_connecting) return;
    setState(() => _connecting = true);
    try {
      final api = HttpApi(_apiUrl.text.trim());
      final c = LiveController(
        api: api,
        wallet: createWallet(),
        store: createPendingStore(),
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
        await c.openRegistration(Uri.base);
      });
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<Map<String, String>?> _form(
    String title,
    Map<String, String> fields,
  ) async {
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final entry in controllers.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: TextField(
                      controller: entry.value,
                      decoration: InputDecoration(labelText: entry.key),
                      maxLines: entry.key == 'QR payload' ? 6 : 1,
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, {
              for (final entry in controllers.entries)
                entry.key: entry.value.text.trim(),
            }),
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
    final fields = await _form('Tạo hồ sơ cơ sở', {'Tên cơ sở': ''});
    if (fields != null)
      await _run(() => _controller!.createMerchant(fields['Tên cơ sở']!));
  }

  Future<void> _createPlan() async {
    final fields = await _form('Tạo gói on-chain', {
      'Tên gói': 'Gym demo',
      'Mô tả': 'Gói thử nghiệm',
      'USDC mỗi kỳ': '50',
      'Số kỳ': '2',
      'Giây mỗi kỳ': '60',
      'Giây ân hạn': '120',
    });
    if (fields == null) return;
    await _run(() async {
      final amount = parseTokenAmount(fields['USDC mỗi kỳ']!);
      final periods = int.tryParse(fields['Số kỳ']!);
      final duration = int.tryParse(fields['Giây mỗi kỳ']!);
      final grace = int.tryParse(fields['Giây ân hạn']!);
      if (amount == null ||
          periods == null ||
          periods < 1 ||
          periods > 120 ||
          duration == null ||
          duration < 1 ||
          grace == null ||
          grace < 1 ||
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
    });
  }

  Future<bool> _confirm(String title, String message) async =>
      await _withModal<bool?>(
        () => showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(message),
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
  Future<void> _qr(String title, String payload) async {
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
                  const Text(
                    'Mã check-in có hạn 15 phút. Tạo lại mã không thu hồi mã cũ chưa dùng; contract chỉ tiêu thụ nonce một lần.',
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Clipboard.setData(ClipboardData(text: payload)),
              child: const Text('Sao chép payload'),
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
    await _qr('QR check-in ký số', payload);
  });
  Future<void> _importQr() async {
    final fields = await _form('Nhập QR check-in', {'QR payload': ''});
    if (fields == null) return;
    if (!await _confirm(
      'Giải ngân một kỳ',
      'Kiểm tra payload của khách. Sau bước kiểm chứng, ví merchant sẽ yêu cầu ký giao dịch và trả gas.',
    ))
      return;
    await _run(() => _controller!.confirmQr(fields['QR payload']!));
  }

  Future<void> _showDetail(Json sub) async => _run(() async {
    final id = sub['subscription_id'];
    final c = _controller!;
    final data = {
      'subscription': await c.detail(id),
      'eligibility': await c.eligibility(id),
      'events': await c.events(id),
    };
    if (!mounted) return;
    await _withModal(
      () => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Gói #$id — dữ liệu API/chain'),
          content: SizedBox(
            width: 700,
            child: SingleChildScrollView(
              child: SelectableText(
                const JsonEncoder.withIndent('  ').convert(data),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Đóng'),
            ),
          ],
        ),
      ),
    );
  });
  Widget _heading(String value) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 10),
    child: Text(value, style: Theme.of(context).textTheme.titleLarge),
  );
  String _money(dynamic value) =>
      formatTokenAmount(BigInt.parse(value.toString()));
  Widget _subscription(Json sub, {required bool merchant}) {
    final active = sub['status'] == 'ACTIVE';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Subscription #${sub['subscription_id']} · ${sub['status']}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              'Gốc còn lại: ${_money(sub['remaining_principal'])} mUSDC · ${sub['completed_periods']}/${sub['total_periods']} kỳ',
            ),
            Text(
              'Kỳ tiếp: ${sub['next_release_at'] ?? '—'}\nRefund từ: ${sub['refund_available_at'] ?? '—'}',
            ),
            Text(
              'Nguồn: ${sub['sync']['source']} · block ${sub['sync']['block_number']}',
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
                    child: const Text('Refund'),
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
        title: const Text('PrePaidGuard — API / ví thật'),
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
                const Text(
                  'TESTNET · Dữ liệu thật từ API và blockchain. Ví trình duyệt EIP-1193 ký; app không giữ private key.',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _apiUrl,
                  enabled: !busy && !logged,
                  decoration: const InputDecoration(
                    labelText: 'API URL',
                    hintText: 'http://localhost:8000',
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    FilledButton(
                      onPressed: busy ? null : _connect,
                      child: const Text('Kết nối API'),
                    ),
                    if (connected && !logged)
                      FilledButton(
                        onPressed: busy ? null : () => _run(() => c!.login()),
                        child: const Text('Kết nối ví / Đăng nhập'),
                      ),
                    if (connected)
                      OutlinedButton(
                        onPressed: busy ? null : () => _run(() => c!.refresh()),
                        child: const Text('Refresh trạng thái'),
                      ),
                    if (logged)
                      TextButton(
                        onPressed: busy ? null : () => _run(() => c!.logout()),
                        child: const Text('Đăng xuất ví'),
                      ),
                  ],
                ),
                if (busy)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: LinearProgressIndicator(),
                  ),
                if (c?.notice.isNotEmpty ?? false) Text(c!.notice),
                if (connected)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: SelectableText(
                      'Chain: ${c!.config!['chain_id']} · Deployment: ${c.config!['deployment_id']}\nVault: ${c.config!['vault_address']}\nYield: ${c.config!['yield_mode']} · Ví: ${c.account ?? 'chưa đăng nhập'}',
                    ),
                  ),
                if (connected) ...[
                  _heading('Gói đã publish'),
                  if (c!.plans.isEmpty) const Text('Chưa có gói đã đồng bộ.'),
                  for (final plan in c.plans)
                    Card(
                      child: ListTile(
                        title: Text(
                          '${plan['title']} · Plan #${plan['plan_id']}',
                        ),
                        subtitle: Text(
                          '${plan['total_periods']} kỳ · Tổng ${_money(plan['total_price'])} mUSDC\nKỳ ${plan['period_duration_seconds']} giây · ân hạn ${plan['grace_period_seconds']} giây',
                        ),
                        trailing: Wrap(
                          children: [
                            IconButton(
                              tooltip: 'QR đăng ký',
                              onPressed: busy
                                  ? null
                                  : () => _qr(
                                      'QR đăng ký gói',
                                      Uri.base
                                          .replace(
                                            queryParameters: {
                                              'real': '1',
                                              'plan_id': plan['plan_id'],
                                              'chain_id': c.config!['chain_id']
                                                  .toString(),
                                              'vault':
                                                  c.config!['vault_address'],
                                            },
                                          )
                                          .toString(),
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
                                        await _run(() => c.subscribe(plan));
                                      }
                                    },
                              child: const Text('Đăng ký'),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
                if (logged) ...[
                  _heading('Gói của tôi'),
                  for (final issue in c!.issues)
                    Text(
                      'Cảnh báo gói #${issue['subscription_id']}: ${issue['code']} — ${issue['message']}',
                      style: const TextStyle(color: Colors.orange),
                    ),
                  if (c.memberships.isEmpty)
                    const Text('Chưa có subscription đã đồng bộ.'),
                  for (final sub in c.memberships)
                    _subscription(sub, merchant: false),
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
                        trailing: TextButton(
                          onPressed: busy
                              ? null
                              : () => _run(() => c.publishDraft(draft)),
                          child: const Text('Publish draft'),
                        ),
                      ),
                    for (final issue in c.merchantIssues)
                      Text(
                        'Cảnh báo gói #${issue['subscription_id']}: ${issue['code']} — ${issue['message']}',
                        style: const TextStyle(color: Colors.orange),
                      ),
                    for (final sub in c.merchantMemberships)
                      _subscription(sub, merchant: true),
                  ],
                  _heading('Giao dịch của phiên / khôi phục'),
                  const Text(
                    'Hash lưu theo ví + deployment để phục hồi sau reload. JWT chỉ ở bộ nhớ; reload cần ký SIWE lại. Pending không có nghĩa đã thanh toán.',
                  ),
                  for (final item in c.pending)
                    ListTile(
                      title: Text('${item['action']} · ${item['status']}'),
                      subtitle: SelectableText(
                        '${item['tx_hash']}${item['last_error'] != null ? '\n${item['last_error']}' : ''}',
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
