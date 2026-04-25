import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:sankatmitra/core/theme/app_theme.dart';
import 'package:sankatmitra/core/routes/app_router.dart';
import 'package:sankatmitra/data/models/user_model.dart';
import 'package:sankatmitra/data/repositories/location_repository.dart';
import 'package:sankatmitra/data/services/connectivity_service.dart';
import 'package:sankatmitra/data/services/ai_triage_service.dart';
import 'package:sankatmitra/features/shared/widgets/layer_status_bar.dart';

class HomeScreen extends StatefulWidget {
  final UserModel? user;
  const HomeScreen({super.key, this.user});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final LocationRepository _repo = LocationRepository();
  final MapController _mapController = MapController();

  List<UserModel> _users = [];
  ConnectivityLayer _currentLayer = ConnectivityLayer.cloud;
  bool _isSOS = false;
  bool _isInitialized = false;

  late AnimationController _pulseController;
  late AnimationController _radarController;
  late Animation<double> _pulseScale;
  late Animation<double> _radarSpin;

  StreamSubscription? _usersSub;
  StreamSubscription? _layerSub;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _radarController = AnimationController(
        vsync: this, duration: const Duration(seconds: 3))
      ..repeat();

    _pulseScale = Tween<double>(begin: 1.0, end: 1.14).animate(
        CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));
    _radarSpin = Tween<double>(begin: 0, end: 2 * pi).animate(_radarController);

    _startSession();
  }

  Future<void> _startSession() async {
    if (widget.user == null) return;
    await _repo.startSession(user: widget.user!);

    _layerSub =
        _repo.layerStream.listen((l) => mounted ? setState(() => _currentLayer = l) : null);
    _usersSub = _repo.usersStream.listen((users) {
      if (mounted) {
        setState(() => _users = users);
        _fitMarkers(users);
      }
    });

    setState(() => _isInitialized = true);
  }

  void _fitMarkers(List<UserModel> users) {
    if (users.isEmpty) return;
    final valid = users.where((u) => u.lat != 0 && u.lng != 0).toList();
    if (valid.isEmpty) return;
    if (valid.length == 1) {
      _mapController.move(LatLng(valid.first.lat, valid.first.lng), 16);
      return;
    }
    double minLat = valid.first.lat, maxLat = valid.first.lat;
    double minLng = valid.first.lng, maxLng = valid.first.lng;
    for (final u in valid) {
      if (u.lat < minLat) minLat = u.lat;
      if (u.lat > maxLat) maxLat = u.lat;
      if (u.lng < minLng) minLng = u.lng;
      if (u.lng > maxLng) maxLng = u.lng;
    }
    _mapController.fitCamera(CameraFit.bounds(
      bounds: LatLngBounds(
        LatLng(minLat - 0.005, minLng - 0.005),
        LatLng(maxLat + 0.005, maxLng + 0.005),
      ),
      padding: const EdgeInsets.all(80),
    ));
  }

  // ── SOS Confirmation Dialog ─────────────────────────────────────────────
  Future<void> _showSOSConfirmDialog() async {
    final descController = TextEditingController();
    bool confirmed = false;
    int countdown = 5;
    Timer? countdownTimer;
    String pendingDescription = '';

    await showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      isDismissible: false,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            // Start countdown when dialog opens
            countdownTimer ??= Timer.periodic(const Duration(seconds: 1), (t) {
              if (countdown <= 1) {
                t.cancel();
                confirmed = true;
                Navigator.pop(ctx);
              } else {
                setSheet(() => countdown--);
              }
            });

            return Padding(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(ctx).viewInsets.bottom,
                  left: 24, right: 24, top: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Header ─────────────────────────────────────────────
                  Row(
                    children: [
                      Container(
                        width: 48, height: 48,
                        decoration: BoxDecoration(
                          color: AppTheme.primaryRed.withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.sos_rounded,
                            color: AppTheme.primaryRed, size: 26),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Confirm SOS Alert',
                                style: TextStyle(
                                    color: AppTheme.textPrimary,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800)),
                            Text('Your location will be broadcast to all responders',
                                style: TextStyle(
                                    color: AppTheme.textSecondary, fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // ── Incident description (for AI triage) ───────────────
                  const Text('WHAT IS HAPPENING? (optional)',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textSecondary,
                          letterSpacing: 1.5)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: descController,
                    style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                    maxLines: 3,
                    onChanged: (v) => pendingDescription = v,
                    decoration: InputDecoration(
                      hintText: 'e.g. Building collapsed, I am trapped on 2nd floor...',
                      hintStyle: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 13),
                      filled: true,
                      fillColor: AppTheme.bgSurface,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                        const BorderSide(color: AppTheme.primaryRed, width: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.auto_awesome_rounded,
                          color: AppTheme.alertBlue, size: 12),
                      const SizedBox(width: 4),
                      Text(
                        'AI will auto-assign priority level for responders',
                        style: const TextStyle(
                            color: AppTheme.alertBlue, fontSize: 11),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // ── Countdown + Buttons ────────────────────────────────
                  Row(
                    children: [
                      // Cancel
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            countdownTimer?.cancel();
                            confirmed = false;
                            Navigator.pop(ctx);
                          },
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppTheme.textSecondary),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text('CANCEL',
                              style: TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Confirm + countdown
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: () {
                            countdownTimer?.cancel();
                            confirmed = true;
                            Navigator.pop(ctx);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryRed,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.sos_rounded,
                                  color: Colors.white, size: 18),
                              const SizedBox(width: 8),
                              Text(
                                'SEND SOS ($countdown)',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1,
                                    fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            );
          },
        );
      },
    );

    countdownTimer?.cancel();

    if (confirmed) {
      HapticFeedback.heavyImpact();
      setState(() => _isSOS = true);
      await _repo.triggerSOS(
          incidentDescription: descController.text.trim());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: AppTheme.primaryRed,
          content: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('🆘 SOS SENT — Broadcasting on all layers!',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold)),
                    if (descController.text.trim().isNotEmpty)
                      const Text('AI triage running...',
                          style: TextStyle(color: Colors.white70, fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 4),
        ));
      }
    }
    descController.dispose();
  }

  void _cancelSOS() {
    HapticFeedback.mediumImpact();
    setState(() => _isSOS = false);
    _repo.cancelSOS();
  }

  // ── Priority badge widget ───────────────────────────────────────────────
  Widget _priorityBadge(String priority) {
    if (priority.isEmpty) return const SizedBox.shrink();
    final label = AiTriageService.priorityLabel(priority);
    final colorHex = AiTriageService.priorityColor(priority);
    final color = _hexColor(colorHex);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.6)),
      ),
      child: Text(
        '$priority · $label',
        style: TextStyle(
            color: color, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.5),
      ),
    );
  }

  Color _hexColor(String hex) {
    hex = hex.replaceFirst('#', '');
    return Color(int.parse('FF$hex', radix: 16));
  }

  @override
  void dispose() {
    _usersSub?.cancel();
    _layerSub?.cancel();
    _pulseController.dispose();
    _radarController.dispose();
    _repo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final role = widget.user?.role ?? UserRole.victim;
    final sosCount = _users.where((u) => u.isSOS).length;
    final myUser = _users.firstWhere(
          (u) => u.userId == widget.user?.userId,
      orElse: () => widget.user ?? UserModel(
          userId: '', sessionId: '', role: role, lat: 0, lng: 0, timestamp: 0),
    );

    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.all(8),
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.bgCard.withOpacity(0.9),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white12),
            ),
            child: AnimatedBuilder(
              animation: _radarSpin,
              builder: (_, __) => Transform.rotate(
                angle: _isSOS ? _radarSpin.value : 0,
                child: const Icon(Icons.crisis_alert_rounded,
                    color: AppTheme.primaryRed, size: 20),
              ),
            ),
          ),
        ),
        title: Column(
          children: [
            const Text('SankatMitra',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                    color: AppTheme.textPrimary)),
            Text(
              widget.user?.displayName ?? '—',
              style: const TextStyle(
                  fontSize: 10, color: AppTheme.textSecondary, letterSpacing: 1),
            ),
          ],
        ),
        actions: [
          if (sosCount > 0)
            Container(
              margin: const EdgeInsets.only(right: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: AppTheme.primaryRed,
                  borderRadius: BorderRadius.circular(20)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.sos_rounded, color: Colors.white, size: 12),
                  const SizedBox(width: 4),
                  Text('$sosCount',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w900)),
                ],
              ),
            ),
          Container(
            margin: const EdgeInsets.only(right: 4),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: role == UserRole.responder
                  ? AppTheme.safeGreen.withOpacity(0.15)
                  : AppTheme.primaryRed.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: role == UserRole.responder
                      ? AppTheme.safeGreen
                      : AppTheme.primaryRed,
                  width: 1),
            ),
            child: Text(
              role.name.toUpperCase(),
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: role == UserRole.responder
                      ? AppTheme.safeGreen
                      : AppTheme.primaryRed,
                  letterSpacing: 1),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.dashboard_customize_rounded, size: 20),
            color: AppTheme.alertBlue,
            onPressed: () => Navigator.pushNamed(context, AppRouter.dashboard),
          ),
        ],
      ),
      body: Stack(
        children: [
          // ── OpenStreetMap ──────────────────────────────────────────────
          if (_isInitialized)
            FlutterMap(
              mapController: _mapController,
              options: const MapOptions(
                  initialCenter: LatLng(20.5937, 78.9629),
                  initialZoom: 5,
                  backgroundColor: Color(0xFF1a2535)),
              children: [
                TileLayer(
                  urlTemplate:
                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.sankatmitra',
                ),
                CircleLayer(
                  circles: _users
                      .where((u) => u.isSOS && u.lat != 0)
                      .map((u) => CircleMarker(
                    point: LatLng(u.lat, u.lng),
                    radius: 40,
                    color: AppTheme.primaryRed.withOpacity(0.2),
                    borderColor: AppTheme.primaryRed,
                    borderStrokeWidth: 2,
                    useRadiusInMeter: false,
                  ))
                      .toList(),
                ),
                MarkerLayer(
                  markers: _users.where((u) => u.lat != 0).map((u) {
                    final isMe = u.userId == widget.user?.userId;
                    Color c;
                    IconData ico;
                    if (isMe) {
                      c = AppTheme.alertBlue;
                      ico = Icons.my_location_rounded;
                    } else if (u.role == UserRole.responder) {
                      c = AppTheme.safeGreen;
                      ico = Icons.emergency_rounded;
                    } else {
                      c = u.isSOS ? AppTheme.primaryRed : AppTheme.accentOrange;
                      ico = u.isSOS ? Icons.sos_rounded : Icons.person_pin_rounded;
                    }
                    return Marker(
                      point: LatLng(u.lat, u.lng),
                      width: 60,
                      height: 76,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Priority badge above marker (NEW)
                          if (u.priority.isNotEmpty)
                            _priorityBadge(u.priority),
                          Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                              border:
                              Border.all(color: Colors.white, width: 2),
                              boxShadow: [
                                BoxShadow(
                                    color: c.withOpacity(0.6),
                                    blurRadius: 8,
                                    spreadRadius: 2)
                              ],
                            ),
                            child: Icon(ico, color: Colors.white, size: 18),
                          ),
                          // Name label
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppTheme.bgCard.withOpacity(0.85),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              u.displayName,
                              style: const TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontSize: 8,
                                  fontWeight: FontWeight.w700),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(width: 2, height: 6, color: c),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
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
                    Text('Acquiring location...',
                        style: TextStyle(color: AppTheme.textSecondary)),
                  ],
                ),
              ),
            ),

          // ── Top gradient ───────────────────────────────────────────────
          Positioned(
            top: 0, left: 0, right: 0, height: 130,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xEE0D0D0D), Colors.transparent]),
              ),
            ),
          ),

          // ── Layer status ───────────────────────────────────────────────
          Positioned(
            top: 100, left: 0, right: 0,
            child: Center(child: LayerStatusBar(layer: _currentLayer)),
          ),

          // ── Stats chips ────────────────────────────────────────────────
          Positioned(
            top: 148, left: 16, right: 16,
            child: Row(
              children: [
                _StatChip(
                    icon: Icons.people_rounded,
                    label: '${_users.length} active',
                    color: AppTheme.alertBlue),
                const SizedBox(width: 8),
                _StatChip(
                    icon: Icons.emergency_rounded,
                    label:
                    '${_users.where((u) => u.role == UserRole.responder).length} responders',
                    color: AppTheme.safeGreen),
                if (sosCount > 0) ...[
                  const SizedBox(width: 8),
                  _StatChip(
                      icon: Icons.sos_rounded,
                      label: '$sosCount SOS',
                      color: AppTheme.primaryRed,
                      pulse: true,
                      pulseController: _pulseController),
                ],
              ],
            ),
          ),

          // ── My priority badge (if AI triage returned) ─────────────────
          if (_isSOS && myUser.priority.isNotEmpty)
            Positioned(
              top: 190, left: 0, right: 0,
              child: Center(
                child: Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: _hexColor(
                        AiTriageService.priorityColor(myUser.priority))
                        .withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: _hexColor(AiTriageService.priorityColor(
                            myUser.priority))),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.auto_awesome_rounded,
                          color: AppTheme.alertBlue, size: 12),
                      const SizedBox(width: 6),
                      Text(
                        'AI Priority: ${myUser.priority} · ${AiTriageService.priorityLabel(myUser.priority)}',
                        style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ── OSM Attribution ────────────────────────────────────────────
          Positioned(
            bottom: 280, right: 8,
            child: Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4)),
              child: const Text('© OpenStreetMap',
                  style: TextStyle(color: Colors.white60, fontSize: 9)),
            ),
          ),

          // ── Bottom action panel ────────────────────────────────────────
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 44),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Color(0xFF0D0D0D),
                    Color(0xCC0D0D0D),
                    Colors.transparent
                  ],
                  stops: [0.0, 0.6, 1.0],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (role == UserRole.victim) ...[
                    AnimatedBuilder(
                      animation: _pulseScale,
                      builder: (_, child) => Transform.scale(
                          scale: _isSOS ? _pulseScale.value : 1.0,
                          child: child),
                      child: GestureDetector(
                        onTap: _isSOS ? _cancelSOS : _showSOSConfirmDialog,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 400),
                          width: 130, height: 130,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: _isSOS
                                  ? [AppTheme.deepRed, const Color(0xFF7B0000)]
                                  : [AppTheme.primaryRed, AppTheme.deepRed],
                            ),
                            border: Border.all(
                                color: _isSOS
                                    ? Colors.white38
                                    : Colors.white24,
                                width: 3),
                            boxShadow: [
                              BoxShadow(
                                color: (_isSOS
                                    ? AppTheme.deepRed
                                    : AppTheme.primaryRed)
                                    .withOpacity(_isSOS ? 0.8 : 0.5),
                                blurRadius: _isSOS ? 60 : 30,
                                spreadRadius: _isSOS ? 20 : 5,
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
                                  size: 44),
                              const SizedBox(height: 4),
                              Text(
                                _isSOS ? 'CANCEL' : 'SOS',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 4),
                              ),
                              if (_isSOS)
                                const Text('BROADCASTING',
                                    style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 9,
                                        letterSpacing: 1.5)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 400),
                      style: TextStyle(
                        color: _isSOS
                            ? AppTheme.primaryRed
                            : AppTheme.textSecondary,
                        fontSize: 13,
                        fontWeight: _isSOS ? FontWeight.w700 : FontWeight.normal,
                      ),
                      child: Text(
                        _isSOS
                            ? '🆘 SOS ACTIVE — Your location is being shared'
                            : 'Tap SOS to alert all nearby responders',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],

                  if (role == UserRole.responder) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.bgCard,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: AppTheme.safeGreen.withOpacity(0.5),
                            width: 1.5),
                        boxShadow: [
                          BoxShadow(
                              color: AppTheme.safeGreen.withOpacity(0.1),
                              blurRadius: 20,
                              spreadRadius: 2)
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 48, height: 48,
                            decoration: BoxDecoration(
                              color: AppTheme.safeGreen.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(Icons.emergency_rounded,
                                color: AppTheme.safeGreen, size: 24),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('RESPONDER ACTIVE',
                                    style: TextStyle(
                                        color: AppTheme.safeGreen,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13,
                                        letterSpacing: 1.5)),
                                Text(
                                  '${_users.where((u) => u.isSOS).length} SOS · ${_users.where((u) => u.role == UserRole.victim).length} victims',
                                  style: const TextStyle(
                                      color: AppTheme.textSecondary, fontSize: 12),
                                ),
                                // Show P0 count if any
                                if (_users.any((u) => u.priority == 'P0'))
                                  Text(
                                    '⚠ ${_users.where((u) => u.priority == 'P0').length} CRITICAL (P0) need immediate response',
                                    style: const TextStyle(
                                        color: AppTheme.primaryRed,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700),
                                  ),
                              ],
                            ),
                          ),
                          AnimatedBuilder(
                            animation: _pulseController,
                            builder: (_, __) => Container(
                              width: 12, height: 12,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppTheme.safeGreen,
                                boxShadow: [
                                  BoxShadow(
                                      color: AppTheme.safeGreen,
                                      blurRadius:
                                      4 + _pulseController.value * 8,
                                      spreadRadius: _pulseController.value * 2)
                                ],
                              ),
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

          // ── SOS red overlay ────────────────────────────────────────────
          if (_isSOS)
            IgnorePointer(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 500),
                opacity: 0.06,
                child: Container(color: AppTheme.primaryRed),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool pulse;
  final AnimationController? pulseController;

  const _StatChip({
    required this.icon,
    required this.label,
    required this.color,
    this.pulse = false,
    this.pulseController,
  });

  @override
  Widget build(BuildContext context) {
    Widget chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5)),
        ],
      ),
    );

    if (pulse && pulseController != null) {
      return AnimatedBuilder(
        animation: pulseController!,
        builder: (_, child) =>
            Opacity(opacity: 0.7 + pulseController!.value * 0.3, child: child),
        child: chip,
      );
    }
    return chip;
  }
}