import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/live_comment.dart';
import '../services/api_service.dart';
import '../widgets/page_filter_chip.dart';

class LiveCommentsScreen extends StatefulWidget {
  const LiveCommentsScreen({super.key});

  @override
  State<LiveCommentsScreen> createState() => _LiveCommentsScreenState();
}

class _LiveCommentsScreenState extends State<LiveCommentsScreen> {
  List<LiveComment> _comments = [];
  List<PageInfo> _pages = [];
  String? _selectedPageId;
  bool _loading = true;
  bool _filterOrders = false;
  final _searchCtrl = TextEditingController();
  String _searchText = '';

  @override
  void initState() {
    super.initState();
    _loadPages();
    _loadComments();
  }

  Future<void> _loadPages() async {
    try {
      final pages = await ApiService.getPages();
      setState(() => _pages = pages);
    } catch (_) {}
  }

  Future<void> _loadComments() async {
    setState(() => _loading = true);
    try {
      final comments =
          await ApiService.getLiveComments(pageId: _selectedPageId);
      setState(() {
        _comments = comments;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  List<LiveComment> get _filtered {
    var list = _comments;
    if (_filterOrders) list = list.where((c) => c.hasOrder).toList();
    if (_searchText.isNotEmpty) {
      list = list
          .where((c) =>
              (c.name ?? '')
                  .toLowerCase()
                  .contains(_searchText.toLowerCase()) ||
              (c.message ?? '')
                  .toLowerCase()
                  .contains(_searchText.toLowerCase()))
          .toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bình luận Live'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadComments),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(110),
          child: Column(
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _searchText = v),
                  decoration: InputDecoration(
                    hintText: 'Tìm kiếm bình luận...',
                    prefixIcon:
                        const Icon(Icons.search, color: AppTheme.textSecondary),
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
                  ),
                ),
              ),
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  children: [
                    PageFilterChip(
                      label: 'Tất cả',
                      selected: _selectedPageId == null,
                      onTap: () {
                        setState(() => _selectedPageId = null);
                        _loadComments();
                      },
                    ),
                    ..._pages.map((p) => PageFilterChip(
                          label: p.displayName,
                          selected: _selectedPageId == p.pageid,
                          onTap: () {
                            setState(() => _selectedPageId = p.pageid);
                            _loadComments();
                          },
                        )),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Text('Có chốt đơn'),
                      selected: _filterOrders,
                      onSelected: (v) => setState(() => _filterOrders = v),
                      backgroundColor: AppTheme.darkSurface,
                      selectedColor: AppTheme.primary.withValues(alpha: 0.3),
                      checkmarkColor: AppTheme.primary,
                      labelStyle: TextStyle(
                        color: _filterOrders
                            ? AppTheme.primary
                            : AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                      side: BorderSide.none,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary))
          : _filtered.isEmpty
              ? Center(
                  child: Text('Không có bình luận',
                      style: TextStyle(color: AppTheme.textSecondary)))
              : RefreshIndicator(
                  onRefresh: _loadComments,
                  color: AppTheme.primary,
                  child: ListView.separated(
                    itemCount: _filtered.length,
                    separatorBuilder: (_, __) => Divider(
                        height: 0,
                        color: AppTheme.darkSurface.withValues(alpha: 0.5)),
                    itemBuilder: (_, i) => _buildCommentTile(_filtered[i]),
                  ),
                ),
    );
  }

  Widget _buildCommentTile(LiveComment c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppTheme.darkSurface,
            child: Text(
              (c.name ?? '?').substring(0, 1).toUpperCase(),
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      c.name ?? 'Ẩn danh',
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    if (c.hasOrder) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.accent.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: AppTheme.accent.withValues(alpha: 0.5)),
                        ),
                        child: Text(
                          'Chốt: ${c.chot}',
                          style: const TextStyle(
                              color: AppTheme.accent,
                              fontSize: 11,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  c.message ?? '',
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 13),
                ),
                if (c.gia != null && c.gia!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    '💰 ${c.gia}',
                    style:
                        const TextStyle(color: AppTheme.accent, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  c.timecomment ?? '',
                  style: TextStyle(
                      color: AppTheme.textSecondary.withValues(alpha: 0.6),
                      fontSize: 11),
                ),
              ],
            ),
          ),
          Column(
            children: [
              if (c.slchot != null && c.slchot! > 0)
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${c.slchot}',
                    style: const TextStyle(
                        color: AppTheme.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
