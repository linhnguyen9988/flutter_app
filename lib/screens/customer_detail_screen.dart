import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'dart:io' show Platform;
import '../theme/app_theme.dart';
import '../models/customer.dart';
import '../models/live_comment.dart';
import '../models/order.dart';
import '../services/api_service.dart';
import 'chat_screen.dart';
import 'order_timeline_screen.dart';
import 'qr_scan_screen.dart';
import '../services/reload_aware_mixin.dart';

const String _mainUrl = 'https://aodaigiabao.com';

class CustomerDetailScreen extends StatefulWidget {
  final Customer customer;
  final List<String> selectedLiveIds;
  final List<LiveComment> liveComments;
  const CustomerDetailScreen({
    super.key,
    required this.customer,
    this.selectedLiveIds = const [],
    this.liveComments = const [],
  });

  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen>
    with ReloadAwareMixin<CustomerDetailScreen> {
  bool get isDark => Theme.of(context).brightness == Brightness.dark;

  late Customer _customer;
  bool _saving = false;
  final Set<String> _editingFields = {};

  bool get _editing => _editingFields.isNotEmpty;
  bool _phoneCopied = false;
  bool _isEditing(String f) => _editingFields.contains(f);
  void _startEdit(String f) => setState(() => _editingFields.add(f));
  void _stopEdit(String f) {
    setState(() => _editingFields.remove(f));
    _saveChanges(silent: true);
  }

  late TextEditingController _phoneCtrl;
  late TextEditingController _addressCtrl;
  late TextEditingController _noteCtrl;
  String _selectedLabel = '';
  late TextEditingController _tagCtrl;

  final _codCtrl = TextEditingController(text: '0');
  final _kgCtrl = TextEditingController(text: '1');
  List<Map<String, dynamic>> _savedAddresses = [];
  int _selectedAddressIndex = 0;
  Map<String, dynamic>? get _selectedAddress => _savedAddresses.isEmpty
      ? null
      : _savedAddresses[
          _selectedAddressIndex.clamp(0, _savedAddresses.length - 1)];
  bool _loadingAddresses = false;
  bool _creatingOrder = false;
  bool _printing = false;

  List<Order> _recentOrders = [];
  bool _loadingOrders = false;

  List<Map<String, dynamic>> _liveChotData = [];
  bool _loadingLiveChots = false;
  bool _includeShipLive = true;

  Map<String, dynamic>? _lastMessage;
  bool _loadingLastMsg = false;

  @override
  void initState() {
    super.initState();
    _customer = widget.customer;
    _phoneCtrl = TextEditingController(text: _customer.phone ?? '');
    _addressCtrl = TextEditingController(text: _customer.diachi ?? '');
    _noteCtrl = TextEditingController(text: _customer.note ?? '');
    _selectedLabel = _customer.label ?? '';
    _tagCtrl = TextEditingController(text: _customer.tag ?? '');
    _loadSavedAddresses();
    _loadRecentOrders();
    _loadLiveChots();
    _loadLastMessage();
  }

  @override
  void onReload() {
    _loadRecentOrders();
    _loadLiveChots();
    _loadLastMessage();
    _loadSavedAddresses();
  }

  @override
  void dispose() {
    _codCtrl.dispose();
    _kgCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _noteCtrl.dispose();
    _tagCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadLastMessage() async {
    final userid = _customer.userid ?? '';
    if (userid.isEmpty) return;
    setState(() => _loadingLastMsg = true);
    try {
      final result =
          await ApiService.getConversation(userid, limit: 1, offset: 0);
      if (mounted && result.messages.isNotEmpty) {
        setState(() => _lastMessage = result.messages.first.toJson());
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingLastMsg = false);
    }
  }

  String _lastMsgPreview(Map<String, dynamic> msg) {
    final isPage =
        (msg['sender']?.toString() ?? '') == (_customer.pageid ?? '');
    final prefix = isPage ? 'Bạn: ' : '';
    final text = (msg['message'] ?? '').toString().trim();
    final image = (msg['image'] ?? '').toString().trim();

    if (text.isNotEmpty) return '$prefix$text';

    if (image.isNotEmpty) {
      final lower = image.toLowerCase();
      final isLike = lower.contains('like') ||
          lower.contains('369239263222822') ||
          lower.contains('sticker');
      if (isLike) return '$prefix👍';
      return '${prefix}Hình ảnh';
    }

    return '$prefix(Tin nhắn)';
  }

  Future<void> _loadRecentOrders() async {
    final userid = _customer.userid ?? '';
    if (userid.isEmpty) return;
    setState(() => _loadingOrders = true);
    try {
      final orders = await ApiService.getUserOrders(userid);
      if (mounted) setState(() => _recentOrders = orders);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingOrders = false);
    }
  }

  Future<void> _loadLiveChots() async {
    final userid = _customer.userid ?? '';
    if (userid.isEmpty) return;

    if (widget.liveComments.isNotEmpty) {
      final data = widget.liveComments
          .where((c) =>
              c.userid == userid &&
              (c.chot?.toUpperCase() == 'CHỐT' ||
                  c.chot?.toUpperCase() == 'CHOT') &&
              (c.slchot ?? 0) > 0)
          .map((c) => c.toJson())
          .toList();
      if (mounted) setState(() => _liveChotData = data);
      return;
    }

    final liveIds = widget.selectedLiveIds;
    if (liveIds.isEmpty) return;
    setState(() => _loadingLiveChots = true);
    try {
      final data = await ApiService.getCustomerLiveChots(
        userid: userid,
        liveIds: liveIds,
      );
      if (mounted) setState(() => _liveChotData = data);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingLiveChots = false);
    }
  }

