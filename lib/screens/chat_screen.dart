import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
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
  bool get isDark => Theme.of(context).brightness == Brightness.dark;

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
  io.Socket? _socket;
  bool _isLoadingHistory = false;
  bool _initialLoad = true;
  int _readWatermark = 0;
  final Map<String, String> _reactions = {};

  String get _avatarUrl =>
      'https://aodaigiabao.com/images/ava/${widget.sender}.jpg';

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
      : AppTheme.textSubColor(isDark);

  @override
  void initState() {
    super.initState();
    if (widget.initialMessage != null && widget.initialMessage!.isNotEmpty) {
      _replyCtrl.text = widget.initialMessage!;
    }
    _loadConversation();
    _loadCustomer();
    _loadLatestOrder();
    _connectSocket();
  }

  void _connectSocket() {
    _socket = io.io(
      'https://aodaigiabao.com',
      io.OptionBuilder()
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

        _reactions.clear();
        if (result.reactions.isNotEmpty) {
          _reactions.addAll(result.reactions);
        }
        for (var m in msgs) {
          if (m.reactions != null && m.reactions!.isNotEmpty) {
            _reactions[m.messid] = m.reactions! as String;
          }
        }

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
    if (_loadingMore || !_hasMore || _isLoadingHistory) return;
    _isLoadingHistory = true;
    setState(() => _loadingMore = true);
    _offset += 10;
    try {
      final result = await ApiService.getConversation(widget.sender,
          limit: 10, offset: _offset);

      final msgs = result.messages
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

      final prevPixels =
          _scrollCtrl.hasClients ? _scrollCtrl.position.pixels : 0.0;
      final prevMaxExtent =
          _scrollCtrl.hasClients ? _scrollCtrl.position.maxScrollExtent : 0.0;

      setState(() {
        if (result.reactions.isNotEmpty) {
          _reactions.addAll(result.reactions);
        }

        _messages = [...msgs, ..._messages];
        _hasMore = msgs.length == 10;
        _loadingMore = false;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollCtrl.hasClients) return;
        final newMaxExtent = _scrollCtrl.position.maxScrollExtent;
        final addedHeight = newMaxExtent - prevMaxExtent;
        _scrollCtrl.jumpTo(prevPixels + addedHeight);

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
    final ts = DateTime.now().millisecondsSinceEpoch;
    final localId = 'local_$ts';

    final pendingMsg = Message(
      id: 0,
      messid: localId,
      sender: widget.pageId,
      recipient: widget.sender,
      message: text.isNotEmpty ? text : null,
      image: imageFile?.path,
      time: DateTime.now().toIso8601String(),
      isRead: 1,
      timestamp: ts,
      isPending: true,
    );
    setState(() {
      _messages.add(pendingMsg);
      _pickedImage = null;
      _replyCtrl.clear();
    });
    _scrollToBottom();

    try {
      final ok = await ApiService.sendMessage(
        recipient: widget.sender,
        message: text,
        pageId: widget.pageId,
        imageFile: imageFile,
      );
      if (mounted) {
        setState(() {
          final idx = _messages.indexWhere((m) => m.messid == localId);
          if (idx >= 0) {
            if (ok) {
              _messages[idx] = Message(
                id: 0,
                messid: localId,
                sender: pendingMsg.sender,
                recipient: pendingMsg.recipient,
                message: pendingMsg.message,
                image: pendingMsg.image,
                time: pendingMsg.time,
                isRead: 1,
                timestamp: ts,
                isPending: false,
                isFailed: false,
              );
            } else {
              _messages[idx] = Message(
                id: 0,
                messid: localId,
                sender: pendingMsg.sender,
                recipient: pendingMsg.recipient,
                message: pendingMsg.message,
                image: pendingMsg.image,
                time: pendingMsg.time,
                isRead: 1,
                timestamp: ts,
                isPending: false,
                isFailed: true,
              );
            }
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          final idx = _messages.indexWhere((m) => m.messid == localId);
          if (idx >= 0) {
            _messages[idx] = Message(
              id: 0,
              messid: localId,
              sender: pendingMsg.sender,
              recipient: pendingMsg.recipient,
              message: pendingMsg.message,
              image: pendingMsg.image,
              time: pendingMsg.time,
              isRead: 1,
              timestamp: ts,
              isPending: false,
              isFailed: true,
            );
          }
        });
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
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
                      ? Center(
                          child: Text('Chưa có tin nhắn',
                              style: TextStyle(
                                  color: AppTheme.textSubColor(isDark))))
                      : RefreshIndicator(
                          color: AppTheme.primary,
                          onRefresh: _hasMore
                              ? () async {
                                  await _loadMore();
                                }
                              : () async {},
                          child: ListView.builder(
                            controller: _scrollCtrl,
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            itemCount: _messages.length,
                            itemBuilder: (_, i) {
                              return _buildBubble(_messages[i]);
                            },
                          ),
                        ),
            ),
            if (_pickedImage != null) _buildImagePreview(),
            _buildReplyBar(),
          ],
        ),
      ),
    );
  }

  List<String> _parseImageUrls(Message msg) {
    final images = msg.imageList;
    if (images.isEmpty) return [];

    if (images.length == 1 && images.first.contains(';')) {
      return images.first
          .split(';')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return images;
  }

  Widget _buildBubble(Message msg) {
    final isIncoming = msg.sender == widget.sender;
    final images = _parseImageUrls(msg);
    final isRead =
        !isIncoming && _readWatermark >= msg.timestamp && msg.timestamp > 0;
    final reaction = _reactions[msg.messid];

    final galleryUrls = images
        .where((p) => p.startsWith('http') || !p.toLowerCase().contains('like'))
        .where((p) => p.startsWith('http'))
        .map((p) => _getAbsoluteUrl(p))
        .toList();

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
                if (images.length > 1)
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      _buildImageGrid(images, galleryUrls: galleryUrls),
                      if (reaction != null)
                        Positioned(
                          bottom: -10,
                          left: 6,
                          child: _buildReactionBadge(reaction),
                        ),
                    ],
                  )
                else if (images.length == 1)
                  ...images.map((path) {
                    if (path.toLowerCase().contains('like')) {
                      return const Padding(
                        padding: EdgeInsets.only(bottom: 4),
                        child: Text('👍', style: TextStyle(fontSize: 30)),
                      );
                    }
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
                          _buildImageBubble(url, allUrls: [url]),
                          if (reaction != null)
                            Positioned(
                              bottom: -10,
                              left: 6,
                              child: _buildReactionBadge(reaction),
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
                                ? AppTheme.surfaceColor(isDark)
                                : AppTheme.primary,
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(18),
                              topRight: const Radius.circular(18),
                              bottomLeft: Radius.circular(isIncoming ? 4 : 18),
                              bottomRight: Radius.circular(isIncoming ? 18 : 4),
                            ),
                          ),
                          child: Text(msg.message!,
                              style: TextStyle(
                                  color: isIncoming
                                      ? AppTheme.textColor(isDark)
                                      : Colors.white,
                                  fontSize: 14)),
                        ),
                      ),
                      if (reaction != null)
                        Positioned(
                          bottom: -10,
                          left: 6,
                          child: _buildReactionBadge(reaction),
                        ),
                    ],
                  ),
                SizedBox(height: reaction != null ? 14 : 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!isIncoming && msg.isPending) ...[
                      SizedBox(
                        width: 10,
                        height: 10,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: AppTheme.textSubColor(isDark),
                        ),
                      ),
                      const SizedBox(width: 3),
                    ] else if (!isIncoming && msg.isFailed) ...[
                      const Icon(Icons.error_outline,
                          size: 11, color: Colors.red),
                      const SizedBox(width: 3),
                    ] else if (!isIncoming &&
                        msg.messid.startsWith('local_')) ...[
                      const Icon(Icons.check_circle,
                          size: 11, color: Color(0xFF34C759)),
                      const SizedBox(width: 3),
                    ],
                    Text(_formatTime(msg.dateTime),
                        style: TextStyle(
                            color: AppTheme.textSubColor(isDark), fontSize: 8)),
                    if (isRead) ...[
                      const SizedBox(width: 3),
                      CircleAvatar(
                        radius: 4,
                        backgroundColor: AppTheme.surfaceColor(isDark),
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

  Widget _buildImageGrid(List<String> urls, {List<String>? galleryUrls}) {
    const double gridWidth = 220;
    const double gap = 2.0;

    final validUrls =
        urls.where((u) => !u.toLowerCase().contains('like')).toList();
    final likeCount = urls.length - validUrls.length;

    final absGalleryUrls = galleryUrls ??
        validUrls
            .where((u) => u.startsWith('http'))
            .map((u) => _getAbsoluteUrl(u))
            .toList();

    final count = validUrls.length;

    Widget grid;

    if (count == 0) {
      grid = const SizedBox.shrink();
    } else if (count == 2) {
      grid = SizedBox(
        width: gridWidth,
        child: Row(
          children: [
            Expanded(
                child: _buildGridCell(validUrls[0],
                    height: 140,
                    allUrls: absGalleryUrls,
                    borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(12),
                        bottomLeft: Radius.circular(12)))),
            SizedBox(width: gap),
            Expanded(
                child: _buildGridCell(validUrls[1],
                    height: 140,
                    allUrls: absGalleryUrls,
                    borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(12),
                        bottomRight: Radius.circular(12)))),
          ],
        ),
      );
    } else if (count == 3) {
      grid = SizedBox(
        width: gridWidth,
        child: Row(
          children: [
            Expanded(
              child: _buildGridCell(validUrls[0],
                  height: 142 + gap,
                  allUrls: absGalleryUrls,
                  borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(12),
                      bottomLeft: Radius.circular(12))),
            ),
            SizedBox(width: gap),
            Expanded(
              child: Column(
                children: [
                  _buildGridCell(validUrls[1],
                      height: 70,
                      allUrls: absGalleryUrls,
                      borderRadius: const BorderRadius.only(
                          topRight: Radius.circular(12))),
                  SizedBox(height: gap),
                  _buildGridCell(validUrls[2],
                      height: 70,
                      allUrls: absGalleryUrls,
                      borderRadius: const BorderRadius.only(
                          bottomRight: Radius.circular(12))),
                ],
              ),
            ),
          ],
        ),
      );
    } else {
      final displayUrls = validUrls.take(4).toList();
      final overflow = count - 4;

      grid = SizedBox(
        width: gridWidth,
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                    child: _buildGridCell(displayUrls[0],
                        height: 108,
                        allUrls: absGalleryUrls,
                        borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(12)))),
                SizedBox(width: gap),
                Expanded(
                    child: _buildGridCell(displayUrls[1],
                        height: 108,
                        allUrls: absGalleryUrls,
                        borderRadius: const BorderRadius.only(
                            topRight: Radius.circular(12)))),
              ],
            ),
            SizedBox(height: gap),
            Row(
              children: [
                Expanded(
                    child: _buildGridCell(displayUrls[2],
                        height: 108,
                        allUrls: absGalleryUrls,
                        borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(12)))),
                SizedBox(width: gap),
                Expanded(
                  child: Stack(
                    children: [
                      _buildGridCell(displayUrls[3],
                          height: 108,
                          allUrls: absGalleryUrls,
                          borderRadius: const BorderRadius.only(
                              bottomRight: Radius.circular(12))),
                      if (overflow > 0)
                        Positioned.fill(
                          child: ClipRRect(
                            borderRadius: const BorderRadius.only(
                                bottomRight: Radius.circular(12)),
                            child: Container(
                              color: Colors.black54,
                              child: Center(
                                child: Text(
                                  '+$overflow',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: grid,
        ),
        if (likeCount > 0)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('👍', style: TextStyle(fontSize: 30)),
          ),
      ],
    );
  }

  Widget _buildGridCell(String path,
      {required double height,
      BorderRadius? borderRadius,
      List<String>? allUrls}) {
    final isLocal = !path.startsWith('http');
    final url = isLocal ? path : _getAbsoluteUrl(path);

    Widget image;
    if (isLocal) {
      image = Image.file(
        File(url),
        height: height,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          height: height,
          color: AppTheme.surfaceColor(isDark),
          child: Icon(Icons.broken_image, color: AppTheme.textSubColor(isDark)),
        ),
      );
    } else {
      image = Image.network(
        url,
        height: height,
        width: double.infinity,
        fit: BoxFit.cover,
        loadingBuilder: (_, child, progress) {
          if (progress == null) return child;
          return Container(
            height: height,
            color: AppTheme.surfaceColor(isDark),
            child: const Center(
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppTheme.primary),
            ),
          );
        },
        errorBuilder: (_, __, ___) => Container(
          height: height,
          color: AppTheme.surfaceColor(isDark),
          child: Icon(Icons.broken_image, color: AppTheme.textSubColor(isDark)),
        ),
      );
    }

    return GestureDetector(
      onTap: () {
        if (isLocal) return;
        _openImage(url, allUrls: allUrls);
      },
      child: ClipRRect(
        borderRadius: borderRadius ?? BorderRadius.zero,
        child: image,
      ),
    );
  }

  Widget _buildReactionBadge(String emoji) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: AppTheme.cardColor(isDark),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.surfaceColor(isDark), width: 1.5),
      ),
      child: Text(emoji, style: const TextStyle(fontSize: 12)),
    );
  }

  Widget _buildImageBubble(String url, {List<String>? allUrls}) {
    return GestureDetector(
      onTap: () => _openImage(url, allUrls: allUrls),
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
                color: AppTheme.surfaceColor(isDark),
                child: const Center(
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppTheme.primary)));
          },
          errorBuilder: (_, __, ___) => Container(
            width: 200,
            height: 80,
            color: AppTheme.surfaceColor(isDark),
            child: Center(
                child: Icon(Icons.broken_image,
                    color: AppTheme.textSubColor(isDark))),
          ),
        ),
      ),
    );
  }

  Widget _buildImagePreview() {
    return Container(
      color: AppTheme.cardColor(isDark),
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
                  style: TextStyle(
                      color: AppTheme.textSubColor(isDark), fontSize: 13))),
          IconButton(
            icon: Icon(Icons.close,
                color: AppTheme.textSubColor(isDark), size: 20),
            onPressed: () => setState(() => _pickedImage = null),
          ),
        ],
      ),
    );
  }

  Widget _buildReplyBar() {
    return Container(
      color: AppTheme.cardColor(isDark),
      padding: EdgeInsets.only(
        left: 8,
        right: 8,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 8,
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: _pickFromCamera,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: Icon(Icons.camera_alt_outlined,
                  color: AppTheme.textSubColor(isDark), size: 22),
            ),
          ),
          GestureDetector(
            onTap: _pickFromGallery,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: Icon(Icons.photo_library_outlined,
                  color: AppTheme.textSubColor(isDark), size: 22),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: _replyCtrl,
              minLines: 1,
              maxLines: 15,
              decoration: InputDecoration(
                hintText: 'Nhập tin nhắn...',
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                suffixIcon: Padding(
                  padding: const EdgeInsets.only(right: 6, top: 6, bottom: 6),
                  child: GestureDetector(
                    onTap: (_replyCtrl.text.isNotEmpty || _pickedImage != null)
                        ? _sendReply
                        : null,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color:
                            (_replyCtrl.text.isNotEmpty || _pickedImage != null)
                                ? AppTheme.primary
                                : AppTheme.textSubColor(isDark)
                                    .withValues(alpha: 0.3),
                      ),
                      child: const Icon(
                        Icons.arrow_upward_rounded,
                        size: 18,
                        color: Colors.white,
                      ),
                    ),
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

  void _openImage(String url, {List<String>? allUrls}) {
    final urls = (allUrls != null && allUrls.isNotEmpty) ? allUrls : [url];
    final initialIndex = urls.indexOf(url).clamp(0, urls.length - 1);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _ImageGalleryViewer(
          urls: urls,
          initialIndex: initialIndex,
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} '
      '${dt.day}/${dt.month}/${dt.year}';
}

class _ImageGalleryViewer extends StatefulWidget {
  final List<String> urls;
  final int initialIndex;

  const _ImageGalleryViewer({
    required this.urls,
    this.initialIndex = 0,
  });

  @override
  State<_ImageGalleryViewer> createState() => _ImageGalleryViewerState();
}

class _ImageGalleryViewerState extends State<_ImageGalleryViewer>
    with SingleTickerProviderStateMixin {
  late final PageController _pageCtrl;
  late int _currentIndex;

  double _dragOffsetY = 0.0;
  bool _isDragging = false;

  late final AnimationController _snapBackCtrl;
  late Animation<double> _snapBackAnim;

  static const double _dismissThreshold = 50.0;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageCtrl = PageController(initialPage: widget.initialIndex);

    _snapBackCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _snapBackCtrl.dispose();
    super.dispose();
  }

  void _onVerticalDragStart(DragStartDetails details) {
    _snapBackCtrl.stop();
    setState(() {
      _isDragging = true;
      _dragOffsetY = 0.0;
    });
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    setState(() => _dragOffsetY += details.delta.dy);
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    if (_dragOffsetY.abs() >= _dismissThreshold) {
      Navigator.of(context).pop();
    } else {
      final startOffset = _dragOffsetY;
      _snapBackAnim = Tween<double>(begin: startOffset, end: 0.0).animate(
        CurvedAnimation(parent: _snapBackCtrl, curve: Curves.easeOut),
      )..addListener(() {
          if (mounted) setState(() => _dragOffsetY = _snapBackAnim.value);
        });
      _snapBackCtrl.forward(from: 0.0).whenComplete(() {
        if (mounted) setState(() => _isDragging = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dimFactor = (1.0 - (_dragOffsetY.abs() / 300.0).clamp(0.0, 1.0));

    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: dimFactor),
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: dimFactor),
        iconTheme: const IconThemeData(color: Colors.white),
        title: widget.urls.length > 1
            ? Text(
                '${_currentIndex + 1} / ${widget.urls.length}',
                style: const TextStyle(color: Colors.white, fontSize: 15),
              )
            : null,
      ),
      body: GestureDetector(
        onVerticalDragStart: _onVerticalDragStart,
        onVerticalDragUpdate: _onVerticalDragUpdate,
        onVerticalDragEnd: _onVerticalDragEnd,
        child: Stack(
          children: [
            Transform.translate(
              offset: Offset(0, _dragOffsetY),
              child: PageView.builder(
                controller: _pageCtrl,
                physics: _isDragging
                    ? const NeverScrollableScrollPhysics()
                    : const PageScrollPhysics(),
                itemCount: widget.urls.length,
                onPageChanged: (i) => setState(() => _currentIndex = i),
                itemBuilder: (_, i) {
                  return InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 4.0,
                    child: Center(
                      child: Image.network(
                        widget.urls[i],
                        fit: BoxFit.contain,
                        loadingBuilder: (_, child, progress) {
                          if (progress == null) return child;
                          return const Center(
                            child: CircularProgressIndicator(
                              color: Colors.white54,
                            ),
                          );
                        },
                        errorBuilder: (_, __, ___) => const Center(
                          child: Icon(
                            Icons.broken_image,
                            color: Colors.white54,
                            size: 48,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (widget.urls.length > 1)
              Positioned(
                bottom: 24,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    widget.urls.length,
                    (i) => AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: _currentIndex == i ? 20 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color:
                            _currentIndex == i ? Colors.white : Colors.white38,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
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
  bool get isDark => Theme.of(context).brightness == Brightness.dark;

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
      backgroundColor: AppTheme.surfaceColor(isDark),
      backgroundImage: url.isNotEmpty ? NetworkImage(url) : null,
      onBackgroundImageError:
          url.isNotEmpty && !_useFallback && widget.fallbackUrl.isNotEmpty
              ? (_, __) => setState(() => _useFallback = true)
              : (_, __) {},
    );
  }
}
