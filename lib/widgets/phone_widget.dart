import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io' show Platform;
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

  Future<void> _call(BuildContext context) async {
    try {
      if (Platform.isAndroid) {
        // android.intent.action.CALL gọi luôn, không qua dialer
        const platform = MethodChannel('app/phone_call');
        await platform.invokeMethod('call', {'number': phone});
      } else {
        // iOS: tel: scheme tự gọi luôn sau khi user confirm popup hệ thống
        final uri = Uri.parse('tel:$phone');
        await launchUrl(uri);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Không thể gọi: $phone'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final defaultStyle = TextStyle(
      color: AppTheme.primary,
      fontSize: 13,
      fontWeight: FontWeight.w500,
    );

    return GestureDetector(
      onTap: () => _call(context),
      onLongPress: () {
        Clipboard.setData(ClipboardData(text: phone));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Đã copy: $phone'),
          duration: const Duration(seconds: 1),
        ));
      },
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
