import 'package:ao_dai_gia_bao/widgets/page_filter_chip.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/order.dart';
import '../models/live_comment.dart';
import '../services/api_service.dart';
import '../widgets/app_sidebar.dart';
import 'order_timeline_screen.dart';

class OrdersScreen extends StatefulWidget {
  final List<String> Function()? getLiveIds;
  final List<LiveComment> Function()? getLiveComments;
  const OrdersScreen({super.key, this.getLiveIds, this.getLiveComments});

  @override
  State<OrdersScreen> createState() => OrdersScreenState();
}

class OrdersScreenState extends State<OrdersScreen> {
  bool get isDark => Theme.of(context).brightness == Brightness.dark;

  List<Order> _orders = [];
  bool _loading = true;
  String? _statusFilter;
  final _searchCtrl = TextEditingController();
  String _searchText = '';

  final _statusOptions = [
    {'label': 'Tất cả', 'value': null},
    {'label': 'Mới tạo', 'value': 'new'},
    {'label': 'Đang xử lý', 'value': 'processing'},
    {'label': 'Đang vận chuyển', 'value': 'shipping'},
    {'label': 'Đang phát', 'value': 'delivering'},
    {'label': 'Phát thành công', 'value': 'success'},
    {'label': 'Có vấn đề', 'value': 'ton'},
    {'label': 'Chuyển hoàn', 'value': 'return'},
    {'label': 'Đã hủy', 'value': 'cancel'},
  ];

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  void reload() => _loadOrders();

