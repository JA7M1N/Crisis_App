import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:sankatmitra/core/theme/app_theme.dart';
import 'package:sankatmitra/data/models/user_model.dart';
import 'package:sankatmitra/data/services/supabase_service.dart';
import 'package:sankatmitra/data/services/connectivity_service.dart';
import 'package:sankatmitra/features/shared/widgets/layer_status_bar.dart';

class CoordinatorDashboard extends StatefulWidget {
  const CoordinatorDashboard({super.key});

  @override
  State<CoordinatorDashboard> createState() => _CoordinatorDashboardState();
}

class _CoordinatorDashboardState extends State<CoordinatorDashboard>
    with TickerProviderStateMixin {
  final SupabaseService _supabase = SupabaseService();
  final ConnectivityService _connectivity = ConnectivityService();
  final MapController _mapController = MapController();

  List<UserModel> _users = [];
  StreamSubscription? _usersSub;
  ConnectivityLayer _layer = ConnectivityLayer.cloud;

  late AnimationController _slideController;
  late AnimationController _pulseController;
  late Animation<Offset> _panelSlide;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _panelSlide = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOut));

    _slideController.forward();
    _connectivity.startMonitoring();
    _connectivity.layerStream.listen((l) {
      if (mounted) setState(() => _layer = l);
    });

    _usersSub = _supabase.streamAllUsers().listen((users) {
      if (mounted) {
        setState(() => _users = users);
        _fitAll(users);
      }
    });
  }

  void _fitAll(List<UserModel> users) {
    final validUsers = users.where((u) => u.lat != 0 && u.lng != 0).toList();
    if (validUsers.isEmpty) return;
    if (validUsers.length == 1) {
      _mapController.move(LatLng(validUsers.first.lat, validUsers.first.lng), 14);
      return;
    }
    var minLat = validUsers.first.lat, maxLat = validUsers.first.lat;
    var minLng = validUsers.first.lng, maxLng = validUsers.first.lng;
    for (final u in validUsers) {
      if (u.lat < minLat) minLat = u.lat;
      if (u.lat > maxLat) maxLat = u.lat;
      if (u.lng < minLng) minLng = u.lng;
      if (u.lng > maxLng) maxLng = u.lng;
    }
    _mapController.fitCamera(CameraFit.bounds(
      bounds: LatLngBounds(
        LatLng(minLat - 0.01, minLng - 0.01),
        LatLng(maxLat + 0.01, maxLng + 0.01),
      ),
      padding: const EdgeInsets.all(80),
    ));
  }

  @override
  void dispose() {
    _usersSub?.cancel();
    _slideController.dispose();
    _pulseController.dispose();
    _connectivity.dispose();
    super.dispose();
  }

  int get _victimCount => _users.where((u) => u.role == UserRole.victim).length;
  int get _responderCount => _users.where((u) => u.role == UserRole.responder).length;
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
          icon: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppTheme.bgCard.withOpacity(0.9),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white12),
            ),
            child: const Icon(Icons.arrow_back_ios_rounded, size: 16),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppTheme.alertBlue.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.satellite_alt_rounded,
                  color: AppTheme.alertBlue, size: 18),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Command Center',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1),
                ),
                Text(
                  'All Active Sessions',
                  style: TextStyle(fontSize: 10, color: AppTheme.textSecondary, letterSpacing: 0.5),
                ),
              ],
            ),
          ],
        ),
        actions: [
          if (_sosCount > 0)
            AnimatedBuilder(
              animation: _pulseController,
              builder: (_, child) => Opacity(
                opacity: 0.7 + _pulseController.value * 0.3,
                child: child,
              ),
              child: Container(
                margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primaryRed,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.sos_rounded, color: Colors.white, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      '$_sosCount ACTIVE',
                      style: const TextStyle(
                        color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          // ── OpenStreetMap ────────────────────────────────────────────────
          FlutterMap(
            mapController: _mapController,
            options: const MapOptions(
              initialCenter: LatLng(20.5937, 78.9629),
              initialZoom: 5,
              backgroundColor: Color(0xFF1a2535),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.sankatmitra',
              ),
              // SOS pulse circles
              CircleLayer(
                circles: _users
                    .where((u) => u.isSOS && u.lat != 0)
                    .map((u) => CircleMarker(
                          point: LatLng(u.lat, u.lng),
                          radius: 50,
                          color: AppTheme.primaryRed.withOpacity(0.15),
                          borderColor: AppTheme.primaryRed,
                          borderStrokeWidth: 2,
                          useRadiusInMeter: false,
                        ))
                    .toList(),
              ),
              // User markers
              MarkerLayer(
                markers: _users.where((u) => u.lat != 0).map((u) {
                  Color c;
                  IconData ico;
                  if (u.role == UserRole.responder) {
                    c = AppTheme.safeGreen;
                    ico = Icons.emergency_rounded;
                  } else if (u.isSOS) {
                    c = AppTheme.primaryRed;
                    ico = Icons.sos_rounded;
                  } else {
                    c = AppTheme.accentOrange;
                    ico = Icons.person_pin_rounded;
                  }
                  return Marker(
                    point: LatLng(u.lat, u.lng),
                    width: 44,
                    height: 54,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [BoxShadow(color: c.withOpacity(0.6), blurRadius: 8, spreadRadius: 2)],
                          ),
                          child: Icon(ico, color: Colors.white, size: 16),
                        ),
                        Container(width: 2, height: 7, color: c),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
          ),

          // ── Gradient overlays ─────────────────────────────────────────────
          Positioned(
            top: 0, left: 0, right: 0, height: 130,
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

          // ── Layer status ─────────────────────────────────────────────────
          Positioned(
            top: 95, left: 0, right: 0,
            child: Center(child: LayerStatusBar(layer: _layer)),
          ),

          // ── Attribution ───────────────────────────────────────────────────
          Positioned(
            bottom: 310, right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
              child: const Text('© OpenStreetMap', style: TextStyle(color: Colors.white60, fontSize: 9)),
            ),
          ),

          // ── Fit FAB ───────────────────────────────────────────────────────
          Positioned(
            bottom: 320, right: 12,
            child: FloatingActionButton.small(
              heroTag: 'fit',
              backgroundColor: AppTheme.bgCard,
              onPressed: () => _fitAll(_users),
              child: const Icon(Icons.center_focus_strong_rounded, color: AppTheme.textPrimary, size: 18),
            ),
          ),

          // ── Bottom stats panel ────────────────────────────────────────────
          SlideTransition(
            position: _panelSlide,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                decoration: BoxDecoration(
                  color: AppTheme.bgCard,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                  boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 30, spreadRadius: 5)],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Handle
                    const SizedBox(height: 10),
                    Container(
                      width: 36, height: 4,
                      decoration: BoxDecoration(color: AppTheme.textSecondary, borderRadius: BorderRadius.circular(2)),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text(
                                'LIVE SITUATION REPORT',
                                style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 1.5),
                              ),
                              const Spacer(),
                              AnimatedBuilder(
                                animation: _pulseController,
                                builder: (_, __) => Container(
                                  width: 8, height: 8,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: AppTheme.safeGreen,
                                    boxShadow: [BoxShadow(color: AppTheme.safeGreen, blurRadius: 4 + _pulseController.value * 8)],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Text('LIVE', style: TextStyle(color: AppTheme.safeGreen, fontSize: 10, fontWeight: FontWeight.w700)),
                            ],
                          ),
                          const SizedBox(height: 14),
                          // Stat cards row
                          Row(
                            children: [
                              _StatCard(label: 'TOTAL', value: '${_users.length}', color: AppTheme.alertBlue, icon: Icons.people_rounded),
                              const SizedBox(width: 10),
                              _StatCard(label: 'VICTIMS', value: '$_victimCount', color: AppTheme.accentOrange, icon: Icons.person_pin_circle_outlined),
                              const SizedBox(width: 10),
                              _StatCard(label: 'RESPONDERS', value: '$_responderCount', color: AppTheme.safeGreen, icon: Icons.emergency_rounded),
                              const SizedBox(width: 10),
                              _StatCard(
                                label: 'SOS', value: '$_sosCount',
                                color: _sosCount > 0 ? AppTheme.primaryRed : AppTheme.textSecondary,
                                icon: Icons.sos_rounded,
                                highlight: _sosCount > 0,
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          const Divider(color: Color(0x15FFFFFF)),
                          const SizedBox(height: 10),
                          // Users list
                          if (_users.isEmpty)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 16),
                              child: Center(
                                child: Text('Waiting for users to join...', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                              ),
                            )
                          else
                            SizedBox(
                              height: 110,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                itemCount: _users.length,
                                itemBuilder: (_, i) => _UserChip(user: _users[i]),
                              ),
                            ),
                          const SizedBox(height: 4),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
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
  final bool highlight;

  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(highlight ? 0.15 : 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(highlight ? 0.5 : 0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 22),
            ),
            Text(
              label,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 8, fontWeight: FontWeight.w700, letterSpacing: 0.5),
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
        : user.isSOS
            ? AppTheme.primaryRed
            : AppTheme.accentOrange;

    return Container(
      margin: const EdgeInsets.only(right: 10, bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
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
                user.role == UserRole.responder ? Icons.emergency_rounded : Icons.person_pin_circle_outlined,
                color: color, size: 13,
              ),
              const SizedBox(width: 4),
              Text(
                user.role.name.toUpperCase(),
                style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1),
              ),
              if (user.isSOS) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(color: AppTheme.primaryRed, borderRadius: BorderRadius.circular(4)),
                  child: const Text('SOS', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w900)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'ID: ...${user.userId.length > 8 ? user.userId.substring(user.userId.length - 8) : user.userId}',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10, fontFamily: 'monospace'),
          ),
          Text(
            '${user.lat.toStringAsFixed(3)}, ${user.lng.toStringAsFixed(3)}',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 9),
          ),
          Text(
            'SID: ${user.sessionId.length > 8 ? user.sessionId.substring(0, 8) : user.sessionId}',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 9),
          ),
        ],
      ),
    );
  }
}
