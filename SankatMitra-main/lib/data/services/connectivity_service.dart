import 'dart:async';
import 'package:internet_connection_checker/internet_connection_checker.dart';

enum ConnectivityLayer { firebase, sms, bluetooth }

class ConnectivityService {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  // Using the singleton instance
  final InternetConnectionChecker _checker = InternetConnectionChecker.instance;

  final StreamController<ConnectivityLayer> _layerController =
      StreamController<ConnectivityLayer>.broadcast();

  Stream<ConnectivityLayer> get layerStream => _layerController.stream;

  ConnectivityLayer _currentLayer = ConnectivityLayer.firebase;
  ConnectivityLayer get currentLayer => _currentLayer;

  StreamSubscription? _checkerSub;

  /// Starts monitoring connectivity and auto-switches layers
  void startMonitoring() {
    _checkerSub?.cancel();
    _checkerSub = _checker.onStatusChange.listen((status) {
      if (status == InternetConnectionStatus.connected) {
        _setLayer(ConnectivityLayer.firebase);
      } else {
        _setLayer(ConnectivityLayer.sms);
      }
    });

    // Initial check
    _checker.hasConnection.then((has) {
      _setLayer(has ? ConnectivityLayer.firebase : ConnectivityLayer.sms);
    });
  }

  /// Force switch to Bluetooth (offline P2P)
  void switchToBluetooth() {
    _setLayer(ConnectivityLayer.bluetooth);
  }

  /// Force switch back to auto detection
  void resumeAutoDetection() {
    startMonitoring();
  }

  void _setLayer(ConnectivityLayer layer) {
    if (_currentLayer != layer) {
      _currentLayer = layer;
      _layerController.add(layer);
    }
  }

  Future<bool> hasConnection() => _checker.hasConnection;

  void dispose() {
    _checkerSub?.cancel();
    _layerController.close();
  }
}
