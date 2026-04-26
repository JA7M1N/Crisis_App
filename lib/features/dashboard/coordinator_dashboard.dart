import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:sankatmitra/core/theme/app_theme.dart';
import 'package:sankatmitra/data/models/user_model.dart';
import 'package:sankatmitra/data/models/broadcast_message_model.dart';
import 'package:sankatmitra/data/services/supabase_service.dart';
import 'package:sankatmitra/data/services/connectivity_service.dart';
import 'package:sankatmitra/data/services/incident_timeline_service.dart';
import 'package:sankatmitra/features/shared/widgets/layer_status_bar.dart';

class CoordinatorDashboard extends StatefulWidget {
  final String? sessionId;
  final String coordinatorName;
  const CoordinatorDashboard({super.key, this.sessionId, this.coordinatorName = 'Coordinator'});

  @override
  State<CoordinatorDashboard> createState() => _CoordinatorDashboardState();
}

class _CoordinatorDashboardState extends State<CoordinatorDashboard>
    with TickerProviderStateMixin {
  final SupabaseService _supabase = SupabaseService();
  final ConnectivityService _connectivity = ConnectivityService();
  final IncidentTimelineService _timelineSvc = IncidentTimelineService();
  final MapController _mapController = MapController();

  List<UserModel> _users = [];
  List<TimelineEvent> _timelineEvents = [];
  List<BroadcastMessage> _broadcasts = [];

  StreamSubscription? _usersSub;
  StreamSubscription? _timelineSub;
  StreamSubscription? _broadcastSub;

  ConnectivityLayer _layer = ConnectivityLayer.cloud;

  late AnimationController _slideController;
  late AnimationController _pulseController;
  late Animation<Offset> _panelSlide;

  // UI state
  bool _showTimeline = false;
  bool _showBroadcast = false;
  final TextEditingController _broadcastController = TextEditingController();

  // Coordinator's session — streams ALL sessions so use a fixed key
  // sessionId is passed from route args or defaults to DEMO2025

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
    ).animate(
        CurvedAnimation(parent: _slideController, curve: Curves.easeOut));

    _slideController.forward();
    _connectivity.startMonitoring();
    _connectivity.layerStream.listen((l) {
      if (mounted) setState(() => _layer = l);
    });

    // Stream all users across all sessions
    _usersSub = _supabase.streamAllUsers().listen((users) {
      if (mounted) {
        const order = {'P0': 0, 'P1': 1, 'P2': 2, 'P3': 3};
        users.sort((a, b) =>
            (order[a.priority] ?? 4).compareTo(order[b.priority] ?? 4));
        setState(() => _users = users);
        _fitAll(users);
      }
    });

    // Stream incident timeline for coordinator session
    _timelineSub =
        _timelineSvc.streamTimeline(widget.sessionId ?? 'DEMO2025').listen((events) {
          if (mounted) setState(() => _timelineEvents = events.reversed.toList());
        });

    // Stream broadcast messages
    _broadcastSub =
        _supabase.streamBroadcasts(widget.sessionId ?? 'DEMO2025').listen((msgs) {
          if (mounted) setState(() => _broadcasts = msgs);
        });
  }

  void _fitAll(List<UserModel> users) {
    final v = users.where((u) => u.lat != 0 && u.lng != 0).toList();
    if (v.isEmpty) return;
    if (v.length == 1) {
      _mapController.move(LatLng(v.first.lat, v.first.lng), 14);
      return;
    }
    var minLat = v.first.lat, maxLat = v.first.lat;
    var minLng = v.first.lng, maxLng = v.first.lng;
    for (final u in v) {
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

  Future<void> _sendBroadcast() async {
    final msg = _broadcastController.text.trim();
    if (msg.isEmpty) return;
    await _supabase.sendBroadcast(
      sessionId: widget.sessionId ?? 'DEMO2025',
      senderName: 'Coordinator',
      message: msg,
    );
    _broadcastController.clear();
    setState(() => _showBroadcast = false);
  }

  @override
  void dispose() {
    _usersSub?.cancel();
    _timelineSub?.cancel();
    _broadcastSub?.cancel();
    _broadcastController.dispose();
    _slideController.dispose();
    _pulseController.dispose();
    _connectivity.dispose();
    super.dispose();
  }

  int get _victimCount =>
      _users.where((u) => u.role == UserRole.victim).length;
  int get _responderCount =>
      _users.where((u) => u.role == UserRole.responder).length;
  int get _sosCount => _users.where((u) => u.isSOS).length;

  // ── Timeline icon helper ────────────────────────────────────────────────
  IconData _timelineIcon(String type) {
    switch (type) {
      case 'sos_triggered':
        return Icons.sos_rounded;
      case 'sos_cancelled':
        return Icons.check_circle_rounded;
      case 'layer_switch':
        return Icons.wifi_off_rounded;
      case 'responder_arrived':
        return Icons.directions_run_rounded;
      case 'user_joined':
        return Icons.person_add_rounded;
      default:
        return Icons.info_rounded;
    }
  }

  Color _timelineColor(String colorHex) {
    try {
      return Color(int.parse('FF${colorHex.replaceFirst('#', '')}', radix: 16));
    } catch (_) {
      return AppTheme.textSecondary;
    }
  }

  String _timeLabel(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    final s = t.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

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
              color: AppTheme.bgCard.withValues(alpha: 0.9),
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
                color: AppTheme.alertBlue.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.satellite_alt_rounded,
                  color: AppTheme.alertBlue, size: 18),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Command Center',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1)),
                Text('All Active Sessions',
                    style: TextStyle(
                        fontSize: 10,
                        color: AppTheme.textSecondary,
                        letterSpacing: 0.5)),
              ],
            ),
          ],
        ),
        actions: [
          if (_sosCount > 0)
            AnimatedBuilder(
              animation: _pulseController,
              builder: (_, child) =>
                  Opacity(opacity: 0.7 + _pulseController.value * 0.3, child: child),
              child: Container(
                margin: const EdgeInsets.only(right: 12),
                padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primaryRed,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.sos_rounded, color: Colors.white, size: 14),
                    const SizedBox(width: 4),
                    Text('$_sosCount ACTIVE',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1)),
                  ],
                ),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          // ── Map ───────────────────────────────────────────────────────────
          FlutterMap(
            mapController: _mapController,
            options: const MapOptions(
              initialCenter: LatLng(20.5937, 78.9629),
              initialZoom: 5,
              backgroundColor: Color(0xFF1a2535),
            ),
            children: [
              TileLayer(
                urlTemplate:
                'https://tiles.stadiamaps.com/tiles/alidade_smooth_dark/{z}/{x}/{y}{r}.png',
                userAgentPackageName: 'com.sankatmitra.app',
                tileProvider: NetworkTileProvider(),
                maxNativeZoom: 20,
              ),
              CircleLayer(
                circles: _users
                    .where((u) => u.isSOS && u.lat != 0)
                    .map((u) => CircleMarker(
                  point: LatLng(u.lat, u.lng),
                  radius: 50,
                  color: AppTheme.primaryRed.withValues(alpha: 0.15),
                  borderColor: AppTheme.primaryRed,
                  borderStrokeWidth: 2,
                  useRadiusInMeter: false,
                ))
                    .toList(),
              ),
              MarkerLayer(
                markers: _users.where((u) => u.lat != 0).map((u) {
                  Color c;
                  IconData ico;
                  if (u.role == UserRole.responder) {
                    c = u.onMyWay ? Colors.greenAccent : AppTheme.safeGreen;
                    ico = u.onMyWay
                        ? Icons.directions_run_rounded
                        : Icons.emergency_rounded;
                  } else if (u.isSOS) {
                    c = AppTheme.primaryRed;
                    ico = Icons.sos_rounded;
                  } else {
                    c = AppTheme.accentOrange;
                    ico = Icons.person_pin_rounded;
                  }
                  return Marker(
                    point: LatLng(u.lat, u.lng),
                    width: 80,
                    height: 60,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // "On way" badge
                        if (u.onMyWay)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 1),
                            margin: const EdgeInsets.only(bottom: 2),
                            decoration: BoxDecoration(
                              color: Colors.greenAccent.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                  color: Colors.greenAccent.withValues(alpha: 0.7)),
                            ),
                            child: const Text('On way',
                                style: TextStyle(
                                    color: Colors.greenAccent,
                                    fontSize: 7,
                                    fontWeight: FontWeight.w800)),
                          ),
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border:
                            Border.all(color: Colors.white, width: 2),
                            boxShadow: [
                              BoxShadow(
                                  color: c.withValues(alpha: 0.6),
                                  blurRadius: 8,
                                  spreadRadius: 2)
                            ],
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

          // ── Gradients ─────────────────────────────────────────────────────
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

          // ── Layer status ──────────────────────────────────────────────────
          Positioned(
            top: 95, left: 0, right: 0,
            child: Center(child: LayerStatusBar(layer: _layer)),
          ),

          // ── Attribution ───────────────────────────────────────────────────
          Positioned(
            bottom: 310, right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4)),
              child: const Text('© Stadia Maps © OSM',
                  style: TextStyle(color: Colors.white60, fontSize: 9)),
            ),
          ),

          // ── Fit FAB ───────────────────────────────────────────────────────
          Positioned(
            bottom: 320, right: 12,
            child: FloatingActionButton.small(
              heroTag: 'fit',
              backgroundColor: AppTheme.bgCard,
              onPressed: () => _fitAll(_users),
              child: const Icon(Icons.center_focus_strong_rounded,
                  color: AppTheme.textPrimary, size: 18),
            ),
          ),

          // ── Timeline toggle FAB ───────────────────────────────────────────
          Positioned(
            bottom: 370, right: 12,
            child: FloatingActionButton.small(
              heroTag: 'timeline',
              backgroundColor:
              _showTimeline ? AppTheme.alertBlue : AppTheme.bgCard,
              onPressed: () => setState(() {
                _showTimeline = !_showTimeline;
                if (_showTimeline) _showBroadcast = false;
              }),
              child: Icon(Icons.timeline_rounded,
                  color: _showTimeline
                      ? Colors.white
                      : AppTheme.textSecondary,
                  size: 18),
            ),
          ),

          // ── Broadcast FAB ─────────────────────────────────────────────────
          Positioned(
            bottom: 420, right: 12,
            child: FloatingActionButton.small(
              heroTag: 'broadcast',
              backgroundColor:
              _showBroadcast ? Colors.blueAccent : AppTheme.bgCard,
              onPressed: () => setState(() {
                _showBroadcast = !_showBroadcast;
                if (_showBroadcast) _showTimeline = false;
              }),
              child: Icon(Icons.campaign_rounded,
                  color: _showBroadcast
                      ? Colors.white
                      : AppTheme.textSecondary,
                  size: 18),
            ),
          ),

          // ── Broadcast panel ───────────────────────────────────────────────
          if (_showBroadcast)
            Positioned(
              bottom: 330,
              right: 12,
              width: 300,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.bgCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.4)),
                  boxShadow: const [
                    BoxShadow(color: Colors.black45, blurRadius: 12)
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.campaign_rounded,
                            color: Colors.blueAccent, size: 16),
                        const SizedBox(width: 6),
                        const Text('BROADCAST TO ALL',
                            style: TextStyle(
                                color: Colors.blueAccent,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1)),
                        const Spacer(),
                        if (_broadcasts.isNotEmpty)
                          Text('${_broadcasts.length} sent',
                              style: const TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 10)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Recent messages
                    if (_broadcasts.isNotEmpty) ...[
                      ...(_broadcasts.take(3).map((b) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.blueAccent.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(b.message,
                                    style: const TextStyle(
                                        color: AppTheme.textPrimary,
                                        fontSize: 12)),
                              ),
                              Text(b.timeLabel,
                                  style: const TextStyle(
                                      color: AppTheme.textSecondary,
                                      fontSize: 10)),
                            ],
                          ),
                        ),
                      ))),
                      const Divider(color: Colors.white12),
                    ],
                    // Input row
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _broadcastController,
                            style: const TextStyle(
                                color: AppTheme.textPrimary, fontSize: 13),
                            decoration: InputDecoration(
                              hintText: 'Alert message...',
                              hintStyle: const TextStyle(
                                  color: AppTheme.textSecondary, fontSize: 13),
                              filled: true,
                              fillColor: AppTheme.bgSurface,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                            ),
                            onSubmitted: (_) => _sendBroadcast(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: _sendBroadcast,
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.blueAccent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.send_rounded,
                                color: Colors.white, size: 16),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

          // ── Timeline panel ────────────────────────────────────────────────
          if (_showTimeline)
            Positioned(
              bottom: 330,
              right: 12,
              width: 320,
              child: Container(
                constraints: const BoxConstraints(maxHeight: 400),
                decoration: BoxDecoration(
                  color: AppTheme.bgCard,
                  borderRadius: BorderRadius.circular(16),
                  border:
                  Border.all(color: AppTheme.alertBlue.withValues(alpha: 0.3)),
                  boxShadow: const [
                    BoxShadow(color: Colors.black45, blurRadius: 12)
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
                      child: Row(
                        children: [
                          const Icon(Icons.timeline_rounded,
                              color: AppTheme.alertBlue, size: 16),
                          const SizedBox(width: 8),
                          const Text('INCIDENT TIMELINE',
                              style: TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                  letterSpacing: 1)),
                          const Spacer(),
                          if (_timelineEvents.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.alertBlue.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text('${_timelineEvents.length}',
                                  style: const TextStyle(
                                      color: AppTheme.alertBlue,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700)),
                            ),
                          IconButton(
                            icon: const Icon(Icons.close,
                                color: AppTheme.textSecondary, size: 16),
                            onPressed: () =>
                                setState(() => _showTimeline = false),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ),
                    const Divider(color: Colors.white12, height: 1),
                    // Events
                    Flexible(
                      child: _timelineEvents.isEmpty
                          ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(
                          child: Text('No events yet',
                              style: TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 13)),
                        ),
                      )
                          : ListView.separated(
                        shrinkWrap: true,
                        padding:
                        const EdgeInsets.symmetric(vertical: 6),
                        itemCount: _timelineEvents.length,
                        separatorBuilder: (_, __) =>
                            Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
                        itemBuilder: (_, i) {
                          final e = _timelineEvents[i];
                          final color = _timelineColor(e.colorHex);
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 7),
                            child: Row(
                              crossAxisAlignment:
                              CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                      _timelineIcon(e.type),
                                      color: color,
                                      size: 14),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                    children: [
                                      Text(e.detail,
                                          style: const TextStyle(
                                              color:
                                              AppTheme.textPrimary,
                                              fontSize: 12,
                                              fontWeight:
                                              FontWeight.w600)),
                                      const SizedBox(height: 2),
                                      Row(
                                        children: [
                                          Text(
                                            _timeLabel(e.timestamp),
                                            style: const TextStyle(
                                                color:
                                                AppTheme.textSecondary,
                                                fontSize: 10,
                                                fontFamily: 'monospace'),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(e.actorName,
                                              style: const TextStyle(
                                                  color: AppTheme
                                                      .textSecondary,
                                                  fontSize: 10)),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
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
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  boxShadow: const [
                    BoxShadow(color: Colors.black54, blurRadius: 30, spreadRadius: 5)
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 36, height: 4,
                      decoration: BoxDecoration(
                          color: AppTheme.textSecondary,
                          borderRadius: BorderRadius.circular(2)),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text('LIVE SITUATION REPORT',
                                  style: TextStyle(
                                      color: AppTheme.textPrimary,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12,
                                      letterSpacing: 1.5)),
                              const Spacer(),
                              AnimatedBuilder(
                                animation: _pulseController,
                                builder: (_, __) => Container(
                                  width: 8, height: 8,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: AppTheme.safeGreen,
                                    boxShadow: [
                                      BoxShadow(
                                          color: AppTheme.safeGreen,
                                          blurRadius:
                                          4 + _pulseController.value * 8)
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Text('LIVE',
                                  style: TextStyle(
                                      color: AppTheme.safeGreen,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700)),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              _StatCard(
                                  label: 'TOTAL',
                                  value: '${_users.length}',
                                  color: AppTheme.alertBlue,
                                  icon: Icons.people_rounded),
                              const SizedBox(width: 10),
                              _StatCard(
                                  label: 'VICTIMS',
                                  value: '$_victimCount',
                                  color: AppTheme.accentOrange,
                                  icon: Icons.person_pin_circle_outlined),
                              const SizedBox(width: 10),
                              _StatCard(
                                  label: 'RESPONDERS',
                                  value: '$_responderCount',
                                  color: AppTheme.safeGreen,
                                  icon: Icons.emergency_rounded),
                              const SizedBox(width: 10),
                              _StatCard(
                                label: 'SOS',
                                value: '$_sosCount',
                                color: _sosCount > 0
                                    ? AppTheme.primaryRed
                                    : AppTheme.textSecondary,
                                icon: Icons.sos_rounded,
                                highlight: _sosCount > 0,
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          const Divider(color: Color(0x15FFFFFF)),
                          const SizedBox(height: 10),
                          if (_users.isEmpty)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 16),
                              child: Center(
                                child: Text('Waiting for users to join...',
                                    style: TextStyle(
                                        color: AppTheme.textSecondary,
                                        fontSize: 13)),
                              ),
                            )
                          else
                            SizedBox(
                              height: 110,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                itemCount: _users.length,
                                itemBuilder: (_, i) =>
                                    _UserChip(user: _users[i]),
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

// ── Sub-widgets ──────────────────────────────────────────────────────────────

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
          color: color.withValues(alpha: highlight ? 0.15 : 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: highlight ? 0.5 : 0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 4),
            Text(value,
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                    fontSize: 22)),
            Text(label,
                style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _UserChip extends StatelessWidget {
  final UserModel user;
  const _UserChip({required this.user});

  String _lastSeen(int timestamp) {
    if (timestamp == 0) return 'just now';
    final diff = DateTime.now().millisecondsSinceEpoch - timestamp;
    final mins = (diff / 60000).floor();
    if (mins < 1) return 'just now';
    if (mins == 1) return '1 min ago';
    if (mins < 60) return '$mins min ago';
    return '${(mins / 60).floor()}h ago';
  }

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
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
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
                color: color, size: 13,
              ),
              const SizedBox(width: 4),
              Text(user.role.name.toUpperCase(),
                  style: TextStyle(
                      color: color,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1)),
              if (user.isSOS) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                      color: AppTheme.primaryRed,
                      borderRadius: BorderRadius.circular(4)),
                  child: const Text('SOS',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.w900)),
                ),
              ],
              // "On my way" badge
              if (user.onMyWay) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.greenAccent.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                        color: Colors.greenAccent.withValues(alpha: 0.6)),
                  ),
                  child: const Text('On way',
                      style: TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 8,
                          fontWeight: FontWeight.w900)),
                ),
              ],
              if (user.priority.isNotEmpty) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppTheme.alertBlue.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                        color: AppTheme.alertBlue.withValues(alpha: 0.6)),
                  ),
                  child: Text(user.priority,
                      style: const TextStyle(
                          color: AppTheme.alertBlue,
                          fontSize: 8,
                          fontWeight: FontWeight.w900)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            user.displayName,
            style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 11,
                fontWeight: FontWeight.w700),
          ),
          Text(
            '${user.lat.toStringAsFixed(3)}, ${user.lng.toStringAsFixed(3)}',
            style: const TextStyle(
                color: AppTheme.textSecondary, fontSize: 9),
          ),
          Text('🕐 ${_lastSeen(user.timestamp)}',
              style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 9,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}