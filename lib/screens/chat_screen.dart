import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:image_picker/image_picker.dart';
import '../theme/app_theme.dart';
import '../models/message.dart';
import '../models/customer.dart';
import '../models/live_comment.dart';
import '../models/order.dart';
import '../services/api_service.dart';
import 'order_timeline_screen.dart';
import 'customer_detail_screen.dart';

class ChatScreen extends StatefulWidget {
  final String sender;
  final String pageId;
  final String? customerName;
  final String? customerId;
  final String? initialMessage;
  final String? avatarUrl;
  final List<String> selectedLiveIds;
  final List<LiveComment> liveComments;

  const ChatScreen({
    super.key,
    required this.sender,
    required this.pageId,
    this.customerName,
    this.customerId,
    this.initialMessage,
    this.avatarUrl,
    this.selectedLiveIds = const [],
    this.liveComments = const [],
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  List<Message> _messages = [];
  Customer? _customer;
  Order? _latestOrder;
  bool _loading = true;
  bool _sending = false;
  File? _pickedImage;
  final _replyCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  int _offset = 0;
  bool _hasMore = true;
  bool _loadingMore = false;
  final _picker = ImagePicker();
  IO.Socket? _socket;
  // ignore: unused_field
  bool _isLoadingHistory = false;
  bool _initialLoad = true;
  int _readWatermark = 0;
  final Map<String, String> _reactions = {};

  String get _avatarUrl =>
      'https://aodaigiabao.com/images/ava/${widget.sender}.jpg';

  // Fallback FB picture nếu ảnh server chưa kịp lưu
  String get _fbPicture => widget.avatarUrl ?? '';

  String get _displayName =>
      _customer?.fbname ?? widget.customerName ?? widget.sender;

  String get _latestOrderInfo {
    final o = _latestOrder;
    if (o == null) return '';
    final gia = o.cod != null ? o.codFormatted : '?đ';
    final kg = o.kg != null ? '${o.kg}kg' : '?kg';
    String ngay = '';
    try {
      final raw = o.time ?? '';
      if (raw.isNotEmpty) {
        final dt = DateTime.parse(raw);
        final dd = dt.day.toString().padLeft(2, '0');
        final mm = dt.month.toString().padLeft(2, '0');
        final yy = (dt.year % 100).toString().padLeft(2, '0');
        ngay = '$dd/$mm/$yy';
      }
    } catch (_) {}
    final status = o.displayStatus;
    return [gia, kg, if (ngay.isNotEmpty) ngay, status].join(' · ');
  }

  Color get _latestOrderColor => _latestOrder != null
      ? Order.statusColor(_latestOrder!.statuscode)
      : AppTheme.textSecondary;

  @override
  void initState() {
    super.initState();
    // Tự điền tin nhắn chốt đơn nếu có
    if (widget.initialMessage != null && widget.initialMessage!.isNotEmpty) {
      _replyCtrl.text = widget.initialMessage!;
    }
    _loadConversation();
    _loadCustomer();
    _loadLatestOrder();
    _connectSocket();
  }

  void _connectSocket() {
    _socket = IO.io(
      'https://aodaigiabao.com',
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .build(),
    );

    _socket!.on('new-message', (data) {
      if (!mounted) return;
      final d = Map<String, dynamic>.from(data);

      final senderId = d['senderId']?.toString() ?? '';
      final recipientId = d['recipientId']?.toString() ?? '';

      final isEcho = d['is_echo'] == true || d['is_echo'] == 'true';

      final actualSender =
          isEcho ? (d['pageId']?.toString() ?? widget.pageId) : senderId;
      final actualRecipient =
          isEcho ? senderId : (d['pageId']?.toString() ?? widget.pageId);

      final khachId = isEcho ? recipientId : senderId;

      if (khachId == widget.sender) {
        final text = d['messageText'] ?? d['message'] ?? '';
        final img = d['messageImg'] ?? '';
        final ts = d['timestamp'];
        int timestamp = 0;
        if (ts != null) timestamp = int.tryParse(ts.toString()) ?? 0;

        final newMsg = Message(
          id: 0,
          messid: d['messid']?.toString() ??
              DateTime.now().millisecondsSinceEpoch.toString(),
          sender: actualSender,
          recipient: actualRecipient,
          message: text.isNotEmpty ? text : null,
          image: img.isNotEmpty ? img : null,
          time: DateTime.now().toIso8601String(),
          isRead: 0,
          timestamp:
              timestamp > 0 ? timestamp : DateTime.now().millisecondsSinceEpoch,
        );

        final isDup = _messages.any((m) => m.messid == newMsg.messid);
        if (isDup) return;

        if (isEcho) {
          final localIdx = _messages.lastIndexWhere((m) =>
              m.messid.startsWith('local_') &&
              (newMsg.timestamp - m.timestamp).abs() < 15000);
          if (localIdx >= 0) {
            setState(() => _messages[localIdx] = newMsg);
            return;
          }
        }

        setState(() => _messages.add(newMsg));
        _scrollToBottom();
      }
    });

    _socket!.connect();

    // Khách đã đọc tin của page
    _socket!.on('read', (data) {
      if (!mounted) return;
      final d = Map<String, dynamic>.from(data);
      final senderId = d['senderId']?.toString() ?? '';
      final watermark = d['watermark'];
      if (senderId != widget.sender) return;
      final wm = watermark is int
          ? watermark
          : int.tryParse(watermark.toString()) ?? 0;
      if (wm > _readWatermark) {
        setState(() => _readWatermark = wm);
      }
    });

    // Khách thả reaction vào tin của page
    _socket!.on('reaction', (data) {
      if (!mounted) return;
      final d = Map<String, dynamic>.from(data);
      final senderId = d['senderId']?.toString() ?? '';
      final mid = d['mid']?.toString() ?? '';
      final emoji = d['emoji']?.toString() ?? '';
      if (senderId != widget.sender || mid.isEmpty || emoji.isEmpty) return;
      setState(() => _reactions[mid] = emoji);
    });
  }

  Future<void> _loadCustomer() async {
    try {
      // Tìm khách theo psid/userid
      final list = await ApiService.getCustomers(search: widget.sender);
      if (list.isNotEmpty && mounted) {
        setState(() => _customer = list.first);
      }
    } catch (_) {}
  }

  Future<void> _loadLatestOrder() async {
    try {
      final orders = await ApiService.getUserOrders(widget.sender);
      if (orders.isNotEmpty && mounted) {
        setState(() => _latestOrder = orders.first);
      }
    } catch (_) {}
  }

  String _getAbsoluteUrl(String path) {
    if (path.isEmpty) return '';
    if (path.startsWith('http')) return path;
    const domain = 'https://aodaigiabao.com';
    return path.startsWith('/') ? '$domain$path' : '$domain/$path';
  }

  Future<void> _loadConversation() async {
    _offset = 0;
    setState(() => _loading = true);
    try {
      final result = await ApiService.getConversation(widget.sender,
          limit: 10, offset: _offset);

      final msgs = result.messages
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

      setState(() {
        _messages = msgs;
        _loading = false;
        _hasMore = msgs.length == 10;

        _reactions.clear(); // Xoá cũ cho chắc
        if (result.reactions.isNotEmpty) {
          _reactions.addAll(result.reactions);
        }
        for (var m in msgs) {
          if (m.reactions != null && m.reactions!.isNotEmpty) {
            _reactions[m.messid] = m.reactions! as String;
          }
        }
        // ------------------------------------------------

        if (result.readWatermark > _readWatermark) {
          _readWatermark = result.readWatermark;
        }
      });

      if (_initialLoad) {
        _initialLoad = false;
        _scrollToBottom();
      }
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    _isLoadingHistory = true;
    setState(() => _loadingMore = true);
    _offset += 10;
    try {
      // Gọi API lấy thêm tin nhắn cũ kèm reaction và watermark
      final result = await ApiService.getConversation(widget.sender,
          limit: 10, offset: _offset);

      final msgs = result.messages
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

      // Lưu vị trí cuộn hiện tại trước khi render tin nhắn mới
      final prevPixels =
          _scrollCtrl.hasClients ? _scrollCtrl.position.pixels : 0.0;
      final prevMaxExtent =
          _scrollCtrl.hasClients ? _scrollCtrl.position.maxScrollExtent : 0.0;

      setState(() {
        // Nạp thêm reaction từ DB vào Map hiển thị để không bị thiếu icon
        if (result.reactions.isNotEmpty) {
          _reactions.addAll(result.reactions);
        }

        // Thêm tin nhắn cũ vào đầu danh sách hiện tại
        _messages = [...msgs, ..._messages];
        _hasMore = msgs.length == 10;
        _loadingMore = false;
      });

      // Sau khi Flutter vẽ lại UI, bù lại chiều cao để giữ nguyên vị trí nhìn của user
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollCtrl.hasClients) return;
        final newMaxExtent = _scrollCtrl.position.maxScrollExtent;
        final addedHeight = newMaxExtent - prevMaxExtent;
        _scrollCtrl.jumpTo(prevPixels + addedHeight);

        // Reset flag chờ ổn định
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) _isLoadingHistory = false;
        });
      });
    } catch (e) {
      if (mounted) setState(() => _loadingMore = false);
      _isLoadingHistory = false;
    }
  }

  void _scrollToBottom() {
    // Dùng delay để chờ ảnh trong list render xong rồi mới scroll
    Future.delayed(const Duration(milliseconds: 400), () {
      if (!mounted || !_scrollCtrl.hasClients) return;
      _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
    });
  }

  Future<void> _pickFromGallery() async {
    final picked =
        await _picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked != null) setState(() => _pickedImage = File(picked.path));
  }

  Future<void> _pickFromCamera() async {
    final picked =
        await _picker.pickImage(source: ImageSource.camera, imageQuality: 80);
    if (picked != null) setState(() => _pickedImage = File(picked.path));
  }

  Future<void> _sendReply() async {
    final text = _replyCtrl.text.trim();
    if ((text.isEmpty && _pickedImage == null) || _sending) return;
    setState(() => _sending = true);

    final imageFile = _pickedImage;

    try {
      final ok = await ApiService.sendMessage(
        recipient: widget.sender,
        message: text,
        pageId: widget.pageId,
        imageFile: imageFile,
      );
      if (ok) {
        _replyCtrl.clear();
        if (mounted) {
          setState(() {
            _pickedImage = null;
            // Optimistic update — hiện ngay cho user thấy, socket echo sẽ cập nhật sau
            final ts = DateTime.now().millisecondsSinceEpoch;
            _messages.add(Message(
              id: 0,
              messid: 'local_$ts',
              sender: widget.pageId,
              recipient: widget.sender,
              message: text.isNotEmpty ? text : null,
              image: imageFile?.path, // null nếu chỉ gửi chữ
              time: DateTime.now().toIso8601String(),
              isRead: 1,
              timestamp: ts,
            ));
          });
          _scrollToBottom();
        }
      } else {
        _showError('Gửi thất bại');
      }
    } catch (_) {
      _showError('Lỗi kết nối');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            // Avatar: thử ava/{userid}.jpg, fallback FB picture nếu lỗi
            _AvatarWithFallback(
              primaryUrl: _avatarUrl,
              fallbackUrl: _fbPicture,
              radius: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _displayName,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (_latestOrderInfo.isNotEmpty)
                    GestureDetector(
                      onTap: _latestOrder != null
                          ? () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      OrderTimelineScreen(order: _latestOrder!),
                                ),
                              )
                          : null,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              _latestOrderInfo,
                              style: TextStyle(
                                fontSize: 11,
                                color: _latestOrderColor,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 3),
                          Icon(Icons.chevron_right,
                              size: 13, color: _latestOrderColor),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh), onPressed: _loadConversation),
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: 'Chi tiết khách hàng',
            onPressed: () {
              if (_customer != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CustomerDetailScreen(
                      customer: _customer!,
                      selectedLiveIds: widget.selectedLiveIds,
                      liveComments: widget.liveComments,
                    ),
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Đang tải thông tin khách hàng...'),
                  ),
                );
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppTheme.primary))
                  : _messages.isEmpty
                      ? const Center(
                          child: Text('Chưa có tin nhắn',
                              style: TextStyle(color: AppTheme.textSecondary)))
                      : Listener(
                          onPointerUp: (_) {
                            if (!_scrollCtrl.hasClients) return;
                            if (_scrollCtrl.position.pixels <= 60) {
                              _loadMore();
                            }
                          },
                          child: NotificationListener<ScrollUpdateNotification>(
                            onNotification: (n) {
                              return false;
                            },
                            child: ListView.builder(
                              controller: _scrollCtrl,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              itemCount:
                                  _messages.length + (_loadingMore ? 1 : 0),
                              itemBuilder: (_, i) {
                                if (i == 0 && _loadingMore) {
                                  return const Padding(
                                    padding: EdgeInsets.all(8),
                                    child: Center(
                                        child: SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: AppTheme.primary))),
                                  );
                                }
                                final msgIdx = _loadingMore ? i - 1 : i;
                                return _buildBubble(_messages[msgIdx]);
                              },
                            ),
                          ),
                        ),
            ),
            // Preview ảnh đã chọn
            if (_pickedImage != null) _buildImagePreview(),
            _buildReplyBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildBubble(Message msg) {
    final isIncoming = msg.sender == widget.sender;
    final images = msg.imageList;
    final isRead =
        !isIncoming && _readWatermark >= msg.timestamp && msg.timestamp > 0;
    final reaction = _reactions[msg.messid];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment:
            isIncoming ? MainAxisAlignment.start : MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (isIncoming) ...[
            _AvatarWithFallback(
              primaryUrl: _avatarUrl,
              fallbackUrl: _fbPicture,
              radius: 14,
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isIncoming
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.end,
              children: [
                if (images.isNotEmpty)
                  ...images.map((path) {
                    // Kiểm tra like trước tiên — bất kể path dạng gì
                    if (path.toLowerCase().contains('like')) {
                      return const Padding(
                        padding: EdgeInsets.only(bottom: 4),
                        child: Text('👍', style: TextStyle(fontSize: 30)),
                      );
                    }
                    // path local (ảnh vừa gửi chưa có URL server)
                    if (!path.startsWith('http')) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(
                            File(path),
                            width: 200,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const SizedBox.shrink(),
                          ),
                        ),
                      );
                    }
                    final url = _getAbsoluteUrl(path);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          _buildImageBubble(url),
                          if (reaction != null)
                            Positioned(
                              bottom: -10,
                              left: 6,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: AppTheme.darkCard,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                      color: AppTheme.darkSurface, width: 1.5),
                                ),
                                child: Text(reaction,
                                    style: const TextStyle(fontSize: 12)),
                              ),
                            ),
                        ],
                      ),
                    );
                  }),
                if (msg.message != null && msg.message!.isNotEmpty)
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      GestureDetector(
                        onLongPress: () {
                          HapticFeedback.mediumImpact();
                          Clipboard.setData(ClipboardData(text: msg.message!));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Đã copy tin nhắn'),
                              duration: Duration(seconds: 1),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: isIncoming
                                ? AppTheme.darkSurface
                                : AppTheme.primary,
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(18),
                              topRight: const Radius.circular(18),
                              bottomLeft: Radius.circular(isIncoming ? 4 : 18),
                              bottomRight: Radius.circular(isIncoming ? 18 : 4),
                            ),
                          ),
                          child: Text(msg.message!,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 14)),
                        ),
                      ),
                      // Reaction emoji khách thả — góc dưới trái bubble
                      if (reaction != null)
                        Positioned(
                          bottom: -10,
                          left: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppTheme.darkCard,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: AppTheme.darkSurface, width: 1.5),
                            ),
                            child: Text(reaction,
                                style: const TextStyle(fontSize: 12)),
                          ),
                        ),
                    ],
                  ),
                SizedBox(height: reaction != null ? 14 : 2),
                // Timestamp + avatar đã đọc
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_formatTime(msg.dateTime),
                        style: const TextStyle(
                            color: AppTheme.textSecondary, fontSize: 8)),
                    if (isRead) ...[
                      const SizedBox(width: 3),
                      CircleAvatar(
                        radius: 4,
                        backgroundColor: AppTheme.darkSurface,
                        backgroundImage: NetworkImage(_avatarUrl),
                        onBackgroundImageError: (_, __) {},
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageBubble(String url) {
    return GestureDetector(
      onTap: () => _openImage(url),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          url,
          width: 200,
          fit: BoxFit.cover,
          loadingBuilder: (_, child, progress) {
            if (progress == null) return child;
            return Container(
                width: 200,
                height: 120,
                color: AppTheme.darkSurface,
                child: const Center(
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppTheme.primary)));
          },
          errorBuilder: (_, __, ___) => Container(
            width: 200,
            height: 80,
            color: AppTheme.darkSurface,
            child: const Center(
                child: Icon(Icons.broken_image, color: AppTheme.textSecondary)),
          ),
        ),
      ),
    );
  }

  Widget _buildImagePreview() {
    return Container(
      color: AppTheme.darkCard,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(_pickedImage!,
                width: 60, height: 60, fit: BoxFit.cover),
          ),
          const SizedBox(width: 10),
          Expanded(
              child: Text('Ảnh đã chọn',
                  style:
                      TextStyle(color: AppTheme.textSecondary, fontSize: 13))),
          IconButton(
            icon: const Icon(Icons.close,
                color: AppTheme.textSecondary, size: 20),
            onPressed: () => setState(() => _pickedImage = null),
          ),
        ],
      ),
    );
  }

  Widget _buildReplyBar() {
    return Container(
      color: AppTheme.darkCard,
      padding: EdgeInsets.only(
        left: 8,
        right: 8,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 8,
      ),
      child: Row(
        children: [
          // Camera + Gallery sát nhau
          GestureDetector(
            onTap: _pickFromCamera,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: Icon(Icons.camera_alt_outlined,
                  color: AppTheme.textSecondary, size: 22),
            ),
          ),
          GestureDetector(
            onTap: _pickFromGallery,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: Icon(Icons.photo_library_outlined,
                  color: AppTheme.textSecondary, size: 22),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: _replyCtrl,
              minLines: 1,
              maxLines: 12,
              decoration: InputDecoration(
                hintText: 'Nhập tin nhắn...',
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                suffixIcon: _sending
                    ? const Padding(
                        padding: EdgeInsets.all(10),
                        child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppTheme.primary)),
                      )
                    : GestureDetector(
                        onTap: _sendReply,
                        child: Icon(
                          Icons.send_rounded,
                          size: 20,
                          color: (_replyCtrl.text.isNotEmpty ||
                                  _pickedImage != null)
                              ? AppTheme.primary
                              : AppTheme.textSecondary,
                        ),
                      ),
              ),
              textInputAction: TextInputAction.newline,
              onChanged: (_) => setState(() {}),
            ),
          ),
        ],
      ),
    );
  }

  void _openImage(String url) {
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => Scaffold(
                  backgroundColor: Colors.black,
                  appBar: AppBar(
                      backgroundColor: Colors.black,
                      iconTheme: const IconThemeData(color: Colors.white)),
                  body: Center(
                      child: InteractiveViewer(
                          child: Image.network(url, fit: BoxFit.contain))),
                )));
  }

  String _formatTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} '
      '${dt.day}/${dt.month}/${dt.year}';
}

// Widget avatar tự fallback: thử primaryUrl trước, nếu lỗi dùng fallbackUrl (FB picture)
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
