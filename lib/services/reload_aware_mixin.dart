import 'package:flutter/material.dart';
import '../main.dart' show routeObserver;
import 'reload_service.dart';

/// Mixin cho các detail screen (Navigator push) muốn tự reload khi:
/// 1. App wake up / có mạng lại (qua ReloadService)
/// 2. Screen được pop về (didPopNext)
///
/// Cách dùng:
/// ```dart
/// class _MyScreenState extends State<MyScreen>
///     with ReloadAwareMixin<MyScreen> {
///
///   @override
///   void onReload() => _loadData();   // implement method này
/// }
/// ```
mixin ReloadAwareMixin<T extends StatefulWidget> on State<T>
    implements RouteAware {
  bool _pendingReload = false;

  /// Implement trong screen: gọi hàm load data của screen đó
  void onReload();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) {
      routeObserver.subscribe(this, route);
    }
    // Lắng nghe ReloadService
    ReloadService.instance.addListener(_onReloadSignal);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    ReloadService.instance.removeListener(_onReloadSignal);
    super.dispose();
  }

  void _onReloadSignal() {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    final isVisible = route?.isCurrent ?? false;
    if (isVisible) {
      // Screen đang visible → reload ngay
      onReload();
    } else {
      // Screen bị covered (có screen khác push lên trên) → đánh dấu
      _pendingReload = true;
    }
  }

  // ── RouteAware callbacks ───────────────────────────────────────

  /// Screen trở lại visible sau khi screen con bị pop
  @override
  void didPopNext() {
    if (_pendingReload) {
      _pendingReload = false;
      onReload();
    }
  }

  /// Screen lần đầu được push lên (đã có initState load rồi, bỏ qua)
  @override
  void didPush() {}

  /// Screen này bị một screen khác push lên trên
  @override
  void didPushNext() {}

  /// Screen này bị pop
  @override
  void didPop() {
    routeObserver.unsubscribe(this);
    ReloadService.instance.removeListener(_onReloadSignal);
  }
}
