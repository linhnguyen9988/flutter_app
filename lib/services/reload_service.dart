import 'package:flutter/material.dart';

/// Broadcast signal để tất cả screen tự reload khi app wake up hoặc có mạng lại.
/// Dùng với RouteAware: screen visible reload ngay, screen bị covered reload khi pop về.
class ReloadService extends ChangeNotifier {
  static final ReloadService instance = ReloadService._();
  ReloadService._();

  void triggerReload() {
    notifyListeners();
  }
}
