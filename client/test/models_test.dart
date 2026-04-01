import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sahaay/models/models.dart';

// ─── Fake DocumentSnapshot ──────────────────────────────────────────────────
// Minimal fake that provides `id` and `data()` without requiring Firebase
// initialization.  Only the members used by fromDoc are implemented; everything
// else throws UnimplementedError so the test fails fast if the production code
// touches something unexpected.

class FakeDocumentSnapshot implements DocumentSnapshot<Map<String, dynamic>> {
  @override
  final String id;
  final Map<String, dynamic>? _data;

  FakeDocumentSnapshot({required this.id, Map<String, dynamic>? data})
      : _data = data;

  @override
  Map<String, dynamic>? data() => _data;

  @override
  bool get exists => _data != null;

  // ── Unimplemented stubs ────────────────────────────────────────────────

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      '${invocation.memberName} is not implemented in FakeDocumentSnapshot');
}

// ─── Tests ──────────────────────────────────────────────────────────────────

void main() {
  // ════════════════════════════════════════════════════════════════════════════
  // SahaayUser
  // ════════════════════════════════════════════════════════════════════════════

  group('SahaayUser.fromDoc', () {
    test('parses complete valid data', () {
      final now = DateTime(2025, 6, 15, 10, 30);
      final doc = FakeDocumentSnapshot(
        id: 'user-123',
        data: {
          'name': 'Alice',
          'phone_number': '+911234567890',
          'profile_photo_url': 'https://example.com/photo.jpg',
          'location': const GeoPoint(28.6139, 77.2090),
          'geohash': 'ttnfv2u',
          'is_available_for_help': true,
          'last_active': Timestamp.fromDate(now),
        },
      );

      final user = SahaayUser.fromDoc(doc);

      expect(user.userId, 'user-123');
      expect(user.name, 'Alice');
      expect(user.phoneNumber, '+911234567890');
      expect(user.profilePhotoUrl, 'https://example.com/photo.jpg');
      expect(user.location.latitude, 28.6139);
      expect(user.location.longitude, 77.2090);
      expect(user.geohash, 'ttnfv2u');
      expect(user.isAvailableForHelp, isTrue);
      expect(user.lastActive, now);
    });

    test('handles missing / null fields with safe defaults', () {
      final doc = FakeDocumentSnapshot(id: 'user-empty', data: {});

      final user = SahaayUser.fromDoc(doc);

      expect(user.userId, 'user-empty');
      expect(user.name, '');
      expect(user.phoneNumber, '');
      expect(user.profilePhotoUrl, isNull);
      expect(user.location.latitude, 0);
      expect(user.location.longitude, 0);
      expect(user.geohash, '');
      expect(user.isAvailableForHelp, isFalse);
      // lastActive falls back to DateTime.now(); just verify it is recent
      expect(
        user.lastActive.difference(DateTime.now()).inSeconds.abs(),
        lessThan(2),
      );
    });

    test('handles explicit null values in map', () {
      final doc = FakeDocumentSnapshot(
        id: 'user-nulls',
        data: {
          'name': null,
          'phone_number': null,
          'profile_photo_url': null,
          'location': null,
          'geohash': null,
          'is_available_for_help': null,
          'last_active': null,
        },
      );

      final user = SahaayUser.fromDoc(doc);

      expect(user.name, '');
      expect(user.phoneNumber, '');
      expect(user.profilePhotoUrl, isNull);
      expect(user.location, const GeoPoint(0, 0));
      expect(user.geohash, '');
      expect(user.isAvailableForHelp, isFalse);
    });
  });

  group('SahaayUser.toMap', () {
    test('produces expected keys and values', () {
      final now = DateTime(2025, 1, 1);
      final user = SahaayUser(
        userId: 'u1',
        name: 'Bob',
        phoneNumber: '+910000000000',
        profilePhotoUrl: null,
        location: const GeoPoint(10, 20),
        geohash: 'abc',
        isAvailableForHelp: true,
        lastActive: now,
      );

      final map = user.toMap();

      expect(map['name'], 'Bob');
      expect(map['phone_number'], '+910000000000');
      expect(map['profile_photo_url'], isNull);
      expect(map['location'], const GeoPoint(10, 20));
      expect(map['geohash'], 'abc');
      expect(map['is_available_for_help'], isTrue);
      expect(map['last_active'], Timestamp.fromDate(now));
    });
  });

  // ════════════════════════════════════════════════════════════════════════════
  // SosEvent
  // ════════════════════════════════════════════════════════════════════════════

  group('SosEvent.fromDoc', () {
    test('parses complete valid data', () {
      final ts = DateTime(2025, 3, 10, 14, 0);
      final doc = FakeDocumentSnapshot(
        id: 'sos-001',
        data: {
          'triggered_by': 'user-abc',
          'location': const GeoPoint(12.9716, 77.5946),
          'timestamp': Timestamp.fromDate(ts),
          'status': 'ACTIVE',
          'responders': ['resp-1', 'resp-2'],
        },
      );

      final event = SosEvent.fromDoc(doc);

      expect(event.sosId, 'sos-001');
      expect(event.triggeredBy, 'user-abc');
      expect(event.location.latitude, 12.9716);
      expect(event.location.longitude, 77.5946);
      expect(event.timestamp, ts);
      expect(event.status, SosStatus.active);
      expect(event.responders, ['resp-1', 'resp-2']);
    });

    test('defaults when all fields are missing', () {
      final doc = FakeDocumentSnapshot(id: 'sos-empty', data: {});

      final event = SosEvent.fromDoc(doc);

      expect(event.sosId, 'sos-empty');
      expect(event.triggeredBy, '');
      expect(event.location, const GeoPoint(0, 0));
      expect(event.status, SosStatus.active);
      expect(event.responders, isEmpty);
    });
  });

  group('SosEvent.fromMap', () {
    test('parses with GeoPoint location', () {
      final ts = DateTime(2025, 5, 20, 8, 0);
      final map = <String, dynamic>{
        'triggered_by': 'user-xyz',
        'location': const GeoPoint(19.076, 72.8777),
        'timestamp': Timestamp.fromDate(ts),
        'status': 'RESOLVED',
        'responders': ['r1'],
      };

      final event = SosEvent.fromMap('sos-map-1', map);

      expect(event.sosId, 'sos-map-1');
      expect(event.triggeredBy, 'user-xyz');
      expect(event.location.latitude, 19.076);
      expect(event.location.longitude, 72.8777);
      expect(event.timestamp, ts);
      expect(event.status, SosStatus.resolved);
      expect(event.responders, ['r1']);
    });

    test('parses with lat/lng map location (Cloud Function response)', () {
      final map = <String, dynamic>{
        'triggered_by': 'user-cf',
        'location': {'lat': 13.0827, 'lng': 80.2707},
        'timestamp': '2025-05-20T08:00:00.000',
        'status': 'EXPIRED',
        'responders': [],
      };

      final event = SosEvent.fromMap('sos-map-2', map);

      expect(event.location.latitude, 13.0827);
      expect(event.location.longitude, 80.2707);
      expect(event.status, SosStatus.expired);
      expect(event.timestamp, DateTime(2025, 5, 20, 8, 0));
    });

    test('handles null location map values', () {
      final map = <String, dynamic>{
        'location': {'lat': null, 'lng': null},
        'timestamp': null,
        'status': null,
        'responders': null,
      };

      final event = SosEvent.fromMap('sos-null', map);

      expect(event.location.latitude, 0);
      expect(event.location.longitude, 0);
      expect(event.status, SosStatus.active);
      expect(event.responders, isEmpty);
    });

    test('handles completely missing fields', () {
      final event = SosEvent.fromMap('sos-bare', <String, dynamic>{});

      expect(event.sosId, 'sos-bare');
      expect(event.triggeredBy, '');
      expect(event.status, SosStatus.active);
      expect(event.responders, isEmpty);
    });
  });

  group('SosStatus enum parsing', () {
    test('parses lowercase status strings', () {
      for (final status in SosStatus.values) {
        final doc = FakeDocumentSnapshot(
          id: 'sos-${status.name}',
          data: {'status': status.name},
        );
        final event = SosEvent.fromDoc(doc);
        expect(event.status, status);
      }
    });

    test('parses uppercase status strings', () {
      for (final status in SosStatus.values) {
        final doc = FakeDocumentSnapshot(
          id: 'sos-${status.name}',
          data: {'status': status.name.toUpperCase()},
        );
        final event = SosEvent.fromDoc(doc);
        expect(event.status, status);
      }
    });

    test('falls back to active for unknown status', () {
      final doc = FakeDocumentSnapshot(
        id: 'sos-x',
        data: {'status': 'UNKNOWN_VALUE'},
      );
      final event = SosEvent.fromDoc(doc);
      expect(event.status, SosStatus.active);
    });
  });

  group('SosEvent.toMap roundtrip', () {
    test('fromDoc -> toMap preserves core fields', () {
      final ts = DateTime(2025, 7, 1, 12, 0);
      final doc = FakeDocumentSnapshot(
        id: 'rt-1',
        data: {
          'triggered_by': 'uid-rt',
          'location': const GeoPoint(40.7128, -74.0060),
          'timestamp': Timestamp.fromDate(ts),
          'status': 'RESOLVED',
          'responders': ['a', 'b'],
        },
      );

      final event = SosEvent.fromDoc(doc);
      final map = event.toMap();

      expect(map['triggered_by'], 'uid-rt');
      expect(map['location'], const GeoPoint(40.7128, -74.0060));
      expect(map['timestamp'], Timestamp.fromDate(ts));
      expect(map['status'], 'RESOLVED');
      expect(map['responders'], ['a', 'b']);
    });

    test('fromMap -> toMap preserves core fields', () {
      final ts = DateTime(2025, 7, 1, 12, 0);
      final input = <String, dynamic>{
        'triggered_by': 'uid-rt2',
        'location': const GeoPoint(35.6762, 139.6503),
        'timestamp': Timestamp.fromDate(ts),
        'status': 'ACTIVE',
        'responders': ['c'],
      };

      final event = SosEvent.fromMap('rt-2', input);
      final map = event.toMap();

      expect(map['triggered_by'], 'uid-rt2');
      expect(map['location'], const GeoPoint(35.6762, 139.6503));
      expect(map['timestamp'], Timestamp.fromDate(ts));
      expect(map['status'], 'ACTIVE');
      expect(map['responders'], ['c']);
    });
  });
}
