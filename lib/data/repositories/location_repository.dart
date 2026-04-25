import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:sankatmitra/data/models/user_model.dart';
import 'package:sankatmitra/data/services/location_service.dart';
import 'package:sankatmitra/data/services/supabase_service.dart';
import 'package:sankatmitra/data/services/connectivity_service.dart';
import 'package:sankatmitra/data/services/sms_service.dart';
import 'package:sankatmitra/data/services/nearby_service.dart';
import 'package:sankatmitra/data/services/ai_triage_service.dart';

class LocationRepository {
  final LocationService _locationService;
  final SupabaseService _supabaseService;
  final ConnectivityService _connectivityService;
  final SmsService _smsService;
  final NearbyService _nearbyService;
  final AiTriageService _aiTriageService;

  StreamSubscription<ConnectivityLayer>? _layerSub;
  Timer? _updateTimer;

  UserModel? _currentUser;
  bool _isSOS = false;
  String _currentPriority = '';
  List<String> _emergencyContacts = [];

  final StreamController<List<UserModel>> _usersController =
  StreamController<List<UserModel>>.broadcast();

  Stream<List<UserModel>> get usersStream => _usersController.stream;

  LocationRepository({
    LocationService? locationService,
    SupabaseService? supabaseService,
    ConnectivityService? connectivityService,
    SmsService? smsService,
    NearbyService? nearbyService,
    AiTriageService? aiTriageService,
  })  : _locationService = locationService ?? LocationService(),
        _supabaseService = supabaseService ?? SupabaseService(),
        _connectivityService = connectivityService ?? ConnectivityService(),
        _smsService = smsService ?? SmsService(),
        _nearbyService = nearbyService ?? NearbyService(),
        _aiTriageService = aiTriageService ?? AiTriageService();

  Future<void> startSession({
    required UserModel user,
    List<String> emergencyContacts = const [],
  }) async {
    _currentUser = user;
    _emergencyContacts = emergencyContacts;

    await _locationService.requestPermissions();
    _locationService.startStreaming();
    _connectivityService.startMonitoring();

    _layerSub = _connectivityService.layerStream.listen(_onLayerChanged);

    _updateTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _pushLocationUpdate();
    });

    _supabaseService
        .streamSessionUsers(user.sessionId)
        .listen((users) => _usersController.add(users));

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
        _usersController
            .add([if (_currentUser != null) _currentUser!, peer]);
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
      priority: _currentPriority,
    );

    final layer = _connectivityService.currentLayer;

    switch (layer) {
      case ConnectivityLayer.cloud:
        try {
          await _supabaseService.updateUserLocation(
            sessionId: _currentUser!.sessionId,
            userId: _currentUser!.userId,
            name: _currentUser!.name,
            lat: pos.latitude,
            lng: pos.longitude,
            role: _currentUser!.role,
            isSOS: _isSOS,
            priority: _currentPriority,
          );
        } catch (_) {
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

  /// Trigger SOS with optional incident description for AI triage
  Future<void> triggerSOS({String incidentDescription = ''}) async {
    _isSOS = true;

    // Run AI triage in background — SOS broadcasts immediately, doesn't wait
    if (incidentDescription.isNotEmpty) {
      _aiTriageService.triageIncident(incidentDescription).then((priority) {
        if (priority.isNotEmpty) {
          _currentPriority = priority;
          _pushLocationUpdate(); // push again with priority
        }
      });
    }

    await _pushLocationUpdate();

    // Always try SMS fallback on SOS
    final pos = _locationService.lastPosition;
    if (pos != null && _emergencyContacts.isNotEmpty) {
      await _smsService.sendSosToAll(
        contacts: _emergencyContacts,
        lat: pos.latitude,
        lng: pos.longitude,
      );
    }
  }

  void cancelSOS() {
    _isSOS = false;
    _currentPriority = '';
    _pushLocationUpdate();
  }

  Future<void> stopSession() async {
    _updateTimer?.cancel();
    _layerSub?.cancel();
    _locationService.stopStreaming();
    await _nearbyService.stop();
    if (_currentUser != null) {
      await _supabaseService.removeUser(
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