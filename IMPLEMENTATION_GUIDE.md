# SankatMitra — Feature Implementation Guide

## What's in this patch

| Feature | New Files | Modified Files |
|---|---|---|
| Offline Map Tiles | `tile_cache_service.dart` | `home_screen.dart`, `pubspec.yaml` |
| Broadcast Messages | `broadcast_service.dart`, `broadcast_banner.dart` | `home_screen.dart`, `coordinator_dashboard.dart` |
| Incident Timeline | `incident_timeline_service.dart`, `incident_timeline_panel.dart` | `location_repository.dart`, `coordinator_dashboard.dart` |
| "I'm on my way" Status | — | `user_model.dart`, `supabase_service.dart`, `location_repository.dart`, `home_screen.dart`, `coordinator_dashboard.dart` |
| Silent Panic Mode | `silent_panic_service.dart`, `MainActivity.kt` | `home_screen.dart` |

---

## STEP 1 — Run the new Supabase SQL

Open your Supabase project → SQL Editor → run this **once**:

```sql
-- Add new columns to existing session_users table
ALTER TABLE session_users
  ADD COLUMN IF NOT EXISTS on_my_way    boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS on_my_way_to text    NOT NULL DEFAULT '';

-- New table: broadcast_messages
CREATE TABLE IF NOT EXISTS broadcast_messages (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id  text NOT NULL,
  sender_name text NOT NULL DEFAULT 'Coordinator',
  text        text NOT NULL,
  type        text NOT NULL DEFAULT 'info',  -- 'info' | 'warning' | 'critical'
  sent_at     timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE broadcast_messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY "allow all" ON broadcast_messages FOR ALL USING (true) WITH CHECK (true);
ALTER PUBLICATION supabase_realtime ADD TABLE broadcast_messages;

-- New table: incident_timeline
CREATE TABLE IF NOT EXISTS incident_timeline (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id  text NOT NULL,
  type        text NOT NULL,
  actor_name  text NOT NULL DEFAULT '',
  detail      text NOT NULL DEFAULT '',
  timestamp   timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE incident_timeline ENABLE ROW LEVEL SECURITY;
CREATE POLICY "allow all" ON incident_timeline FOR ALL USING (true) WITH CHECK (true);
ALTER PUBLICATION supabase_realtime ADD TABLE incident_timeline;
```

---

## STEP 2 — Copy new files into your project

### New files to CREATE (copy from output/ folder):

```
lib/data/services/tile_cache_service.dart
lib/data/services/broadcast_service.dart
lib/data/services/incident_timeline_service.dart
lib/data/services/silent_panic_service.dart
lib/features/shared/widgets/broadcast_banner.dart
lib/features/shared/widgets/incident_timeline_panel.dart
```

### Files to REPLACE (overwrite existing with output/ versions):

```
pubspec.yaml
lib/data/models/user_model.dart
lib/data/services/supabase_service.dart
lib/data/repositories/location_repository.dart
lib/features/home/home_screen.dart
lib/features/dashboard/coordinator_dashboard.dart
android/app/src/main/kotlin/com/example/sankatmitra/MainActivity.kt
```

---

## STEP 3 — Install new pub packages

```bash
flutter pub get
```

The two new dependencies added to pubspec.yaml are:
- `path_provider: ^2.1.4` — for the tile cache directory on device
- `http: ^1.2.2` — for fetching and caching tile images

---

## STEP 4 — Enable offline tile caching (one line change)

In `lib/features/home/home_screen.dart`, find the TileLayer inside FlutterMap (~line 290) and uncomment the tileProvider line:

```dart
TileLayer(
  urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
  subdomains: const ['a', 'b', 'c', 'd'],
  userAgentPackageName: 'com.example.sankatmitra',
  tileProvider: CachedTileProvider(),   // <-- UNCOMMENT THIS LINE
),
```

**Note:** CachedTileProvider is defined inside tile_cache_service.dart. It auto-caches every tile the user views while online. When offline, it serves tiles from disk transparently.

**Optional — pre-warm tiles for a known disaster zone:**
```dart
// Call this anywhere you have connectivity (e.g. after startSession)
await TileCacheService().prewarmArea(
  minLat: 22.2, maxLat: 22.4,
  minLng: 73.1, maxLng: 73.3,
  minZoom: 12, maxZoom: 16,
  onProgress: (done, total) => print('$done/$total tiles cached'),
);
```

---

## STEP 5 — How Broadcast Messages work

