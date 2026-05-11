import 'package:flutter/material.dart';
import '../models/order.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  bool get isDark => Theme.of(context).brightness == Brightness.dark;

  int _days = 1;
  bool _loading = false;
  String? _error;

  // Switch: false = ngày tạo, true = ngày giao (last_update)
  bool _useUpdatedDate = false;

  // Customer stats
  int _totalCustomers = 0;
  int _customersWithPhone = 0;

  // Order stats
  int _totalOrders = 0;
  int _totalCod = 0;
  final Map<int, _StatusStat> _statusStats = {};

  final List<_DayOption> _dayOptions = const [
    _DayOption(days: 1, label: '1 ngày'),
    _DayOption(days: 3, label: '3 ngày'),
    _DayOption(days: 7, label: '7 ngày'),
    _DayOption(days: 30, label: '30 ngày'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  DateTime get _fromDate => DateTime.now().subtract(Duration(days: _days - 1));

  String get _fromDateStr {
    final d = _fromDate;
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _statusStats.clear();
    });
    try {
      await Future.wait([_loadCustomers(), _loadOrders()]);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  Future<void> _loadCustomers() async {
    final data = await ApiService.getCustomerStats(fromDate: _fromDateStr);
    if (mounted) {
      setState(() {
        _totalCustomers = _toInt(data['totalCustomers']);
        _customersWithPhone = _toInt(data['withPhone']);
      });
    }
  }

  Future<void> _loadOrders() async {
    final data = await ApiService.getOrderStats(
      fromDate: _fromDateStr,
      dateMode: _useUpdatedDate ? 'updated' : 'created',
    );
    final List byStatus = data['byStatus'] as List? ?? [];
    final Map<int, _StatusStat> stats = {};
    for (final s in byStatus) {
      final code = s['statuscode'] != null ? _toInt(s['statuscode']) : -1;
      stats[code] = _StatusStat(
        code: code,
        label: s['statustext']?.toString() ?? 'Không rõ',
        color: Order.statusColor(code),
        count: _toInt(s['cnt']),
        totalCod: _toInt(s['totalCod']),
      );
    }
    if (mounted) {
      setState(() {
        _totalOrders = _toInt(data['totalOrders']);
        _totalCod = _toInt(data['totalCod']);
        _statusStats
          ..clear()
          ..addAll(stats);
      });
    }
  }

  String _formatMoney(int amount) {
    final str = amount.abs().toString();
    final buf = StringBuffer();
    for (int i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) buf.write('.');
      buf.write(str[i]);
    }
    return '${amount < 0 ? '-' : ''}${buf}đ';
  }

  @override
  Widget build(BuildContext context) {
    final textColor = AppTheme.textColor(isDark);
    final subColor = AppTheme.textSubColor(isDark);
    final cardColor = AppTheme.cardColor(isDark);
    final bgColor = AppTheme.bgColor(isDark);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text('Thống kê'),
        backgroundColor: cardColor,
      ),
      body: Column(
        children: [
          // Day selector
          Container(
            color: cardColor,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Row(
              children: _dayOptions.map((opt) {
                final selected = _days == opt.days;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: GestureDetector(
                      onTap: () {
                        if (_days != opt.days) {
                          setState(() => _days = opt.days);
                          _load();
                        }
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: selected
                              ? AppTheme.primary
                              : AppTheme.surfaceColor(isDark),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Text(
                            opt.label,
                            style: TextStyle(
                              color: selected ? Colors.white : subColor,
                              fontWeight:
                                  selected ? FontWeight.w700 : FontWeight.w400,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.error_outline,
                                color: Colors.red, size: 40),
                            const SizedBox(height: 12),
                            Text(_error!,
                                style: TextStyle(color: subColor),
                                textAlign: TextAlign.center),
                            const SizedBox(height: 16),
                            ElevatedButton(
                                onPressed: _load, child: const Text('Thử lại')),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            // ── Khách hàng ──
                            _SectionHeader(
                                label: 'Khách hàng mới',
                                icon: Icons.people_outline,
                                color: AppTheme.primary,
                                isDark: isDark),
                            const SizedBox(height: 10),
                            IntrinsicHeight(
                                child: Row(
                              children: [
                                Expanded(
                                  child: _StatCard(
                                    label: 'Tổng khách mới',
                                    value: '$_totalCustomers',
                                    icon: Icons.person_add_outlined,
                                    iconColor: AppTheme.primary,
                                    isDark: isDark,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _StatCard(
                                    label: 'Có số điện thoại',
                                    value: '$_customersWithPhone',
                                    icon: Icons.phone_outlined,
                                    iconColor: AppTheme.accent,
                                    isDark: isDark,
                                    sub: _totalCustomers > 0
                                        ? '${(_customersWithPhone * 100 / _totalCustomers).toStringAsFixed(0)}%'
                                        : null,
                                  ),
                                ),
                              ],
                            )),
                            const SizedBox(height: 24),

                            // ── Đơn hàng ──
                            Row(
                              children: [
                                Expanded(
                                  child: _SectionHeader(
                                    label: 'Đơn hàng',
                                    icon: Icons.receipt_long_outlined,
                                    color: const Color(0xFF9C27B0),
                                    isDark: isDark,
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () {
                                    setState(() =>
                                        _useUpdatedDate = !_useUpdatedDate);
                                    _loadOrders();
                                  },
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: _useUpdatedDate
                                          ? AppTheme.accent
                                              .withValues(alpha: 0.15)
                                          : AppTheme.surfaceColor(isDark),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: _useUpdatedDate
                                            ? AppTheme.accent
                                            : AppTheme.dividerColor(isDark),
                                        width: 1,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          _useUpdatedDate
                                              ? Icons.local_shipping_outlined
                                              : Icons.add_circle_outline,
                                          size: 13,
                                          color: _useUpdatedDate
                                              ? AppTheme.accent
                                              : AppTheme.primary,
                                        ),
                                        const SizedBox(width: 5),
                                        Text(
                                          _useUpdatedDate
                                              ? 'Ngày giao'
                                              : 'Ngày tạo',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: _useUpdatedDate
                                                ? AppTheme.accent
                                                : AppTheme.primary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            IntrinsicHeight(
                                child: Row(
                              children: [
                                Expanded(
                                  child: _StatCard(
                                    label: 'Tổng đơn',
                                    value: '$_totalOrders',
                                    icon: Icons.inventory_2_outlined,
                                    iconColor: const Color(0xFF9C27B0),
                                    isDark: isDark,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _StatCard(
                                    label: 'Tổng COD',
                                    value: _formatMoney(_totalCod),
                                    icon: Icons.payments_outlined,
                                    iconColor: AppTheme.accent,
                                    isDark: isDark,
                                    smallValue: true,
                                  ),
                                ),
                              ],
                            )),
                            if (_statusStats.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              Container(
                                decoration: BoxDecoration(
                                  color: cardColor,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                          16, 14, 16, 8),
                                      child: Row(
                                        children: [
                                          Text(
                                            'Chi tiết theo trạng thái',
                                            style: TextStyle(
                                              color: textColor,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 14,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 7, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: _useUpdatedDate
                                                  ? AppTheme.accent
                                                      .withValues(alpha: 0.12)
                                                  : AppTheme.primary
                                                      .withValues(alpha: 0.12),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              _useUpdatedDate
                                                  ? 'theo ngày giao'
                                                  : 'theo ngày tạo',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600,
                                                color: _useUpdatedDate
                                                    ? AppTheme.accent
                                                    : AppTheme.primary,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    ..._buildStatusRows(textColor, subColor),
                                    const SizedBox(height: 8),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 32),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildStatusRows(Color textColor, Color subColor) {
    final sorted = _statusStats.values.toList()
      ..sort((a, b) => b.count.compareTo(a.count));
    final List<Widget> rows = [];
    for (int i = 0; i < sorted.length; i++) {
      final s = sorted[i];
      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: s.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  s.label,
                  style: TextStyle(color: textColor, fontSize: 13),
                ),
              ),
              Text(
                '${s.count} đơn',
                style: TextStyle(
                    color: subColor, fontSize: 12, fontWeight: FontWeight.w500),
              ),
              const SizedBox(width: 12),
              Text(
                _formatMoney(s.totalCod),
                style: TextStyle(
                  color: s.color,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      );
      if (i < sorted.length - 1) {
        rows.add(Divider(
          height: 1,
          indent: 36,
          color: AppTheme.dividerColor(isDark),
        ));
      }
    }
    return rows;
  }
}

class _StatusStat {
  final int code;
  final String label;
  final Color color;
  final int count;
  final int totalCod;
  const _StatusStat({
    required this.code,
    required this.label,
    required this.color,
    required this.count,
    required this.totalCod,
  });
}

class _DayOption {
  final int days;
  final String label;
  const _DayOption({required this.days, required this.label});
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool isDark;

  const _SectionHeader({
    required this.label,
    required this.icon,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            color: AppTheme.textColor(isDark),
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color iconColor;
  final bool isDark;
  final String? sub;
  final bool smallValue;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.iconColor,
    required this.isDark,
    this.sub,
    this.smallValue = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardColor(isDark),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.max,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: iconColor, size: 16),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              color: AppTheme.textColor(isDark),
              fontSize: smallValue ? 18 : 26,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (sub != null) ...[
            const SizedBox(height: 2),
            Text(
              sub!,
              style: TextStyle(
                color: iconColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: AppTheme.textSubColor(isDark),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
