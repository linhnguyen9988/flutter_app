import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
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

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  // 4 tabs thực (QR giữa là nút nổi, không phải tab)
  final List<Widget> _screens = const [
    MessagingScreen(),
    ChotDonScreen(),
    OrdersScreen(), // placeholder bên phải QR
    CustomersScreen(),
  ];

  void _openQR() {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const QrScanScreen(),
        transitionsBuilder: (_, anim, __, child) => SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
              .animate(
                  CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: _buildBottomNav(),
      floatingActionButton: _buildQrFab(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }

  Widget _buildQrFab() {
    return GestureDetector(
      onTap: _openQR,
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [Color(0xFF1877F2), Color(0xFF0052CC)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primary.withOpacity(0.5),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Icon(Icons.qr_code_scanner, color: Colors.white, size: 28),
      ),
    );
  }

  Widget _buildBottomNav() {
    return BottomAppBar(
      color: AppTheme.darkCard,
      shape: const CircularNotchedRectangle(),
      notchMargin: 8,
      elevation: 0,
      child: SizedBox(
        height: 60,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            // Left side: 2 tabs
            _navItem(
                0, Icons.chat_bubble_outline, Icons.chat_bubble, 'Tin nhắn'),
            _navItem(
                1, Icons.shopping_bag_outlined, Icons.shopping_bag, 'Chốt đơn'),
            // Center: space for FAB
            const SizedBox(width: 60),
            // Right side: 2 tabs
            _navItem(2, Icons.local_shipping_outlined, Icons.local_shipping,
                'Đơn hàng'),
            _navItem(3, Icons.people_outline, Icons.people, 'Khách hàng'),
          ],
        ),
      ),
    );
  }

  Widget _navItem(int index, IconData icon, IconData activeIcon, String label) {
    final isSelected = _currentIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 70,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isSelected ? activeIcon : icon,
              color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
              size: 24,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
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
