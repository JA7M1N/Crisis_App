import 'dart:async';
import 'package:internet_connection_checker/internet_connection_checker.dart';

// Renamed 'firebase' → 'cloud' to be backend-agnostic
enum ConnectivityLayer { cloud, sms, bluetooth }

class ConnectivityService {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  final InternetConnectionChecker _checker = InternetConnectionChecker.instance;

  final StreamController<ConnectivityLayer> _layerController =
      StreamController<ConnectivityLayer>.broadcast();

  Stream<ConnectivityLayer> get layerStream => _layerController.stream;

  ConnectivityLayer _currentLayer = ConnectivityLayer.cloud;
  ConnectivityLayer get currentLayer => _currentLayer;

  StreamSubscription? _checkerSub;

  void startMonitoring() {
    _checkerSub?.cancel();
    _checkerSub = _checker.onStatusChange.listen((status) {
      if (status == InternetConnectionStatus.connected) {
        _setLayer(ConnectivityLayer.cloud);
      } else {
        _setLayer(ConnectivityLayer.sms);
      }
    });

    _checker.hasConnection.then((has) {
      _setLayer(has ? ConnectivityLayer.cloud : ConnectivityLayer.sms);
    });
  }

  void switchToBluetooth() => _setLayer(ConnectivityLayer.bluetooth);
  void resumeAutoDetection() => startMonitoring();

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
