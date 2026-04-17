import 'package:flutter/material.dart';
import '../main.dart' show routeObserver;
import 'reload_service.dart';

mixin ReloadAwareMixin<T extends StatefulWidget> on State<T>
    implements RouteAware {
  bool _pendingReload = false;

  void onReload();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) {
      routeObserver.subscribe(this, route);
    }
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
      onReload();
    } else {
      _pendingReload = true;
    }
  }

  @override
  void didPopNext() {
    if (_pendingReload) {
      _pendingReload = false;
      onReload();
    }
  }

  @override
  void didPush() {}

  @override
  void didPushNext() {}

  @override
  void didPop() {
    routeObserver.unsubscribe(this);
    ReloadService.instance.removeListener(_onReloadSignal);
  }
}
