# 🆘 SankatMitra (CrisisLink)
### Real-Time Emergency Response Network

> **Hackathon Prototype** — Built to save lives when infrastructure fails.

---

## 🔥 What's Changed in This Version

| Before | After |
|--------|-------|
| Firebase (paid, requires Google account) | **Supabase** (100% free, open source) |
| Google Maps (requires billing-enabled API key) | **OpenStreetMap via flutter_map** (completely free, no key) |
| `firebase_core`, `firebase_database` packages | `supabase_flutter`, `flutter_map`, `latlong2` |
| `google-services.json` required | **No config files needed for maps** |

---

## 🚀 Quick Setup (5 minutes)

### 1. Get a FREE Supabase Project
1. Go to [supabase.com](https://supabase.com) → **Start your project** (no credit card)
2. Create a new project (any name, any region)
3. Copy your **Project URL** and **anon key** from: `Settings → API`

### 2. Create the Database Table
Go to `Supabase Dashboard → SQL Editor` and run:

```sql
create table if not exists session_users (
  user_id     text not null,
  session_id  text not null,
  role        text not null default 'victim',
  lat         double precision not null default 0,
  lng         double precision not null default 0,
  timestamp   bigint not null,
  is_sos      boolean not null default false,
  updated_at  timestamptz not null default now(),
  primary key (session_id, user_id)
);

-- Enable Row Level Security (open policy for hackathon)
alter table session_users enable row level security;
create policy "allow all" on session_users
  for all using (true) with check (true);

-- Enable Realtime for live location updates
alter publication supabase_realtime add table session_users;
```

### 3. Configure the App
Open `lib/main.dart` and replace the placeholders:

```dart
const String supabaseUrl = 'https://YOUR_PROJECT.supabase.co';
const String supabaseAnonKey = 'YOUR_ANON_KEY_HERE';
```

### 4. Run the App
```bash
flutter pub get
flutter run
```

**That's it. No Google billing account. No API keys for maps.**

---

## 🗺️ Maps: OpenStreetMap (Zero Cost)

`flutter_map` renders OpenStreetMap tiles — a fully open, free map service used by Wikipedia, humanitarian orgs, and 95% of apps that don't want Google's billing model.

- ✅ No API key required
- ✅ No billing account
- ✅ Works offline with cached tiles (advanced: add `flutter_map_tile_caching`)
- ✅ Attributing `© OpenStreetMap` in the UI (required by OSM license — already done)

---

## 🏗️ Architecture

```
Multi-Layer Connectivity (auto-failover):

┌─────────────────────────────────────────────────────────┐
│  Layer 1: CLOUD  →  Supabase Realtime (WebSocket)       │
│           Full internet available — live sync globally   │
├─────────────────────────────────────────────────────────┤
│  Layer 2: MESH P2P  →  Google Nearby Connections        │
│           No internet — direct device-to-device via BT   │
├─────────────────────────────────────────────────────────┤
│  Layer 3: SMS FALLBACK  →  Background SMS broadcast     │
│           Cellular only — coordinates via text message   │
└─────────────────────────────────────────────────────────┘
```

### Directory Structure
```
lib/
├── core/
│   ├── routes/app_router.dart          # Navigation
│   └── theme/app_theme.dart           # Dark hackathon theme
├── data/
│   ├── models/user_model.dart          # UserModel (with Supabase factory)
│   ├── repositories/location_repository.dart  # 3-layer orchestrator
│   └── services/
│       ├── supabase_service.dart       # ← NEW: Replaces firebase_service
│       ├── connectivity_service.dart   # Layer detection & switching
│       ├── location_service.dart       # GPS / geolocator
│       ├── nearby_service.dart         # P2P mesh (Nearby Connections)
│       └── sms_service.dart            # SMS fallback
└── features/
    ├── splash/                         # Animated boot screen
    ├── role_selection/                 # Victim / Responder / Coordinator
    ├── home/home_screen.dart           # ← Map + SOS (now OpenStreetMap)
    ├── dashboard/coordinator_dashboard.dart  # ← Command center (OpenStreetMap)
    └── shared/widgets/layer_status_bar.dart  # Connectivity indicator
```

---

## 👥 Roles

| Role | Description |
|------|-------------|
| 🔴 **Victim** | Share real-time location. One-tap SOS triggers multi-channel broadcast |
| 🟢 **Responder** | See all victims on live map. Navigate to SOS alerts |
| 🔵 **Coordinator** | Dashboard view of ALL sessions — situation report with live stats |

---

## 🛣️ Roadmap (Hackathon Extensions)

- [ ] **AI Triage** — Gemini API to score incident severity (P0–P3)
- [ ] **Offline Routing** — Bearing-based navigation when internet is down
- [ ] **FCM Critical Alerts** — Bypass Silent/DND for incoming SOS
- [ ] **E2E Encryption** — Encrypt P2P and SMS payloads
- [ ] **Battery Adaptive Polling** — Reduce GPS frequency when stationary

---

## 📦 Dependencies

```yaml
flutter_map: ^7.0.2        # OpenStreetMap rendering (FREE)
latlong2: ^0.9.1           # Coordinate types for flutter_map
supabase_flutter: ^2.5.6   # Realtime backend (FREE tier: 500MB DB, 2GB bandwidth)
geolocator: ^13.0.2        # GPS location
nearby_connections: ^4.1.0 # P2P mesh networking
telephony: ^0.2.0          # SMS fallback
```

---

## 🏆 Hackathon Demo Script

1. **Device A** → Select "Victim" → Join session `DEMO01`
2. **Device B** → Select "Responder" → Join session `DEMO01`
3. **Device C** → Select "Coordinator" → View Command Center
4. On Device A → Tap the **SOS button** → Watch it propagate to B and C in real-time
5. Kill WiFi on Device A → Watch layer switch to **MESH P2P** automatically
6. Kill Bluetooth → Watch layer switch to **SMS FALLBACK**

---

*Built with Flutter • Supabase • OpenStreetMap • Google Nearby Connections*
