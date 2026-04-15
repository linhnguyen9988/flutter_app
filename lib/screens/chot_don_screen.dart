import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../models/live_comment.dart';
import '../models/customer.dart';
import '../services/api_service.dart';
import '../widgets/app_sidebar.dart';
import 'chat_screen.dart';
import 'customer_detail_screen.dart';

// URL socket backend của bạn (không có /api)
const String _socketUrl = 'https://aodaigiabao.com';
const String _avaBase = 'https://aodaigiabao.com/images/ava';

class ChotDonScreen extends StatefulWidget {
  const ChotDonScreen({super.key});

  @override
  State<ChotDonScreen> createState() => ChotDonScreenState();
}

class ChotDonScreenState extends State<ChotDonScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  // Livestreams
  List<Map<String, dynamic>> _livestreams = [];
  final List<Map<String, dynamic>> _selectedLives = [];
  bool _loadingLives = true;

  // Comments
  List<LiveComment> _comments = [];
  bool _loadingComments = false;

  // Public getter để HomeScreen lấy comments truyền vào QrScanScreen
  List<LiveComment> get comments => _comments;

  // Public getter để các screen khác biết live nào đang được chọn
  List<String> get selectedLiveIds =>
      _selectedLives.map((l) => l['id'].toString()).toList();

  // Public — gọi từ HomeScreen khi app resume
  void reload() => _loadLivestreams();
  final _searchCtrl = TextEditingController();
  String _searchText = '';
  bool _searchVisible = false;

  // Giữ vị trí scroll danh sách bình luận + ẩn/hiện header
  final _commentScrollCtrl = ScrollController();
  bool _headerVisible = true;
  double _lastScrollOffset = 0;

  // Socket
  IO.Socket? _socket;
  bool _socketConnected = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _loadLivestreams();
    _connectSocket();
    _commentScrollCtrl.addListener(_onCommentScroll);
  }

  void _onCommentScroll() {
    final offset = _commentScrollCtrl.offset;
    final diff = offset - _lastScrollOffset;
    if (diff > 8 && _headerVisible) {
      // Kéo lên → ẩn header
      setState(() => _headerVisible = false);
    } else if (diff < -8 && !_headerVisible) {
      // Kéo xuống → hiện header
      setState(() => _headerVisible = true);
    }
    _lastScrollOffset = offset;
  }

  @override
  void dispose() {
    // 1. Xóa các listener trước
    _socket?.off('connect');
    _socket?.off('reconnect');
    _socket?.off('disconnect');
    _socket?.off('new-comment');

    // 2. Sau đó mới disconnect và dispose socket
    _socket?.disconnect();
    _socket?.dispose();

    _tabCtrl.dispose();
    _searchCtrl.dispose();
    _commentScrollCtrl.removeListener(_onCommentScroll);
    _commentScrollCtrl.dispose();
    super.dispose();
  }

  // ── Socket ────────────────────────────────────────────────────
  void _connectSocket() {
    _socket = IO.io(
        _socketUrl,
        IO.OptionBuilder()
            .setTransports(['websocket'])
            .disableAutoConnect()
            .build());

    _socket!.onConnect((_) {
      if (mounted) setState(() => _socketConnected = true);
      // Rejoin tất cả rooms đang chọn (reconnect case)
      for (final live in _selectedLives) {
        _socket!.emit('join-live-stream', live['id']);
      }
    });

    _socket!.onReconnect((_) {
      if (mounted) {
        for (final live in _selectedLives) {
          _socket!.emit('join-live-stream', live['id']);
        }
      }
    });

    _socket!.onDisconnect((_) {
      // Kiểm tra mounted cực kỳ quan trọng ở đây
      if (mounted) {
        setState(() {
          _socketConnected = false;
        });
      }
    });
    // Lắng nghe bình luận mới từ webhook backend
    _socket!.on('new-comment', (data) {
      if (!mounted) return;
      final Map<String, dynamic> d = Map<String, dynamic>.from(data);
      final newComment = LiveComment.fromSocket(d);
      // Chỉ thêm nếu thuộc live đang xem
      final joinedIds = _selectedLives.map((l) => l['id']).toSet();
      if (joinedIds.contains(newComment.liveid)) {
        // Tránh duplicate
        final exists = _comments.any(
            (c) => c.commentid == newComment.commentid && c.commentid != null);
        if (!exists) setState(() => _comments.insert(0, newComment));
      }
    });

    _socket!.connect();
  }

  void _joinLiveRoom(String liveId) {
    // Emit dù connected hay không - socket.io client sẽ queue lại
    _socket?.emit('join-live-stream', liveId);
  }

  // ── Load livestreams ──────────────────────────────────────────
  Future<void> _loadLivestreams() async {
    setState(() => _loadingLives = true);
    try {
      final lives = await ApiService.getRecentLivestreams(limit: 5);
      setState(() {
        _livestreams = lives;
        _loadingLives = false;
      });
    } catch (_) {
      setState(() => _loadingLives = false);
    }
  }

  // ── Load comments của live đã chọn ───────────────────────────
  Future<void> _loadComments(String liveId, {bool clearFirst = false}) async {
    setState(() => _loadingComments = true);
    try {
      final list = await ApiService.getLiveComments(liveId: liveId);
      setState(() {
        if (clearFirst) {
          _comments = list;
        } else {
          final existingIds = _comments.map((c) => c.idx).toSet();
          final newItems =
              list.where((c) => !existingIds.contains(c.idx)).toList();
          _comments = [..._comments, ...newItems];
        }
        _comments.sort((a, b) => b.idx.compareTo(a.idx));
        _loadingComments = false;
      });
    } catch (_) {
      setState(() => _loadingComments = false);
    }
  }

  Future<void> _reloadAllComments() async {
    setState(() {
      _loadingComments = true;
      _comments = [];
    });
    try {
      for (final live in _selectedLives) {
        final list = await ApiService.getLiveComments(liveId: live['id']);
        final existingIds = _comments.map((c) => c.idx).toSet();
        final newItems =
            list.where((c) => !existingIds.contains(c.idx)).toList();
        _comments = [..._comments, ...newItems];
      }
      _comments.sort((a, b) => b.idx.compareTo(a.idx));
      setState(() => _loadingComments = false);
    } catch (_) {
      setState(() => _loadingComments = false);
    }
  }

  void _onSelectLive(Map<String, dynamic> live) {
    final index = _selectedLives.indexWhere((l) => l['id'] == live['id']);

    setState(() {
      if (index == -1) {
        _selectedLives.add(live);
        _joinLiveRoom(live['id']);
        _loadComments(live['id']);
      } else {
        final removedId = live['id'];
        _socket?.emit('leave-live-stream', removedId);
        _selectedLives.removeAt(index);
        _comments.removeWhere((c) => c.liveid == removedId);
      }
    });
  }

  // ── Filter ───────────────────────────────────────────────────
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

  List<LiveComment> get _filtered {
    var list = _comments;
    if (_searchText.isNotEmpty) {
      final q = _nd(_searchText);
      list = list
          .where((c) =>
              _nd(c.name ?? '').contains(q) ||
              (c.customerPhone ?? '').contains(q) ||
              _nd(c.message ?? '').contains(q))
          .toList();
    }
    return list;
  }

  // ── Build ──────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _searchVisible
            ? Container(
                height: 36,
                margin: const EdgeInsets.only(top: 4, bottom: 4),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: TextField(
                    controller: _searchCtrl,
                    autofocus: true,
                    textAlignVertical: TextAlignVertical.center,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                    decoration: InputDecoration(
                      isCollapsed: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      hintText: 'Tìm tên, SĐT, bình luận...',
                      hintStyle: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 14,
                      ),
                      suffixIcon: _searchText.isNotEmpty
                          ? GestureDetector(
                              onTap: () {
                                _searchCtrl.clear();
                                setState(() => _searchText = '');
                              },
                              child: const Icon(Icons.close,
                                  color: AppTheme.textSecondary, size: 18),
                            )
                          : null,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                    ),
                    onChanged: (v) => setState(() => _searchText = v),
                  ),
                ),
              )
            : _buildAppBarLiveSelector(),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Icon(Icons.circle,
                size: 10,
                color: _socketConnected ? AppTheme.accent : Colors.red),
          ),
          if (_selectedUser != null)
            IconButton(
              icon: const Icon(Icons.shopping_cart_outlined,
                  color: AppTheme.primary),
              onPressed: () => _tabCtrl.animateTo(1),
            ),
          IconButton(
            icon: Icon(
              _searchVisible ? Icons.search_off : Icons.search,
              color: _searchVisible ? AppTheme.primary : null,
            ),
            onPressed: () {
              setState(() {
                _searchVisible = !_searchVisible;
                if (!_searchVisible) {
                  _searchCtrl.clear();
                  _searchText = '';
                }
              });
            },
          ),
          IconButton(
            padding: const EdgeInsets.only(right: 8),
            icon: const Icon(Icons.refresh),
            onPressed: _selectedLives.isNotEmpty
                ? _reloadAllComments
                : _loadLivestreams,
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => AppSidebar.show(context),
          ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: AppTheme.primary,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.textSecondary,
          tabs: const [
            Tab(text: 'Bình luận live'),
            Tab(text: 'Chốt đơn'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          KeepAliveWrapper(child: _buildCommentsTab()),
          _buildCartTab(),
        ],
      ),
    );
  }

  // ── TAB 1: Bình luận ──────────────────────────────────────────
  Widget _buildCommentsTab() {
    return Column(
      children: [
        Expanded(child: _buildCommentList()),
      ],
    );
  }

  // ── Live selector compact cho AppBar ─────────────────────────
  Widget _buildAppBarLiveSelector() {
    if (_loadingLives) {
      return const SizedBox(
        height: 36,
        child: Center(
            child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppTheme.primary))),
      );
    }

    String label;
    if (_selectedLives.isEmpty) {
      label = 'Chọn livestream...';
    } else if (_selectedLives.length == 1) {
      final live = _selectedLives.first;
      final name = live['name'] ?? live['id'] ?? '';
      final count = (live['luotincuoi'] as num?)?.toInt() ?? 0;
      label = count > 0 ? '$name ($count chốt)' : name;
    } else {
      final totalCount = _selectedLives.fold<int>(
          0, (sum, l) => sum + ((l['luotincuoi'] as num?)?.toInt() ?? 0));
      label = totalCount > 0
          ? '${_selectedLives.length} livestream · $totalCount chốt'
          : '${_selectedLives.length} livestream';
    }

    final hasLive = _selectedLives.any((l) => l['status'] == 'LIVE');

    return GestureDetector(
      onTap: _livestreams.isEmpty ? null : () => _showLivePickerSheet(),
      child: Container(
        height: 36,
        constraints: const BoxConstraints(minWidth: 150, maxWidth: 280),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: AppTheme.darkSurface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.max,
          children: [
            if (hasLive) ...[
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                    color: Colors.red, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: _selectedLives.isEmpty
                      ? AppTheme.textSecondary
                      : Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.expand_more,
                color: AppTheme.textSecondary, size: 16),
          ],
        ),
      ),
    );
  }

  // Sheet chọn live — bấm vào AppBar selector để mở
  void _showLivePickerSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.darkCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: AppTheme.darkSurface,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 12),
            ..._livestreams.map((live) {
              final id = live['id'] ?? '';
              final name = live['name'] ?? id;
              final time = live['time'] ?? '';
              final isLive = live['status'] == 'LIVE';
              final alreadyAdded = _selectedLives.any((l) => l['id'] == id);

              final luotincuoi = (live['luotincuoi'] as num?)?.toInt() ?? 0;
              return ListTile(
                dense: true,
                leading: Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(
                    color: isLive ? Colors.red : AppTheme.textSecondary,
                    shape: BoxShape.circle,
                  ),
                ),
                title: Row(children: [
                  Flexible(
                    child: Text(name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color:
                                alreadyAdded ? AppTheme.primary : Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  ),
                  if (isLive) ...[
                    const SizedBox(width: 6),
                    const _LiveBadge(),
                  ],
                ]),
                subtitle: Row(
                  children: [
                    if (time.isNotEmpty)
                      Text(time,
                          style: const TextStyle(
                              color: AppTheme.textSecondary, fontSize: 11)),
                    if (time.isNotEmpty && luotincuoi > 0)
                      const Text(' · ',
                          style: TextStyle(
                              color: AppTheme.textSecondary, fontSize: 11)),
                    if (luotincuoi > 0)
                      Text('$luotincuoi chốt',
                          style: TextStyle(
                              color: AppTheme.accent,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                  ],
                ),
                trailing: alreadyAdded
                    ? const Icon(Icons.check_circle,
                        color: AppTheme.primary, size: 20)
                    : const Icon(Icons.add_circle_outline,
                        color: AppTheme.textSecondary, size: 20),
                onTap: () {
                  _onSelectLive(live);
                  Navigator.pop(context);
                },
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildCommentList() {
    if (_selectedLives.isEmpty) {
      return _buildEmpty('Chọn một livestream\nđể xem bình luận');
    }
    if (_loadingComments) {
      return const Center(
          child: CircularProgressIndicator(color: AppTheme.primary));
    }
    if (_filtered.isEmpty) {
      return _buildEmpty('Chưa có bình luận');
    }
    return RefreshIndicator(
      onRefresh: _reloadAllComments,
      color: AppTheme.primary,
      child: ListView.separated(
        key: const PageStorageKey('comment_list'),
        controller: _commentScrollCtrl,
        itemCount: _filtered.length,
        separatorBuilder: (_, __) =>
            Divider(height: 0, color: AppTheme.darkSurface.withOpacity(0.4)),
        itemBuilder: (_, i) {
          final c = _filtered[i];
          return _buildCommentTile(c,
              key: ValueKey(c.commentid ?? c.idx.toString()));
        },
      ),
    );
  }

  // Màu tên theo label
  Color _nameColor(String? label) {
    switch (label) {
      case 'Bom hàng':
      case 'Xả hàng':
        return Colors.red;
      case 'Có vấn đề':
        return Colors.amber;
      default:
        return AppTheme.textPrimary;
    }
  }

  Widget _abroadTag() => Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: const Color(0xFFFF69B4).withOpacity(0.18),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFFF69B4).withOpacity(0.5)),
        ),
        child: const Text('🌏 NN',
            style: TextStyle(
                color: Color(0xFFFF69B4),
                fontSize: 10,
                fontWeight: FontWeight.w600)),
      );

  Widget _labelTag(String label) {
    final color = label == 'Có vấn đề' ? Colors.amber : Colors.red;
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildCommentTile(LiveComment c, {Key? key}) {
    // Wrap với KeyedSubtree để Flutter track đúng widget state theo commentid
    return KeyedSubtree(
      key: key,
      child: _buildCommentTileInner(c),
    );
  }

  Widget _buildCommentTileInner(LiveComment c) {
    final avaUrl = c.avatarUrlResolved(_avaBase);
    final nameColor = _nameColor(c.customerLabel);
    final hasLabel = c.customerLabel != null && c.customerLabel!.isNotEmpty;
    final hasPhone = c.customerPhone != null && c.customerPhone!.isNotEmpty;

    return InkWell(
      onTap: () => _showCommentDetail(c),
      onLongPress: () {
        HapticFeedback.mediumImpact();
        final customer = Customer(
          id: 0,
          userid: c.userid,
          fbname: c.fbnamex ?? c.name,
          phone: c.customerPhone,
          diachi: c.diachi,
          avalink: c.avatarUrl,
          label: c.customerLabel,
          pageid: c.pageid,
        );
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CustomerDetailScreen(
              customer: customer,
              selectedLiveIds: selectedLiveIds,
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _RetryAvatar(
              radius: 20,
              primaryUrl: avaUrl.isNotEmpty ? avaUrl : null,
              userid: c.userid,
              name: c.name,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Tên + label tag + nước ngoài badge
                  Row(children: [
                    Flexible(
                      child: Text(c.name ?? 'Ẩn danh',
                          style: TextStyle(
                              color: nameColor,
                              fontWeight: FontWeight.w600,
                              fontSize: 13),
                          overflow: TextOverflow.ellipsis),
                    ),
                    if (c.diachi != null && c.diachi!.isNotEmpty) ...[
                      const SizedBox(width: 3),
                      const Icon(Icons.location_on,
                          color: AppTheme.accent, size: 12),
                    ],
                    if (c.isAbroad) _abroadTag(),
                    if (hasLabel) _labelTag(c.customerLabel!),
                    const Spacer(),
                  ]),
                  // SĐT — hiển thị thuần, tap gọi/copy ở modal bên dưới
                  if (hasPhone)
                    Text(
                      c.customerPhone!,
                      style: const TextStyle(
                          color: AppTheme.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                    ),
                  const SizedBox(height: 3),
                  Text(c.message ?? '',
                      style: TextStyle(
                          color: AppTheme.textSecondary, fontSize: 12),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  if (c.hasOrder) ...[
                    const SizedBox(height: 5),
                    Row(children: [
                      _tag('📦 ${c.chot}', AppTheme.primary),
                      if (c.gia != null && c.gia!.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        _tag('💰 ${c.gia}', AppTheme.accent),
                      ],
                      if (c.slchot != null && c.slchot! > 1) ...[
                        const SizedBox(width: 6),
                        _tag('x${c.slchot}', Colors.orange),
                      ],
                    ]),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 6),
            // Cột nút bên phải
            Column(mainAxisSize: MainAxisSize.min, children: [
              if (c.hasOrder) ...[
                GestureDetector(
                  onTap: () => _openUserCart(c),
                  child: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                        color: AppTheme.primary.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.add_shopping_cart,
                        color: AppTheme.primary, size: 18),
                  ),
                ),
                const SizedBox(height: 4),
              ],
              // Nút xem toàn bộ bình luận của khách trong live này
              GestureDetector(
                onTap: () => _showUserComments(c),
                child: Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                      color: AppTheme.darkSurface,
                      borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.format_list_bulleted,
                      color: AppTheme.textSecondary, size: 18),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  void _showUserComments(LiveComment c) {
    final userComments = _comments.where((x) => x.userid == c.userid).toList();
    final avaUrl = c.avatarUrlResolved(_avaBase);
    final nameColor = _nameColor(c.customerLabel);

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.darkCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, ctrl) => Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(children: [
              Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: AppTheme.darkSurface,
                      borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 12),
              Row(children: [
                _RetryAvatar(
                  radius: 20,
                  primaryUrl: avaUrl.isNotEmpty ? avaUrl : null,
                  userid: c.userid,
                  name: c.name,
                ),
                const SizedBox(width: 10),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Row(children: [
                        Text(c.name ?? '',
                            style: TextStyle(
                                color: nameColor,
                                fontWeight: FontWeight.w700,
                                fontSize: 15)),
                        if (c.diachi != null && c.diachi!.isNotEmpty) ...[
                          const SizedBox(width: 3),
                          const Icon(Icons.location_on,
                              color: AppTheme.accent, size: 12),
                        ],
                        if (c.customerLabel != null &&
                            c.customerLabel!.isNotEmpty)
                          _labelTag(c.customerLabel!),
                      ]),
                      if (c.customerPhone != null &&
                          c.customerPhone!.isNotEmpty)
                        GestureDetector(
                          onTap: () async {
                            final uri = Uri.parse('tel:${c.customerPhone}');
                            if (await canLaunchUrl(uri)) launchUrl(uri);
                          },
                          onLongPress: () {
                            HapticFeedback.mediumImpact();
                            Clipboard.setData(
                                ClipboardData(text: c.customerPhone!));
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text('Đã copy: ${c.customerPhone}'),
                              duration: const Duration(seconds: 1),
                            ));
                          },
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.phone,
                                size: 11, color: AppTheme.accent),
                            const SizedBox(width: 4),
                            Text(c.customerPhone!,
                                style: const TextStyle(
                                    color: AppTheme.accent, fontSize: 12)),
                          ]),
                        ),
                    ])),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color: AppTheme.darkSurface,
                      borderRadius: BorderRadius.circular(10)),
                  child: Text('${userComments.length} bình luận',
                      style: TextStyle(
                          color: AppTheme.textSecondary, fontSize: 12)),
                ),
              ]),
            ]),
          ),
          const Divider(height: 0, color: Color(0xFF3A3B3C)),
          Expanded(
            child: userComments.isEmpty
                ? Center(
                    child: Text('Không có bình luận',
                        style: TextStyle(color: AppTheme.textSecondary)))
                : ListView.separated(
                    controller: ctrl,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: userComments.length,
                    separatorBuilder: (_, __) => Divider(
                        height: 0,
                        color: AppTheme.darkSurface.withOpacity(0.4)),
                    itemBuilder: (_, i) {
                      final uc = userComments[i];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        title: Text(uc.message ?? '',
                            style: const TextStyle(
                                color: AppTheme.textPrimary, fontSize: 13)),
                        subtitle: uc.hasOrder
                            ? Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Row(children: [
                                  _tag('📦 ${uc.chot}', AppTheme.primary),
                                  if (uc.gia != null && uc.gia!.isNotEmpty) ...[
                                    const SizedBox(width: 6),
                                    _tag('💰 ${uc.gia}', AppTheme.accent),
                                  ],
                                ]),
                              )
                            : null,
                        trailing: uc.hasOrder
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Nút xả
                                  GestureDetector(
                                    onTap: () async {
                                      await ApiService.postRaw(
                                        'https://aodaigiabao.com/updatechot',
                                        {
                                          'commentid': uc.commentid ?? '',
                                          'chot': 'XẢ HÀNG',
                                          'gia': uc.gia ?? '',
                                          'luotincuoi': uc.luotin ?? 0,
                                          'liveid': uc.liveid ?? '',
                                          'luotcuoilive': uc.luotin ?? 0,
                                          'slchot': uc.slchot ?? 1,
                                        },
                                      );
                                      if (mounted) {
                                        setState(() {
                                          final idx = _comments.indexWhere(
                                              (x) =>
                                                  x.commentid == uc.commentid);
                                          if (idx >= 0) {
                                            _comments[idx] =
                                                LiveComment.fromJson({
                                              ..._comments[idx].toJson(),
                                              'chot': 'XẢ HÀNG',
                                            });
                                          }
                                        });
                                        Navigator.pop(context);
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                            content: Text('Đã xả hàng ✓'),
                                            backgroundColor: Colors.orange,
                                          ),
                                        );
                                      }
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(6),
                                      margin: const EdgeInsets.only(right: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.withOpacity(0.13),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(Icons.undo,
                                          color: Colors.orange, size: 16),
                                    ),
                                  ),
                                  // Nút xem giỏ hàng
                                  GestureDetector(
                                    onTap: () {
                                      Navigator.pop(context);
                                      _openUserCart(uc);
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color:
                                            AppTheme.primary.withOpacity(0.13),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(
                                          Icons.shopping_cart_outlined,
                                          color: AppTheme.primary,
                                          size: 16),
                                    ),
                                  ),
                                ],
                              )
                            : null,
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }

  // ── TAB 2: Cart ───────────────────────────────────────────────
  // ── TAB 2: Chốt đơn ─────────────────────────────────────────
  // _selectedUser: khách đang xem, _userComments: bình luận chốt của khách đó
  LiveComment? _selectedUser;
  List<LiveComment> _userComments = [];
  bool _includeShip = true; // Toggle phí ship

  void _openUserCart(LiveComment c) {
    final userChotComments = _comments
        .where((x) => x.userid == c.userid && x.hasOrder)
        .toList()
      ..sort((a, b) => _parsePrice(a.gia).compareTo(_parsePrice(b.gia)));

    setState(() {
      _selectedUser = c;
      _userComments = List<LiveComment>.from(userChotComments); // copy độc lập
      _includeShip = true;
    });
    _tabCtrl.animateTo(1);
  }

  void openCartFromQr(LiveComment rep, List<LiveComment> chotComments) {
    setState(() {
      _selectedUser = rep;
      _userComments = List<LiveComment>.from(chotComments); // copy độc lập
      _includeShip = true;
    });
    _tabCtrl.animateTo(1);
  }

  // Parse giá: lấy số đầu tiên trong chuỗi, vd "35k" -> 35000, "120.000" -> 120000
  int _parsePrice(String? raw) {
    if (raw == null || raw.isEmpty) return 0;
    final cleaned = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleaned.isEmpty) return 0;
    int val = int.tryParse(cleaned) ?? 0;
    // Nếu < 1000 thì coi là nghìn (35 -> 35000)
    if (val > 0 && val < 1000) val *= 1000;
    return val;
  }

  String _formatMoney(int val) {
    // Hiện số đầy đủ, thêm dấu chấm phân cách nghìn cho dễ đọc
    if (val == 0) return '0';
    final str = val.toString();
    final buf = StringBuffer();
    for (int i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) buf.write('.');
      buf.write(str[i]);
    }
    return buf.toString() + 'đ';
  }

  // Format gọn cho tin nhắn: 150000 -> 150k, 150500 -> 150.5k
  String _formatMoneyK(int val) {
    if (val == 0) return '0';
    if (val % 1000 == 0) return '${val ~/ 1000}k';
    final k = val / 1000;
    final str = k.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '');
    return '${str}k';
  }

  // Tạo chuỗi chốt đơn để gửi tin nhắn
  String _buildOrderMessage(LiveComment user, List<LiveComment> items,
      {bool includeShip = true}) {
    final name = user.name ?? 'bạn';
    const pronoun = 'chị';

    // Gom các item cùng giá: price -> tổng qty
    final Map<int, int> priceQtyMap = {};
    int total = 0;
    for (final c in items) {
      final price = _parsePrice(c.gia);
      final qty = c.slchot ?? 1;
      priceQtyMap[price] = (priceQtyMap[price] ?? 0) + qty;
      total += price * qty;
    }

    // Sort giá tăng dần
    final sortedPrices = priceQtyMap.keys.toList()..sort();
    final lines = <String>[];
    for (final price in sortedPrices) {
      final qty = priceQtyMap[price]!;
      final lineTotal = price * qty;
      lines.add(
          '$qty vải giá ${_formatMoneyK(price)} = ${_formatMoneyK(lineTotal)}');
    }

    const ship = 20000;
    final grandTotal = total + (includeShip ? ship : 0);

    return 'Chào $pronoun $name, đơn hàng của $pronoun:\n'
        '${lines.join("\n")}\n'
        '${includeShip ? "Phí ship 20k. " : ""}Tổng ${_formatMoneyK(grandTotal)}.\n'
        'Em ship hàng $pronoun nha!';
  }

  Widget _buildCartTab() {
    if (_selectedUser == null) {
      return _buildEmpty('Bấm 🛒 ở bình luận để xem đơn chốt của khách');
    }

    final u = _selectedUser!;
    // Snapshot list ngay đầu build — tránh race condition giữa itemCount và itemBuilder
    final items = List<LiveComment>.from(_userComments);
    final avaUrl = u.avatarUrlResolved(_avaBase);
    final nameColor = _nameColor(u.customerLabel);

    // Tính tổng
    int subtotal = 0;
    int totalQty = 0;
    for (final c in items) {
      final qty = c.slchot ?? 1;
      subtotal += _parsePrice(c.gia) * qty;
      totalQty += qty;
    }
    const ship = 20000;
    final grandTotal = subtotal + (_includeShip ? ship : 0);

    return Column(children: [
      // Header khách hàng
      Container(
        color: AppTheme.darkCard,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          _RetryAvatar(
            radius: 22,
            primaryUrl: avaUrl.isNotEmpty ? avaUrl : null,
            userid: u.userid,
            name: u.name,
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Row(children: [
                  Text(u.name ?? '',
                      style: TextStyle(
                          color: nameColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 15)),
                  if (u.diachi != null && u.diachi!.isNotEmpty) ...[
                    const SizedBox(width: 3),
                    const Icon(Icons.location_on,
                        color: AppTheme.accent, size: 12),
                  ],
                  if (u.customerLabel != null && u.customerLabel!.isNotEmpty)
                    _labelTag(u.customerLabel!),
                ]),
                if (u.customerPhone != null && u.customerPhone!.isNotEmpty)
                  GestureDetector(
                    onTap: () async {
                      final uri = Uri.parse('tel:${u.customerPhone}');
                      if (await canLaunchUrl(uri)) launchUrl(uri);
                    },
                    onLongPress: () {
                      HapticFeedback.mediumImpact();
                      Clipboard.setData(ClipboardData(text: u.customerPhone!));
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('Đã copy: ${u.customerPhone}'),
                        duration: const Duration(seconds: 1),
                      ));
                    },
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.phone, size: 11, color: AppTheme.accent),
                      const SizedBox(width: 4),
                      Text(u.customerPhone!,
                          style: const TextStyle(
                              color: AppTheme.accent, fontSize: 12)),
                    ]),
                  ),
              ])),
          // Nút clear
          IconButton(
            icon: const Icon(Icons.close, color: AppTheme.textSecondary),
            onPressed: () => setState(() {
              _selectedUser = null;
              _userComments = [];
            }),
          ),
        ]),
      ),
      const Divider(height: 0, color: Color(0xFF3A3B3C)),

      // Danh sách bình luận chốt
      Expanded(
        child: items.isEmpty
            ? _buildEmpty('Khách này chưa có bình luận chốt')
            : ListView.separated(
                key: ValueKey('${u.userid}_${items.length}'),
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: items.length,
                separatorBuilder: (_, __) => Divider(
                    height: 0, color: AppTheme.darkSurface.withOpacity(0.4)),
                itemBuilder: (_, i) {
                  if (i >= items.length) return const SizedBox.shrink();
                  final c = items[i];
                  final price = _parsePrice(c.gia);
                  final qty = c.slchot ?? 1;
                  final lineTotal = price * qty;
                  return ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    title: Text(c.message ?? '',
                        style: const TextStyle(
                            color: AppTheme.textSecondary, fontSize: 12)),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          _tag('📦 ${c.chot ?? ''}', AppTheme.primary),
                          if (c.gia != null && c.gia!.isNotEmpty)
                            _tag(
                                '${_formatMoney(price)} × $qty = ${_formatMoney(lineTotal)}',
                                AppTheme.accent),
                        ],
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Nút xả chốt
                        GestureDetector(
                          onTap: () => _xaComment(c),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            margin: const EdgeInsets.only(right: 6),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.13),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.undo,
                                color: Colors.orange, size: 18),
                          ),
                        ),
                        // Nút xoá khỏi giỏ
                        GestureDetector(
                          onTap: () {
                            final updated =
                                List<LiveComment>.from(_userComments);
                            updated.removeAt(i);
                            setState(() => _userComments = updated);
                          },
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.remove_circle_outline,
                                color: Colors.red, size: 18),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),

      // Tổng kết + nút gửi
      Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        color: AppTheme.darkCard,
        child: Column(children: [
          // Tóm tắt giá
          Row(children: [
            Text('Hàng:',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('$totalQty vải',
                  style: const TextStyle(
                      color: AppTheme.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ),
            const Spacer(),
            Text(_formatMoney(subtotal),
                style: const TextStyle(color: Colors.white, fontSize: 13)),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            Text('Ship:',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => setState(() => _includeShip = !_includeShip),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: _includeShip
                      ? AppTheme.accent.withOpacity(0.15)
                      : AppTheme.darkSurface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _includeShip
                        ? AppTheme.accent.withOpacity(0.5)
                        : AppTheme.darkSurface,
                  ),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(
                    _includeShip
                        ? Icons.check_circle_outline
                        : Icons.remove_circle_outline,
                    size: 13,
                    color:
                        _includeShip ? AppTheme.accent : AppTheme.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _includeShip ? '20.000đ' : 'Bỏ ship',
                    style: TextStyle(
                      color: _includeShip
                          ? AppTheme.accent
                          : AppTheme.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ]),
              ),
            ),
            const Spacer(),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            const Text('Tổng:',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15)),
            const Spacer(),
            Text(_formatMoney(grandTotal),
                style: const TextStyle(
                    color: AppTheme.accent,
                    fontWeight: FontWeight.w800,
                    fontSize: 16)),
          ]),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              icon:
                  const Icon(Icons.send_rounded, color: Colors.white, size: 18),
              label: const Text('Gửi tin nhắn chốt',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15)),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14))),
              onPressed: items.isEmpty ? null : _goToChat,
            ),
          ),
        ]),
      ),
    ]);
  }

  void _goToChat() {
    if (_selectedUser == null) return;
    final msg = _buildOrderMessage(_selectedUser!, _userComments,
        includeShip: _includeShip);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          sender: _selectedUser!.userid ?? '',
          pageId: _selectedUser!.pageid ?? '',
          customerName: _selectedUser!.name,
          initialMessage: msg,
        ),
      ),
    );
  }

  // ── Detail sheet ──────────────────────────────────────────────
  void _showCommentDetail(LiveComment c) {
    final avaUrl = c.avatarUrlResolved(_avaBase);
    // Input controllers cho dialog
    final giaCtrl = TextEditingController(text: c.gia ?? '');
    final slCtrl = TextEditingController(text: (c.slchot ?? 1).toString());

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.darkCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
                child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: AppTheme.darkSurface,
                        borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            // Header: avatar + tên
            Row(children: [
              _RetryAvatar(
                radius: 24,
                primaryUrl: avaUrl.isNotEmpty ? avaUrl : null,
                userid: c.userid,
                name: c.name,
                fontSize: 18,
              ),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(c.name ?? '',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 16)),
                    if (c.customerPhone != null && c.customerPhone!.isNotEmpty)
                      GestureDetector(
                        onTap: () async {
                          final uri = Uri.parse('tel:${c.customerPhone}');
                          if (await canLaunchUrl(uri)) launchUrl(uri);
                        },
                        onLongPress: () {
                          HapticFeedback.mediumImpact();
                          Clipboard.setData(
                              ClipboardData(text: c.customerPhone!));
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('Đã copy: ${c.customerPhone}'),
                            duration: const Duration(seconds: 1),
                          ));
                        },
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.phone,
                              size: 11, color: AppTheme.accent),
                          const SizedBox(width: 4),
                          Text(c.customerPhone!,
                              style: const TextStyle(
                                  color: AppTheme.accent, fontSize: 12)),
                        ]),
                      ),
                  ])),
            ]),
            const SizedBox(height: 8),
            Text(c.message ?? '',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
            // Tags chốt hiện có
            if (c.chot != null && c.chot!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(children: [
                _tag('📦 ${c.chot}', AppTheme.primary),
                if (c.gia != null && c.gia!.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  _tag('💰 ${c.gia}', AppTheme.accent),
                ],
                if (c.slchot != null && c.slchot! > 1) ...[
                  const SizedBox(width: 6),
                  _tag('x${c.slchot}', Colors.orange),
                ],
              ]),
            ],
            const SizedBox(height: 14),
            // Input giá + số lượng
            Row(children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: giaCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Giá (VD: 35000)',
                    hintStyle: TextStyle(
                        color: AppTheme.textSecondary.withOpacity(0.6),
                        fontSize: 12),
                    prefixIcon: const Icon(Icons.payments_outlined,
                        color: AppTheme.textSecondary, size: 16),
                    filled: true,
                    fillColor: AppTheme.darkSurface,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 10),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 70,
                child: TextField(
                  controller: slCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    hintText: 'SL',
                    hintStyle: TextStyle(
                        color: AppTheme.textSecondary.withOpacity(0.6),
                        fontSize: 12),
                    filled: true,
                    fillColor: AppTheme.darkSurface,
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 14),
            // Nút hành động
            Row(children: [
              // Xả chốt — chỉ hiện khi đã chốt
              if (c.hasOrder) ...[
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.remove_circle_outline, size: 15),
                    label: const Text('Xả', style: TextStyle(fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.orange,
                        side: BorderSide(color: Colors.orange.withOpacity(0.5)),
                        padding: const EdgeInsets.symmetric(vertical: 10)),
                    onPressed: () {
                      Navigator.pop(context);
                      _xaComment(c);
                    },
                  ),
                ),
                const SizedBox(width: 8),
              ],
              // Xem đơn chốt
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.shopping_cart_outlined, size: 15),
                  label: const Text('Xem đơn', style: TextStyle(fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primary,
                      side:
                          BorderSide(color: AppTheme.primary.withOpacity(0.5)),
                      padding: const EdgeInsets.symmetric(vertical: 10)),
                  onPressed: () {
                    Navigator.pop(context);
                    _openUserCart(c);
                  },
                ),
              ),
              const SizedBox(width: 8),
              // In đơn
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.print_outlined, size: 15),
                  label: const Text('In', style: TextStyle(fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.textSecondary,
                      side: BorderSide(color: AppTheme.darkSurface),
                      padding: const EdgeInsets.symmetric(vertical: 10)),
                  onPressed: () {
                    Navigator.pop(context);
                    _printComment(
                        c, giaCtrl.text, int.tryParse(slCtrl.text) ?? 1);
                  },
                ),
              ),
              const SizedBox(width: 8),
              // Chốt
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.check_circle_outline,
                      size: 15, color: Colors.white),
                  label: const Text('Chốt',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accent,
                      padding: const EdgeInsets.symmetric(vertical: 10)),
                  onPressed: () {
                    Navigator.pop(context);
                    _chotComment(
                        c, giaCtrl.text, int.tryParse(slCtrl.text) ?? 1);
                  },
                ),
              ),
            ]),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  // Gọi API in đơn
  Future<void> _printComment(LiveComment c, String gia, int sl) async {
    final cleanGia = gia.replaceAll(RegExp(r'[^0-9]'), '');
    final now = DateTime.now();
    final date =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
    final printData = {
      'date': date,
      'name': c.name ?? '',
      'phone': c.customerPhone ?? '',
      'comment': c.message ?? '',
      'gia': cleanGia.isEmpty ? '0' : cleanGia,
      'id': (c.khid ?? c.idx).toString(),
      'avabase64': 'https://aodaigiabao.com/images/ava/${c.userid ?? ""}.jpg',
      'note': c.note ?? '', // note của livestream (table livestream)
      'address': c.diachi ?? '',
      'region': c.region ?? c.nuocngoai ?? '',
    };
    try {
      // 1. Sinh PDF
      final pdfRes = await ApiService.postRaw(
          'https://aodaigiabao.com/api/generate-pdf', printData);

      if (pdfRes == null || pdfRes['error'] != null) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content:
                  Text('Lỗi tạo PDF: ${pdfRes?['error'] ?? 'null response'}'),
              backgroundColor: Colors.red));
        return;
      }

      if (pdfRes['success'] != true) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  'PDF thất bại: ${pdfRes['message'] ?? pdfRes.toString()}'),
              backgroundColor: Colors.red));
        return;
      }

      // 2. Gửi lệnh in từng tờ
      for (int k = 0; k < sl; k++) {
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
          if (mounted)
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(
                    'Lỗi gửi lệnh in tờ ${k + 1}: ${printRes?['error'] ?? 'null'}'),
                backgroundColor: Colors.red));
          return;
        }
      }

      // Không hiện thông báo thành công
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Lỗi kết nối: $e'), backgroundColor: Colors.red));
    }
  }

  // Tính luot cao nhất trong toàn bộ comments (tương đương highAndLow trong JS)
  int _maxLuotin() {
    int max = 0;
    for (final c in _comments) {
      final v = c.luotin ?? 0;
      if (v > max) max = v;
    }
    return max;
  }

  // Gọi API chốt + in đơn
  Future<void> _chotComment(LiveComment c, String gia, int sl) async {
    final cleanGia = gia.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanGia.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Nhập giá trước khi chốt'),
          backgroundColor: Colors.orange));
      return;
    }

    // Tính luotcuoi như JS:
    // luotincuoi = max luotin toàn bảng (highAndLow)
    // xx = luotin của comment này
    // luotcuoi = (xx==0) ? luotincuoi+1 : xx
    // luotcuoilive = (xx==0) ? luotcuoi : luotincuoi
    final luotincuoi = _maxLuotin();
    final xx = c.luotin ?? 0;
    final luotcuoi = (xx == 0) ? (luotincuoi + 1) : xx;
    final luotcuoilive = (xx == 0) ? luotcuoi : luotincuoi;

    final now = DateTime.now();
    final date =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';

    try {
      // 1. Cập nhật chốt vào DB
      final chotRes =
          await ApiService.postRaw('https://aodaigiabao.com/updatechot', {
        'commentid': c.commentid ?? '',
        'chot': 'CHỐT',
        'gia': cleanGia,
        'luotincuoi': luotcuoi,
        'liveid': c.liveid ?? '',
        'luotcuoilive': luotcuoilive,
        'slchot': sl,
      });

      if (chotRes == null || chotRes['error'] != null) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content:
                  Text('Lỗi lưu DB: ${chotRes?['error'] ?? 'null response'}'),
              backgroundColor: Colors.red));
        return;
      }

      // 2. Cập nhật local UI
      if (mounted) {
        setState(() {
          final idx = _comments.indexWhere((x) => x.commentid == c.commentid);
          if (idx >= 0) {
            _comments[idx] = LiveComment.fromJson({
              ..._comments[idx].toJson(),
              'chot': 'CHỐT',
              'gia': cleanGia,
              'slchot': sl,
              'luotin': luotcuoi,
            });
          }
        });
      }

      // 3. Sinh PDF
      final printData = {
        'date': date,
        'luotcuoi': luotcuoi,
        'name': c.name ?? '',
        'phone': c.customerPhone ?? '',
        'comment': c.message ?? '',
        'gia': cleanGia,
        'id': (c.khid ?? c.idx).toString(),
        'avabase64': 'https://aodaigiabao.com/images/ava/${c.userid ?? ""}.jpg',
        'note': c.note ?? '',
        'address': c.diachi ?? '',
        'region': c.region ?? c.nuocngoai ?? '',
      };
      final pdfRes = await ApiService.postRaw(
          'https://aodaigiabao.com/api/generate-pdf', printData);

      if (pdfRes == null || pdfRes['error'] != null) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content:
                  Text('Lỗi tạo PDF: ${pdfRes?['error'] ?? 'null response'}'),
              backgroundColor: Colors.orange));
        return;
      }

      if (pdfRes['success'] != true) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  'PDF thất bại: ${pdfRes['message'] ?? pdfRes.toString()}'),
              backgroundColor: Colors.orange));
        return;
      }

      // 4. Gửi lệnh in từng tờ
      for (int k = 0; k < sl; k++) {
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
          if (mounted)
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(
                    'Lỗi gửi lệnh in tờ ${k + 1}: ${printRes?['error'] ?? 'null'}'),
                backgroundColor: Colors.red));
          return;
        }
      }

      // Không hiện thông báo thành công
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Lỗi khi chốt: $e'), backgroundColor: Colors.red));
    }
  }

  // Xả chốt — gọi /updatexa với chot='' và commentid
  Future<void> _xaComment(LiveComment c) async {
    try {
      await ApiService.postRaw('https://aodaigiabao.com/updatexa', {
        'commentid': c.commentid ?? '',
        'chot': '',
      });
      if (mounted) {
        setState(() {
          final idx = _comments.indexWhere((x) => x.commentid == c.commentid);
          if (idx >= 0) {
            _comments[idx] = LiveComment.fromJson({
              ..._comments[idx].toJson(),
              'chot': '',
              'gia': '',
            });
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Đã xả chốt'), backgroundColor: Colors.orange));
      }
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Lỗi khi xả chốt'), backgroundColor: Colors.red));
    }
  }

  // ── Helpers ───────────────────────────────────────────────────
  Widget _buildEmpty(String msg) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.inbox_outlined, color: AppTheme.textSecondary, size: 48),
          const SizedBox(height: 12),
          Text(msg,
              style: TextStyle(color: AppTheme.textSecondary),
              textAlign: TextAlign.center),
        ]),
      );

  Widget _tag(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.3))),
        child: Text(text,
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      );
}

