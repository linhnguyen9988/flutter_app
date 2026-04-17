import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class AuthService extends ChangeNotifier {
  static const _keyToken = 'auth_token';
  static const _keyUser = 'auth_user';
  static const _keyBiometric = 'biometric_enabled';
  static const _keyUsername = 'saved_username';
  static const _keyPassword = 'saved_password';

  String? _token;
  Map<String, dynamic>? _user;

  String? get token => _token;
  Map<String, dynamic>? get user => _user;
  bool get isLoggedIn => _token != null;
  Future<bool> tryAutoLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final savedToken = prefs.getString(_keyToken);
    final savedUser = prefs.getString(_keyUser);
    if (savedToken != null && savedUser != null) {
      _token = savedToken;
      _user = json.decode(savedUser);
      ApiService.setToken(savedToken);
      ApiService.setUserId(_user?['id']?.toString() ?? '');
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<String?> login(String username, String password) async {
    try {
      final uri = Uri.parse('${ApiService.baseUrl}/auth/login');
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'username': username, 'password': password}),
      );
      final data = json.decode(res.body);
      if (res.statusCode == 200 && data['token'] != null) {
        _token = data['token'];
        _user = data['user'];
        ApiService.setToken(_token!);
        ApiService.setUserId(_user?['id']?.toString() ?? '');
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_keyToken, _token!);
        await prefs.setString(_keyUser, json.encode(_user));
        await prefs.setString(_keyUsername, username);
        await prefs.setString(_keyPassword, password);
        notifyListeners();
        return null;
      }
      return data['message'] ?? 'Đăng nhập thất bại';
    } catch (_) {
      return 'Không kết nối được server';
    }
  }

  Future<bool> isBiometricEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyBiometric) ?? false;
  }

  Future<void> setBiometricEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyBiometric, value);
  }

  Future<String?> loginWithBiometric() async {
    try {
      final localAuth = LocalAuthentication();
      final ok = await localAuth.authenticate(
        localizedReason: 'Xác thực để đăng nhập',
      );
      if (!ok) return 'Xác thực thất bại';

      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString(_keyUsername);
      final password = prefs.getString(_keyPassword);
      if (username == null || password == null) {
        return 'Chưa có thông tin đăng nhập đã lưu';
      }
      return login(username, password);
    } catch (e) {
      return 'Lỗi sinh trắc học: $e';
    }
  }

  Future<String?> changePassword(String oldPass, String newPass) async {
    try {
      final uri = Uri.parse('${ApiService.baseUrl}/auth/change-password');
      final res = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          if (_token != null) 'Authorization': 'Bearer $_token',
        },
        body: json.encode({'oldPassword': oldPass, 'newPassword': newPass}),
      );
      final data = json.decode(res.body);
      if (res.statusCode == 200 && data['success'] == true) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_keyPassword, newPass);
        return null;
      }
      return data['message'] ?? 'Đổi mật khẩu thất bại';
    } catch (_) {
      return 'Không kết nối được server';
    }
  }

  Future<void> logout() async {
    _token = null;
    _user = null;
    ApiService.setToken('');
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyToken);
    await prefs.remove(_keyUser);
    notifyListeners();
  }
}
