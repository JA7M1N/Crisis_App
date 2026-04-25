import 'dart:async';
import 'package:sankatmitra/data/models/user_model.dart';

/// Provides fake demo users that make the map look live during presentations.
/// No network calls — purely in-memory. Call [startDemo] then listen to [stream].
class DemoSeedService {
  static final DemoSeedService _instance = DemoSeedService._internal();
  factory DemoSeedService() => _instance;
  DemoSeedService._internal();

  final StreamController<List<UserModel>> _controller =
  StreamController<List<UserModel>>.broadcast();

  Stream<List<UserModel>> get stream => _controller.stream;

  Timer? _driftTimer;
  bool _active = false;

  /// Base coords — we'll scatter demo users ±0.002° around this point.
  /// Pass the device's real location so they appear nearby on the map.
  void startDemo({double baseLat = 22.3072, double baseLng = 73.1812}) {
    if (_active) return;
    _active = true;

    // Initial snapshot — 3 victims + 2 responders with different priorities
    final List<_DemoUser> seeds = [
      _DemoUser(
        userId: 'demo-v1',
        name: 'Rahul S.',
        role: UserRole.victim,
        lat: baseLat + 0.0012,
        lng: baseLng - 0.0018,
        isSOS: true,
        priority: 'P0',
      ),
      _DemoUser(
        userId: 'demo-v2',
        name: 'Priya K.',
        role: UserRole.victim,
        lat: baseLat - 0.0008,
        lng: baseLng + 0.0022,
        isSOS: true,
        priority: 'P1',
      ),
      _DemoUser(
        userId: 'demo-v3',
        name: 'Amit D.',
        role: UserRole.victim,
        lat: baseLat + 0.0025,
        lng: baseLng + 0.0010,
        isSOS: false,
        priority: 'P2',
      ),
      _DemoUser(
        userId: 'demo-r1',
        name: 'NDRF Alpha',
        role: UserRole.responder,
        lat: baseLat - 0.0015,
        lng: baseLng - 0.0005,
        isSOS: false,
        priority: '',
      ),
      _DemoUser(
        userId: 'demo-r2',
        name: 'NDRF Bravo',
        role: UserRole.responder,
        lat: baseLat + 0.0005,
        lng: baseLng - 0.0030,
        isSOS: false,
        priority: '',
      ),
    ];

    _emit(seeds);

    // Drift positions slightly every 4 seconds to simulate live movement
    _driftTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      for (final s in seeds) {
        s.drift();
      }
      _emit(seeds);
    });
  }

  void stopDemo() {
    _driftTimer?.cancel();
    _active = false;
    _controller.add([]);
  }

  bool get isActive => _active;

  void dispose() {
    _driftTimer?.cancel();
    _controller.close();
  }

  void _emit(List<_DemoUser> seeds) {
    final now = DateTime.now().millisecondsSinceEpoch;
    _controller.add(seeds.map((s) => UserModel(
      userId: s.userId,
      sessionId: 'DEMO-2025',
      name: s.name,
      role: s.role,
      lat: s.lat,
      lng: s.lng,
      timestamp: now,
      isSOS: s.isSOS,
      priority: s.priority,
    )).toList());
  }
}

class _DemoUser {
  final String userId;
  final String name;
  final UserRole role;
  double lat;
  double lng;
  final bool isSOS;
  final String priority;

  _DemoUser({
    required this.userId,
    required this.name,
    required this.role,
    required this.lat,
    required this.lng,
    required this.isSOS,
    required this.priority,
  });

  /// Tiny random walk to simulate live GPS updates
  void drift() {
    // ±0.00005 ≈ ±5 metres
    lat += (DateTime.now().microsecond % 10 - 5) * 0.00001;
    lng += (DateTime.now().microsecond % 10 - 5) * 0.00001;
  }
}