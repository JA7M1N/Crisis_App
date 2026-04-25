import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:sankatmitra/data/models/user_model.dart';
import 'package:sankatmitra/data/services/location_service.dart';
import 'package:sankatmitra/data/services/firebase_service.dart';
import 'package:sankatmitra/data/services/connectivity_service.dart';
import 'package:sankatmitra/data/services/sms_service.dart';
import 'package:sankatmitra/data/services/nearby_service.dart';

/// Orchestrates all 3 location layers
class LocationRepository {
  final LocationService _locationService;
  final FirebaseService _firebaseService;
  final ConnectivityService _connectivityService;
  final SmsService _smsService;
  final NearbyService _nearbyService;

  StreamSubscription<Position>? _gpsSub;
  StreamSubscription<ConnectivityLayer>? _layerSub;
  Timer? _updateTimer;

  UserModel? _currentUser;
  bool _isSOS = false;
  List<String> _emergencyContacts = [];

  final StreamController<List<UserModel>> _usersController =
      StreamController<List<UserModel>>.broadcast();

  Stream<List<UserModel>> get usersStream => _usersController.stream;

  LocationRepository({
    LocationService? locationService,
    FirebaseService? firebaseService,
    ConnectivityService? connectivityService,
    SmsService? smsService,
    NearbyService? nearbyService,
  })  : _locationService = locationService ?? LocationService(),
        _firebaseService = firebaseService ?? FirebaseService(),
        _connectivityService = connectivityService ?? ConnectivityService(),
        _smsService = smsService ?? SmsService(),
        _nearbyService = nearbyService ?? NearbyService();

  /// Initialize tracking session
  Future<void> startSession({
    required UserModel user,
    List<String> emergencyContacts = const [],
  }) async {
    _currentUser = user;
    _emergencyContacts = emergencyContacts;

    // Request GPS
    await _locationService.requestPermissions();
    _locationService.startStreaming();

    // Start connectivity monitoring
    _connectivityService.startMonitoring();

    // Listen to layer changes
    _layerSub = _connectivityService.layerStream.listen(_onLayerChanged);

    // Start periodic updates every 5 seconds
    _updateTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _pushLocationUpdate();
    });

    // Also subscribe to Firebase users stream
    _firebaseService
        .streamSessionUsers(user.sessionId)
        .listen((users) => _usersController.add(users));

    // Setup auto-remove on disconnect
    _firebaseService.onDisconnectRemove(user.sessionId, user.userId);

    // Initial push
    _pushLocationUpdate();
  }

  void _onLayerChanged(ConnectivityLayer layer) {
    if (layer == ConnectivityLayer.bluetooth && !_nearbyService.isRunning) {
      _nearbyService.startNearby(userName: _currentUser?.userId ?? 'unknown');
      _nearbyService.onPeerLocationReceived = (id, lat, lng) {
        final peer = UserModel(
          userId: id,
          sessionId: _currentUser?.sessionId ?? '',
          role: UserRole.victim,
          lat: lat,
          lng: lng,
          timestamp: DateTime.now().millisecondsSinceEpoch,
        );
        _usersController.add([if (_currentUser != null) _currentUser!, peer]);
      };
    }
  }

  Future<void> _pushLocationUpdate() async {
    final pos = await _locationService.getCurrentPosition();
    if (pos == null || _currentUser == null) return;

    _currentUser = _currentUser!.copyWith(
      lat: pos.latitude,
      lng: pos.longitude,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      isSOS: _isSOS,
    );

    final layer = _connectivityService.currentLayer;

    switch (layer) {
      case ConnectivityLayer.firebase:
        try {
          await _firebaseService.updateUserLocation(
            sessionId: _currentUser!.sessionId,
            userId: _currentUser!.userId,
            lat: pos.latitude,
            lng: pos.longitude,
            role: _currentUser!.role,
            isSOS: _isSOS,
          );
        } catch (_) {
          // Fallback to SMS
          _connectivityService.switchToBluetooth();
        }
        break;

      case ConnectivityLayer.sms:
        if (_emergencyContacts.isNotEmpty) {
          await _smsService.sendSosToAll(
            contacts: _emergencyContacts,
            lat: pos.latitude,
            lng: pos.longitude,
          );
        }
        break;

      case ConnectivityLayer.bluetooth:
        await _nearbyService.broadcastLocation(pos.latitude, pos.longitude);
        break;
    }
  }

  /// Trigger SOS mode
  Future<void> triggerSOS() async {
    _isSOS = true;
    await _pushLocationUpdate();

    // Always try SMS when SOS is triggered
    final pos = _locationService.lastPosition;
    if (pos != null && _emergencyContacts.isNotEmpty) {
      await _smsService.sendSosToAll(
        contacts: _emergencyContacts,
        lat: pos.latitude,
        lng: pos.longitude,
      );
    }
  }

  /// Cancel SOS
  void cancelSOS() {
    _isSOS = false;
    _pushLocationUpdate();
  }

  Future<void> stopSession() async {
    _updateTimer?.cancel();
    _gpsSub?.cancel();
    _layerSub?.cancel();
    _locationService.stopStreaming();
    await _nearbyService.stop();
    if (_currentUser != null) {
      await _firebaseService.removeUser(
          _currentUser!.sessionId, _currentUser!.userId);
    }
  }

  ConnectivityLayer get currentLayer => _connectivityService.currentLayer;
  Stream<ConnectivityLayer> get layerStream => _connectivityService.layerStream;

  void dispose() {
    stopSession();
    _usersController.close();
    _connectivityService.dispose();
  }
}
