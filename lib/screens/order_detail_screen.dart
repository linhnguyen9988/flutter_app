import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import 'chat_screen.dart';
import '../models/order.dart';
import '../services/api_service.dart';
import 'order_timeline_screen.dart';
import '../services/reload_aware_mixin.dart';

class OrderDetailScreen extends StatefulWidget {
  final Order order;
  const OrderDetailScreen({super.key, required this.order});

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen>
    with ReloadAwareMixin<OrderDetailScreen> {
  bool get isDark => Theme.of(context).brightness == Brightness.dark;

  late Order _order;
  bool _saving = false;
  bool _loadingOrder = false;
  String _pageId = '';
  String _lastNote = '';

  @override
  void onReload() => _loadOrderByRealId();

  @override
  void initState() {
    super.initState();
    _order = widget.order;
    if (_order.id == 0 && (_order.realorderid?.isNotEmpty == true)) {
      _loadOrderByRealId();
    } else {
      _loadPageId();
      _loadLastNote();
    }
  }

  Future<void> _loadOrderByRealId() async {
    setState(() => _loadingOrder = true);
    try {
      final orders = await ApiService.getOrders(
        search: _order.realorderid,
        limit: 1,
      );
      if (mounted && orders.isNotEmpty) {
        setState(() => _order = orders.first);
        _loadPageId();
        _loadLastNote();
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingOrder = false);
    }
  }

  Future<void> _loadPageId() async {
    final userid = _order.userid ?? '';
    if (userid.isEmpty) return;
    final pid = await ApiService.getPageIdByUserid(userid);
    if (mounted && pid.isNotEmpty) setState(() => _pageId = pid);
  }

  Future<void> _loadLastNote() async {
    final realId = _order.realorderid ?? '';
    if (realId.isEmpty) return;
    try {
      final logs = await ApiService.getOrderLogs(realId);
      if (mounted && logs.isNotEmpty) {
        final latestNote = logs.first['note']?.toString().trim() ?? '';
        if (latestNote.isNotEmpty) setState(() => _lastNote = latestNote);
      }
    } catch (_) {}
  }

  Future<void> _cancelOrder() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.cardColor(isDark),
        title: Text('Xác nhận hủy đơn',
            style: TextStyle(color: AppTheme.textColor(isDark), fontSize: 16)),
        content: Text(
          'Hủy đơn ${_order.realorderid ?? _order.id.toString()}?\nThao tác này không thể hoàn tác.',
          style: TextStyle(color: AppTheme.textSubColor(isDark), fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Không',
                style: TextStyle(color: AppTheme.textSubColor(isDark))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hủy đơn',
                style:
                    TextStyle(color: Colors.red, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _saving = true);
    try {
      final realId = _order.realorderid ?? '';
      if (realId.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Không có mã đơn thực để hủy'),
              backgroundColor: Colors.red));
        }
        setState(() => _saving = false);
        return;
      }
      final result = await ApiService.postRaw(
        'https://aodaigiabao.com/huydonviettel',
        {
          'realorderid': realId,
          'xoa': 0,
        },
      );
      if (!mounted) return;
      final msg = result?['message']?.toString() ?? 'Đã gửi yêu cầu hủy';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red.shade700),
      );
      setState(() => _order = Order(
            id: _order.id,
            name: _order.name,
            phone: _order.phone,
            address: _order.address,
            kg: _order.kg,
            cod: _order.cod,
            status: _order.status,
            date: _order.date,
            orderid: _order.orderid,
            realorderid: _order.realorderid,
            khid: _order.khid,
            statuscode: 107,
            statustext: 'Đơn hàng đã hủy',
            realfbid: _order.realfbid,
            userid: _order.userid,
            time: _order.time,
            shipperName: _order.shipperName,
            shipperPhone: _order.shipperPhone,
            lastUpdate: _order.lastUpdate,
          ));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Lỗi kết nối'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Đã copy!'), duration: Duration(seconds: 1)),
    );
  }

  Color _statusColor(int? code) => Order.statusColor(code);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chi tiết đơn hàng'),
        actions: [
          if (_order.userid != null && _order.userid!.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.chat_bubble_outline, size: 20),
              tooltip: 'Nhắn tin khách',
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChatScreen(
                      sender: _order.userid!,
                      pageId: _pageId,
                      customerName: _order.name,
                    ),
                  )),
            ),
          if (_saving)
            Padding(
              padding: const EdgeInsets.all(14),
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppTheme.primary)),
            ),
        ],
      ),
      body: _loadingOrder
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => OrderTimelineScreen(order: _order),
                        )),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _statusColor(_order.statuscode)
                            .withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: _statusColor(_order.statuscode)
                                .withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.circle,
                              color: _statusColor(_order.statuscode), size: 12),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _order.displayStatus,
                                  style: TextStyle(
                                    color: _statusColor(_order.statuscode),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                                if (_lastNote.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    _lastNote,
                                    style: TextStyle(
                                      color: _statusColor(_order.statuscode)
                                          .withValues(alpha: 0.8),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const Icon(Icons.timeline_outlined,
                              color: AppTheme.primary, size: 18),
                          const SizedBox(width: 4)
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _sectionTitle('Thông tin người nhận'),
                  _infoCard(children: [
                    _infoRow('Tên', _order.name ?? '-', copyable: true),
                    _divider(),
                    _infoRow('Điện thoại', _order.phone ?? '-', copyable: true),
                    _divider(),
                    _infoRow('Địa chỉ', _order.address ?? '-'),
                  ]),
                  const SizedBox(height: 16),
                  _sectionTitle('Thông tin vận chuyển'),
                  _infoCard(children: [
                    _infoRow('Mã đơn', _order.realorderid ?? '-',
                        copyable: true),
                    _divider(),
                    _infoRow('Ngày tạo', _order.date ?? '-'),
                    _divider(),
                    _infoRow(
                        'Cập nhật cuối', _formatDateTime(_order.lastUpdate)),
                  ]),
                  const SizedBox(height: 16),
                  _sectionTitle('Thông tin giao hàng'),
                  _infoCard(children: [
                    _infoRow('COD', _order.codFormatted,
                        valueColor: AppTheme.accent, bold: true),
                    _divider(),
                    _infoRow('Khối lượng',
                        _order.kg != null ? '${_order.kg} kg' : '-'),
                    if (_order.shipperName != null) ...[
                      _divider(),
                      _infoRow('Shipper', _order.shipperName!),
                      _divider(),
                      _infoRow('SĐT Shipper', _order.shipperPhone ?? '-',
                          copyable: true),
                    ],
                  ]),
                  const SizedBox(height: 16),
                  if (_lastNote.isNotEmpty) ...[
                    _sectionTitle('Ghi chú trạng thái'),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.cardColor(isDark),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(_lastNote,
                          style: TextStyle(
                              color: AppTheme.textSubColor(isDark), fontSize: 13)),
                    ),
                    const SizedBox(height: 20),
                  ],
                  if ((_order.statuscode ?? 999) < 107) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _saving ? null : _cancelOrder,
                        icon: const Icon(Icons.cancel_outlined,
                            color: Colors.red, size: 18),
                        label: const Text('Hủy đơn hàng',
                            style: TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.w600)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.red, width: 1.5),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
    );
  }

  String _formatDateTime(String? raw) {
    if (raw == null || raw.isEmpty) return '-';
    try {
      final dt = DateTime.parse(raw).toLocal();
      final hh = dt.hour.toString().padLeft(2, '0');
      final mm = dt.minute.toString().padLeft(2, '0');
      final ss = dt.second.toString().padLeft(2, '0');
      final dd = dt.day.toString().padLeft(2, '0');
      final mo = dt.month.toString().padLeft(2, '0');
      return '$hh:$mm:$ss - $dd/$mo/${dt.year}';
    } catch (_) {
      return raw;
    }
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t,
            style: TextStyle(
                color: AppTheme.textSubColor(isDark),
                fontSize: 13,
                fontWeight: FontWeight.w600)),
      );

  Widget _infoCard({required List<Widget> children}) => Container(
        decoration: BoxDecoration(
            color: AppTheme.cardColor(isDark), borderRadius: BorderRadius.circular(12)),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );

  Widget _divider() => Divider(
      height: 0,
      color: AppTheme.surfaceColor(isDark).withValues(alpha: 0.5),
      indent: 16,
      endIndent: 16);

  Widget _infoRow(String label, String value,
      {bool copyable = false, Color? valueColor, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 110,
              child: Text(label,
                  style:
                      TextStyle(color: AppTheme.textSubColor(isDark), fontSize: 13))),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: valueColor ?? AppTheme.textColor(isDark),
                fontSize: 13,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
          if (copyable && value != '-')
            GestureDetector(
              onTap: () => _copyToClipboard(value),
              child: Icon(Icons.copy_outlined,
                  color: AppTheme.textSubColor(isDark), size: 16),
            ),
        ],
      ),
    );
  }
}
