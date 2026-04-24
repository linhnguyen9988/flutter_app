import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:provider/provider.dart';
import 'package:ao_dai_gia_bao/services/auth_service.dart';
import 'package:ao_dai_gia_bao/services/notification_service.dart';
import 'package:ao_dai_gia_bao/theme/app_theme.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  bool get isDark => Theme.of(context).brightness == Brightness.dark;

  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String _error = '';
  bool _biometricAvailable = false;
  // ignore: unused_field
  bool _biometricEnabled = false;
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _fadeAnim = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero)
        .animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));
    _animCtrl.forward();
    _checkBiometric();
  }

  Future<void> _checkBiometric() async {
    final auth = context.read<AuthService>();
    final localAuth = LocalAuthentication();
    final available = await localAuth.canCheckBiometrics ||
        await localAuth.isDeviceSupported();
    final enabled = await auth.isBiometricEnabled();
    if (mounted) {
      setState(() {
        _biometricAvailable = available && enabled;
        _biometricEnabled = enabled;
      });
    }
  }

  Future<void> _loginBiometric() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    final auth = context.read<AuthService>();
    final err = await auth.loginWithBiometric();
    if (!mounted) return;
    if (err == null) {
      await NotificationService.init();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(PageRouteBuilder(
        pageBuilder: (_, __, ___) => const HomeScreen(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ));
    } else {
      setState(() {
        _error = err;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final username = _userCtrl.text.trim();
    final password = _passCtrl.text;

    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = 'Vui lòng nhập đầy đủ thông tin');
      return;
    }

    setState(() {
      _loading = true;
      _error = '';
    });

    try {
      final auth = context.read<AuthService>();
      final err = await auth.login(username, password);

      if (!mounted) return;

      if (err == null) {
        await NotificationService.init();
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const HomeScreen(),
            transitionsBuilder: (_, anim, __, child) =>
                FadeTransition(opacity: anim, child: child),
            transitionDuration: const Duration(milliseconds: 400),
          ),
        );
      } else {
        setState(() {
          _error = err;
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Lỗi kết nối hệ thống';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgColor(isDark),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: FadeTransition(
              opacity: _fadeAnim,
              child: SlideTransition(
                position: _slideAnim,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Column(
                        children: [
                          Container(
                            width: 90,
                            height: 90,
                            padding: const EdgeInsets.all(0),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.1),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                )
                              ],
                            ),
                            child: ClipOval(
                              child: Image.asset(
                                'assets/images/icon.png',
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'Áo Dài Gia Bảo',
                            style: TextStyle(
                              color: Color(0xFF1877F2),
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Hệ thống quản lý bán hàng',
                            style: TextStyle(
                                color: AppTheme.textSubColor(isDark),
                                fontSize: 14,
                                letterSpacing: 0.3),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 48),
                    _buildLabel('Tên đăng nhập'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _userCtrl,
                      keyboardType: TextInputType.text,
                      textInputAction: TextInputAction.next,
                      style: TextStyle(color: AppTheme.textColor(isDark)),
                      decoration: _inputDecoration(
                        hint: 'Nhập username...',
                        icon: Icons.person_outline,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _buildLabel('Mật khẩu'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _passCtrl,
                      obscureText: _obscure,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _login(),
                      style: TextStyle(color: AppTheme.textColor(isDark)),
                      decoration: _inputDecoration(
                        hint: 'Nhập mật khẩu...',
                        icon: Icons.lock_outline,
                        suffix: IconButton(
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            color: AppTheme.textSubColor(isDark),
                            size: 20,
                          ),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_error.isNotEmpty)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: Colors.red.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline,
                                color: Colors.redAccent, size: 18),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(_error,
                                  style: const TextStyle(
                                      color: Colors.redAccent, fontSize: 13)),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 28),
                    SizedBox(
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _login,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          disabledBackgroundColor:
                              AppTheme.primary.withValues(alpha: 0.5),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                        child: _loading
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Đăng Nhập',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.1,
                                ),
                              ),
                      ),
                    ),
                    if (_biometricAvailable) ...[
                      const SizedBox(height: 16),
                      GestureDetector(
                        onTap: _loading ? null : _loginBiometric,
                        child: Column(children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color:
                                      AppTheme.primary.withValues(alpha: 0.4),
                                  width: 1.5),
                              color: AppTheme.primary.withValues(alpha: 0.08),
                            ),
                            child: const Icon(Icons.fingerprint,
                                color: AppTheme.primary, size: 30),
                          ),
                          const SizedBox(height: 6),
                          Text('Đăng nhập sinh trắc học',
                              style: TextStyle(
                                  color: AppTheme.textSubColor(isDark), fontSize: 12)),
                        ]),
                      ),
                    ],
                    const SizedBox(height: 40),
                    Center(
                      child: Text(
                        'ADGB Version 1.0.0',
                        style: TextStyle(
                            color:
                                AppTheme.textSubColor(isDark).withValues(alpha: 0.4),
                            fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Text(
          text,
          style: TextStyle(
              color: AppTheme.textSubColor(isDark),
              fontSize: 13,
              fontWeight: FontWeight.w600),
        ),
      );

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) =>
      InputDecoration(
        hintText: hint,
        hintStyle:
            TextStyle(color: AppTheme.textSubColor(isDark).withValues(alpha: 0.5)),
        prefixIcon: Icon(icon, color: AppTheme.textSubColor(isDark), size: 20),
        suffixIcon: suffix,
        filled: true,
        fillColor: AppTheme.cardColor(isDark),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      );
}
