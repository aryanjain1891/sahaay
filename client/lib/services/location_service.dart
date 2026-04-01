import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geoflutterfire_plus/geoflutterfire_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  Timer? _updateTimer;
  Position? _lastKnownPosition;

  Position? get lastKnownPosition => _lastKnownPosition;

  // ─── Permission handling ───────────────────────────────────────────────────

  Future<bool> requestPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      // Guide user to settings — don't crash
      await Geolocator.openAppSettings();
      return false;
    }

    return permission == LocationPermission.whileInUse ||
           permission == LocationPermission.always;
  }

  // ─── Get current position ─────────────────────────────────────────────────

  Future<Position?> getCurrentPosition() async {
    final hasPermission = await requestPermission();
    if (!hasPermission) return _lastKnownPosition; // graceful degradation

    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      _lastKnownPosition = pos;
      return pos;
    } catch (_) {
      // Fall back to last known
      return _lastKnownPosition ?? await Geolocator.getLastKnownPosition();
    }
  }

  // ─── Periodic background updates (every 45s) ──────────────────────────────

  void startPeriodicUpdates() {
    _updateTimer?.cancel();
    _updateTimer = Timer.periodic(const Duration(seconds: 45), (_) async {
      await _pushLocationToFirestore();
    });
  }

  void stopPeriodicUpdates() {
    _updateTimer?.cancel();
    _updateTimer = null;
  }

  Future<void> _pushLocationToFirestore() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final pos = await getCurrentPosition();
    if (pos == null) return;

    final geoPoint = GeoFirePoint(GeoPoint(pos.latitude, pos.longitude));

    await FirebaseFirestore.instance.collection('users').doc(uid).update({
      'location': GeoPoint(pos.latitude, pos.longitude),
      'geohash': geoPoint.geohash,
      'last_active': FieldValue.serverTimestamp(),
    });
  }

  // ─── One-shot push (call on foreground) ───────────────────────────────────

  Future<void> pushLocationNow() => _pushLocationToFirestore();

  // ─── Convert Position → Firestore-ready map ───────────────────────────────

  static Map<String, dynamic> toFirestoreMap(Position pos) {
    final geoPoint = GeoFirePoint(GeoPoint(pos.latitude, pos.longitude));
    return {
      'location': GeoPoint(pos.latitude, pos.longitude),
      'geohash': geoPoint.geohash,
      'last_active': FieldValue.serverTimestamp(),
    };
  }

}