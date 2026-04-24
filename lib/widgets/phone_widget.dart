import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';

class PhoneWidget extends StatelessWidget {
  final String phone;
  final TextStyle? style;
  final Widget? prefix;

  const PhoneWidget({
    super.key,
    required this.phone,
    this.style,
    this.prefix,
  });

  void _show(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardColor(isDark),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.surfaceColor(isDark),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(phone,
                style: TextStyle(
                    color: AppTheme.textColor(isDark),
                    fontSize: 22,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.phone, size: 18),
                      label: const Text('Gọi ngay'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () async {
                        Navigator.pop(context);
                        final uri = Uri.parse('tel:$phone');
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text('Sao chép'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.textColor(isDark),
                        side: BorderSide(color: AppTheme.surfaceColor(isDark)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        Clipboard.setData(ClipboardData(text: phone));
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('Đã copy: $phone'),
                          duration: const Duration(seconds: 1),
                        ));
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final defaultStyle = TextStyle(
      color: AppTheme.primary,
      fontSize: 13,
      fontWeight: FontWeight.w500,
    );

    return GestureDetector(
      onTap: () => _show(context),
      child: prefix != null
          ? Row(mainAxisSize: MainAxisSize.min, children: [
              prefix!,
              const SizedBox(width: 4),
              Text(phone, style: style ?? defaultStyle),
            ])
          : Text(phone, style: style ?? defaultStyle),
    );
  }
}
