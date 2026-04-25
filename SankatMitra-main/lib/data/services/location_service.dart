import 'dart:async';
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

  /// Request all required location permissions
  Future<bool> requestPermissions() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return false;
    }
    if (permission == LocationPermission.deniedForever) return false;
    return true;
  }

  /// Get single current position
  Future<Position?> getCurrentPosition() async {
    try {
      final granted = await requestPermissions();
      if (!granted) return null;
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      _lastPosition = pos;
      return pos;
    } catch (e) {
      return null;
    }
  }

  /// Start streaming location updates
  void startStreaming() {
    _positionStream?.cancel();
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // meters
        timeLimit: Duration(seconds: 5),
      ),
    ).listen(
      (pos) {
        _lastPosition = pos;
        _positionController.add(pos);
      },
      onError: (e) {
        // Silently continue on error
      },
    );
  }

  /// Stop location streaming
  void stopStreaming() {
    _positionStream?.cancel();
    _positionStream = null;
  }

  void dispose() {
    stopStreaming();
    _positionController.close();
  }
}
