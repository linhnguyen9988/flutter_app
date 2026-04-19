import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/order.dart';
import '../screens/order_detail_screen.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import '../services/reload_aware_mixin.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen>
    with ReloadAwareMixin<NotificationScreen> {
  List<Map<String, dynamic>> _notis = [];
  bool _loading = true;
  String? _error;
  StreamSubscription<Map<String, dynamic>>? _notiSub;

  @override
  void initState() {
    super.initState();
    _load();
    // Lắng nghe FCM mới, insert lên đầu list realtime
    _notiSub = NotificationService.onNewNoti.listen((noti) {
      if (mounted) setState(() => _notis.insert(0, noti));
    });
  }

  @override
  void dispose() {
    _notiSub?.cancel();
    super.dispose();
  }

  @override
  void onReload() => _load();

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (ApiService.token.isNotEmpty)
          'Authorization': 'Bearer ${ApiService.token}',
      };

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Backend dùng req.user.id (từ JWT) để query userid trong bảng users
      final uri = Uri.parse('${ApiService.baseUrl}/notifications');
      final res = await http.get(uri, headers: _headers);
      if (res.statusCode == 200) {
        final List data = json.decode(utf8.decode(res.bodyBytes));
        if (mounted) setState(() => _notis = data.cast<Map<String, dynamic>>());
      } else {
        if (mounted) setState(() => _error = 'Lỗi ${res.statusCode}');
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Không kết nối được server');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markRead(Map<String, dynamic> noti) async {
    final id = noti['id']?.toString() ?? '';
    if (id.isEmpty || noti['is_read'] == 1 || noti['is_read'] == true) return;
    try {
      await http.post(
        Uri.parse('${ApiService.baseUrl}/notifications/$id/read'),
        headers: _headers,
      );
      if (mounted) setState(() => noti['is_read'] = 1);
      // Cancel notification khỏi status bar theo noti_id
      NotificationService.cancelByNotiId(id);
    } catch (_) {}
  }

  Future<void> _deleteNoti(Map<String, dynamic> noti) async {
    final id = noti['id']?.toString() ?? '';
    if (id.isEmpty) return;
    try {
      await http.delete(
        Uri.parse('\${ApiService.baseUrl}/notifications/\$id'),
        headers: _headers,
      );
      if (mounted) {
        setState(() => _notis.removeWhere((n) => n['id']?.toString() == id));
      }
    } catch (_) {}
  }

  Future<void> _markAllRead() async {
    try {
      await http.post(
        Uri.parse('${ApiService.baseUrl}/notifications/read-all'),
        headers: _headers,
      );
      if (mounted) {
        setState(() {
          for (final n in _notis) {
            n['is_read'] = 1;
          }
        });
      }
      await NotificationService.cancelAll();
    } catch (_) {}
  }

  void _onTap(Map<String, dynamic> noti) {
    _markRead(noti);
    final realorderid = noti['realorderid']?.toString() ?? '';
    if (realorderid.isEmpty) return;
    final statusRaw = noti['status_code'];
    final order = Order(
      id: 0,
      realorderid: realorderid,
      statuscode: statusRaw is int
          ? statusRaw
          : int.tryParse(statusRaw?.toString() ?? ''),
    );
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => OrderDetailScreen(order: order)),
    );
  }

  bool _isRead(Map<String, dynamic> n) =>
      n['is_read'] == 1 || n['is_read'] == true || n['is_read'] == '1';

  int get _unreadCount => _notis.where((n) => !_isRead(n)).length;

  String _formatTime(dynamic ts) {
    if (ts == null) return '';
    try {
      final dt = DateTime.parse(ts.toString()).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 1) return 'Vừa xong';
      if (diff.inHours < 1) return '${diff.inMinutes} phút trước';
      if (diff.inDays < 1) return '${diff.inHours} giờ trước';
      if (diff.inDays < 7) return '${diff.inDays} ngày trước';
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return '';
    }
  }

  Color _statusColor(int? code) => Order.statusColor(code);

  String _statusEmoji(int? code) {
    if (code == null) return '📦';
    if ([505, 506, 507].contains(code)) return '⚠️';
    if ([502, 515, 551, 504].contains(code)) return '🔄';
    return '📦';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Thông báo'),
            if (_unreadCount > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$_unreadCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (_unreadCount > 0)
            TextButton(
              onPressed: _markAllRead,
              child: const Text(
                'Đọc tất cả',
                style: TextStyle(color: AppTheme.primary, fontSize: 13),
              ),
            ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            )
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.wifi_off,
                        color: AppTheme.textSecondary,
                        size: 48,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: const TextStyle(color: AppTheme.textSecondary),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Thử lại'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                        ),
                      ),
                    ],
                  ),
                )
              : _notis.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.notifications_none,
                            color: AppTheme.textSecondary,
                            size: 48,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Chưa có thông báo',
                            style: TextStyle(color: AppTheme.textSecondary),
                          ),
                          const SizedBox(height: 16),
                          TextButton.icon(
                            onPressed: _load,
                            icon: const Icon(Icons.refresh, size: 16),
                            label: const Text('Tải lại'),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      color: AppTheme.primary,
                      child: ListView.separated(
                        itemCount: _notis.length,
                        separatorBuilder: (_, __) => Divider(
                          height: 0,
                          color: AppTheme.darkSurface.withValues(alpha: 0.5),
                        ),
                        itemBuilder: (_, i) {
                          final n = _notis[i];
                          final read = _isRead(n);
                          final statusCode = n['status_code'] is int
                              ? n['status_code'] as int
                              : int.tryParse(
                                  n['status_code']?.toString() ?? '');
                          final title = n['title']?.toString() ??
                              '${_statusEmoji(statusCode)} Đơn hàng';
                          final body = n['body']?.toString() ?? '';
                          final realorderid =
                              n['realorderid']?.toString() ?? '';
                          final time = _formatTime(n['sent_at']);

                          return Dismissible(
                            key: ValueKey(n['id']?.toString() ?? i.toString()),
                            direction: DismissDirection.endToStart,
                            confirmDismiss: (_) async {
                              return await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      backgroundColor: AppTheme.darkCard,
                                      title: const Text(
                                        'Xóa thông báo',
                                        style: TextStyle(color: Colors.white),
                                      ),
                                      content: const Text(
                                        'Bạn có chắc muốn xóa thông báo này?',
                                        style: TextStyle(
                                            color: AppTheme.textSecondary),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(ctx, false),
                                          child: const Text(
                                            'Hủy',
                                            style: TextStyle(
                                              color: AppTheme.textSecondary,
                                            ),
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(ctx, true),
                                          child: const Text(
                                            'Xóa',
                                            style: TextStyle(
                                              color: Colors.red,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ) ??
                                  false;
                            },
                            onDismissed: (_) => _deleteNoti(n),
                            background: Container(
                              color: Colors.red.shade700,
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              child: const Icon(
                                Icons.delete_outline,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                            child: InkWell(
                              onTap: () => _onTap(n),
                              child: Container(
                                color: read
                                    ? Colors.transparent
                                    : AppTheme.primary.withValues(alpha: 0.06),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 42,
                                      height: 42,
                                      decoration: BoxDecoration(
                                        color: _statusColor(
                                          statusCode,
                                        ).withValues(alpha: 0.12),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Center(
                                        child: Text(
                                          _statusEmoji(statusCode),
                                          style: const TextStyle(fontSize: 18),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  title,
                                                  style: TextStyle(
                                                    color: read
                                                        ? AppTheme.textPrimary
                                                        : Colors.white,
                                                    fontWeight: read
                                                        ? FontWeight.w500
                                                        : FontWeight.w700,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                              ),
                                              if (!read)
                                                Container(
                                                  width: 8,
                                                  height: 8,
                                                  margin: const EdgeInsets.only(
                                                    left: 6,
                                                  ),
                                                  decoration:
                                                      const BoxDecoration(
                                                    color: AppTheme.primary,
                                                    shape: BoxShape.circle,
                                                  ),
                                                ),
                                            ],
                                          ),
                                          if (body.isNotEmpty) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              body,
                                              style: const TextStyle(
                                                color: AppTheme.textSecondary,
                                                fontSize: 12,
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                          if (realorderid.isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              realorderid,
                                              style: TextStyle(
                                                color: _statusColor(statusCode),
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                          if (time.isNotEmpty) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              time,
                                              style: TextStyle(
                                                color: AppTheme.textSecondary
                                                    .withValues(alpha: 0.6),
                                                fontSize: 11,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
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
}
