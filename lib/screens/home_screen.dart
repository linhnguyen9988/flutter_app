import 'dart:async';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../services/reload_service.dart';
import '../theme/app_theme.dart';
import '../models/live_comment.dart';
import 'messaging_screen.dart';
import 'chot_don_screen.dart';
import 'qr_scan_screen.dart';
import 'customers_screen.dart';
import 'orders_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  bool get isDark => Theme.of(context).brightness == Brightness.dark;

  int _currentIndex = 0;

  final GlobalKey<ChotDonScreenState> _chotDonKey =
      GlobalKey<ChotDonScreenState>();
  final GlobalKey<OrdersScreenState> _ordersKey =
      GlobalKey<OrdersScreenState>();
  final GlobalKey<MessagingScreenState> _messagingKey =
      GlobalKey<MessagingScreenState>();
  final GlobalKey<CustomersScreenState> _customersKey =
      GlobalKey<CustomersScreenState>();

  late final List<Widget> _screens;

  DateTime? _pausedAt;
  static const _reloadThreshold = Duration(seconds: 30);

  StreamSubscription<List<ConnectivityResult>>? _connectSub;
  bool _isOnline = true;
  bool _showBanner = false;
  bool _bannerIsOnline = false;
  Timer? _hideBannerTimer;

  late final AnimationController _bannerAnim;
  late final Animation<Offset> _bannerSlide;

  int _unreadMessages = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _bannerAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _bannerSlide = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _bannerAnim, curve: Curves.easeOut));

    _screens = [
      ChotDonScreen(key: _chotDonKey),
      OrdersScreen(
        key: _ordersKey,
        getLiveIds: () => _chotDonKey.currentState?.selectedLiveIds ?? [],
        getLiveComments: () => _chotDonKey.currentState?.comments ?? [],
      ),
      MessagingScreen(
        key: _messagingKey,
        getLiveIds: () => _chotDonKey.currentState?.selectedLiveIds ?? [],
        getLiveComments: () => _chotDonKey.currentState?.comments ?? [],
        onUnreadChanged: (count) {
          if (mounted) setState(() => _unreadMessages = count);
        },
      ),
      CustomersScreen(
          key: _customersKey,
          getLiveIds: () => _chotDonKey.currentState?.selectedLiveIds ?? [],
          getLiveComments: () => _chotDonKey.currentState?.comments ?? []),
    ];

    _initConnectivity();
  }

  Future<void> _initConnectivity() async {
    final results = await Connectivity().checkConnectivity();
    _isOnline = _hasConnection(results);

    _connectSub =
        Connectivity().onConnectivityChanged.listen(_onConnectivityChanged);
  }

  bool _hasConnection(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final online = _hasConnection(results);
    if (online == _isOnline) return;

    setState(() {
      _isOnline = online;
      _bannerIsOnline = online;
      _showBanner = true;
    });

    _bannerAnim.forward(from: 0);
    _hideBannerTimer?.cancel();

    if (online) {
      _reloadAll();
      _hideBannerTimer = Timer(const Duration(seconds: 3), _hideBanner);
    }
  }

  void _hideBanner() {
    _bannerAnim.reverse().then((_) {
      if (mounted) setState(() => _showBanner = false);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectSub?.cancel();
    _hideBannerTimer?.cancel();
    _bannerAnim.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _pausedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      if (_pausedAt != null) {
        final elapsed = DateTime.now().difference(_pausedAt!);
        if (elapsed >= _reloadThreshold) {
          debugPrint(
              '[HomeScreen] App resumed after ${elapsed.inSeconds}s — reloading');
          _reloadAll();
        } else {
          debugPrint(
              '[HomeScreen] App resumed after ${elapsed.inSeconds}s — skip reload');
        }
        _pausedAt = null;
      }
    }
  }

  void _reloadAll() {
    _chotDonKey.currentState?.reload();
    _ordersKey.currentState?.reload();
    _messagingKey.currentState?.reload();
    _customersKey.currentState?.reload();
    ReloadService.instance.triggerReload();
  }

  Future<void> _openQR() async {
    final comments = _chotDonKey.currentState?.comments ?? <LiveComment>[];

    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => QrScanScreen(liveComments: comments),
        transitionsBuilder: (_, anim, __, child) => SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
              .animate(
                  CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ),
    );

    if (result != null && result['action'] == 'chotDon') {
      setState(() => _currentIndex = 0);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _chotDonKey.currentState?.openCartFromQr(
          result['comment'] as LiveComment,
          result['chotComments'] as List<LiveComment>,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(index: _currentIndex, children: _screens),
          if (_showBanner)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SlideTransition(
                position: _bannerSlide,
                child: SafeArea(
                  bottom: false,
                  child: _ConnectivityBanner(isOnline: _bannerIsOnline),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardColor(isDark),
        border:
            Border(top: BorderSide(color: AppTheme.surfaceColor(isDark), width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 0),
          child: SizedBox(
            height: 60,
            child: Row(
              children: [
                Expanded(
                    child: _navItem(0, Icons.shopping_bag_outlined,
                        Icons.shopping_bag, 'Chốt đơn')),
                Expanded(
                    child: _navItem(1, Icons.local_shipping_outlined,
                        Icons.local_shipping, 'Đơn hàng')),
                GestureDetector(
                  onTap: _openQR,
                  behavior: HitTestBehavior.opaque,
                  child: SizedBox(
                    width: 60,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 45,
                          height: 45,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppTheme.primary,
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.primary.withValues(alpha: 0.35),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              )
                            ],
                          ),
                          child: const Icon(Icons.qr_code_scanner,
                              color: Colors.white, size: 20),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                    child: _navItem(2, Icons.chat_bubble_outline,
                        Icons.chat_bubble, 'Tin nhắn')),
                Expanded(
                    child: _navItem(
                        3, Icons.people_outline, Icons.people, 'Khách hàng')),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _navItem(int index, IconData icon, IconData activeIcon, String label) {
    final isSelected = _currentIndex == index;
    final showBadge = index == 2 && _unreadMessages > 0;

    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: double.infinity,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  isSelected ? activeIcon : icon,
                  color: isSelected ? AppTheme.primary : AppTheme.textSubColor(isDark),
                  size: 24,
                ),
                if (showBadge)
                  Positioned(
                    right: -6,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(10),
                        border:
                            Border.all(color: AppTheme.cardColor(isDark), width: 1.5),
                      ),
                      constraints:
                          const BoxConstraints(minWidth: 18, minHeight: 18),
                      child: Text(
                        _unreadMessages > 99 ? '99+' : '$_unreadMessages',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          height: 1.1,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? AppTheme.primary : AppTheme.textSubColor(isDark),
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectivityBanner extends StatelessWidget {
  final bool isOnline;
  const _ConnectivityBanner({required this.isOnline});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: isOnline ? AppTheme.accent : Colors.red.shade700,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isOnline ? Icons.wifi : Icons.wifi_off,
            color: Colors.white,
            size: 16,
          ),
          const SizedBox(width: 8),
          Text(
            isOnline ? 'Đã kết nối trở lại' : 'Mất kết nối internet',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
