import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:sankatmitra/core/theme/app_theme.dart';
import 'package:sankatmitra/core/routes/app_router.dart';
import 'package:sankatmitra/data/models/user_model.dart';
import 'package:sankatmitra/data/repositories/location_repository.dart';
import 'package:sankatmitra/data/services/connectivity_service.dart';
import 'package:sankatmitra/features/shared/widgets/layer_status_bar.dart';

class HomeScreen extends StatefulWidget {
  final UserModel? user;
  const HomeScreen({super.key, this.user});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin {
  final LocationRepository _repo = LocationRepository();
  GoogleMapController? _mapController;

  Set<Marker> _markers = {};
  List<UserModel> _users = [];
  ConnectivityLayer _currentLayer = ConnectivityLayer.firebase;
  bool _isSOS = false;
  bool _isInitialized = false;

  late AnimationController _sosController;
  late AnimationController _pulseController;
  late Animation<double> _sosFade;
  late Animation<double> _pulseScale;

  StreamSubscription? _usersSub;
  StreamSubscription? _layerSub;

  @override
  void initState() {
    super.initState();

    _sosController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _sosFade = Tween<double>(begin: 1, end: 0).animate(_sosController);
    _pulseScale = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _startSession();
  }

  Future<void> _startSession() async {
    if (widget.user == null) return;

    await _repo.startSession(user: widget.user!);

    _layerSub = _repo.layerStream.listen((layer) {
      if (mounted) setState(() => _currentLayer = layer);
    });

    _usersSub = _repo.usersStream.listen((users) {
      if (mounted) {
        setState(() => _users = users);
        _updateMarkers(users);
        _fitMarkers(users);
      }
    });

    setState(() => _isInitialized = true);
  }

  void _updateMarkers(List<UserModel> users) async {
    final newMarkers = <Marker>{};

    for (final user in users) {
      final isMe = user.userId == widget.user?.userId;
      final color = isMe
          ? BitmapDescriptor.hueBlue
          : user.role == UserRole.responder
              ? BitmapDescriptor.hueGreen
              : BitmapDescriptor.hueRed;

      newMarkers.add(
        Marker(
          markerId: MarkerId(user.userId),
          position: LatLng(user.lat, user.lng),
          icon: await BitmapDescriptor.defaultMarkerWithHue(color),
          infoWindow: InfoWindow(
            title: isMe
                ? '📍 You (${user.role.name})'
                : '${user.role == UserRole.responder ? '🟢' : '🔴'} ${user.role.name}',
            snippet: user.isSOS ? '🆘 SOS ACTIVE' : 'Active',
          ),
        ),
      );
    }

    if (mounted) setState(() => _markers = newMarkers);
  }

  void _fitMarkers(List<UserModel> users) {
    if (_mapController == null || users.isEmpty) return;
    if (users.length == 1) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(users.first.lat, users.first.lng),
          16,
        ),
      );
      return;
    }

    double minLat = users.first.lat, maxLat = users.first.lat;
    double minLng = users.first.lng, maxLng = users.first.lng;

    for (final u in users) {
      if (u.lat < minLat) minLat = u.lat;
      if (u.lat > maxLat) maxLat = u.lat;
      if (u.lng < minLng) minLng = u.lng;
      if (u.lng > maxLng) maxLng = u.lng;
    }

    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat - 0.005, minLng - 0.005),
          northeast: LatLng(maxLat + 0.005, maxLng + 0.005),
        ),
        80,
      ),
    );
  }

  Future<void> _triggerSOS() async {
    setState(() => _isSOS = true);
    _sosController.forward();
    await _repo.triggerSOS();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.primaryRed,
          content: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.white),
              SizedBox(width: 8),
              Text('🆘 SOS SENT — Location shared across all layers!',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  void _cancelSOS() {
    setState(() => _isSOS = false);
    _sosController.reverse();
    _repo.cancelSOS();
  }

  @override
  void dispose() {
    _usersSub?.cancel();
    _layerSub?.cancel();
    _sosController.dispose();
    _pulseController.dispose();
    _repo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final role = widget.user?.role ?? UserRole.victim;

    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.crisis_alert_rounded,
                color: AppTheme.primaryRed, size: 20),
            const SizedBox(width: 8),
            const Text('CrisisLink'),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: role == UserRole.responder
                    ? AppTheme.safeGreen.withOpacity(0.2)
                    : AppTheme.primaryRed.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: role == UserRole.responder
                      ? AppTheme.safeGreen
                      : AppTheme.primaryRed,
                  width: 1,
                ),
              ),
              child: Text(
                role.name.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: role == UserRole.responder
                      ? AppTheme.safeGreen
                      : AppTheme.primaryRed,
                  letterSpacing: 1,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.dashboard_rounded),
            color: AppTheme.alertBlue,
            onPressed: () =>
                Navigator.pushNamed(context, AppRouter.dashboard),
            tooltip: 'Coordinator View',
          ),
        ],
      ),
      body: Stack(
        children: [
          // Google Map
          if (_isInitialized)
            GoogleMap(
              initialCameraPosition: const CameraPosition(
                target: LatLng(20.5937, 78.9629), // India center
                zoom: 5,
              ),
              markers: _markers,
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              mapType: MapType.normal,
              onMapCreated: (ctrl) {
                _mapController = ctrl;
                ctrl.setMapStyle(_mapStyle);
              },
            )
          else
            Container(
              color: AppTheme.bgDark,
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: AppTheme.primaryRed),
                    SizedBox(height: 16),
                    Text(
                      'Acquiring location...',
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
            ),

          // Top gradient overlay
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 120,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xCC0D0D0D), Colors.transparent],
                ),
              ),
            ),
          ),

          // Layer status bar
          Positioned(
            top: 95,
            left: 0,
            right: 0,
            child: Center(
              child: LayerStatusBar(layer: _currentLayer),
            ),
          ),

          // User count chip
          Positioned(
            top: 145,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.bgCard,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0x33FFFFFF)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.people_rounded,
                      color: AppTheme.textSecondary, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    '${_users.length} active',
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Bottom panel
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Color(0xFF0D0D0D), Colors.transparent],
                  stops: [0.7, 1.0],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // SOS Button
                  if (role == UserRole.victim) ...[
                    AnimatedBuilder(
                      animation: _pulseScale,
                      builder: (_, child) => Transform.scale(
                        scale: _isSOS ? _pulseScale.value : 1.0,
                        child: child,
                      ),
                      child: GestureDetector(
                        onTap: _isSOS ? _cancelSOS : _triggerSOS,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 400),
                          width: 140,
                          height: 140,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color:
                                _isSOS ? AppTheme.deepRed : AppTheme.primaryRed,
                            border: Border.all(
                              color: _isSOS
                                  ? Colors.white30
                                  : AppTheme.primaryRed.withOpacity(0.3),
                              width: 4,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: (_isSOS
                                        ? AppTheme.deepRed
                                        : AppTheme.primaryRed)
                                    .withOpacity(0.5),
                                blurRadius: _isSOS ? 50 : 30,
                                spreadRadius: _isSOS ? 15 : 5,
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _isSOS
                                    ? Icons.cancel_rounded
                                    : Icons.sos_rounded,
                                color: Colors.white,
                                size: 48,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _isSOS ? 'CANCEL' : 'SOS',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _isSOS
                          ? '🆘 SOS ACTIVE — Broadcasting location'
                          : 'Tap to trigger SOS and share your location',
                      style: TextStyle(
                        color: _isSOS
                            ? AppTheme.primaryRed
                            : AppTheme.textSecondary,
                        fontSize: 13,
                        fontWeight:
                            _isSOS ? FontWeight.w700 : FontWeight.normal,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],

                  if (role == UserRole.responder) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.bgCard,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.safeGreen, width: 1),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.emergency_rounded,
                              color: AppTheme.safeGreen),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'RESPONDER MODE ACTIVE',
                                  style: TextStyle(
                                    color: AppTheme.safeGreen,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                    letterSpacing: 1,
                                  ),
                                ),
                                Text(
                                  'You are visible to ${_users.where((u) => u.role == UserRole.victim).length} victims',
                                  style: const TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppTheme.safeGreen,
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.safeGreen,
                                  blurRadius: 8,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // SOS flash overlay when active
          if (_isSOS)
            IgnorePointer(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 500),
                opacity: 0.08,
                child: Container(color: AppTheme.primaryRed),
              ),
            ),
        ],
      ),
    );
  }
}