  String _formatOrderDate(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    try {
      final dt = DateTime.parse(raw).toLocal();
      final dd = dt.day.toString().padLeft(2, '0');
      final mm = dt.month.toString().padLeft(2, '0');
      final yy = (dt.year % 100).toString().padLeft(2, '0');
      return '$dd/$mm/$yy';
    } catch (_) {
      return raw;
    }
  }

  Future<void> _loadSavedAddresses() async {
    final phone = _customer.phone ?? '';
    if (phone.isEmpty) return;
    setState(() => _loadingAddresses = true);
    try {
      final res = await ApiService.postRaw(
        '$_mainUrl/getdiachilendon',
        {'phone': phone},
      );
      if (res != null && res['data'] != null) {
        final list = (res['data'] as List).cast<Map<String, dynamic>>();
        setState(() {
          _savedAddresses = list;
          _selectedAddressIndex = 0;
        });
      }
    } catch (_) {
    } finally {
      setState(() => _loadingAddresses = false);
    }
  }

  Future<void> _checkAddress() async {
    final address = _addressCtrl.text.trim();
    if (address.isEmpty) return;
    _snack('Đang kiểm tra địa chỉ...', AppTheme.primary);
    try {
      final res = await ApiService.postRaw(
        '$_mainUrl/checkaddress',
        {
          'phone': _customer.phone ?? '',
          'khid': _customer.id,
          'name': _customer.displayName,
          'diachi': address,
          'userid': _customer.userid ?? '',
        },
      );
      if (res == null) {
        _snack('Lỗi kết nối', Colors.red);
        return;
      }
      if (res['error'] != null) {
        _snack(res['error'].toString(), Colors.red);
        return;
      }
      final adx = res['adx']?.toString() ?? '';
      _snack('✓ $adx', AppTheme.accent);

      final newEntry = {
        'address': address,
        'phone': _customer.phone ?? '',
        'userid': _customer.userid ?? '',
        'xa': '',
        'huyen': '',
        'tinh': '',
      };
      setState(() {
        final exists =
            _savedAddresses.any((a) => a['address']?.toString() == address);
        if (!exists) _savedAddresses.insert(0, newEntry);
        final idx = _savedAddresses
            .indexWhere((a) => a['address']?.toString() == address);
        _selectedAddressIndex = idx >= 0 ? idx : 0;
      });
    } catch (e) {
      _snack('Lỗi: $e', Colors.red);
    }
  }

  String _formatCod(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return '';
    final n = int.tryParse(digits) ?? 0;
    final s = n.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  Widget _buildLiveChotBanner() {
    if (_loadingLiveChots) {
      return Row(children: [
        const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
                strokeWidth: 1.5, color: AppTheme.primary)),
        const SizedBox(width: 6),
        Text('Đang kiểm tra chốt live...',
            style:
                TextStyle(color: AppTheme.textSubColor(isDark), fontSize: 11)),
      ]);
    }

    int parsePrice(String? raw) {
      if (raw == null || raw.isEmpty) return 0;
      final cleaned = raw.replaceAll(RegExp(r'[^0-9]'), '');
      if (cleaned.isEmpty) return 0;
      int val = int.tryParse(cleaned) ?? 0;
      if (val > 0 && val < 1000) val *= 1000;
      return val;
    }

