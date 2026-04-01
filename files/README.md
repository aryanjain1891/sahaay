# Sahaay — Hyperlocal Emergency Response Network

MVP scaffold. Two sides: Flutter client + Firebase backend.

## Project structure

```
sahaay/
├── flutter/                      # Flutter app
│   ├── pubspec.yaml
│   └── lib/
│       ├── main.dart             # Entry point, Firebase init, FCM setup
│       ├── models/models.dart    # SahaayUser, SosEvent, SosResponse
│       ├── sos_service.dart      # SOS trigger, cancel, accept, navigate
│       ├── services/
│       │   └── location_service.dart  # GPS, geohash, periodic updates
│       └── screens/
│           ├── auth_screen.dart       # Phone OTP login
│           ├── home_screen.dart       # SOS button + availability toggle
│           └── sos_detail_screen.dart # Responder accept screen
│
├── functions/                    # Firebase Cloud Functions (TypeScript)
│   ├── package.json
│   └── src/index.ts
│       ├── triggerSos            # HTTPS callable: create event + geo-query + FCM
│       ├── autoExpireSos         # Pub/Sub: expire stale events every 5 min
│       └── onSosAccepted         # Firestore trigger: notify victim on accept
│
└── firestore.rules               # Security rules
```

## Setup

### 1. Firebase project
```bash
firebase login
firebase projects:create sahaay-mvp
firebase use sahaay-mvp
```

### 2. Enable services in Firebase console
- Authentication → Phone
- Firestore Database → production mode
- Cloud Functions
- Cloud Messaging

### 3. Flutter setup
```bash
cd flutter
flutterfire configure   # links your Firebase project
flutter pub get
```

Add to AndroidManifest.xml:
```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
<uses-permission android:name="android.permission.CALL_PHONE"/>
<uses-permission android:name="android.permission.SEND_SMS"/>
<!-- Google Maps -->
<meta-data android:name="com.google.android.geo.API_KEY" android:value="YOUR_MAPS_KEY"/>
```

Add to Info.plist (iOS):
```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>Sahaay needs your location to find nearby helpers.</string>
<key>NSLocationAlwaysUsageDescription</key>
<string>Sahaay needs background location for SOS alerts.</string>
```

### 4. Functions setup
```bash
cd functions
npm install
npm run build
firebase deploy --only functions
```

### 5. Firestore indexes needed
Create in Firebase console (or firestore.indexes.json):
- Collection: `sos_events`, fields: `status ASC, timestamp DESC`
- Collection: `users`, fields: `geohash ASC, is_available_for_help ASC, last_active ASC`

## Key design decisions

| Decision | Rationale |
|---|---|
| Cloud Function for SOS trigger | Geo-query + FCM fan-out should not run on device |
| Geohash + Haversine second pass | Geohash cells aren't perfect circles — strictMode filter needed |
| 45s location update interval | Battery vs freshness tradeoff — tunable |
| Debounce 30s client-side | Prevents accidental re-triggers; checked server-side too |
| asia-south1 region | Lowest latency for India |

## What's NOT built yet (Phase 2)
- Profile creation screen (name, photo upload)
- Emergency contacts management
- Trust / reputation system
- SMS fallback (use `url_launcher` SMS intent client-side for now)
- Offline queue for pending SOS alerts
