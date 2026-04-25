import 'dart:async';
import 'dart:typed_data';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';

typedef OnPeerData = void Function(String deviceId, double lat, double lng);

class NearbyService {
  static final NearbyService _instance = NearbyService._internal();
  factory NearbyService() => _instance;
  NearbyService._internal();

  static const String _serviceId = 'com.crisislink.nearby';
  static const Strategy _strategy = Strategy.P2P_CLUSTER;

  bool _isRunning = false;
  bool get isRunning => _isRunning;

  final Set<String> _connectedEndpoints = {};
  OnPeerData? onPeerLocationReceived;

  /// Request all Bluetooth/WiFi P2P permissions
  Future<bool> requestPermissions() async {
    final statuses = await [
      Permission.bluetooth,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.nearbyWifiDevices,
      Permission.locationWhenInUse,
    ].request();
    return statuses.values.every((s) => s.isGranted);
  }

  /// Start advertising (being discoverable) and discovering peers
  Future<void> startNearby({required String userName}) async {
    final granted = await requestPermissions();
    if (!granted) return;

    try {
      await Nearby().startAdvertising(
        userName,
        _strategy,
        serviceId: _serviceId,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
      );

      await Nearby().startDiscovery(
        userName,
        _strategy,
        serviceId: _serviceId,
        onEndpointFound: (id, name, serviceId) {
          Nearby().requestConnection(
            userName,
            id,
            onConnectionInitiated: _onConnectionInitiated,
            onConnectionResult: _onConnectionResult,
            onDisconnected: _onDisconnected,
          );
        },
        onEndpointLost: (id) {},
      );

      _isRunning = true;
    } catch (e) {
      _isRunning = false;
    }
  }

  void _onConnectionInitiated(String id, ConnectionInfo info) {
    Nearby().acceptConnection(
      id,
      onPayLoadRecieved: (endpointId, payload) {
        if (payload.type == PayloadType.BYTES && payload.bytes != null) {
          final raw = String.fromCharCodes(payload.bytes!);
          final parts = raw.split(',');
          if (parts.length >= 2) {
            final lat = double.tryParse(parts[0]);
            final lng = double.tryParse(parts[1]);
            if (lat != null && lng != null) {
              onPeerLocationReceived?.call(endpointId, lat, lng);
            }
          }
        }
      },
      onPayloadTransferUpdate: (endpointId, update) {},
    );
  }

  void _onConnectionResult(String id, Status status) {
    if (status == Status.CONNECTED) {
      _connectedEndpoints.add(id);
    }
  }

  void _onDisconnected(String id) {
    _connectedEndpoints.remove(id);
  }

  /// Broadcast own location to all connected peers
  Future<void> broadcastLocation(double lat, double lng) async {
    if (!_isRunning || _connectedEndpoints.isEmpty) return;
    try {
      final payload = '$lat,$lng';
      for (final endpointId in _connectedEndpoints) {
        await Nearby().sendBytesPayload(
          endpointId,
          Uint8List.fromList(payload.codeUnits),
        );
      }
    } catch (_) {}
  }

  /// Broadcast to specific endpoint
  Future<void> sendLocationToEndpoint(
      String endpointId, double lat, double lng) async {
    try {
      final data = '$lat,$lng';
      await Nearby().sendBytesPayload(endpointId, Uint8List.fromList(data.codeUnits));
    } catch (_) {}
  }

  Future<void> stop() async {
    try {
      await Nearby().stopAllEndpoints();
      await Nearby().stopAdvertising();
      await Nearby().stopDiscovery();
    } catch (_) {}
    _isRunning = false;
  }
}