    String formatMoneyK(int n) {
      if (n == 0) return '0';
      if (n % 1000 == 0) return '${n ~/ 1000}';
      final k = n / 1000;
      final str = k.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '');
      return str;
    }

    final chotItems = _liveChotData.where((item) {
      final chot = (item['chot'] ?? '').toString().toUpperCase().trim();
      final sl = (item['slchot'] as num?)?.toInt() ?? 0;
      return (chot == 'CHỐT' || chot == 'CHOT') && sl > 0;
    }).toList();

    if (chotItems.isEmpty) {
      return Row(children: [
        Icon(Icons.live_tv_outlined,
            size: 13,
            color: AppTheme.textSubColor(isDark).withValues(alpha: 0.5)),
        const SizedBox(width: 5),
        Text('Chưa chốt trong live đang xem',
            style: TextStyle(
                color: AppTheme.textSubColor(isDark).withValues(alpha: 0.6),
                fontSize: 11)),
      ]);
    }

    final Map<int, int> priceQtyMap = {};
    int totalAmount = 0;
    int totalSl = 0;
    for (final item in chotItems) {
      final price = parsePrice((item['gia'] ?? '').toString());
      final qty = (item['slchot'] as num?)?.toInt() ?? 1;
      priceQtyMap[price] = (priceQtyMap[price] ?? 0) + qty;
      totalAmount += price * qty;
      totalSl += qty;
    }

    String buildChotMessage() {
      const pronoun = 'chị';
      final sortedPrices = priceQtyMap.keys.toList()..sort();
      final lines = <String>[];
      for (final price in sortedPrices) {
        final qty = priceQtyMap[price]!;
        final lineTotal = price * qty;
        lines.add(
            '$qty vải ${formatMoneyK(price)} = ${formatMoneyK(lineTotal)}');
      }
      const ship = 20000;
      final grandTotal = totalAmount + (_includeShipLive ? ship : 0);

      final buffer = StringBuffer();
      buffer.writeln('Đơn hàng của $pronoun:');
      for (final line in lines) {
        buffer.writeln(line);
      }
      if (_includeShipLive) {
        buffer.writeln('Phí ship 20k. Tổng ${formatMoneyK(grandTotal)}.');
      } else {
        buffer.writeln('Miễn ship. Tổng ${formatMoneyK(grandTotal)}.');
      }
      final hasAddress = _addressCtrl.text.trim().isNotEmpty;
      buffer.write(hasAddress
          ? 'Em ship hàng $pronoun nha!'
          : 'Em xin địa chỉ để gửi hàng nha!');
      return buffer.toString();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: AppTheme.primary.withValues(alpha: 0.3), width: 1),
      ),
      child: Row(children: [
        Icon(Icons.live_tv, size: 13, color: AppTheme.primary),
        const SizedBox(width: 6),
        Expanded(
          child: GestureDetector(
            onTap: _customer.userid != null && _customer.userid!.isNotEmpty
                ? () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          sender: _customer.userid!,
                          pageId: _customer.pageid ?? '',
                          initialMessage: buildChotMessage(),
                          selectedLiveIds: widget.selectedLiveIds,
                          liveComments: widget.liveComments,
                        ),
                      ),
                    )
                : null,
            child: Text(
              'Chốt được $totalSl vải trong live mới',
              style: TextStyle(
                  color: AppTheme.primary,
                  fontSize: 11.5,
                  height: 1.3,
                  fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => setState(() => _includeShipLive = !_includeShipLive),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _includeShipLive
                  ? AppTheme.accent.withValues(alpha: 0.15)
                  : AppTheme.surfaceColor(isDark),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: _includeShipLive
                    ? AppTheme.accent.withValues(alpha: 0.5)
                    : AppTheme.textSubColor(isDark).withValues(alpha: 0.3),
              ),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(
                _includeShipLive
                    ? Icons.local_shipping
                    : Icons.local_shipping_outlined,
                size: 11,
                color: _includeShipLive
                    ? AppTheme.accent
                    : AppTheme.textSubColor(isDark),
              ),
              const SizedBox(width: 3),
              Text(
                _includeShipLive ? 'Ship 20k' : 'Free ship',
                style: TextStyle(
                  color: _includeShipLive
                      ? AppTheme.accent
                      : AppTheme.textSubColor(isDark),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  String _addressLabel(Map<String, dynamic> a) =>
      (a['address'] ?? '').toString();

  int _calcLabelKg(double kgInput) {
    int kg = (kgInput * 1000).round();
    if (kg <= 1000) return 500;
    if (kg <= 2000) return 1000;
    if (kg <= 3000) return 1500;
    if (kg <= 4000) return 2000;
    if (kg <= 6000) return kg - 2000;
    if (kg <= 9000) return kg - 3000;
    if (kg <= 15000) return kg - 4000;
    return kg - 5000;
  }

  Future<String> _makeBarcodeBase64(String data) async {
    try {
      final url = 'https://barcodeapi.org/api/128/${Uri.encodeComponent(data)}';
      final res =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final b64 = base64Encode(res.bodyBytes);
        return '<div style="width:208px;height:30px;overflow:hidden;">'
            '<img src="data:image/png;base64,$b64" width="208" style="display:block;"/>'
            '</div>';
      }
    } catch (_) {}
    return '<p style="font-size:10px;">$data</p>';
  }

  Future<String> _makeQrBase64(String data) async {
    try {
      final url = 'https://api.qrserver.com/v1/create-qr-code/'
          '?size=76x76&data=${Uri.encodeComponent(data)}&format=png&margin=2';
      final res =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final b64 = base64Encode(res.bodyBytes);
        return '<img src="data:image/png;base64,$b64" width="76" height="76"/>';
      }
    } catch (_) {}
    return '<p style="font-size:9px;word-break:break-all;">$data</p>';
  }

  Future<String> _buildPrintHtml({
    required Map<String, dynamic> res,
    required String fbname,
    required String phone,
    required String address,
    required int cod,
    required double kgInput,
  }) async {
    final labelKgGram = _calcLabelKg(kgInput);
    final labelKgKg = labelKgGram / 1000;
    final realorderid = res['realorderid']?.toString() ?? '';
    final tinh = res['tinh']?.toString() ?? '';
    final huyen = res['huyen']?.toString() ?? '';
    final xa = res['xa']?.toString() ?? '';
    final codStr = cod == 0
        ? '0'
        : cod.toString().replaceAllMapped(
            RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');

    final barcodeHtml = await _makeBarcodeBase64(realorderid);
    final qrHtml = await _makeQrBase64(realorderid);

    return '''<html><head>
<style>
  body { width: 360px; margin: 2mm 0mm 2mm 2mm; line-height: 1.6; }
  table { width: 360px; font-family: "tahoma"; border-collapse: collapse; }
  @media print{@page {size: landscape}}
  *, html {margin:0;padding:0;}
</style>
</head>
<body>
<table>
  <tr><td colspan="2">Tỉnh/TP: <p style="font-size:14px;display:inline;font-weight: bold;">$tinh</p></td></tr>
  <tr><td colspan="2">Quận/Huyện: <p style="font-size:13px;display:inline;font-weight: bold;">$huyen</p></td></tr>
  <tr><td colspan="2">Phường/Xã: <p style="font-size:13px;display:inline;font-weight: bold;">$xa</p></td></tr>
  <tr><td colspan="2" align="right"><p style="font-size:10px;display:inline;">$labelKgKg KG</p></td></tr>
  <tr><td colspan="2"><center>$barcodeHtml<br><p style="font-size:10px;display:inline;vertical-align: top;">$realorderid</p></center></td></tr>
  <tr><td colspan="2"><h5>$fbname • $phone</h5></td></tr>
  <tr><td colspan="2"><p style="font-size:10px;display:inline;vertical-align: top;">$address</p></td></tr>
  <tr>
    <td><p style="font-size:10px;display:inline;vertical-align: top;">Cho xem hàng, không nhận thu 30k</p><br>
    <p style="font-size:10px;display:inline;">1 x Vải</p><br>
    <p style="font-size:18px;display:inline;">Tiền thu hộ: <b>$codStr đ</b></p></td>
    <td>$qrHtml</td>
  </tr>
</table>
</body></html>''';
  }

  Future<void> _createOrder() async {
    final codRaw = _codCtrl.text.replaceAll('.', '').trim();
    final kgStr = _kgCtrl.text.trim();

    final int cod = int.tryParse(codRaw) ?? -1;
    if (cod < 0) {
      _snack('COD không hợp lệ (không được âm)', Colors.orange);
      return;
    }

    final double kg = double.tryParse(kgStr) ?? -1;
    if (kg < 0) {
      _snack('Số ký không hợp lệ (không được âm)', Colors.orange);
      return;
    }
    if (kg > 20) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: AppTheme.cardColor(isDark),
          title: Text('Cảnh báo khối lượng',
              style:
                  TextStyle(color: AppTheme.textColor(isDark), fontSize: 16)),
          content: Text(
            'Khối lượng $kgStr kg khá lớn (> 20kg). Vẫn tiếp tục lên đơn?',
            style:
                TextStyle(color: AppTheme.textSubColor(isDark), fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Hủy',
                  style: TextStyle(color: AppTheme.textSubColor(isDark))),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Vẫn lên đơn',
                  style: TextStyle(
                      color: AppTheme.accent, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    if (_selectedAddress == null) {
      _snack(
          'Vui lòng check địa chỉ trước khi lên đơn (nhấn đúp vào ô Địa chỉ → nhập → ✓)',
          Colors.orange);
      return;
    }
    final address = _addressLabel(_selectedAddress!);
    if (address.isEmpty) {
      _snack('Địa chỉ không hợp lệ', Colors.orange);
      return;
    }

    final phone = _phoneCtrl.text.trim();

    if (phone.length != 10 && !phone.startsWith('02')) {
      _snack('Số điện thoại không hợp lệ (cần 10 số)', Colors.orange);
      return;
    }

    setState(() => _creatingOrder = true);
    try {
      final fbname = _customer.fbname ?? _customer.displayName;
      final body = {
        'edit': 0,
        'realorderid': '',
        'fbname': fbname,
        'address': address,
        'phone': phone,
        'cod': cod.toString(),
        'kg': kg.toString(),
        'khid': _customer.id,
        'userid': _customer.userid ?? '',
        'realfbid': _customer.realfbid ?? '',
      };

      final res =
          await ApiService.postRaw('$_mainUrl/createorderviettel', body);
      if (res == null) {
        _snack('Lỗi kết nối server', Colors.red);
        return;
      }
      if (res['error'] != null) {
        _snack(res['error'].toString(), Colors.red);
        return;
      }

      final realorderid = res['realorderid']?.toString() ?? '';
      _snack('Lên đơn thành công! Mã: $realorderid', AppTheme.accent);
      _codCtrl.clear();
      _kgCtrl.clear();

      if (realorderid.isEmpty) return;

      if (mounted) {
        FocusManager.instance.primaryFocus?.unfocus();
        await Future.delayed(const Duration(milliseconds: 300));
        if (!mounted) return;
        Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) =>
                QrScanScreen(liveComments: widget.liveComments),
            transitionsBuilder: (_, anim, __, child) => SlideTransition(
              position:
                  Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
                      .animate(CurvedAnimation(
                          parent: anim, curve: Curves.easeOutCubic)),
              child: child,
            ),
          ),
        );
      }

      final html = await _buildPrintHtml(
        res: res,
        fbname: fbname,
        phone: phone,
        address: address,
        cod: cod,
        kgInput: kg,
      );

      try {
        await http.post(
          Uri.parse('$_mainUrl/printviettel'),
          body: {
            'html': html,
            'realorderid': realorderid,
          },
        );
      } catch (_) {}

      try {
        final userId = ApiService.userId;
        final printRes = await http.post(
          Uri.parse('$_mainUrl/print-order'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'userId': userId,
            'type': 'html',
            'content': html,
            'config': {
              'printerName': 'HPRT N41',
              'widthMm': 150,
              'heightMm': 100,
            },
          }),
        );
        final printData = json.decode(utf8.decode(printRes.bodyBytes));
        if (printData['success'] != true) {
          _snack('Máy in đang Offline!', Colors.orange);
        }
      } catch (_) {}
    } catch (e) {
      _snack('Lỗi: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _creatingOrder = false);
    }
  }

  Future<void> _printCustomerLabel() async {
    if (_printing) return;
    setState(() => _printing = true);
    try {
      final now = DateTime.now();
      final date =
          '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
      final userid = _customer.userid ?? '';
      final printData = {
        'date': date,
        'name': _customer.fbname ?? _customer.userid ?? '',
        'phone': _customer.phone ?? '',
        'comment': '',
        'gia': '0',
        'id': _customer.id.toString(),
        'avabase64': userid.isNotEmpty
            ? 'https://aodaigiabao.com/images/ava/$userid.jpg'
            : '',
        'note': '',
        'address': _customer.diachi ?? '',
        'region': '',
      };

      final pdfRes = await ApiService.postRaw(
          'https://aodaigiabao.com/api/generate-pdf', printData);

      if (pdfRes == null || pdfRes['error'] != null) {
        _snack('Lỗi tạo PDF: ${pdfRes?['error'] ?? 'null'}', Colors.red);
        return;
      }
      if (pdfRes['success'] != true) {
        _snack('PDF thất bại: ${pdfRes['message'] ?? ''}', Colors.red);
        return;
      }

      final printRes =
          await ApiService.postRaw('https://aodaigiabao.com/print-order', {
        'userId': ApiService.userId,
        'type': 'pdf',
        'content': pdfRes['pdfBase64'],
        'config': {
          'printerName': 'XP-80C',
          'widthMm': 80,
          'heightMm': 297,
          'marginTopPx': -5,
        },
      });

      if (printRes == null || printRes['error'] != null) {
        _snack('Lỗi gửi lệnh in: ${printRes?['error'] ?? 'null'}', Colors.red);
      }
    } catch (e) {
      _snack('Lỗi kết nối máy in: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 0).copyWith(
          bottom: MediaQuery.of(context).size.height - 120,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ));
  }

  Future<void> _saveChanges({bool silent = false}) async {
    setState(() => _saving = true);
    try {
      final ok = await ApiService.updateCustomer(_customer.id, {
        'phone': _phoneCtrl.text,
        'diachi': _addressCtrl.text,
        'note': _noteCtrl.text,
        'label': _selectedLabel,
        'tag': _tagCtrl.text,
        'important': _customer.important ?? '0',
        'userid': _customer.userid,
      });
      if (ok) {
        setState(() => _editingFields.clear());
        if (!silent) _snack('Đã lưu thành công ✓', AppTheme.accent);
        _loadSavedAddresses();
      }
    } catch (_) {
      _snack('Lỗi khi lưu', Colors.red);
    } finally {
      setState(() => _saving = false);
    }
  }

  static const _labelOptions = [
    'Bom hàng',
    'Xả hàng',
    'Có vấn đề',
    'Thân thiết',
    'Xóa nhãn'
  ];

  Color _labelColor(String label) {
    switch (label) {
      case 'Bom hàng':
      case 'Xả hàng':
        return Colors.red;
      case 'Có vấn đề':
        return Colors.amber;
      case 'Thân thiết':
        return Colors.lightGreenAccent;
      default:
        return AppTheme.textSubColor(isDark);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chi tiết khách hàng'),
        actions: [
          _printing
              ? Padding(
                  padding: const EdgeInsets.all(12),
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppTheme.textColor(isDark))))
              : IconButton(
                  icon: const Icon(Icons.print_outlined),
                  tooltip: 'In tem',
                  onPressed: _printCustomerLabel,
                ),
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Quét QR',
            onPressed: () {
              Navigator.of(context)
                ..pop()
                ..push(PageRouteBuilder(
                  pageBuilder: (_, __, ___) =>
                      QrScanScreen(liveComments: widget.liveComments),
                  transitionsBuilder: (_, anim, __, child) => SlideTransition(
                    position: Tween<Offset>(
                            begin: const Offset(0, 1), end: Offset.zero)
                        .animate(CurvedAnimation(
                            parent: anim, curve: Curves.easeOutCubic)),
                    child: child,
                  ),
                ));
            },
          ),
          if (_editing)
            _saving
                ? Padding(
                    padding: const EdgeInsets.all(12),
                    child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppTheme.textColor(isDark))))
                : TextButton(
                    onPressed: _saveChanges,
                    child: const Text('Lưu',
                        style: TextStyle(
                            color: AppTheme.accent,
                            fontWeight: FontWeight.w700))),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
                child: Column(children: [
              CircleAvatar(
                radius: 40,
                backgroundColor: AppTheme.surfaceColor(isDark),
                backgroundImage: _customer.userid != null &&
                        _customer.userid!.isNotEmpty
                    ? NetworkImage(
                        'https://aodaigiabao.com/images/ava/${_customer.userid}.jpg')
                    : null,
                onBackgroundImageError:
                    _customer.userid != null ? (_, __) {} : null,
                child: null,
              ),
              const SizedBox(height: 12),
              Text(_customer.displayName,
                  style: TextStyle(
                      color: AppTheme.textColor(isDark),
                      fontSize: 20,
                      fontWeight: FontWeight.w700)),
              if (_selectedLabel.isNotEmpty) ...[
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: _labelColor(_selectedLabel).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color:
                            _labelColor(_selectedLabel).withValues(alpha: 0.4)),
                  ),
                  child: Text(_selectedLabel,
                      style: TextStyle(
                          color: _labelColor(_selectedLabel),
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ])),
            const SizedBox(height: 24),
            _sectionHeader('Liên hệ'),
            _infoCard(children: [
              _editableField('Số điện thoại', _phoneCtrl, Icons.phone,
                  fieldKey: 'phone'),
              _editableField('Địa chỉ', _addressCtrl, Icons.location_on,
                  fieldKey: 'address', onSaved: _checkAddress),
              _buildLastMessageRow(),
            ]),
            const SizedBox(height: 16),
            _sectionHeader('Lên đơn ViettelPost'),
            Container(
              decoration: BoxDecoration(
                  color: AppTheme.cardColor(isDark),
                  borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.all(14),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                        flex: 6,
                        child: TextField(
                          controller: _codCtrl,
                          keyboardType: TextInputType.number,
                          style: TextStyle(
                              color: AppTheme.textColor(isDark), fontSize: 14),
                          decoration: _orderInput(
                              'COD (VD: 1.000.000)', Icons.payments_outlined),
                          onChanged: (v) {
                            final formatted = _formatCod(v);
                            if (formatted != v) {
                              _codCtrl.value = TextEditingValue(
                                text: formatted,
                                selection: TextSelection.collapsed(
                                    offset: formatted.length),
                              );
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 4,
                        child: TextField(
                          controller: _kgCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          style: TextStyle(
                              color: AppTheme.textColor(isDark), fontSize: 14),
                          decoration: _orderInput('Ký', Icons.scale_outlined),
                          onTap: () {
                            _kgCtrl.selection = TextSelection(
                              baseOffset: 0,
                              extentOffset: _kgCtrl.text.length,
                            );
                          },
                          onEditingComplete: () {
                            if (_kgCtrl.text.trim().isEmpty) {
                              _kgCtrl.text = '1';
                            }
                            FocusScope.of(context).unfocus();
                          },
                          onTapOutside: (_) {
                            if (_kgCtrl.text.trim().isEmpty) {
                              _kgCtrl.text = '1';
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 46,
                        height: 46,
                        child: ElevatedButton(
                          onPressed: _creatingOrder ? null : _createOrder,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.accent,
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          child: _creatingOrder
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.local_shipping,
                                  color: Colors.white, size: 20),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 10),
                    if (_loadingAddresses)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Center(
                            child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: AppTheme.primary))),
                      )
                    else if (_savedAddresses.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text(
                            'Chưa có địa chỉ giao hàng, thêm địa chỉ để lên đơn.',
                            style: TextStyle(
                                color: AppTheme.textSubColor(isDark),
                                fontSize: 12)),
                      )
                    else
                      DropdownButtonHideUnderline(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceColor(isDark),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: DropdownButton<int>(
                            isExpanded: true,
                            dropdownColor: AppTheme.surfaceColor(isDark),
                            value: _selectedAddressIndex.clamp(
                                0, _savedAddresses.length - 1),
                            icon: Icon(Icons.expand_more,
                                color: AppTheme.textSubColor(isDark), size: 18),
                            style: TextStyle(
                                color: AppTheme.textColor(isDark),
                                fontSize: 13),
                            items: List.generate(_savedAddresses.length, (i) {
                              final a = _savedAddresses[i];
                              final label = _addressLabel(a);
                              return DropdownMenuItem<int>(
                                value: i,
                                child: Text(label,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: AppTheme.textColor(isDark),
                                        fontSize: 12)),
                              );
                            }),
                            onChanged: (i) {
                              if (i != null) {
                                setState(() => _selectedAddressIndex = i);
                              }
                            },
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    _buildLiveChotBanner(),
                  ]),
            ),
            const SizedBox(height: 16),
            _sectionHeader('Ghi chú'),
            GestureDetector(
              onDoubleTap: () => _startEdit('note'),
              child: Container(
                decoration: BoxDecoration(
                  color: AppTheme.cardColor(isDark),
                  borderRadius: BorderRadius.circular(8),
                  border: _isEditing('note')
                      ? Border.all(
                          color: AppTheme.primary.withValues(alpha: 0.4),
                          width: 1)
                      : null,
                ),
                child: _isEditing('note')
                    ? TextField(
                        controller: _noteCtrl,
                        maxLines: 4,
                        autofocus: true,
                        onTapOutside: (_) => _stopEdit('note'),
                        style: TextStyle(
                            color: AppTheme.textColor(isDark), fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Thêm ghi chú...',
                          hintStyle: TextStyle(
                              color: AppTheme.textSubColor(isDark)
                                  .withValues(alpha: 0.6)),
                          contentPadding:
                              const EdgeInsets.fromLTRB(12, 12, 36, 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.check,
                                color: AppTheme.accent, size: 18),
                            onPressed: () => _stopEdit('note'),
                          ),
                        ))
                    : Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          _noteCtrl.text.isEmpty
                              ? 'Chưa có ghi chú  —  nhấn đúp để sửa'
                              : _noteCtrl.text,
                          style: TextStyle(
                              color: _noteCtrl.text.isEmpty
                                  ? AppTheme.textSubColor(isDark)
                                      .withValues(alpha: 0.5)
                                  : AppTheme.textColor(isDark),
                              fontSize: 14),
                        )),
              ),
            ),
            const SizedBox(height: 16),
            _sectionHeader('Đơn hàng gần nhất'),
            if (_loadingOrders)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                    child: CircularProgressIndicator(
                        color: AppTheme.primary, strokeWidth: 2)),
              )
            else if (_recentOrders.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.cardColor(isDark),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('Chưa có đơn hàng',
                    style: TextStyle(
                        color: AppTheme.textSubColor(isDark), fontSize: 13)),
              )
            else
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.cardColor(isDark),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: _recentOrders.asMap().entries.map((e) {
                    final i = e.key;
                    final o = e.value;
                    final color = Order.statusColor(o.statuscode);
                    final ngay = _formatOrderDate(o.time);
                    final info = [
                      o.codFormatted,
                      o.kg != null ? '${o.kg}kg' : '?kg',
                      if (ngay.isNotEmpty) ngay,
                      o.displayStatus,
                    ].join(' · ');
                    return Column(
                      children: [
                        if (i > 0)
                          Divider(
                              height: 0,
                              color: AppTheme.surfaceColor(isDark)
                                  .withValues(alpha: 0.5),
                              indent: 16,
                              endIndent: 16),
                        InkWell(
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(i == 0 ? 12 : 0),
                            bottom: Radius.circular(
                                i == _recentOrders.length - 1 ? 12 : 0),
                          ),
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => OrderTimelineScreen(order: o),
                              )),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            child: Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                      color: color, shape: BoxShape.circle),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    info,
                                    style: TextStyle(
                                        color: color,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Icon(Icons.chevron_right,
                                    color: AppTheme.textSubColor(isDark),
                                    size: 16),
                                if (o.realorderid != null &&
                                    o.realorderid!.isNotEmpty)
                                  _ReprintButton(
                                    realorderid: o.realorderid!,
                                    onError: (msg) =>
                                        _snack(msg, Colors.orange),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            const SizedBox(height: 16),
            _sectionHeader('Phân loại'),
            _infoCard(children: [
              _buildLabelField(),
              _editableField('Tag', _tagCtrl, Icons.tag),
            ]),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  InputDecoration _orderInput(String hint, IconData icon) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
            color: AppTheme.textSubColor(isDark).withValues(alpha: 0.6),
            fontSize: 12),
        prefixIcon: Icon(icon, color: AppTheme.textSubColor(isDark), size: 16),
        filled: true,
        fillColor: AppTheme.surfaceColor(isDark),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none),
      );

  final GlobalKey _labelKey = GlobalKey();
  Widget _buildLabelField() {
    final displayLabel = _selectedLabel.isEmpty
        ? 'Chưa có nhãn  —  nhấn đúp để sửa'
        : _selectedLabel;
    final labelColor = _selectedLabel.isEmpty
        ? AppTheme.textSubColor(isDark).withValues(alpha: 0.5)
        : _labelColor(_selectedLabel);
    final editing = _isEditing('label');
    return GestureDetector(
      onDoubleTap: () {
        _startEdit('label');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final labelContext = _labelKey.currentContext;
          if (labelContext == null) return;
          void triggerTap(Element element) {
            if (element.widget is GestureDetector) {
              final gesture = element.widget as GestureDetector;
              gesture.onTap?.call();
              return;
            }
            element.visitChildren(triggerTap);
          }

          labelContext.visitChildElements(triggerTap);
        });
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [
          Icon(Icons.label, color: AppTheme.textSubColor(isDark), size: 18),
          const SizedBox(width: 12),
          SizedBox(
              width: 100,
              child: Text('Nhãn',
                  style: TextStyle(
                      color: AppTheme.textSubColor(isDark), fontSize: 13))),
          Expanded(
            child: editing
                ? DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                    key: _labelKey,
                    value: null,
                    isExpanded: true,
                    dropdownColor: AppTheme.surfaceColor(isDark),
                    hint: Text(
                        _selectedLabel.isEmpty ? 'Chọn nhãn' : _selectedLabel,
                        style: TextStyle(
                            color: _selectedLabel.isEmpty
                                ? AppTheme.textSubColor(isDark)
                                : _labelColor(_selectedLabel),
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                    icon: Icon(Icons.expand_more,
                        color: AppTheme.textSubColor(isDark), size: 18),
                    items: _labelOptions.map((opt) {
                      final isDelete = opt == 'Xóa nhãn';

                      Color optColor;
                      if (isDelete) {
                        optColor = AppTheme.textSubColor(isDark);
                      } else if (opt == 'Có vấn đề') {
                        optColor = Colors.amber;
                      } else if (opt == 'Thân thiết') {
                        optColor = Colors.lightGreenAccent;
                      } else {
                        optColor = Colors.red;
                      }

                      return DropdownMenuItem<String>(
                        value: opt,
                        child: Text(
                          opt,
                          style: TextStyle(
                            color: optColor,
                            fontSize: 13,
                            fontWeight:
                                isDelete ? FontWeight.w400 : FontWeight.w600,
                          ),
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val == null) return;
                      setState(() {
                        _selectedLabel = val == 'Xóa nhãn' ? '' : val;
                      });
                      _stopEdit('label');
                    },
                  ))
                : Text(displayLabel,
                    style: TextStyle(
                        color: labelColor,
                        fontSize: 13,
                        fontWeight: _selectedLabel.isEmpty
                            ? FontWeight.w400
                            : FontWeight.w600)),
          ),
        ]),
      ),
    );
  }

  Widget _buildLastMessageRow() {
    return GestureDetector(
      onTap: _customer.userid != null && _customer.userid!.isNotEmpty
          ? () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => ChatScreen(
                      sender: _customer.userid!,
                      pageId: _customer.pageid ?? '')))
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          Icon(Icons.chat_bubble_outline,
              color: AppTheme.textSubColor(isDark), size: 18),
          const SizedBox(width: 12),
          SizedBox(
              width: 100,
              child: Text('Tin nhắn',
                  style: TextStyle(
                      color: AppTheme.textSubColor(isDark), fontSize: 13))),
          Expanded(
            child: _loadingLastMsg
                ? const SizedBox(
                    height: 14,
                    child: LinearProgressIndicator(
                        backgroundColor: Colors.transparent,
                        color: AppTheme.primary,
                        minHeight: 2))
                : _lastMessage == null
                    ? Text('Chưa có tin nhắn',
                        style: TextStyle(
                            color: AppTheme.textSubColor(isDark)
                                .withValues(alpha: 0.5),
                            fontSize: 13))
                    : Row(children: [
                        Expanded(
                          child: Text(
                            _lastMsgPreview(_lastMessage!),
                            style: TextStyle(
                                color: AppTheme.textColor(isDark),
                                fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.chevron_right,
                            size: 16, color: AppTheme.textSubColor(isDark)),
                      ]),
          ),
        ]),
      ),
    );
  }

  Widget _sectionHeader(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(title,
            style: TextStyle(
                color: AppTheme.textSubColor(isDark),
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5)),
      );

  Widget _infoCard({required List<Widget> children}) => Container(
        decoration: BoxDecoration(
            color: AppTheme.cardColor(isDark),
            borderRadius: BorderRadius.circular(12)),
        child: Column(children: children),
      );

  Widget _editableField(String label, TextEditingController ctrl, IconData icon,
      {String? fieldKey, VoidCallback? onSaved}) {
    final key = fieldKey ?? label;
    final editing = _isEditing(key);
    final isPhone = key == 'phone';

    void save() {
      _stopEdit(key);
      if (onSaved != null) onSaved();
    }

    Future<void> callPhone() async {
      final phone = ctrl.text.trim();
      if (phone.isEmpty) return;
      try {
        if (Platform.isAndroid) {
          const platform = MethodChannel('app/phone_call');
          await platform.invokeMethod('call', {'number': phone});
        } else {
          final uri = Uri.parse('tel:$phone');
          await launchUrl(uri);
        }
      } catch (_) {}
    }

    return GestureDetector(
      onDoubleTap: () => _startEdit(key),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [
          GestureDetector(
            onTap:
                isPhone && !editing && ctrl.text.isNotEmpty ? callPhone : null,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon,
                  color: isPhone && !editing && ctrl.text.isNotEmpty
                      ? AppTheme.accent
                      : AppTheme.textSubColor(isDark),
                  size: 18),
              const SizedBox(width: 12),
              SizedBox(
                  width: 100,
                  child: Text(label,
                      style: TextStyle(
                          color: isPhone && !editing && ctrl.text.isNotEmpty
                              ? AppTheme.accent
                              : AppTheme.textSubColor(isDark),
                          fontSize: 13))),
            ]),
          ),
          Expanded(
            child: editing
                ? TextField(
                    controller: ctrl,
                    autofocus: true,
                    maxLines: key == 'address' ? null : 1,
                    keyboardType: key == 'address'
                        ? TextInputType.multiline
                        : TextInputType.text,
                    textInputAction: key == 'address'
                        ? TextInputAction.newline
                        : TextInputAction.done,
                    style: TextStyle(
                        color: AppTheme.textColor(isDark), fontSize: 13),
                    onEditingComplete: key == 'address' ? null : save,
                    onTapOutside: (_) => save(),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide:
                            BorderSide(color: AppTheme.surfaceColor(isDark)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide:
                            BorderSide(color: AppTheme.surfaceColor(isDark)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide:
                            BorderSide(color: AppTheme.primary, width: 1),
                      ),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.check,
                            color: AppTheme.accent, size: 18),
                        onPressed: save,
                      ),
                    ))
                : isPhone && ctrl.text.isNotEmpty
                    ? GestureDetector(
                        onDoubleTap: () => _startEdit(key),
                        onLongPress: () {
                          HapticFeedback.mediumImpact();
                          Clipboard.setData(
                              ClipboardData(text: ctrl.text.trim()));
                          setState(() => _phoneCopied = true);
                          Future.delayed(const Duration(milliseconds: 900), () {
                            if (mounted) setState(() => _phoneCopied = false);
                          });
                        },
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 200),
                          style: TextStyle(
                            color: _phoneCopied
                                ? AppTheme.accent
                                : AppTheme.textColor(isDark),
                            fontSize: 13,
                            fontWeight: _phoneCopied
                                ? FontWeight.w700
                                : FontWeight.w400,
                          ),
                          child: Text(ctrl.text),
                        ),
                      )
                    : Text(ctrl.text.isEmpty ? '—  nhấn đúp để sửa' : ctrl.text,
                        style: TextStyle(
                            color: ctrl.text.isEmpty
                                ? AppTheme.textSubColor(isDark)
                                    .withValues(alpha: 0.5)
                                : AppTheme.textColor(isDark),
                            fontSize: 13)),
          ),
        ]),
      ),
    );
  }
}

