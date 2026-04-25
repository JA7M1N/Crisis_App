import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:sankatmitra/core/theme/app_theme.dart';
import 'package:sankatmitra/data/models/user_model.dart';
import 'package:sankatmitra/data/services/firebase_service.dart';
import 'package:sankatmitra/data/services/connectivity_service.dart';
import 'package:sankatmitra/features/shared/widgets/layer_status_bar.dart';

class CoordinatorDashboard extends StatefulWidget {
  const CoordinatorDashboard({super.key});

  @override
  State<CoordinatorDashboard> createState() => _CoordinatorDashboardState();
}

class _CoordinatorDashboardState extends State<CoordinatorDashboard>
    with SingleTickerProviderStateMixin {
  final FirebaseService _firebase = FirebaseService();
  final ConnectivityService _connectivity = ConnectivityService();

  GoogleMapController? _mapController;
  Set<Marker> _markers = {};
  List<UserModel> _users = [];
  StreamSubscription? _usersSub;
  ConnectivityLayer _layer = ConnectivityLayer.firebase;

  late AnimationController _slideController;
  late Animation<Offset> _panelSlide;
  bool _panelExpanded = false;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _panelSlide = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOut));

    _slideController.forward();
    _connectivity.startMonitoring();
    _connectivity.layerStream.listen((l) {
      if (mounted) setState(() => _layer = l);
    });

    _usersSub = _firebase.streamAllUsers().listen((users) {
      if (mounted) {
        setState(() => _users = users);
        _buildMarkers(users);
        _fitAll(users);
      }
    });
  }

  Future<void> _buildMarkers(List<UserModel> users) async {
    final markers = <Marker>{};
    for (final u in users) {
      final hue = u.role == UserRole.responder
          ? BitmapDescriptor.hueGreen
          : u.isSOS
              ? BitmapDescriptor.hueRed
              : BitmapDescriptor.hueOrange;

      markers.add(Marker(
        markerId: MarkerId(u.userId),
        position: LatLng(u.lat, u.lng),
        icon: await BitmapDescriptor.defaultMarkerWithHue(hue),
        infoWindow: InfoWindow(
          title: '${u.role.name.toUpperCase()} · ${u.userId.substring(0, 6)}',
          snippet: u.isSOS ? '🆘 SOS ACTIVE' : 'Session: ${u.sessionId}',
        ),
      ));
    }
    if (mounted) setState(() => _markers = markers);
  }

  void _fitAll(List<UserModel> users) {
    if (_mapController == null || users.isEmpty) return;
    if (users.length == 1) {
      _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(LatLng(users.first.lat, users.first.lng), 14));
      return;
    }
    var minLat = users.first.lat, maxLat = users.first.lat;
    var minLng = users.first.lng, maxLng = users.first.lng;
    for (final u in users) {
      if (u.lat < minLat) minLat = u.lat;
      if (u.lat > maxLat) maxLat = u.lat;
      if (u.lng < minLng) minLng = u.lng;
      if (u.lng > maxLng) maxLng = u.lng;
    }
    _mapController!.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(
        southwest: LatLng(minLat - 0.01, minLng - 0.01),
        northeast: LatLng(maxLat + 0.01, maxLng + 0.01),
      ),
      80,
    ));
  }

  @override
  void dispose() {
    _usersSub?.cancel();
    _slideController.dispose();
    _connectivity.dispose();
    super.dispose();
  }

  int get _victimCount => _users.where((u) => u.role == UserRole.victim).length;
  int get _responderCount =>
      _users.where((u) => u.role == UserRole.responder).length;
  int get _sosCount => _users.where((u) => u.isSOS).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.dashboard_rounded, color: AppTheme.alertBlue, size: 20),
            SizedBox(width: 8),
            Text('Command Center'),
          ],
        ),
      ),
      body: Stack(
        children: [
          // Map
          GoogleMap(
            initialCameraPosition: const CameraPosition(
              target: LatLng(20.5937, 78.9629),
              zoom: 5,
            ),
            markers: _markers,
            mapType: MapType.normal,
            onMapCreated: (ctrl) {
              _mapController = ctrl;
              ctrl.setMapStyle(_darkMapStyle);
            },
          ),

          // Top overlay
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 130,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xEE0D0D0D), Colors.transparent],
                ),
              ),
            ),
          ),

          // Layer bar
          Positioned(
            top: 95,
            left: 0,
            right: 0,
            child: Center(child: LayerStatusBar(layer: _layer)),
          ),

          // Stats panel (bottom)
          SlideTransition(
            position: _panelSlide,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.bgCard,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0x22FFFFFF)),
                  boxShadow: const [
                    BoxShadow(
                        color: Colors.black54, blurRadius: 20, spreadRadius: 5),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Handle
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppTheme.textSecondary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Title row
                    Row(
                      children: [
                        const Text(
                          'LIVE SITUATION REPORT',
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppTheme.safeGreen,
                            boxShadow: [
                              BoxShadow(
                                  color: AppTheme.safeGreen,
                                  blurRadius: 8,
                                  spreadRadius: 2),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Text('LIVE',
                            style: TextStyle(
                                color: AppTheme.safeGreen,
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Stats row
                    Row(
                      children: [
                        _StatCard(
                          label: 'TOTAL',
                          value: '${_users.length}',
                          color: AppTheme.alertBlue,
                          icon: Icons.people_rounded,
                        ),
                        const SizedBox(width: 12),
                        _StatCard(
                          label: 'VICTIMS',
                          value: '$_victimCount',
                          color: AppTheme.primaryRed,
                          icon: Icons.person_pin_circle_outlined,
                        ),
                        const SizedBox(width: 12),
                        _StatCard(
                          label: 'RESPONDERS',
                          value: '$_responderCount',
                          color: AppTheme.safeGreen,
                          icon: Icons.emergency_rounded,
                        ),
                        const SizedBox(width: 12),
                        _StatCard(
                          label: 'SOS ACTIVE',
                          value: '$_sosCount',
                          color: _sosCount > 0
                              ? AppTheme.primaryRed
                              : AppTheme.textSecondary,
                          icon: Icons.sos_rounded,
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),
                    const Divider(color: Color(0x22FFFFFF)),
                    const SizedBox(height: 10),

                    // User list
                    if (_users.isEmpty)
                      const Text('No active users in any session',
                          style: TextStyle(color: AppTheme.textSecondary))
                    else
                      SizedBox(
                        height: 120,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: _users.length,
                          itemBuilder: (_, i) {
                            final u = _users[i];
                            return _UserChip(user: u);
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // Refresh FAB
          Positioned(
            bottom: 280,
            right: 16,
            child: FloatingActionButton.small(
              heroTag: 'fit',
              backgroundColor: AppTheme.bgCard,
              child: const Icon(Icons.center_focus_strong_rounded,
                  color: AppTheme.textPrimary),
              onPressed: () => _fitAll(_users),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: 20,
              ),
            ),
            Text(
              label,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 8,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _UserChip extends StatelessWidget {
  final UserModel user;

  const _UserChip({required this.user});

  @override
  Widget build(BuildContext context) {
    final color = user.role == UserRole.responder
        ? AppTheme.safeGreen
        : AppTheme.primaryRed;

    return Container(
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                user.role == UserRole.responder
                    ? Icons.emergency_rounded
                    : Icons.person_pin_circle_outlined,
                color: color,
                size: 14,
              ),
              const SizedBox(width: 4),
              Text(
                user.role.name.toUpperCase(),
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
              if (user.isSOS) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryRed,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('SOS',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w900)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'ID: ${user.userId.substring(0, 8)}',
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
          Text(
            '${user.lat.toStringAsFixed(4)}, ${user.lng.toStringAsFixed(4)}',
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

const String _darkMapStyle = '''[
  {"elementType":"geometry","stylers":[{"color":"#1d2c4d"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#8ec3b9"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#1a3646"}]},
  {"featureType":"poi","stylers":[{"visibility":"off"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#304a7d"}]},
  {"featureType":"road","elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"featureType":"transit","stylers":[{"visibility":"off"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#0e1626"}]}
]''';
