import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/order.dart';
import '../screens/order_detail_screen.dart';
import 'api_service.dart';

// Handler chạy khi app bị kill — phải là top-level function
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  // FCM tự hiện notification khi app bị kill, không cần làm gì thêm
}

class NotificationService {
  NotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static GlobalKey<NavigatorState>? navigatorKey;

  static const _androidChannel = AndroidNotificationChannel(
    'push_channel',
    'Thông báo',
    description: 'Thông báo từ server',
    importance: Importance.high,
    playSound: true,
  );

  // ── Init ─────────────────────────────────────────────────────
  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // 1. Local notifications (hiện khi foreground)
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: _onTap,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_androidChannel);

    // 2. FCM
    FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);

    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // Lấy token gửi lên server
    await _uploadFcmToken();
    FirebaseMessaging.instance.onTokenRefresh.listen(_saveFcmToken);

    // Foreground — hiện local notification
    FirebaseMessaging.onMessage.listen((message) {
      final title = message.notification?.title ?? message.data['title'] ?? '';
      final body = message.notification?.body ?? message.data['body'] ?? '';
      if (title.isNotEmpty)
        _show(title, body, message.data.isNotEmpty ? message.data : null);
    });

    // Background — user tap noti
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _handleFcmTap(message.data);
    });

    // Killed — user tap noti mở app
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      Future.delayed(const Duration(milliseconds: 500), () {
        _handleFcmTap(initial.data);
      });
    }
  }

  // ── FCM Token ────────────────────────────────────────────────
  static Future<void> _uploadFcmToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _saveFcmToken(token);
    } catch (e) {
      debugPrint('[Noti] FCM token error: $e');
    }
  }

  static Future<void> _saveFcmToken(String token) async {
    debugPrint('[Noti] FCM token: $token');
    try {
      await ApiService.postRaw('https://aodaigiabao.com/api/fcm-token', {
        'userId': ApiService.userId,
        'token': token,
      });
    } catch (_) {}
  }

  // ── Hiện local notification (foreground) ─────────────────────
  static int _notifId = 0;

  static Future<void> _show(String title, String body, dynamic extra) async {
    await _plugin.show(
      _notifId++,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannel.id,
          _androidChannel.name,
          channelDescription: _androidChannel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: extra != null ? json.encode(extra) : null,
    );
  }

  // ── Navigate khi tap ─────────────────────────────────────────
  static void _onTap(NotificationResponse r) {
    if (r.payload == null || r.payload!.isEmpty) return;
    try {
      _handleFcmTap(json.decode(r.payload!) as Map<String, dynamic>);
    } catch (_) {}
  }

  static void _handleFcmTap(Map<String, dynamic> data) {
    if (data['type'] != 'order_status') return;
    final realorderid = data['realorderid']?.toString() ?? '';
    if (realorderid.isEmpty) return;

    // Đánh dấu đã đọc nếu có noti_id trong payload
    final notiId = data['noti_id']?.toString() ?? '';
    if (notiId.isNotEmpty && ApiService.token.isNotEmpty) {
      _markReadById(notiId);
    }

    final statusRaw = data['status'];
    final order = Order(
      id: 0,
      realorderid: realorderid,
      statuscode: statusRaw is int
          ? statusRaw
          : int.tryParse(statusRaw?.toString() ?? ''),
    );
    navigatorKey?.currentState?.push(MaterialPageRoute(
      builder: (_) => OrderDetailScreen(order: order),
    ));
  }

  static Future<void> _markReadById(String id) async {
    try {
      await http.post(
        Uri.parse('\${ApiService.baseUrl}/notifications/\$id/read'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer \${ApiService.token}',
        },
      );
    } catch (_) {}
  }

  // ── Lifecycle ────────────────────────────────────────────────
  static void dispose() {
    _initialized = false;
  }

  static void onUserChanged(String userId) {
    _uploadFcmToken();
  }
}
