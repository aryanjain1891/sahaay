import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'screens/sos_detail_screen.dart';

// Background FCM handler — must be top-level
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  // Notification shown automatically by FCM when app is in background/terminated
}

final FlutterLocalNotificationsPlugin _localNotifications =
    FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // Background message handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Local notifications setup (for foreground FCM)
  await _localNotifications.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    ),
  );

  runApp(const SahaayApp());
}

class SahaayApp extends StatefulWidget {
  const SahaayApp({super.key});

  @override
  State<SahaayApp> createState() => _SahaayAppState();
}

class _SahaayAppState extends State<SahaayApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    _initFcm();
  }

  Future<void> _initFcm() async {
    final messaging = FirebaseMessaging.instance;

    // Request notification permission
    await messaging.requestPermission(alert: true, badge: true, sound: true);

    // Save FCM token to Firestore (called after auth)
    final token = await messaging.getToken();
    if (token != null) _saveFcmToken(token);

    messaging.onTokenRefresh.listen(_saveFcmToken);

    // Foreground messages
    FirebaseMessaging.onMessage.listen((message) {
      final data = message.data;
      if (data['type'] == 'SOS_ALERT') {
        _showForegroundSosNotification(message);
      }
    });

    // Notification tap when app is in background (not terminated)
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _handleNotificationTap(message.data);
    });

    // Notification tap when app was terminated
    final initial = await messaging.getInitialMessage();
    if (initial != null) _handleNotificationTap(initial.data);
  }

  void _saveFcmToken(String token) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    // Use set+merge so this works on first login before the user doc is fully created
    FirebaseFirestore.instance.collection('users').doc(uid).set(
      {'fcm_token': token},
      SetOptions(merge: true),
    );
  }

  void _handleNotificationTap(Map<String, dynamic> data) {
    if (data['type'] == 'SOS_ALERT') {
      final sosId = data['sos_id'] as String?;
      if (sosId != null) {
        _navigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => SosDetailScreen(sosId: sosId)),
        );
      }
    }
  }

  Future<void> _showForegroundSosNotification(RemoteMessage message) async {
    const channel = AndroidNotificationChannel(
      'sos_alerts',
      'SOS Alerts',
      description: 'Emergency SOS alerts from nearby users',
      importance: Importance.max,
      playSound: true,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    await _localNotifications.show(
      0,
      '🚨 SOS Alert Nearby',
      message.data['user_name'] != null
          ? '${message.data['user_name']} needs help • ${message.data['distance']}'
          : 'Someone nearby needs help',
      NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id, channel.name,
          channelDescription: channel.description,
          importance: Importance.max,
          priority: Priority.max,
          fullScreenIntent: true,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: message.data['sos_id'],
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sahaay',
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFF4444),
          background: Color(0xFF0D0D0D),
        ),
        useMaterial3: true,
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          // Show a splash/loading indicator while Firebase resolves auth state
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              backgroundColor: Color(0xFF0D0D0D),
              body: Center(
                child: CircularProgressIndicator(color: Color(0xFFFF4444)),
              ),
            );
          }
          // Signed in → main app
          if (snapshot.hasData) return const HomeScreen();
          // Not signed in → auth flow
          return const AuthScreen();
        },
      ),
    );
  }
}