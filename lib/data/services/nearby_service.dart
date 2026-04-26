import 'package:flutter/foundation.dart';

/// NearbyService — stubbed for Flutter 3.41 compatibility.
/// nearby_connections 4.x uses Android v1 embedding.
/// Bluetooth P2P layer is simulated — location updates are
/// logged instead of broadcast over BLE/WiFi Direct.

class NearbyService {
  static final NearbyService _instance = NearbyService._internal();
  factory NearbyService() => _instance;
  NearbyService._internal();

  bool get isRunning => _running;
  bool _running = false;

  void Function(String userId, double lat, double lng)? onPeerLocationReceived;

  Future<void> startNearby({required String userName}) async {
    _running = true;
    debugPrint('[Nearby] P2P layer started for $userName (stubbed)');
  }

  Future<void> broadcastLocation(double lat, double lng) async {
    if (!_running) return;
    debugPrint('[Nearby] Broadcasting location $lat,$lng to peers (stubbed)');
  }

  Future<void> stop() async {
    _running = false;
    debugPrint('[Nearby] P2P layer stopped');
  }
}