class _ReprintButton extends StatefulWidget {
  final String realorderid;
  final void Function(String) onError;
  const _ReprintButton({required this.realorderid, required this.onError});

  @override
  State<_ReprintButton> createState() => _ReprintButtonState();
}

class _ReprintButtonState extends State<_ReprintButton> {
  bool get isDark => Theme.of(context).brightness == Brightness.dark;

  bool _printing = false;

  Future<void> _reprint() async {
    if (_printing) return;
    setState(() => _printing = true);
    try {
      final txtRes = await http.get(
        Uri.parse('$_mainUrl/donhang/${widget.realorderid}.txt'),
      );
      if (txtRes.statusCode != 200 || txtRes.body.isEmpty) {
        widget.onError('Không tìm thấy nội dung đơn');
        return;
      }
      final html = txtRes.body;

      final userId = ApiService.userId;
      final printRes = await http.post(
        Uri.parse('$_mainUrl/print-order'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'userId': userId,
          'type': 'html',
          'content': html,
          'config': {
            'printerName': 'HPRT N41',
            'widthMm': 150,
            'heightMm': 100,
          },
        }),
      );
      final data = json.decode(utf8.decode(printRes.bodyBytes));
      if (data['success'] != true) {
        widget.onError('Máy in đang Offline!');
      }
    } catch (_) {
      widget.onError('Lỗi kết nối máy in');
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 30,
      height: 30,
      child: _printing
          ? Padding(
              padding: const EdgeInsets.all(6),
              child: CircularProgressIndicator(
                  strokeWidth: 1.5, color: AppTheme.textSubColor(isDark)),
            )
          : IconButton(
              padding: EdgeInsets.zero,
              icon: Icon(Icons.print_outlined,
                  size: 16, color: AppTheme.textSubColor(isDark)),
              onPressed: _reprint,
              tooltip: 'In lại đơn',
            ),
    );
  }
}
