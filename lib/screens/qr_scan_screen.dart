import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../models/live_comment.dart';
import '../services/api_service.dart';
import 'customer_detail_screen.dart';
import 'order_detail_screen.dart';

enum _ScanMode { chotDon, lenDon }

class QrScanScreen extends StatefulWidget {
  final List<LiveComment> liveComments;
  const QrScanScreen({super.key, this.liveComments = const []});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen>
    with SingleTickerProviderStateMixin {
  bool _scanned = false;
  _ScanMode _mode = _ScanMode.chotDon;
  late AnimationController _scanAnim;
  late Animation<double> _scanLine;
  final MobileScannerController _camCtrl = MobileScannerController();

  static const double _frameSize = 260.0;

  @override
  void initState() {
    super.initState();
    _scanAnim = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _scanLine = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _scanAnim, curve: Curves.easeInOut),
    );
    _loadSavedMode();
  }

  Future<void> _loadSavedMode() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('qr_scan_mode');
    if (saved == 'lenDon' && mounted) {
      setState(() => _mode = _ScanMode.lenDon);
    }
  }

  Future<void> _setMode(_ScanMode mode) async {
    setState(() => _mode = mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'qr_scan_mode', mode == _ScanMode.lenDon ? 'lenDon' : 'chotDon');
  }

  @override
  void dispose() {
    _scanAnim.dispose();
    _camCtrl.dispose();
    super.dispose();
  }

  void _onQrDetected(String raw) {
    if (_scanned) return;
    setState(() => _scanned = true);
    _scanAnim.stop();
    _handleCode(raw.trim());
  }

  Future<void> _handleCode(String raw) async {
    String code = raw.contains('1P1') ? raw.replaceAll('1P1', '') : raw;
    code = code.trim();
    if (code.length < 12) {
      final id = int.tryParse(code);
      if (id == null) {
        _showError('Mã không hợp lệ: $code');
        return;
      }
      await _handleCustomerId(id);
    } else {
      await _handleOrderCode(code);
    }
  }

  Future<void> _handleCustomerId(int id) async {
    _showLoading();
    try {
      final customer = await ApiService.getCustomerById(id);
      if (!mounted) return;
      Navigator.pop(context);
      if (customer == null) {
        _showError('Không tìm thấy khách hàng #$id');
        return;
      }

      if (_mode == _ScanMode.chotDon) {
        final userid = customer.userid ?? '';
        if (userid.isEmpty) {
          _showError('Khách hàng này chưa có userid Facebook');
          return;
        }
        final userChotComments = widget.liveComments
            .where((c) => c.userid == userid && c.hasOrder)
            .toList()
          ..sort((a, b) => _parsePrice(a.gia).compareTo(_parsePrice(b.gia)));
        if (userChotComments.isEmpty) {
          _showError('Không tìm thấy bình luận chốt của khách này trong live');
          return;
        }
        final rep = widget.liveComments.firstWhere((c) => c.userid == userid,
            orElse: () => userChotComments.first);
        Navigator.pop(context, {
          'action': 'chotDon',
          'comment': rep,
          'chotComments': userChotComments,
        });
      } else {
        Navigator.pop(context);
        if (!mounted) return;
        final liveIds = widget.liveComments
            .map((c) => c.liveid ?? '')
            .where((id) => id.isNotEmpty)
            .toSet()
            .toList();
        Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CustomerDetailScreen(
                customer: customer,
                selectedLiveIds: liveIds,
                liveComments:
                    widget.liveComments, // truyền để QR lần sau còn có comments
              ),
            ));
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      _showError('Lỗi: $e');
    }
  }

  Future<void> _handleOrderCode(String code) async {
    _showLoading();
    try {
      final orders = await ApiService.getOrders(search: code, limit: 1);
      if (!mounted) return;
      Navigator.pop(context);
      if (orders.isEmpty) {
        _showError('Không tìm thấy đơn hàng: $code');
        return;
      }
      Navigator.pop(context);
      if (!mounted) return;
      Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => OrderDetailScreen(order: orders.first),
          ));
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      _showError('Lỗi: $e');
    }
  }

  void _showLoading() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
          child: CircularProgressIndicator(color: AppTheme.primary)),
    );
  }

  void _showError(String msg) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        title:
            const Text('Không tìm thấy', style: TextStyle(color: Colors.white)),
        content:
            Text(msg, style: const TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() => _scanned = false);
              _scanAnim.repeat(reverse: true);
            },
            child: const Text('Thử lại',
                style: TextStyle(color: AppTheme.primary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('Đóng',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
        ],
      ),
    );
  }

  void _showManualInput() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        title: const Text('Nhập mã', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          keyboardType: TextInputType.text,
          decoration: InputDecoration(
            hintText: 'ID khách / Mã vận đơn...',
            hintStyle: TextStyle(color: AppTheme.textSecondary),
          ),
          onSubmitted: (v) {
            if (v.trim().isNotEmpty) {
              Navigator.pop(context);
              _onQrDetected(v.trim());
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            onPressed: () {
              if (ctrl.text.trim().isNotEmpty) {
                Navigator.pop(context);
                _onQrDetected(ctrl.text.trim());
              }
            },
            child:
                const Text('Tìm kiếm', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  int _parsePrice(String? raw) {
    if (raw == null || raw.isEmpty) return 0;
    final n = int.tryParse(raw.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    return (n > 0 && n < 1000) ? n * 1000 : n;
  }

  @override
  Widget build(BuildContext context) {
    // Tính vị trí frame dựa trên màn hình thực tế
    // Toàn bộ UI nằm trong 1 Stack, overlay và corners dùng cùng coordinate
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Quét mã', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on_outlined, color: Colors.white),
            onPressed: () => _camCtrl.toggleTorch(),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final screenW = constraints.maxWidth;
          final screenH = constraints.maxHeight;

          // Vị trí frame: căn giữa màn hình theo cả 2 chiều
          // Column có mainAxisAlignment.center → tổng height của column = auto
          // Mode switch height ~52px + margin 32 + frame 260 + padding 24 + text ~40 + 6 + 32 + button ~36
          const modeSwitchH = 52.0;
          const marginBelowMode = 32.0;
          const columnContentH = modeSwitchH +
              marginBelowMode +
              _frameSize +
              24.0 +
              40.0 +
              6.0 +
              32.0 +
              36.0;
          final columnTopY = (screenH - columnContentH) / 2;
          final frameTop = columnTopY + modeSwitchH + marginBelowMode;
          final frameLeft = (screenW - _frameSize) / 2;
          final frameRect =
              Rect.fromLTWH(frameLeft, frameTop, _frameSize, _frameSize);

          return Stack(
            children: [
              // Camera
              MobileScanner(
                controller: _camCtrl,
                onDetect: (capture) {
                  final barcode = capture.barcodes.firstOrNull;
                  if (barcode?.rawValue != null)
                    _onQrDetected(barcode!.rawValue!);
                },
              ),

              // Overlay mờ — vẽ đúng vị trí frameRect
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _QrOverlayPainter(frameRect: frameRect),
                  ),
                ),
              ),

              // Corners — vị trí tuyệt đối theo frameRect
              ..._buildCorners(frameRect),

              // Scan line animation bên trong frame
              AnimatedBuilder(
                animation: _scanLine,
                builder: (_, __) => Positioned(
                  top: frameRect.top + 10 + _scanLine.value * (_frameSize - 20),
                  left: frameRect.left + 10,
                  right: screenW - frameRect.right + 10,
                  child: Container(
                    height: 2,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        Colors.transparent,
                        AppTheme.primary.withOpacity(0.8),
                        Colors.transparent,
                      ]),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primary.withOpacity(0.3),
                          blurRadius: 6,
                          spreadRadius: 2,
                        )
                      ],
                    ),
                  ),
                ),
              ),

              // UI controls — nằm trên overlay
              Positioned.fill(
                child: SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Mode switch
                      Container(
                        margin: const EdgeInsets.only(bottom: marginBelowMode),
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _modeBtn(_ScanMode.chotDon,
                                Icons.shopping_cart_outlined, 'Chốt đơn'),
                            const SizedBox(width: 4),
                            _modeBtn(_ScanMode.lenDon,
                                Icons.local_shipping_outlined, 'Lên đơn'),
                          ],
                        ),
                      ),

                      // Frame placeholder (transparent — corners & scan line từ Stack)
                      const SizedBox(width: _frameSize, height: _frameSize),

                      const SizedBox(height: 24),
                      Text(
                        _mode == _ScanMode.chotDon
                            ? 'Quét ID khách → tìm đơn chốt trong live'
                            : 'Quét ID khách → mở trang lên đơn',
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.7), fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Mã vận đơn (≥12 ký tự) → xem chi tiết đơn',
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.35),
                            fontSize: 11),
                      ),
                      const SizedBox(height: 32),
                      TextButton.icon(
                        icon:
                            const Icon(Icons.keyboard, color: AppTheme.primary),
                        label: const Text('Nhập mã thủ công',
                            style: TextStyle(color: AppTheme.primary)),
                        onPressed: _showManualInput,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _buildCorners(Rect r) {
    const size = 24.0, thick = 3.0;
    final c = AppTheme.primary;
    return [
      Positioned(
          top: r.top,
          left: r.left,
          child: _corner(c, size, thick, top: true, left: true)),
      Positioned(
          top: r.top,
          left: r.right - size,
          child: _corner(c, size, thick, top: true, left: false)),
      Positioned(
          top: r.bottom - size,
          left: r.left,
          child: _corner(c, size, thick, top: false, left: true)),
      Positioned(
          top: r.bottom - size,
          left: r.right - size,
          child: _corner(c, size, thick, top: false, left: false)),
    ];
  }

  Widget _corner(Color color, double size, double thick,
      {required bool top, required bool left}) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter:
            _CornerPainter(color: color, thick: thick, top: top, left: left),
      ),
    );
  }

  Widget _modeBtn(_ScanMode mode, IconData icon, String label) {
    final active = _mode == mode;
    return GestureDetector(
      onTap: () => _setMode(mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: active ? AppTheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: active ? Colors.white : Colors.white54),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  color: active ? Colors.white : Colors.white54,
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w400)),
        ]),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  final Color color;
  final double thick;
  final bool top, left;
  _CornerPainter(
      {required this.color,
      required this.thick,
      required this.top,
      required this.left});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = thick
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final path = Path();
    if (top && left) {
      path.moveTo(0, size.height);
      path.lineTo(0, 0);
      path.lineTo(size.width, 0);
    } else if (top && !left) {
      path.moveTo(0, 0);
      path.lineTo(size.width, 0);
      path.lineTo(size.width, size.height);
    } else if (!top && left) {
      path.moveTo(0, 0);
      path.lineTo(0, size.height);
      path.lineTo(size.width, size.height);
    } else {
      path.moveTo(0, size.height);
      path.lineTo(size.width, size.height);
      path.lineTo(size.width, 0);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_) => false;
}

class _QrOverlayPainter extends CustomPainter {
  final Rect frameRect;
  const _QrOverlayPainter({required this.frameRect});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withOpacity(0.55)
      ..style = PaintingStyle.fill;
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(frameRect, const Radius.circular(12)));
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _QrOverlayPainter old) =>
      old.frameRect != frameRect;
}
