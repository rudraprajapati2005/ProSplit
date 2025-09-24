import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _notifSub;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // Local notifications setup
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    await _local.initialize(const InitializationSettings(android: androidInit, iOS: iosInit));

    // Request FCM permission
    await _messaging.requestPermission(alert: true, badge: true, sound: true);

    // Foreground presentation (iOS)
    await _messaging.setForegroundNotificationPresentationOptions(alert: true, badge: true, sound: true);

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final notification = message.notification;
      if (notification != null) {
        _showLocal(notification.title ?? 'Update', notification.body ?? '');
      }
    });
  }

  Future<void> _showLocal(String title, String body) async {
    const androidDetails = AndroidNotificationDetails(
      'general_channel',
      'General',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
    );
    const iosDetails = DarwinNotificationDetails();
    await _local.show(DateTime.now().millisecondsSinceEpoch ~/ 1000, title, body, const NotificationDetails(android: androidDetails, iOS: iosDetails));
  }

  // Save/update FCM token under users/{uid}
  Future<void> syncFcmToken(String userId) async {
    final token = await _messaging.getToken();
    if (token == null) return;
    await FirebaseFirestore.instance.collection('users').doc(userId).set({
      'fcmTokens': FieldValue.arrayUnion([token])
    }, SetOptions(merge: true));

    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      await FirebaseFirestore.instance.collection('users').doc(userId).set({
        'fcmTokens': FieldValue.arrayUnion([newToken])
      }, SetOptions(merge: true));
    });
  }

  // Debug helper: print user's FCM tokens
  Future<void> debugPrintUserFcmTokens(String userId) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
      final data = doc.data() ?? {};
      final tokens = List<String>.from(data['fcmTokens'] ?? const <String>[]);
      if (tokens.isEmpty) {
        print('🔎 FCM tokens for $userId: (none)');
      } else {
        print('🔎 FCM tokens for $userId: ${tokens.join(', ')}');
      }
    } catch (e) {
      print('❌ Error fetching FCM tokens for $userId: $e');
    }
  }

  // Start listening to Firestore notifications for a specific user
  Future<void> startUserNotificationListener(String userId) async {
    await _notifSub?.cancel();
    _notifSub = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('notifications')
        .orderBy('createdAt', descending: true)
        .limit(20)
        .snapshots()
        .listen((snapshot) {
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data();
          if (data == null) continue;
          final title = (data['title'] as String?) ?? 'Notification';
          final body = (data['body'] as String?) ?? '';
          _showLocal(title, body);
        }
      }
    });
  }

  Future<void> stopUserNotificationListener() async {
    await _notifSub?.cancel();
    _notifSub = null;
  }
}


