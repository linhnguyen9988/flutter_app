import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../theme/app_theme.dart';
import '../models/live_comment.dart';
import '../services/api_service.dart';
import '../widgets/app_sidebar.dart';
import 'chat_screen.dart';

const String _mainBackendUrl = 'https://aodaigiabao.com';

class MessagingScreen extends StatefulWidget {
  final List<String> Function()? getLiveIds;
  final List<LiveComment> Function()? getLiveComments;
  const MessagingScreen({
    super.key,
    this.getLiveIds,
    this.getLiveComments,
  });

  @override
  State<MessagingScreen> createState() => MessagingScreenState();
}

class MessagingScreenState extends State<MessagingScreen> {
  List<Map<String, dynamic>> _conversations = [];
  bool _loading = true;
  String _error = '';
  IO.Socket? _socket;
  bool _socketConnected = false;
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _connectSocket();
  }

  void reload() => _loadMessages();

  @override
  void dispose() {
    _socket?.disconnect();
    _socket?.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _connectSocket() {
    _socket = IO.io(
      _mainBackendUrl,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .build(),
    );

    _socket!.onConnect((_) {
      if (mounted) setState(() => _socketConnected = true);
    });

    _socket!.onDisconnect((_) {
      if (mounted) setState(() => _socketConnected = false);
    });

    _socket!.on('new-message', (data) {
      if (!mounted) return;
      final d = Map<String, dynamic>.from(data);
      _onNewMessage(d);
    });

    _socket!.connect();
  }

  void _onNewMessage(Map<String, dynamic> d) {
    final senderId = d['senderId']?.toString() ?? '';
    final recipientId = d['recipientId']?.toString() ?? '';
    final isEcho = d['is_echo'] == true || d['is_echo'] == 'true';
    final text = d['messageText']?.toString() ?? '';
    final fbname = d['fbname']?.toString() ?? '';
    final label = d['label']?.toString() ?? '';
    final image = d['messageImg']?.toString() ?? '';
    final ts = d['timestamp']?.toString() ?? '';

    final khachId = isEcho ? recipientId : senderId;
    final pageId = isEcho ? senderId : recipientId;
    final khachUserId = d['khach_userid']?.toString() ?? khachId;
    final picture = d['picture']?.toString() ?? '';

    if (khachUserId.isEmpty) return;

    setState(() {
      final idx = _conversations.indexWhere(
        (c) => (c['khach_userid']?.toString() ?? '') == khachUserId,
      );

      final preview = text.isNotEmpty
          ? text
          : image.isNotEmpty
              ? '📷 Hình ảnh'
              : '';

      if (idx >= 0) {
        final existing = Map<String, dynamic>.from(_conversations[idx]);
        existing['message'] = preview;
        existing['time'] = ts;
        existing['isNew'] = true;
        existing['is_echo'] = isEcho;
        if (image.isNotEmpty) existing['image'] = image;
        if (fbname.isNotEmpty) existing['ten_khach'] = fbname;
        if (label.isNotEmpty) existing['label'] = label;
        if (picture.isNotEmpty) existing['picture'] = picture;
        existing['khach_userid'] = khachUserId;
        existing['sender'] = senderId;
        existing['recipient'] = recipientId;
        existing['pageid'] = pageId;
        _conversations.removeAt(idx);
        _conversations.insert(0, existing);
      } else {
        _conversations.insert(0, {
          'sender': senderId,
          'recipient': recipientId,
          'khach_userid': khachUserId,
          'pageid': pageId,
          'is_echo': isEcho,
          'message': preview,
          'time': ts,
          'image': image,
          'picture': picture,
          'ten_khach': fbname.isNotEmpty ? fbname : khachUserId,
          'label': label,
          'isNew': true,
        });
      }
    });
  }

  Future<void> _loadMessages() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final uri = Uri.parse('$_mainBackendUrl/api/last-messages');
      final res = await http.get(uri, headers: {
        if (ApiService.token.isNotEmpty)
          'Authorization': 'Bearer ${ApiService.token}',
      });
      if (res.statusCode == 200) {
        final List data = json.decode(res.body);
        setState(() {
          _conversations = data.cast<Map<String, dynamic>>();
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'Lỗi ${res.statusCode}';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Không kết nối được server';
        _loading = false;
      });
    }
  }

  String _displayName(Map<String, dynamic> c) =>
      (c['ten_khach'] ?? c['sender'] ?? '').toString();

  String _previewText(Map<String, dynamic> c) {
    final isPage = _isEcho(c);
    final prefix = isPage ? 'Bạn: ' : '';
    final msg = (c['message'] ?? '').toString();
    final images = c['images'];
    if (msg.isEmpty && images != null && (images as List).isNotEmpty) {
      return '${prefix}📷 Hình ảnh';
    }
    if (msg.isEmpty) return '';
    return '$prefix$msg';
  }

  bool _isEcho(Map<String, dynamic> c) {
    final v = c['is_echo'];
    if (v == null) {
      final sender = c['sender']?.toString() ?? '';
      final pageid = c['pageid']?.toString() ?? '';
      if (pageid.isNotEmpty) return sender == pageid;
      return false;
    }
    return v == 1 || v == '1' || v == true || v == 'true';
  }

  String _khachUserId(Map<String, dynamic> c) {
    final uid = c['khach_userid']?.toString() ?? '';
    if (uid.isNotEmpty) return uid;

    final isEcho = _isEcho(c);
    return isEcho
        ? c['recipient']?.toString() ?? ''
        : c['sender']?.toString() ?? '';
  }

  String _avatarUrl(Map<String, dynamic> c) {
    final userid = _khachUserId(c);
    return 'https://aodaigiabao.com/images/ava/$userid.jpg';
  }

  String _fbPicture(Map<String, dynamic> c) => c['picture']?.toString() ?? '';

  Color _labelColor(String? label) {
    switch (label) {
      case 'Bom hàng':
      case 'Xả hàng':
        return Colors.red;
      case 'Có vấn đề':
        return Colors.amber;
      default:
        return Colors.transparent;
    }
  }

  String _pageId(Map<String, dynamic> c) {
    if (c.containsKey('pageid') &&
        c['pageid'] != null &&
        c['pageid'].toString().isNotEmpty) {
      return c['pageid'].toString();
    }
    final isEcho = _isEcho(c);
    return isEcho
        ? c['sender']?.toString() ?? ''
        : c['recipient']?.toString() ?? '';
  }

  String _formatTime(dynamic ts) {
    if (ts == null) return '';
    try {
      final s = ts.toString().trim();
      if (s.isEmpty) return '';
      DateTime dt;
      if (RegExp(r'^\d+$').hasMatch(s)) {
        final ms = int.parse(s);
        dt = DateTime.fromMillisecondsSinceEpoch(
            ms > 9999999999 ? ms : ms * 1000);
      } else {
        dt = DateTime.parse(s);
      }
      final now = DateTime.now();
      final diff = now.difference(dt);
      final sec = diff.inSeconds;
      final min = diff.inMinutes;
      final hrs = diff.inHours;
      final days = diff.inDays;
      if (sec < 60) return '$sec giây trước';
      if (min < 60) return '$min phút trước';
      if (hrs < 24) return '$hrs giờ trước';
      if (days < 30) return '$days ngày trước';
      final months = (days / 30.44).floor();
      if (months < 12) return '$months tháng trước';
      return '${(days / 365.25).floor()} năm trước';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          const Text('Tin nhắn'),
          const SizedBox(width: 8),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: _socketConnected ? AppTheme.accent : Colors.red,
              shape: BoxShape.circle,
            ),
          ),
        ]),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadMessages,
              visualDensity: VisualDensity.compact,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => AppSidebar.show(context),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary))
          : _error.isNotEmpty
              ? _buildError()
              : _conversations.isEmpty
                  ? _buildEmpty()
                  : RefreshIndicator(
                      onRefresh: _loadMessages,
                      color: AppTheme.primary,
                      child: ListView.separated(
                        controller: _scrollCtrl,
                        itemCount: _conversations.length,
                        separatorBuilder: (_, __) => Divider(
                            height: 0,
                            color: AppTheme.darkSurface.withOpacity(0.5)),
                        itemBuilder: (_, i) {
                          final c = _conversations[i];
                          final khachId = _khachUserId(c);
                          return _buildTile(c, khachId: khachId, index: i);
                        },
                      ),
                    ),
    );
  }

  Widget _buildTile(Map<String, dynamic> c,
      {required String khachId, int index = -1}) {
    final name = _displayName(c);
    final preview = _previewText(c);
    final avaUrl = _avatarUrl(c);
    final label = c['label']?.toString() ?? '';
    final hasLabel = label.isNotEmpty;
    final labelColor = _labelColor(label);
    final isNew = c['isNew'] == true;

    return InkWell(
      onTap: () {
        final idx = _conversations.indexWhere(
          (x) => (x['khach_userid']?.toString() ?? '') == khachId,
        );
        final current = idx >= 0 ? _conversations[idx] : c;
        setState(() => current['isNew'] = false);
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => ChatScreen(
                    sender: khachId,
                    pageId: _pageId(current),
                    customerName: _displayName(current),
                    avatarUrl: _avatarUrl(current),
                    selectedLiveIds: widget.getLiveIds?.call() ?? const [],
                    liveComments: widget.getLiveComments?.call() ?? const [],
                  )),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Stack(children: [
              _AvatarWithFallback(
                primaryUrl: avaUrl,
                fallbackUrl: _fbPicture(c),
                radius: 24,
              ),
              if (hasLabel && labelColor != Colors.transparent)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: labelColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.darkBg, width: 1.5),
                    ),
                  ),
                ),
            ]),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Row(children: [
                        Flexible(
                          child: Text(
                            name,
                            style: TextStyle(
                              color:
                                  isNew ? Colors.white : AppTheme.textPrimary,
                              fontWeight:
                                  isNew ? FontWeight.w700 : FontWeight.w500,
                              fontSize: 15,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (hasLabel) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: labelColor.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                  color: labelColor.withOpacity(0.4)),
                            ),
                            child: Text(label,
                                style: TextStyle(
                                    color: labelColor,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ]),
                    ),
                    Text(
                      _formatTime(c['timestamp'] ?? c['time']),
                      style: TextStyle(
                        color:
                            isNew ? AppTheme.primary : AppTheme.textSecondary,
                        fontSize: 11,
                        fontWeight: isNew ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Row(children: [
                    Expanded(
                      child: Text(
                        preview,
                        style: TextStyle(
                          color: isNew
                              ? AppTheme.textPrimary
                              : AppTheme.textSecondary,
                          fontSize: 13,
                          fontWeight: isNew ? FontWeight.w500 : FontWeight.w400,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                    if (isNew)
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(left: 6),
                        decoration: const BoxDecoration(
                            color: AppTheme.primary, shape: BoxShape.circle),
                      ),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() => Center(
          child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off, color: AppTheme.textSecondary, size: 48),
          const SizedBox(height: 12),
          Text(_error, style: TextStyle(color: AppTheme.textSecondary)),
          const SizedBox(height: 8),
          ElevatedButton(
              onPressed: _loadMessages, child: const Text('Thử lại')),
        ],
      ));

  Widget _buildEmpty() => Center(
          child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.chat_bubble_outline,
              color: AppTheme.textSecondary, size: 48),
          const SizedBox(height: 12),
          Text('Chưa có tin nhắn',
              style: TextStyle(color: AppTheme.textSecondary)),
        ],
      ));
}

class _AvatarWithFallback extends StatefulWidget {
  final String primaryUrl;
  final String fallbackUrl;
  final double radius;

  const _AvatarWithFallback({
    required this.primaryUrl,
    required this.fallbackUrl,
    this.radius = 24,
  });

  @override
  State<_AvatarWithFallback> createState() => _AvatarWithFallbackState();
}

class _AvatarWithFallbackState extends State<_AvatarWithFallback> {
  bool _useFallback = false;

  @override
  void didUpdateWidget(_AvatarWithFallback old) {
    super.didUpdateWidget(old);
    if (old.primaryUrl != widget.primaryUrl) {
      setState(() => _useFallback = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = _useFallback && widget.fallbackUrl.isNotEmpty
        ? widget.fallbackUrl
        : widget.primaryUrl;

    return CircleAvatar(
      radius: widget.radius,
      backgroundColor: AppTheme.darkSurface,
      backgroundImage: url.isNotEmpty ? NetworkImage(url) : null,
      onBackgroundImageError:
          url.isNotEmpty && !_useFallback && widget.fallbackUrl.isNotEmpty
              ? (_, __) => setState(() => _useFallback = true)
              : (_, __) {},
    );
  }
}