  Future<void> _loadOrders() async {
    try {
      List<Order> orders;

      Future<List<Order>> multi(List<String> statuses) async {
        final results = await Future.wait(
          statuses
              .map((s) => ApiService.getOrders(status: s, search: _searchText)),
        );
        final all = results.expand((r) => r).toList();
        all.sort((a, b) => b.id.compareTo(a.id));
        return all;
      }

      if (_statusFilter == 'new') {
        orders = await multi(['-108', '100', '103', '104']);
      } else if (_statusFilter == 'processing') {
        orders = await multi(['102']);
      } else if (_statusFilter == 'shipping') {
        orders = await multi(['200', '202', '300', '400', '509']);
      } else if (_statusFilter == 'delivering') {
        orders = await multi(['500', '508', '550']);
      } else if (_statusFilter == 'success') {
        orders = await multi(['501']);
      } else if (_statusFilter == 'ton') {
        orders = await multi(['505', '506', '507']);
      } else if (_statusFilter == 'return') {
        orders = await multi(['502', '515', '551', '504']);
      } else if (_statusFilter == 'cancel') {
        orders = await multi(['107', '503']);
      } else {
        orders = await ApiService.getOrders(
          status: _statusFilter,
          search: _searchText,
        );
      }

      final q = _nd(_searchText.trim());
      if (q.isNotEmpty) {
        orders = orders.where((o) {
          final name = _nd(o.name ?? '');
          final phone = (o.phone ?? '').toLowerCase();
          final orderid = (o.realorderid ?? '').toLowerCase();
          return name.contains(q) || phone.contains(q) || orderid.contains(q);
        }).toList();
      }

      setState(() {
        _orders = orders;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _cancelOrder(Order order) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.cardColor(isDark),
        title: Text('Xác nhận hủy đơn',
            style: TextStyle(color: AppTheme.textColor(isDark), fontSize: 16)),
        content: Text(
          'Hủy đơn ${order.realorderid ?? order.id.toString()}?\nThao tác này không thể hoàn tác.',
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

    final oldStatus = order.statuscode;
    setState(() {
      final idx = _orders.indexWhere((o) => o.id == order.id);
      if (idx != -1) {
        _orders[idx].statuscode = 107;
      }
    });

    try {
      final result = await ApiService.postRaw(
        'https://aodaigiabao.com/huydonviettel',
        {'realorderid': order.realorderid ?? '', 'xoa': 0},
      );
      if (!mounted) return;

      final msg = result?['message']?.toString() ?? 'Đã hủy đơn';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.green.shade700),
      );

      _loadOrders();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        final idx = _orders.indexWhere((o) => o.id == order.id);
        if (idx != -1) _orders[idx].statuscode = oldStatus;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Lỗi kết nối, chưa hủy được'),
            backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Container(
            height: 36,
            alignment: Alignment.centerLeft,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppTheme.surfaceColor(isDark),
              borderRadius: BorderRadius.circular(10),
            ),
            child: TextField(
              controller: _searchCtrl,
              style: TextStyle(
                  color: AppTheme.textColor(isDark), fontSize: 14, height: 1.0),
              onChanged: (v) {
                setState(() => _searchText = v);
                _loadOrders();
              },
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Mã đơn, tên, sđt...',
                hintStyle: TextStyle(
                    color: AppTheme.textSubColor(isDark).withValues(alpha: 0.7), fontSize: 14),
                prefixIcon: Icon(Icons.search,
                    color: AppTheme.textSubColor(isDark), size: 20),
                suffixIcon: _searchText.isNotEmpty
                    ? GestureDetector(
                        onTap: () {
                          _searchCtrl.clear();
                          setState(() => _searchText = '');
                          _loadOrders();
                        },
                        child: Icon(Icons.close,
                            color: AppTheme.textSubColor(isDark), size: 18),
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.only(top: 11, bottom: 9),
              ),
            ),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 2),
            child: IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadOrders,
              visualDensity: VisualDensity.compact,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => AppSidebar.show(context),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(32),
          child: Transform.translate(
            offset: const Offset(0, -6),
            child: Container(
              height: 32,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: _statusOptions.map((opt) {
                  return PageFilterChip(
                    label: opt['label'] as String,
                    selected: _statusFilter == opt['value'],
                    onTap: () {
                      setState(() => _statusFilter = opt['value']);
                      _loadOrders();
                    },
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary))
          : _orders.isEmpty
              ? Center(
                  child: Text('Không có đơn hàng',
                      style: TextStyle(color: AppTheme.textSubColor(isDark))))
              : RefreshIndicator(
                  onRefresh: _loadOrders,
                  color: AppTheme.primary,
                  child: ListView.separated(
                    itemCount: _orders.length,
                    separatorBuilder: (_, __) => Divider(
                        height: 0,
                        color: AppTheme.dividerColor(isDark)),
                    itemBuilder: (_, i) => _buildOrderTile(_orders[i]),
                  ),
                ),
    );
  }

  static String _nd(String s) {
    const map = {
      'à': 'a',
      'á': 'a',
      'ả': 'a',
      'ã': 'a',
      'ạ': 'a',
      'ă': 'a',
      'ắ': 'a',
      'ặ': 'a',
      'ằ': 'a',
      'ẳ': 'a',
      'ẵ': 'a',
      'â': 'a',
      'ấ': 'a',
      'ầ': 'a',
      'ẩ': 'a',
      'ẫ': 'a',
      'ậ': 'a',
      'è': 'e',
      'é': 'e',
      'ẻ': 'e',
      'ẽ': 'e',
      'ẹ': 'e',
      'ê': 'e',
      'ế': 'e',
      'ề': 'e',
      'ể': 'e',
      'ễ': 'e',
      'ệ': 'e',
      'ì': 'i',
      'í': 'i',
      'ỉ': 'i',
      'ĩ': 'i',
      'ị': 'i',
      'ò': 'o',
      'ó': 'o',
      'ỏ': 'o',
      'õ': 'o',
      'ọ': 'o',
      'ô': 'o',
      'ố': 'o',
      'ồ': 'o',
      'ổ': 'o',
      'ỗ': 'o',
      'ộ': 'o',
      'ơ': 'o',
      'ớ': 'o',
      'ờ': 'o',
      'ở': 'o',
      'ỡ': 'o',
      'ợ': 'o',
      'ù': 'u',
      'ú': 'u',
      'ủ': 'u',
      'ũ': 'u',
      'ụ': 'u',
      'ư': 'u',
      'ứ': 'u',
      'ừ': 'u',
      'ử': 'u',
      'ữ': 'u',
      'ự': 'u',
      'ỳ': 'y',
      'ý': 'y',
      'ỷ': 'y',
      'ỹ': 'y',
      'ỵ': 'y',
      'đ': 'd',
    };
    return s.toLowerCase().split('').map((c) => map[c] ?? c).join();
  }

  Widget _highlight(String text, TextStyle baseStyle,
      {TextOverflow? overflow, int? maxLines}) {
    final q = _nd(_searchText.trim());
    if (q.isEmpty) {
      return Text(text,
          style: baseStyle, overflow: overflow, maxLines: maxLines);
    }
    final lower = _nd(text);
    final spans = <TextSpan>[];
    int start = 0;
    while (true) {
      final idx = lower.indexOf(q, start);
      if (idx < 0) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (idx > start) {
        spans.add(TextSpan(text: text.substring(start, idx)));
      }
      spans.add(TextSpan(
        text: text.substring(idx, idx + q.length),
        style: const TextStyle(
            color: Colors.lightGreen, fontWeight: FontWeight.w700),
      ));
      start = idx + q.length;
    }
    return RichText(
      text: TextSpan(style: baseStyle, children: spans),
      overflow: overflow ?? TextOverflow.clip,
      maxLines: maxLines,
    );
  }

  Widget _buildOrderTile(Order order) {
    final statusColor = Order.statusColor(order.statuscode);
    final canCancel = (order.statuscode ?? 999) < 107;
    final avatarUrl = order.userid != null && order.userid!.isNotEmpty
        ? 'https://aodaigiabao.com/images/ava/${order.userid}.jpg'
        : null;

    final tile = InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => OrderTimelineScreen(
                  order: order,
                  getLiveIds: widget.getLiveIds,
                  getLiveComments: widget.getLiveComments,
                )),
      ),
      child: Container(
        color: AppTheme.bgColor(isDark),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: AppTheme.surfaceColor(isDark),
              backgroundImage:
                  avatarUrl != null ? NetworkImage(avatarUrl) : null,
              onBackgroundImageError: avatarUrl != null ? (_, __) {} : null,
              child: avatarUrl == null
                  ? Icon(Icons.person,
                      color: AppTheme.textSubColor(isDark), size: 20)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _highlight(
                          order.name ?? 'Không có tên',
                          TextStyle(
                            color: AppTheme.textColor(isDark),
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          order.displayStatus,
                          style: TextStyle(
                              color: statusColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              height: 1.3),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  if (order.address != null && order.address!.isNotEmpty)
                    Text(
                      order.address!,
                      style: TextStyle(
                          color: AppTheme.textSubColor(isDark), fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (order.phone != null)
                        _highlight(
                            '📱 ${order.phone}',
                            TextStyle(
                                color: AppTheme.textSubColor(isDark), fontSize: 12)),
                      if (order.phone != null && order.realorderid != null)
                        const Text('  ', style: TextStyle(fontSize: 12)),
                      if (order.realorderid != null)
                        Expanded(
                          child: _highlight(
                              '🔖 ${order.realorderid}',
                              TextStyle(
                                  color: AppTheme.textSubColor(isDark), fontSize: 12),
                              overflow: TextOverflow.ellipsis),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        'COD: ${order.codFormatted}',
                        style: const TextStyle(
                            color: AppTheme.accent,
                            fontSize: 13,
                            fontWeight: FontWeight.w600),
                      ),
                      if (order.kg != null) ...[
                        const SizedBox(width: 10),
                        Text('${order.kg}kg',
                            style: TextStyle(
                                color: AppTheme.textSubColor(isDark), fontSize: 12)),
                      ],
                      const Spacer(),
                      Text(
                        order.date ?? '',
                        style: TextStyle(
                            color: AppTheme.textSubColor(isDark), fontSize: 11),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (!canCancel) return tile;

    return Dismissible(
      key: ValueKey('order_${order.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        await _cancelOrder(order);
        return false;
      },
      background: Container(
        color: Colors.red.shade700,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cancel_outlined, color: Colors.white, size: 28),
            SizedBox(height: 4),
            Text('Hủy đơn',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
      child: tile,
    );
  }
}
