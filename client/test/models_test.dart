import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sahaay/models/models.dart';

void main() {
  // ════════════════════════════════════════════════════════════════════════════
  // SahaayUser
  // ════════════════════════════════════════════════════════════════════════════

  group('SahaayUser.fromMap', () {
    test('parses complete valid data', () {
      final now = DateTime(2025, 6, 15, 10, 30);
      final user = SahaayUser.fromMap('user-123', {
        'name': 'Alice',
        'phone_number': '+911234567890',
        'profile_photo_url': 'https://example.com/photo.jpg',
        'location': const GeoPoint(28.6139, 77.2090),
        'geohash': 'ttnfv2u',
        'is_available_for_help': true,
        'last_active': Timestamp.fromDate(now),
      });

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
      final user = SahaayUser.fromMap('user-empty', {});

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
      final user = SahaayUser.fromMap('user-nulls', {
        'name': null,
        'phone_number': null,
        'profile_photo_url': null,
        'location': null,
        'geohash': null,
        'is_available_for_help': null,
        'last_active': null,
      });

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

  group('SosEvent.fromMap', () {
    test('parses with GeoPoint location', () {
      final ts = DateTime(2025, 5, 20, 8, 0);
      final event = SosEvent.fromMap('sos-map-1', {
        'triggered_by': 'user-xyz',
        'location': const GeoPoint(19.076, 72.8777),
        'timestamp': Timestamp.fromDate(ts),
        'status': 'RESOLVED',
        'responders': ['r1'],
      });

      expect(event.sosId, 'sos-map-1');
      expect(event.triggeredBy, 'user-xyz');
      expect(event.location.latitude, 19.076);
      expect(event.location.longitude, 72.8777);
      expect(event.timestamp, ts);
      expect(event.status, SosStatus.resolved);
      expect(event.responders, ['r1']);
    });

    test('parses with lat/lng map location (Cloud Function response)', () {
      final event = SosEvent.fromMap('sos-map-2', {
        'triggered_by': 'user-cf',
        'location': {'lat': 13.0827, 'lng': 80.2707},
        'timestamp': '2025-05-20T08:00:00.000',
        'status': 'EXPIRED',
        'responders': [],
      });

      expect(event.location.latitude, 13.0827);
      expect(event.location.longitude, 80.2707);
      expect(event.status, SosStatus.expired);
      expect(event.timestamp, DateTime(2025, 5, 20, 8, 0));
    });

    test('handles null location map values', () {
      final event = SosEvent.fromMap('sos-null', {
        'location': {'lat': null, 'lng': null},
        'timestamp': null,
        'status': null,
        'responders': null,
      });

      expect(event.location.latitude, 0);
      expect(event.location.longitude, 0);
      expect(event.status, SosStatus.active);
      expect(event.responders, isEmpty);
    });

    test('handles completely missing fields', () {
      final event = SosEvent.fromMap('sos-bare', {});

      expect(event.sosId, 'sos-bare');
      expect(event.triggeredBy, '');
      expect(event.status, SosStatus.active);
      expect(event.responders, isEmpty);
    });
  });

  group('SosStatus enum parsing', () {
    test('parses lowercase status strings', () {
      for (final status in SosStatus.values) {
        final event = SosEvent.fromMap('sos-${status.name}', {
          'status': status.name,
        });
        expect(event.status, status);
      }
    });

    test('parses uppercase status strings', () {
      for (final status in SosStatus.values) {
        final event = SosEvent.fromMap('sos-${status.name}', {
          'status': status.name.toUpperCase(),
        });
        expect(event.status, status);
      }
    });

    test('falls back to active for unknown status', () {
      final event = SosEvent.fromMap('sos-x', {
        'status': 'UNKNOWN_VALUE',
      });
      expect(event.status, SosStatus.active);
    });
  });

  group('SosEvent.toMap roundtrip', () {
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