// ── Widget badge LIVE nhấp nháy ───────────────────────────────
class _LiveBadge extends StatefulWidget {
  const _LiveBadge();
  @override
  State<_LiveBadge> createState() => _LiveBadgeState();
}

class _LiveBadgeState extends State<_LiveBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.25, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Icon(
        Icons.live_tv,
        color: Colors.red.withOpacity(_anim.value),
        size: 14,
      ),
    );
  }
}

// ── Widget avatar tự retry sau 0.5s với fallback userid.jpg ──────
class _RetryAvatar extends StatefulWidget {
  final String? primaryUrl;
  final String? userid;
  final String? name;
  final double radius;
  final double? fontSize;

  const _RetryAvatar({
    required this.radius,
    this.primaryUrl,
    this.userid,
    this.name,
    this.fontSize,
  });

  @override
  State<_RetryAvatar> createState() => _RetryAvatarState();
}

class _RetryAvatarState extends State<_RetryAvatar> {
  String? _url;
  bool _triedFallback = false;
  bool _loaded = false; // true khi ảnh đã hiện thành công — không reset nữa

  @override
  void initState() {
    super.initState();
    _url = (widget.primaryUrl?.isNotEmpty == true)
        ? widget.primaryUrl
        : _fallbackUrl;
  }

  @override
  void didUpdateWidget(_RetryAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reset khi khách thay đổi — dù ảnh đã load thành công vẫn phải reset
    if (oldWidget.primaryUrl != widget.primaryUrl ||
        oldWidget.userid != widget.userid) {
      _loaded = false;
      _triedFallback = false;
      _url = (widget.primaryUrl?.isNotEmpty == true)
          ? widget.primaryUrl
          : _fallbackUrl;
    }
  }

