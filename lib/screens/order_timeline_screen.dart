import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../models/order.dart';
import '../models/live_comment.dart';
import '../services/api_service.dart';
import '../widgets/phone_widget.dart';
import 'customer_detail_screen.dart';

class OrderTimelineScreen extends StatefulWidget {
  final Order order;
  final List<String> Function()? getLiveIds;
  final List<LiveComment> Function()? getLiveComments;
  const OrderTimelineScreen({
    super.key,
    required this.order,
    this.getLiveIds,
    this.getLiveComments,
  });

  @override
  State<OrderTimelineScreen> createState() => _OrderTimelineScreenState();
}

class _OrderTimelineScreenState extends State<OrderTimelineScreen> {
  List<Map<String, dynamic>> _logs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _openCustomer() async {
    final userid = widget.order.userid;
    if (userid == null || userid.isEmpty) return;
    try {
      final list = await ApiService.getCustomers(search: userid, limit: 1);
      if (!mounted || list.isEmpty) return;
      Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => CustomerDetailScreen(
                    customer: list.first,
                    selectedLiveIds: widget.getLiveIds?.call() ?? [],
                    liveComments: widget.getLiveComments?.call() ?? [],
                  )));
    } catch (_) {}
  }

  Future<void> _loadLogs() async {
    setState(() => _loading = true);
    try {
      final logs =
          await ApiService.getOrderLogs(widget.order.realorderid ?? '');

      // Cùng timestamp + code < 500: sort code nhỏ trước, lớn sau
      // (code lớn hơn = trạng thái đến sau = hiện cuối = index 0 trong list DESC)
      logs.sort((a, b) {
        final timeA = a['status_date_raw']?.toString() ??
            a['created_at']?.toString() ??
            '';
        final timeB = b['status_date_raw']?.toString() ??
            b['created_at']?.toString() ??
            '';
        if (timeA != timeB)
          return 0; // giữ nguyên thứ tự từ backend nếu khác timestamp
        final codeA = (a['status_code'] as int?) ?? 0;
        final codeB = (b['status_code'] as int?) ?? 0;
        if (codeA >= 500 || codeB >= 500) return 0; // không sort nếu >= 500
        // List từ backend là DESC (mới nhất trên đầu)
        // Cùng timestamp: code lớn hơn phải đứng TRƯỚC (index nhỏ hơn = trên timeline)
        return codeB.compareTo(codeA);
      });

      setState(() {
        _logs = logs;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Hành trình đơn hàng',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            if (widget.order.realorderid != null)
              GestureDetector(
                onDoubleTap: () {
                  Clipboard.setData(
                      ClipboardData(text: widget.order.realorderid!));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Đã copy mã vận đơn'),
                    duration: Duration(seconds: 1),
                    behavior: SnackBarBehavior.floating,
                  ));
                },
                child: Text(widget.order.realorderid!,
                    style:
                        TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
              ),
          ],
        ),
        actions: [
          if (widget.order.userid?.isNotEmpty == true)
            IconButton(
              icon: const Icon(Icons.person_outline),
              tooltip: 'Xem khách hàng',
              onPressed: () => _openCustomer(),
            ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadLogs),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary))
          : _logs.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.timeline,
                        color: AppTheme.textSecondary, size: 48),
                    const SizedBox(height: 12),
                    Text('Chưa có dữ liệu hành trình',
                        style: TextStyle(color: AppTheme.textSecondary)),
                  ]),
                )
              : RefreshIndicator(
                  onRefresh: _loadLogs,
                  color: AppTheme.primary,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(
                        vertical: 16, horizontal: 16),
                    itemCount: _logs.length,
                    itemBuilder: (_, i) => _buildTimelineItem(i),
                  ),
                ),
    );
  }

  Widget _buildTimelineItem(int i) {
    final log = _logs[i];
    final isFirst = i == 0;
    final isLast = i == _logs.length - 1;
    final code = log['status_code'] as int?;
    final color = Order.statusColor(code);
    final statusName =
        log['status_name'] ?? Order.statusMap[code] ?? 'Mã $code';
    final location = log['location'] ?? '';
    final note = log['note'] ?? '';
    final date = log['status_date_raw'] ?? log['created_at'] ?? '';
    final employee = log['employee_name'] ?? '';
    final employeePhone = log['employee_phone'] ?? '';

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Timeline line + dot
          SizedBox(
            width: 40,
            child: Column(
              children: [
                // Đường trên
                if (!isFirst)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: AppTheme.darkSurface,
                    ),
                  )
                else
                  const SizedBox(height: 8),
                // Dot
                Container(
                  width: isFirst ? 14 : 10,
                  height: isFirst ? 14 : 10,
                  decoration: BoxDecoration(
                    color: isFirst ? color : AppTheme.darkSurface,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: color,
                      width: isFirst ? 0 : 2,
                    ),
                    boxShadow: isFirst
                        ? [
                            BoxShadow(
                                color: color.withOpacity(0.4),
                                blurRadius: 8,
                                spreadRadius: 2)
                          ]
                        : null,
                  ),
                ),
                // Đường dưới
                if (!isLast)
                  Expanded(
                    child: Container(width: 2, color: AppTheme.darkSurface),
                  )
                else
                  const SizedBox(height: 8),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Content
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                top: isFirst ? 0 : 4,
                bottom: isLast ? 0 : 12,
              ),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isFirst ? color.withOpacity(0.08) : AppTheme.darkCard,
                  borderRadius: BorderRadius.circular(12),
                  border: isFirst
                      ? Border.all(color: color.withOpacity(0.3))
                      : null,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Trạng thái
                    Text(
                      statusName,
                      style: TextStyle(
                        color: isFirst ? color : AppTheme.textPrimary,
                        fontWeight: isFirst ? FontWeight.w700 : FontWeight.w600,
                        fontSize: isFirst ? 15 : 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Thời gian
                    if (date.isNotEmpty)
                      Text(date,
                          style: TextStyle(
                              color: AppTheme.textSecondary, fontSize: 12)),
                    // Địa điểm
                    if (location.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(children: [
                        const Icon(Icons.location_on_outlined,
                            color: AppTheme.textSecondary, size: 13),
                        const SizedBox(width: 4),
                        Expanded(
                            child: Text(location,
                                style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 12))),
                      ]),
                    ],
                    // Nhân viên + SĐT badge
                    if (employee.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.person_outline,
                              color: AppTheme.textSecondary, size: 13),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(employee,
                                style: const TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 12),
                                softWrap: true),
                          ),
                          if (employeePhone.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            PhoneWidget(
                              phone: employeePhone,
                              style: const TextStyle(
                                  color: AppTheme.primary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600),
                              prefix: const Icon(Icons.phone,
                                  size: 10, color: AppTheme.primary),
                            ),
                          ],
                        ],
                      ),
                    ],
                    // Ghi chú
                    if (note.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(note,
                          style: TextStyle(
                              color: AppTheme.textSecondary.withOpacity(0.7),
                              fontSize: 11)),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
