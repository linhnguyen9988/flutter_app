import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/customer.dart';
import '../models/live_comment.dart';
import '../services/api_service.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/page_filter_chip.dart';
import 'customer_detail_screen.dart';

class CustomersScreen extends StatefulWidget {
  final List<String> selectedLiveIds;
  final List<String> Function()? getLiveIds;
  final List<LiveComment> Function()? getLiveComments;
  const CustomersScreen({
    super.key,
    this.selectedLiveIds = const [],
    this.getLiveIds,
    this.getLiveComments,
  });

  @override
  State<CustomersScreen> createState() => CustomersScreenState();
}

class CustomersScreenState extends State<CustomersScreen> {
  bool get isDark => Theme.of(context).brightness == Brightness.dark;

  List<Customer> _customers = [];
  List<PageInfo> _pages = [];
  String? _selectedPageId;
  bool _loading = true;
  final _searchCtrl = TextEditingController();
  String _searchText = '';

  @override
  void initState() {
    super.initState();
    _loadPages();
    _loadCustomers();
  }

  void reload() {
    _loadPages();
    _loadCustomers();
  }

  Future<void> _loadPages() async {
    try {
      final pages = await ApiService.getPages();
      setState(() => _pages = pages);
    } catch (_) {}
  }

  Future<void> _loadCustomers() async {
    setState(() => _loading = true);
    try {
      final list = await ApiService.getCustomers(
        pageId: _selectedPageId,
        search: _searchText,
      );
      setState(() {
        _customers = list;
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
                color: AppTheme.textColor(isDark),
                fontSize: 14,
                height: 1.0,
              ),
              onChanged: (v) {
                setState(() => _searchText = v);
                _loadCustomers();
              },
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Tên, sđt... (${_customers.length})',
                hintStyle: TextStyle(
                    color: AppTheme.textSubColor(isDark).withValues(alpha: 0.7),
                    fontSize: 14),
                prefixIcon: Icon(Icons.search,
                    color: AppTheme.textSubColor(isDark), size: 20),
                suffixIcon: _searchText.isNotEmpty
                    ? GestureDetector(
                        onTap: () {
                          _searchCtrl.clear();
                          setState(() => _searchText = '');
                          _loadCustomers();
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
              onPressed: _loadCustomers,
              visualDensity: VisualDensity.compact,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => AppSidebar.show(context),
          ),
        ],
        bottom: _pages.isEmpty
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(32),
                child: Transform.translate(
                  offset: const Offset(0, -6),
                  child: Container(
                    height: 32,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        PageFilterChip(
                          label: 'Tất cả',
                          selected: _selectedPageId == null,
                          onTap: () {
                            setState(() => _selectedPageId = null);
                            _loadCustomers();
                          },
                        ),
                        ..._pages.map((p) => PageFilterChip(
                              label: p.displayName,
                              selected: _selectedPageId == p.pageid,
                              onTap: () {
                                setState(() => _selectedPageId = p.pageid);
                                _loadCustomers();
                              },
                            )),
                      ],
                    ),
                  ),
                ),
              ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary))
          : _customers.isEmpty
              ? Center(
                  child: Text('Không có khách hàng',
                      style: TextStyle(color: AppTheme.textSubColor(isDark))))
              : RefreshIndicator(
                  onRefresh: _loadCustomers,
                  color: AppTheme.primary,
                  child: ListView.separated(
                    itemCount: _customers.length,
                    separatorBuilder: (_, __) => Divider(
                        height: 0, color: AppTheme.dividerColor(isDark)),
                    itemBuilder: (_, i) => _buildCustomerTile(_customers[i]),
                  ),
                ),
    );
  }

  Widget _buildCustomerTile(Customer c) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Stack(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: AppTheme.surfaceColor(isDark),
            backgroundImage: c.userid != null && c.userid!.isNotEmpty
                ? NetworkImage(
                    'https://aodaigiabao.com/images/ava/${c.userid}.jpg')
                : null,
            onBackgroundImageError: c.userid != null ? (_, __) {} : null,
            child: null,
          ),
          if (c.isImportant)
            const Positioned(
              right: 0,
              bottom: 0,
              child: Icon(Icons.star, color: Colors.amber, size: 14),
            ),
        ],
      ),
      title: Text(
        c.displayName,
        style: TextStyle(
            color: AppTheme.textColor(isDark), fontWeight: FontWeight.w600),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (c.phone != null && c.phone!.isNotEmpty)
            Row(
              children: [
                const Text('📱', style: TextStyle(fontSize: 12)),
                Text(
                  c.phone!,
                  style: TextStyle(
                      color: AppTheme.textSubColor(isDark), fontSize: 12),
                ),
              ],
            ),
          if (c.label != null && c.label!.isNotEmpty)
            Text('🏷 ${c.label}',
                style: TextStyle(
                  color: _labelColor(c.label!),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                )),
        ],
      ),
      trailing: Icon(Icons.chevron_right, color: AppTheme.textSubColor(isDark)),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => CustomerDetailScreen(
                    customer: c,
                    selectedLiveIds:
                        widget.getLiveIds?.call() ?? widget.selectedLiveIds,
                    liveComments: widget.getLiveComments?.call() ?? const [],
                  )),
        );
      },
    );
  }

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
        return AppTheme.accent;
    }
  }
}