### Coordinator sends a broadcast:
- Tap the **📣 BROADCAST** button in the coordinator dashboard action bar or bottom panel
- Choose type: INFO / WARNING / CRITICAL
- Type message → tap SEND
- All users in the session see a slide-down banner with haptic feedback

### Victim/Responder receives it:
- `BroadcastBanner` widget is already added to `HomeScreen`'s Stack
- It listens to Supabase Realtime inserts on `broadcast_messages`
- Auto-dismisses after 6 seconds, or tap to dismiss

### Test it:
1. Open coordinator dashboard on one device/emulator
2. Tap BROADCAST → type "Evacuate zone B" → CRITICAL → SEND
3. On the victim device, a red banner slides down instantly

---

## STEP 6 — How Incident Timeline works

### Events auto-logged (no action needed):
| Event | Trigger |
|---|---|
| `user_joined` | Any user calls `startSession()` |
| `sos_triggered` | Any victim taps SOS |
| `sos_cancelled` | Victim taps Cancel |
| `layer_switch` | Network drops (cloud → BT → SMS) |
| `responder_arrived` | Responder taps "I'm on my way" |

### Viewing the timeline:
- Coordinator: tap **📈 TIMELINE** in the dashboard (app bar or bottom panel)
- A bottom sheet slides up showing all events newest-first with colored icons

---

## STEP 7 — How "I'm on my way" works

### Responder flow:
1. When there are active SOS victims, a green **"I'M ON MY WAY"** button appears in the responder's bottom panel
2. Tap it → pick the victim from the list
3. The responder's marker on the map changes to a running figure with "EN ROUTE" badge
4. A dotted green line draws from responder to victim on both devices
5. Victim sees a green banner: "Ravi is on the way — Help coming!"
6. Timeline logs the event automatically
7. Tap the active status card to clear it when arrived

### What gets stored:
- `on_my_way: true` in session_users for the responder
- `on_my_way_to: <victim_userId>` for the route line

---

## STEP 8 — Silent Panic Mode (vol-down × 3)

### Android setup (already done in the output MainActivity.kt):
The `MainActivity.kt` replacement intercepts `KEYCODE_VOLUME_DOWN` and sends it to Flutter via MethodChannel `sankatmitra/volume_buttons`.

### Flutter side (already wired in home_screen.dart):
`SilentPanicService().init(onSilentSOS: _handleSilentSOS)` in `initState()`

### How it activates:
- Press volume-down **3 times within 2 seconds**
- Phone gives 3 short vibrations (imperceptible to bystanders, no sound)
- SOS triggers silently — same as pressing the SOS button, but no UI needed
- Incident description is set to `"Silent panic — vol-down ×3"` for the timeline

### Adjusting sensitivity:
In `silent_panic_service.dart`:
```dart
static const int _requiredPresses = 3;  // number of presses
static const int _windowMs = 2000;       // milliseconds window
```

---

## STEP 9 — Build and test

```bash
# Clean build recommended after pubspec changes
flutter clean
flutter pub get
flutter run
```

### Quick smoke test checklist:
- [ ] Map tiles appear and are cached after first view (check device storage)
- [ ] Go offline (airplane mode) → tiles still show for viewed areas
- [ ] Coordinator dashboard shows BROADCAST and TIMELINE buttons
- [ ] Send a broadcast → appears on victim device within 1-2 seconds
- [ ] Trigger SOS → appears in Timeline with correct timestamp
- [ ] Responder taps "I'm on my way" → green line appears on map
- [ ] Victim sees "Help coming" banner
- [ ] Vol-down × 3 triggers SOS silently (Android physical device only)

---

## Troubleshooting

**Tiles not caching offline:**
- Make sure `CachedTileProvider()` is uncommented in home_screen.dart
- Check `path_provider` is in pubspec.yaml and `flutter pub get` ran

**Broadcast not appearing:**
- Confirm `broadcast_messages` table exists in Supabase with realtime enabled
- Check that `BroadcastBanner` is in the HomeScreen Stack (already done)
- Make sure sessionId matches between sender (coordinator) and receivers

**Timeline empty:**
- Confirm `incident_timeline` table exists with realtime enabled
- The `IncidentTimelineService` logs on: SOS trigger, cancel, layer switch, user join, responder arrival

**Silent panic not working:**
- Must be a physical Android device (emulators don't send volume hardware events)
- Confirm `MainActivity.kt` is replaced with the new version
- Hot restart after changing MainActivity (requires `flutter run` not just hot reload)

**"on_my_way" column missing error:**
- Run the ALTER TABLE SQL from Step 1 in Supabase SQL Editor
