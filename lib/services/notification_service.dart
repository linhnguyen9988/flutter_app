import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/order.dart';
import '../screens/order_detail_screen.dart';
import 'api_service.dart';

@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await NotificationService.initForBackground();

  final data = message.data;
  final title = data['title']?.toString() ?? message.notification?.title ?? '';
  final body = data['body']?.toString() ?? message.notification?.body ?? '';

  if (title.isNotEmpty) {
    await NotificationService.showFromBackground(title, body, data);
  }
}

class NotificationService {
  NotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static final StreamController<Map<String, dynamic>> _newNotiController =
      StreamController<Map<String, dynamic>>.broadcast();
  static Stream<Map<String, dynamic>> get onNewNoti =>
      _newNotiController.stream;
  static GlobalKey<NavigatorState>? navigatorKey;

  static const _androidChannel = AndroidNotificationChannel(
    'push_channel',
    'Thông báo',
    description: 'Thông báo từ server',
    importance: Importance.high,
    playSound: true,
  );

  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

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

    FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);

    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    await _uploadFcmToken();
    FirebaseMessaging.instance.onTokenRefresh.listen(_saveFcmToken);

    FirebaseMessaging.onMessage.listen((message) {
      final title = message.notification?.title ?? message.data['title'] ?? '';
      final body = message.notification?.body ?? message.data['body'] ?? '';
      if (title.isNotEmpty) {
        _show(title, body, message.data.isNotEmpty ? message.data : null);
        // Broadcast noti mới để các screen đang mở cập nhật realtime
        _newNotiController.add({
          'title': title,
          'body': body,
          'is_read': 0,
          'created_at': DateTime.now().toIso8601String(),
          ...message.data,
        });
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _handleFcmTap(message.data);
    });

    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      Future.delayed(const Duration(milliseconds: 500), () {
        _handleFcmTap(initial.data);
      });
    }
  }

  static Future<void> initForBackground() async {
    if (_initialized) return;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    await _plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: _onTap,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_androidChannel);
    _initialized = true;
  }

  static Future<void> showFromBackground(
      String title, String body, Map<String, dynamic> data) async {
    await _show(title, body, data);
  }

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

  static Future<void> cancelByNotiId(String notiId) async {
    final idInt = int.tryParse(notiId);
    if (idInt != null) {
      try {
        await _plugin.cancel(idInt);
      } on PlatformException catch (e) {
        debugPrint('[Noti] cancel warning (safe to ignore): ${e.message}');
      }
    }
  }

  static Future<void> cancelAll() async {
    try {
      await _plugin.cancelAll();
    } on PlatformException catch (e) {
      debugPrint('[Noti] cancelAll warning (safe to ignore): ${e.message}');
    }
  }

  static int _notifId = 0;

  static Future<void> _show(String title, String body, dynamic extra) async {
    int notifId = _notifId++;
    if (extra is Map && extra['noti_id'] != null) {
      notifId = int.tryParse(extra['noti_id'].toString()) ?? notifId;
    }
    await _plugin.show(
      notifId,
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

    final notiId = data['noti_id']?.toString() ?? '';
    if (notiId.isNotEmpty && ApiService.token.isNotEmpty) {
      _markReadById(notiId);
      cancelByNotiId(notiId);
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
        Uri.parse('${ApiService.baseUrl}/notifications/$id/read'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${ApiService.token}',
        },
      );
    } catch (_) {}
  }

  static void dispose() {
    _initialized = false;
  }

  static void onUserChanged(String userId) {
    _uploadFcmToken();
  }
}
