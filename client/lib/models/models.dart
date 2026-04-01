import 'package:cloud_firestore/cloud_firestore.dart';

// ─── User Model ───────────────────────────────────────────────────────────────

class SahaayUser {
  final String userId;
  final String name;
  final String phoneNumber;
  final String? profilePhotoUrl;
  final GeoPoint location;
  final String geohash;
  final bool isAvailableForHelp;
  final DateTime lastActive;

  SahaayUser({
    required this.userId,
    required this.name,
    required this.phoneNumber,
    this.profilePhotoUrl,
    required this.location,
    required this.geohash,
    required this.isAvailableForHelp,
    required this.lastActive,
  });

  factory SahaayUser.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return SahaayUser.fromMap(doc.id, d);
  }

  factory SahaayUser.fromMap(String id, Map<String, dynamic> d) {
    return SahaayUser(
      userId: id,
      name: d['name'] ?? '',
      phoneNumber: d['phone_number'] ?? '',
      profilePhotoUrl: d['profile_photo_url'],
      location: d['location'] as GeoPoint? ?? const GeoPoint(0, 0),
      geohash: d['geohash'] ?? '',
      isAvailableForHelp: d['is_available_for_help'] ?? false,
      lastActive: (d['last_active'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'phone_number': phoneNumber,
    'profile_photo_url': profilePhotoUrl,
    'location': location,
    'geohash': geohash,
    'is_available_for_help': isAvailableForHelp,
    'last_active': Timestamp.fromDate(lastActive),
  };

  SahaayUser copyWith({bool? isAvailableForHelp, GeoPoint? location, String? geohash}) {
    return SahaayUser(
      userId: userId,
      name: name,
      phoneNumber: phoneNumber,
      profilePhotoUrl: profilePhotoUrl,
      location: location ?? this.location,
      geohash: geohash ?? this.geohash,
      isAvailableForHelp: isAvailableForHelp ?? this.isAvailableForHelp,
      lastActive: DateTime.now(),
    );
  }
}

// ─── SOS Event Model ─────────────────────────────────────────────────────────

enum SosStatus { active, resolved, expired }

class SosEvent {
  final String sosId;
  final String triggeredBy;
  final GeoPoint location;
  final DateTime timestamp;
  final SosStatus status;
  final List<String> responders;

  SosEvent({
    required this.sosId,
    required this.triggeredBy,
    required this.location,
    required this.timestamp,
    required this.status,
    required this.responders,
  });

  factory SosEvent.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return SosEvent(
      sosId: doc.id,
      triggeredBy: d['triggered_by'] ?? '',
      location: d['location'] as GeoPoint? ?? const GeoPoint(0, 0),
      timestamp: (d['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      status: SosStatus.values.firstWhere(
        (s) => s.name == (d['status'] as String?)?.toLowerCase(),
        orElse: () => SosStatus.active,
      ),
      responders: List<String>.from(d['responders'] ?? []),
    );
  }

  /// Create from a plain map (e.g. from Cloud Function response)
  factory SosEvent.fromMap(String id, Map<String, dynamic> d) {
    return SosEvent(
      sosId: id,
      triggeredBy: d['triggered_by'] ?? '',
      location: d['location'] is GeoPoint
          ? d['location'] as GeoPoint
          : GeoPoint(
              (d['location']?['lat'] as num?)?.toDouble() ?? 0,
              (d['location']?['lng'] as num?)?.toDouble() ?? 0,
            ),
      timestamp: d['timestamp'] is Timestamp
          ? (d['timestamp'] as Timestamp).toDate()
          : DateTime.tryParse(d['timestamp'] ?? '') ?? DateTime.now(),
      status: SosStatus.values.firstWhere(
        (s) => s.name == (d['status'] as String?)?.toLowerCase(),
        orElse: () => SosStatus.active,
      ),
      responders: List<String>.from(d['responders'] ?? []),
    );
  }

  Map<String, dynamic> toMap() => {
    'triggered_by': triggeredBy,
    'location': location,
    'timestamp': Timestamp.fromDate(timestamp),
    'status': status.name.toUpperCase(),
    'responders': responders,
  };
}

// ─── Response Log Model ───────────────────────────────────────────────────────

class SosResponse {
  final String responseId;
  final String sosId;
  final String responderId;
  final DateTime acceptedAt;

  SosResponse({
    required this.responseId,
    required this.sosId,
    required this.responderId,
    required this.acceptedAt,
  });

  Map<String, dynamic> toMap() => {
    'sos_id': sosId,
    'responder_id': responderId,
    'accepted_at': Timestamp.fromDate(acceptedAt),
  };
}