import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  StreamSubscription<Position>? _positionStream;
  final StreamController<Position> _positionController =
  StreamController<Position>.broadcast();

  Stream<Position> get positionStream => _positionController.stream;
  Position? _lastPosition;
  Position? get lastPosition => _lastPosition;

  Future<bool> requestPermissions() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return false;
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return false;
      }
      if (permission == LocationPermission.deniedForever) return false;
      return true;
    } catch (_) {
      // On web, permission check may throw — let getCurrentPosition handle it
      return true;
    }
  }

  Future<Position?> getCurrentPosition() async {
    try {
      await requestPermissions();

      // Web: timeLimit causes UnimplementedError on some browsers — skip it
      final settings = kIsWeb
          ? const LocationSettings(accuracy: LocationAccuracy.medium)
          : const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 10),
      );

      final pos = await Geolocator.getCurrentPosition(
          locationSettings: settings);
      _lastPosition = pos;
      return pos;
    } catch (e) {
      // Geolocation denied or unavailable — use fallback so Supabase row
      // still gets written and the user appears on the map
      debugPrint('[LocationService] Using fallback position: $e');
      final fallback = _fallbackPosition();
      _lastPosition = fallback;
      return fallback;
    }
  }

  void startStreaming() {
    _positionStream?.cancel();
    try {
      _positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          distanceFilter: 10,
        ),
      ).listen(
            (pos) {
          _lastPosition = pos;
          _positionController.add(pos);
        },
        onError: (e) {
          debugPrint('[LocationService] Stream error, using fallback: $e');
          // Push fallback so the Supabase row exists and UI stays non-empty
          final fallback = _fallbackPosition();
          _lastPosition = fallback;
          _positionController.add(fallback);
        },
      );
    } catch (e) {
      debugPrint('[LocationService] startStreaming threw: $e');
      // Push one fallback position so the session row is created
      final fallback = _fallbackPosition();
      _lastPosition = fallback;
      _positionController.add(fallback);
    }
  }

  void stopStreaming() {
    _positionStream?.cancel();
    _positionStream = null;
  }

  void dispose() {
    stopStreaming();
    _positionController.close();
  }

  /// Fallback position near Vadodara with a tiny random offset so multiple
  /// demo users don't stack on the exact same pixel.
  Position _fallbackPosition() {
    // Use microsecond as cheap random seed — different each call
    final jitter = (DateTime.now().microsecond / 1000000.0 - 0.5) * 0.04;
    return Position(
      latitude: 22.3072 + jitter,
      longitude: 73.1812 + jitter,
      timestamp: DateTime.now(),
      accuracy: 50,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
  }
}