const String _mapStyle = '''[
  {"elementType":"geometry","stylers":[{"color":"#1d2c4d"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#8ec3b9"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#1a3646"}]},
  {"featureType":"administrative","elementType":"geometry","stylers":[{"visibility":"off"}]},
  {"featureType":"administrative.country","elementType":"labels.text.fill","stylers":[{"color":"#4b6878"}]},
  {"featureType":"administrative.land_parcel","elementType":"labels.text.fill","stylers":[{"color":"#64779e"}]},
  {"featureType":"administrative.province","elementType":"labels.text.fill","stylers":[{"color":"#4b6878"}]},
  {"featureType":"landscape.man_made","elementType":"geometry.stroke","stylers":[{"color":"#334e87"}]},
  {"featureType":"landscape.natural","elementType":"geometry","stylers":[{"color":"#023e58"}]},
  {"featureType":"poi","stylers":[{"visibility":"off"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#304a7d"}]},
  {"featureType":"road","elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#98a5be"}]},
  {"featureType":"road","elementType":"labels.text.stroke","stylers":[{"color":"#1d2c4d"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#2c6675"}]},
  {"featureType":"road.highway","elementType":"labels.text.fill","stylers":[{"color":"#b0d5ce"}]},
  {"featureType":"road.highway","elementType":"labels.text.stroke","stylers":[{"color":"#023e58"}]},
  {"featureType":"transit","stylers":[{"visibility":"off"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#0e1626"}]},
  {"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#4e6d70"}]}
]''';