  String? get _fallbackUrl {
    final uid = widget.userid;
    if (uid != null && uid.isNotEmpty) {
      return 'https://aodaigiabao.com/images/ava/$uid.jpg';
    }
    return null;
  }

  void _onError() {
    _loaded = false; // load thất bại → chưa loaded
    if (_triedFallback) return;
    final fb = _fallbackUrl;
    if (fb == null || fb == _url) return;
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      setState(() {
        _triedFallback = true;
        _url = fb;
      });
    });
  }

  // Gọi khi Image load thành công (không có error)
  void _onLoaded() {
    if (!_loaded) _loaded = true;
  }

  @override
  Widget build(BuildContext context) {
    final initial = (widget.name ?? '?').substring(0, 1).toUpperCase();
    final diameter = widget.radius * 2;

    if (_url == null) {
      return CircleAvatar(
        radius: widget.radius,
        backgroundColor: AppTheme.darkSurface,
        child: Text(initial,
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: widget.fontSize)),
      );
    }

    return ClipOval(
      child: SizedBox(
        width: diameter,
        height: diameter,
        child: Image.network(
          _url!,
          width: diameter,
          height: diameter,
          fit: BoxFit.cover,
          frameBuilder: (_, child, frame, __) {
            if (frame != null) _onLoaded();
            return child;
          },
          errorBuilder: (_, __, ___) {
            _onError();
            return Container(
              width: diameter,
              height: diameter,
              color: AppTheme.darkSurface,
              alignment: Alignment.center,
              child: Text(initial,
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: widget.fontSize)),
            );
          },
        ),
      ),
    );
  }
}

// Giữ state widget con khi TabBarView switch tab
class KeepAliveWrapper extends StatefulWidget {
  final Widget child;
  const KeepAliveWrapper({super.key, required this.child});

  @override
  State<KeepAliveWrapper> createState() => _KeepAliveWrapperState();
}

class _KeepAliveWrapperState extends State<KeepAliveWrapper>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
