import 'package:flutter/material.dart';

class ReloadService extends ChangeNotifier {
  static final ReloadService instance = ReloadService._();
  ReloadService._();

  void triggerReload() {
    notifyListeners();
  }
}
