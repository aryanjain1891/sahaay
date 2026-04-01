import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import '../models/models.dart';
import 'location_service.dart';

class SosService {
  static final SosService _instance = SosService._internal();
  factory SosService() => _instance;
  SosService._internal();

  final _firestore = FirebaseFirestore.instance;
  final _functions = FirebaseFunctions.instanceFor(region: 'asia-south1');
  final _uuid = const Uuid();

  DateTime? _lastSosTrigger;
  static const _debounceDuration = Duration(seconds: 30);

  // ─── Trigger SOS ──────────────────────────────────────────────────────────

  Future<SosTriggerResult> triggerSos() async {
    // Debounce check
    if (_lastSosTrigger != null &&
        DateTime.now().difference(_lastSosTrigger!) < _debounceDuration) {
      return SosTriggerResult.debounced;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return SosTriggerResult.notAuthenticatedResult;

    final pos = await LocationService().getCurrentPosition();

    _lastSosTrigger = DateTime.now();

    try {
      final callable = _functions.httpsCallable('triggerSos');

      final result = await callable.call({
        'lat': pos?.latitude,
        'lng': pos?.longitude,
        'accuracy_flag': pos == null ? 'last_known' : 'current',
      });

      final data = result.data as Map<String, dynamic>;
      final sosId = data['sos_id'] as String;

      // Immediately dial 112
      _dial112();

      return SosTriggerResult.success(sosId);
    } on FirebaseFunctionsException catch (e) {
      return SosTriggerResult.error(e.message ?? 'Unknown error');
    } catch (e) {
      return SosTriggerResult.error('Unexpected error');
    }
  }

  // ─── Cancel SOS ───────────────────────────────────────────────────────────

  Future<void> cancelSos(String sosId) async {
    await _firestore.collection('sos_events').doc(sosId).update({
      'status': 'RESOLVED',
      'cancelled': true,
    });
  }

  // ─── Responder: accept SOS ────────────────────────────────────────────────

  Future<void> acceptSos(String sosId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final batch = _firestore.batch();

    batch.update(_firestore.collection('sos_events').doc(sosId), {
      'responders': FieldValue.arrayUnion([uid]),
    });

    final responseRef = _firestore.collection('responses').doc(_uuid.v4());
    batch.set(responseRef, {
      'sos_id': sosId,
      'responder_id': uid,
      'accepted_at': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  // ─── Navigate to victim ───────────────────────────────────────────────────

  Future<void> navigateTo(double lat, double lng) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // ─── Watch active SOS for current user ────────────────────────────────────

  Stream<SosEvent?> watchActiveSos() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Stream.value(null);

    return _firestore
        .collection('sos_events')
        .where('triggered_by', isEqualTo: uid)
        .where('status', isEqualTo: 'ACTIVE')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .snapshots()
        .map((snap) =>
            snap.docs.isEmpty ? null : SosEvent.fromDoc(snap.docs.first));
  }

  // ─── Fetch nearby active SOS via Cloud Function (geo-scoped) ──────────────

  Future<List<SosEvent>> fetchNearbyActiveSos() async {
    final pos = await LocationService().getCurrentPosition();
    if (pos == null) return [];

    try {
      final callable = _functions.httpsCallable('getNearbyActiveSos');
      final result = await callable.call({
        'lat': pos.latitude,
        'lng': pos.longitude,
      });

      final data = result.data as Map<String, dynamic>;
      final events = (data['events'] as List<dynamic>?) ?? [];

      return events
          .map((e) => SosEvent.fromMap(
                e['sos_id'] as String,
                Map<String, dynamic>.from(e as Map),
              ))
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ─── Sign out (clean up FCM token) ────────────────────────────────────────

  Future<void> cleanUpAndSignOut() async {
    try {
      final callable = _functions.httpsCallable('signOut');
      await callable.call();
    } catch (_) {
      // Best-effort cleanup — proceed with sign out even if this fails
    }
    await FirebaseAuth.instance.signOut();
  }

  // ─── Private: dial 112 ───────────────────────────────────────────────────

  void _dial112() async {
    final uri = Uri(scheme: 'tel', path: '112');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }
}

// ─── Result type ─────────────────────────────────────────────────────────────

class SosTriggerResult {
  final bool ok;
  final String? sosId;
  final String? errorMessage;
  final bool wasDebounced;
  final bool notAuthenticated;

  const SosTriggerResult._({
    required this.ok,
    this.sosId,
    this.errorMessage,
    this.wasDebounced = false,
    this.notAuthenticated = false,
  });

  static SosTriggerResult success(String id) =>
      SosTriggerResult._(ok: true, sosId: id);

  static const SosTriggerResult debounced =
      SosTriggerResult._(ok: false, wasDebounced: true);

  static const SosTriggerResult notAuthenticatedResult =
      SosTriggerResult._(ok: false, notAuthenticated: true);

  static SosTriggerResult error(String msg) =>
      SosTriggerResult._(ok: false, errorMessage: msg);
}
