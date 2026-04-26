import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:sankatmitra/core/theme/app_theme.dart';
import 'package:sankatmitra/core/routes/app_router.dart';
import 'package:sankatmitra/data/models/user_model.dart';
import 'package:sankatmitra/data/models/broadcast_message_model.dart';
import 'package:sankatmitra/data/repositories/location_repository.dart';
import 'package:sankatmitra/data/services/connectivity_service.dart';
import 'package:sankatmitra/data/services/ai_triage_service.dart';
import 'package:sankatmitra/data/services/map_cache_service.dart';
import 'package:sankatmitra/data/services/silent_panic_service.dart';
import 'package:sankatmitra/data/services/incident_timeline_service.dart';
import 'package:sankatmitra/features/shared/widgets/layer_status_bar.dart';
import 'package:sankatmitra/features/shared/widgets/layer_alert_banner.dart';
import 'package:sankatmitra/data/services/demo_seed_service.dart';

class HomeScreen extends StatefulWidget {
  final UserModel? user;
  const HomeScreen({super.key, this.user});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final LocationRepository _repo = LocationRepository();
  final MapController _mapController = MapController();
  final SilentPanicService _silentPanic = SilentPanicService();

  List<UserModel> _users = [];
  ConnectivityLayer _currentLayer = ConnectivityLayer.cloud;
  bool _isSOS = false;
  bool _isInitialized = false;
  bool _onMyWay = false;

  // Demo mode
  bool _isDemoMode = false;
  final DemoSeedService _demoSeed = DemoSeedService();
  StreamSubscription? _demoSub;

  // Animations
  late AnimationController _pulseController;
  late AnimationController _radarController;
  late Animation<double> _pulseScale;
  late Animation<double> _radarSpin;

  // Subscriptions
  StreamSubscription? _usersSub;
  StreamSubscription? _layerSub;
  StreamSubscription? _broadcastSub;
  StreamSubscription? _timelineSub;

  // Navigation
  UserModel? _navigatingTo;
  List<LatLng> _routePoints = [];
  bool _routeLoading = false;

  // Broadcast banner
  BroadcastMessage? _latestBroadcast;

  // Timeline
  bool _showTimeline = false;
  List<TimelineEvent> _timelineEvents = [];
  late IncidentTimelineService _timelineSvc;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _radarController =
    AnimationController(vsync: this, duration: const Duration(seconds: 3))
      ..repeat();

    _pulseScale = Tween<double>(begin: 1.0, end: 1.14).animate(
        CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));
    _radarSpin =
        Tween<double>(begin: 0, end: 2 * pi).animate(_radarController);

    _startSession();
  }

  Future<void> _startSession() async {
    if (widget.user == null) return;
    await _repo.startSession(user: widget.user!);

    _layerSub = _repo.layerStream
        .listen((l) => mounted ? setState(() => _currentLayer = l) : null);

    _usersSub = _repo.usersStream.listen((users) {
      if (mounted) {
        setState(() => _users = users);
        _fitMarkers(users);
      }
    });

    // Supabase-backed incident timeline
    _timelineSvc = IncidentTimelineService();
    _timelineSub =
        _timelineSvc.streamTimeline(widget.user!.sessionId).listen((events) {
          if (mounted) setState(() => _timelineEvents = events.reversed.toList());
        });

    // Broadcast banner — uses supabaseService getter on repo
    _broadcastSub = _repo.supabaseService
        .streamBroadcasts(widget.user!.sessionId)
        .listen((msgs) {
      if (mounted && msgs.isNotEmpty) {
        setState(() => _latestBroadcast = msgs.first);
        Future.delayed(const Duration(seconds: 10), () {
          if (mounted) setState(() => _latestBroadcast = null);
        });
      }
    });

    // Silent panic mode — victims only; silently ignored on web
    if (widget.user?.role == UserRole.victim) {
      _silentPanic.startListening(() {
        if (!_isSOS) _triggerSOSDirectly();
      });
    }

    // Pre-cache tiles around current location (stub until FMTC added)
    final loc = _repo.currentUser;
    if (loc != null && loc.lat != 0) {
      MapCacheService.preCacheArea(lat: loc.lat, lng: loc.lng);
    }

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

  // ── SOS confirm dialog ─────────────────────────────────────────────────────
  Future<void> _showSOSConfirmDialog() async {
    final descController = TextEditingController();
    bool confirmed = false;
    int countdown = 5;
    Timer? countdownTimer;

    await showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      isDismissible: false,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSheet) {
          countdownTimer ??=
              Timer.periodic(const Duration(seconds: 1), (t) {
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
                left: 24,
                right: 24,
                top: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryRed.withValues(alpha: 0.15),
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
                          Text(
                              'Your location will be broadcast to all responders',
                              style: TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Text('WHAT IS HAPPENING? (optional)',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textSecondary,
                        letterSpacing: 1.5)),
                const SizedBox(height: 8),
                TextField(
                  controller: descController,
                  style: const TextStyle(
                      color: AppTheme.textPrimary, fontSize: 14),
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText:
                    'e.g. Building collapsed, trapped on 2nd floor...',
                    hintStyle: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 13),
                    filled: true,
                    fillColor: AppTheme.bgSurface,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                          color: AppTheme.primaryRed, width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                const Row(
                  children: [
                    Icon(Icons.auto_awesome_rounded,
                        color: AppTheme.alertBlue, size: 12),
                    SizedBox(width: 4),
                    Text(
                      'AI will auto-assign priority level for responders',
                      style:
                      TextStyle(color: AppTheme.alertBlue, fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          countdownTimer?.cancel();
                          confirmed = false;
                          Navigator.pop(ctx);
                        },
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(
                              color: AppTheme.textSecondary),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          padding:
                          const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('CANCEL',
                            style: TextStyle(
                                color: AppTheme.textSecondary,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1)),
                      ),
                    ),
                    const SizedBox(width: 12),
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
                          padding:
                          const EdgeInsets.symmetric(vertical: 14),
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
        });
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
                            color: Colors.white,
                            fontWeight: FontWeight.bold)),
                    if (descController.text.trim().isNotEmpty)
                      const Text('AI triage running...',
                          style: TextStyle(
                              color: Colors.white70, fontSize: 11)),
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

  // Silent panic — no dialog, fires immediately
  Future<void> _triggerSOSDirectly() async {
    HapticFeedback.heavyImpact();
    setState(() => _isSOS = true);
    await _repo.triggerSOS(
        incidentDescription: 'Silent panic trigger (vol ×3)');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        backgroundColor: AppTheme.primaryRed,
        content: Text('🆘 SOS triggered silently',
            style:
            TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        duration: Duration(seconds: 3),
      ));
    }
  }

  void _cancelSOS() {
    HapticFeedback.mediumImpact();
    setState(() {
      _isSOS = false;
      _onMyWay = false;
    });
    _repo.cancelSOS();
  }

  // Responder "I'm on my way" toggle
  Future<void> _toggleOnMyWay({String targetName = ''}) async {
    final next = !_onMyWay;
    setState(() => _onMyWay = next);
    await _repo.setOnMyWay(value: next, targetName: targetName);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: next ? AppTheme.safeGreen : AppTheme.bgCard,
        content: Text(
          next ? '🏃 Status set: On my way!' : 'Status cleared',
          style: const TextStyle(color: Colors.white),
        ),
        duration: const Duration(seconds: 2),
      ));
    }
  }

  // ── Demo mode ──────────────────────────────────────────────────────────────
  void _toggleDemoMode() {
    HapticFeedback.mediumImpact();
    if (_isDemoMode) {
      _demoSub?.cancel();
      _demoSeed.stopDemo();
      setState(() {
        _isDemoMode = false;
        _users = [];
      });
    } else {
      final baseLat = _repo.currentUser?.lat ?? 22.3072;
      final baseLng = _repo.currentUser?.lng ?? 73.1812;
      _demoSeed.startDemo(baseLat: baseLat, baseLng: baseLng);
      _demoSub = _demoSeed.stream.listen((users) {
        if (mounted) {
          setState(() => _users = users);
          _fitMarkers(users);
        }
      });
      setState(() => _isDemoMode = true);
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  Widget _priorityBadge(String priority) {
    if (priority.isEmpty) return const SizedBox.shrink();
    final label = AiTriageService.priorityLabel(priority);
    final color = _hexColor(AiTriageService.priorityColor(priority));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: 0.7)),
      ),
      child: Text('$priority · $label',
          style: TextStyle(
              color: color,
              fontSize: 8,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.3),
          maxLines: 1,
          overflow: TextOverflow.visible),
    );
  }

  String _lastSeen(int timestamp) {
    if (timestamp == 0) return 'just now';
    final diff = DateTime.now().millisecondsSinceEpoch - timestamp;
    final mins = (diff / 60000).floor();
    if (mins < 1) return 'just now';
    if (mins == 1) return '1 min ago';
    if (mins < 60) return '$mins min ago';
    return '${(mins / 60).floor()}h ago';
  }

  Color _hexColor(String hex) {
    hex = hex.replaceFirst('#', '');
    return Color(int.parse('FF$hex', radix: 16));
  }

  // ── Routing helpers ────────────────────────────────────────────────────────
  Future<void> _fetchRoute(
      double fromLat, double fromLng, double toLat, double toLng) async {
    if (mounted) setState(() => _routeLoading = true);
    try {
      final url = Uri.parse(
          'https://router.project-osrm.org/route/v1/driving/'
              '$fromLng,$fromLat;$toLng,$toLat'
              '?overview=full&geometries=geojson');
      final res =
      await http.get(url).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final coords =
        data['routes'][0]['geometry']['coordinates'] as List;
        final points = coords
            .map<LatLng>(
                (c) => LatLng(c[1].toDouble(), c[0].toDouble()))
            .toList();
        if (mounted) setState(() => _routePoints = points);
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _routeLoading = false);
    }
  }

  Future<void> _openGoogleMaps(UserModel victim) async {
    final me = _repo.currentUser;
    if (me == null) return;
    final uri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1'
            '&origin=${me.lat},${me.lng}'
            '&destination=${victim.lat},${victim.lng}'
            '&travelmode=driving');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _showVictimNavSheet(UserModel victim) {
    final me = _repo.currentUser;
    if (me == null) return;

    _fetchRoute(me.lat, me.lng, victim.lat, victim.lng);

    _mapController.fitCamera(CameraFit.bounds(
      bounds: LatLngBounds(
        LatLng(
          me.lat < victim.lat ? me.lat - 0.003 : victim.lat - 0.003,
          me.lng < victim.lng ? me.lng - 0.003 : victim.lng - 0.003,
        ),
        LatLng(
          me.lat > victim.lat ? me.lat + 0.003 : victim.lat + 0.003,
          me.lng > victim.lng ? me.lng + 0.003 : victim.lng + 0.003,
        ),
      ),
      padding: const EdgeInsets.all(80),
    ));

    setState(() => _navigatingTo = victim);

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                      color: AppTheme.textSecondary,
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: (victim.isSOS
                          ? AppTheme.primaryRed
                          : AppTheme.accentOrange)
                          .withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      victim.isSOS
                          ? Icons.sos_rounded
                          : Icons.person_pin_circle_outlined,
                      color: victim.isSOS
                          ? AppTheme.primaryRed
                          : AppTheme.accentOrange,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(victim.displayName,
                            style: const TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 17,
                                fontWeight: FontWeight.w800)),
                        if (victim.isSOS)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                                color: AppTheme.primaryRed,
                                borderRadius: BorderRadius.circular(5)),
                            child: const Text('SOS ACTIVE',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900)),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Divider(color: Color(0x15FFFFFF)),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.location_on_rounded,
                      color: AppTheme.textSecondary, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    '${victim.lat.toStringAsFixed(5)}, ${victim.lng.toStringAsFixed(5)}',
                    style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                        fontFamily: 'monospace'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.access_time_rounded,
                      color: AppTheme.textSecondary, size: 12),
                  const SizedBox(width: 4),
                  Text(_lastSeen(victim.timestamp),
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 20),
              if (_routeLoading)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.alertBlue)),
                      SizedBox(width: 8),
                      Text('Loading route...',
                          style: TextStyle(
                              color: AppTheme.alertBlue, fontSize: 12)),
                    ],
                  ),
                )
              else if (_routePoints.isNotEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Icon(Icons.route_rounded,
                          color: AppTheme.safeGreen, size: 14),
                      SizedBox(width: 6),
                      Text('Route shown on map',
                          style: TextStyle(
                              color: AppTheme.safeGreen,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        if (_routePoints.isEmpty) {
                          final me2 = _repo.currentUser;
                          if (me2 != null) {
                            _fetchRoute(me2.lat, me2.lng, victim.lat,
                                victim.lng);
                          }
                        }
                      },
                      icon: const Icon(Icons.map_rounded, size: 16),
                      label: const Text('Show Route'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.alertBlue,
                        side: const BorderSide(color: AppTheme.alertBlue),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        _toggleOnMyWay(targetName: victim.displayName);
                        Navigator.pop(ctx);
                        _openGoogleMaps(victim);
                      },
                      icon: const Icon(Icons.navigation_rounded,
                          size: 18, color: Colors.white),
                      label: const Text("I'm Going!",
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4285F4),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
              if (_navigatingTo != null)
                Center(
                  child: TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      setState(() {
                        _navigatingTo = null;
                        _routePoints = [];
                        _onMyWay = false;
                      });
                      _repo.setOnMyWay(value: false);
                    },
                    child: const Text('Clear navigation',
                        style: TextStyle(
                            color: AppTheme.textSecondary, fontSize: 12)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _usersSub?.cancel();
    _layerSub?.cancel();
    _demoSub?.cancel();
    _broadcastSub?.cancel();
    _timelineSub?.cancel();
    _demoSeed.stopDemo();
    _pulseController.dispose();
    _radarController.dispose();
    _silentPanic.stopListening();
    _repo.dispose();
    super.dispose();
  }

  // ── Timeline panel ─────────────────────────────────────────────────────────
  Widget _buildTimelinePanel() {
    IconData iconFor(String type) {
      switch (type) {
        case 'sos_triggered':     return Icons.sos_rounded;
        case 'sos_cancelled':     return Icons.check_circle_rounded;
        case 'layer_switch':      return Icons.wifi_off_rounded;
        case 'responder_arrived': return Icons.directions_run_rounded;
        case 'user_joined':       return Icons.person_add_rounded;
        default:                  return Icons.info_rounded;
      }
    }

    Color colorFor(String hex) {
      try {
        return Color(
            int.parse('FF${hex.replaceFirst('#', '')}', radix: 16));
      } catch (_) {
        return AppTheme.textSecondary;
      }
    }

    String timeFor(DateTime t) =>
        '${t.hour.toString().padLeft(2, '0')}:'
            '${t.minute.toString().padLeft(2, '0')}:'
            '${t.second.toString().padLeft(2, '0')}';

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: Colors.white12),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 20)
        ],
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(
              children: [
                const Icon(Icons.timeline_rounded,
                    color: AppTheme.alertBlue, size: 16),
                const SizedBox(width: 8),
                const Text('INCIDENT TIMELINE',
                    style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        letterSpacing: 1.5)),
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
                            fontSize: 11,
                            fontWeight: FontWeight.w700)),
                  ),
                IconButton(
                  icon: const Icon(Icons.close,
                      color: AppTheme.textSecondary, size: 20),
                  onPressed: () => setState(() => _showTimeline = false),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white12, height: 1),
          // Events
          Expanded(
            child: _timelineEvents.isEmpty
                ? const Center(
                child: Text('No events yet',
                    style: TextStyle(color: AppTheme.textSecondary)))
                : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 6),
              itemCount: _timelineEvents.length,
              separatorBuilder: (_, __) => Divider(
                  color: Colors.white.withValues(alpha: 0.08), height: 1),
              itemBuilder: (_, i) {
                final e = _timelineEvents[i];
                final c = colorFor(e.colorHex);
                return Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                            color: c.withValues(alpha: 0.15),
                            shape: BoxShape.circle),
                        child: Icon(iconFor(e.type),
                            color: c, size: 14),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                          CrossAxisAlignment.start,
                          children: [
                            Text(e.detail,
                                style: const TextStyle(
                                    color: AppTheme.textPrimary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text(timeFor(e.timestamp),
                                style: const TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 10,
                                    fontFamily: 'monospace')),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final role = widget.user?.role ?? UserRole.victim;
    final sosCount = _users.where((u) => u.isSOS).length;
    final myUser = _users.firstWhere(
          (u) => u.userId == widget.user?.userId,
      orElse: () =>
      widget.user ??
          UserModel(
              userId: '',
              sessionId: '',
              role: role,
              lat: 0,
              lng: 0,
              timestamp: 0),
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
              color: AppTheme.bgCard.withValues(alpha: 0.9),
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
                  fontSize: 10,
                  color: AppTheme.textSecondary,
                  letterSpacing: 1),
            ),
          ],
        ),
        actions: [
          if (sosCount > 0)
            Container(
              margin: const EdgeInsets.only(right: 4),
              padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: AppTheme.primaryRed,
                  borderRadius: BorderRadius.circular(20)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.sos_rounded,
                      color: Colors.white, size: 12),
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
            padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: role == UserRole.responder
                  ? AppTheme.safeGreen.withValues(alpha: 0.15)
                  : AppTheme.primaryRed.withValues(alpha: 0.15),
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
            icon: Icon(
              _isDemoMode
                  ? Icons.stop_circle_rounded
                  : Icons.play_circle_rounded,
              size: 20,
              color: _isDemoMode
                  ? AppTheme.primaryRed
                  : const Color(0xFFFFD54F),
            ),
            onPressed: _toggleDemoMode,
          ),
          IconButton(
            icon: const Icon(Icons.dashboard_customize_rounded, size: 20),
            color: AppTheme.alertBlue,
            onPressed: () =>
                Navigator.pushNamed(context, AppRouter.dashboard),
          ),
        ],
      ),
      body: Stack(
        children: [
          // ── Map ─────────────────────────────────────────────────────────
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
                  'https://tiles.stadiamaps.com/tiles/alidade_smooth_dark/{z}/{x}/{y}{r}.png',
                  userAgentPackageName: 'com.sankatmitra.app',
                  // MapCacheService.tileProvider is NetworkTileProvider()
                  // — swap for FMTC provider when flutter_map_tile_caching is added
                  tileProvider: NetworkTileProvider(),
                  maxNativeZoom: 20,
                ),
                CircleLayer(
                  circles: _users
                      .where((u) => u.isSOS && u.lat != 0)
                      .map((u) => CircleMarker(
                    point: LatLng(u.lat, u.lng),
                    radius: 40,
                    color: AppTheme.primaryRed.withValues(alpha: 0.2),
                    borderColor: AppTheme.primaryRed,
                    borderStrokeWidth: 2,
                    useRadiusInMeter: false,
                  ))
                      .toList(),
                ),
                if (_routePoints.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _routePoints,
                        strokeWidth: 4.5,
                        color: const Color(0xFF4285F4),
                        borderStrokeWidth: 2,
                        borderColor: Colors.white24,
                      ),
                    ],
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
                      c = u.onMyWay
                          ? Colors.greenAccent
                          : AppTheme.safeGreen;
                      ico = u.onMyWay
                          ? Icons.directions_run_rounded
                          : Icons.emergency_rounded;
                    } else {
                      c = u.isSOS
                          ? AppTheme.primaryRed
                          : AppTheme.accentOrange;
                      ico = u.isSOS
                          ? Icons.sos_rounded
                          : Icons.person_pin_rounded;
                    }
                    final tappable = !isMe &&
                        role == UserRole.responder &&
                        u.role == UserRole.victim;
                    return Marker(
                      point: LatLng(u.lat, u.lng),
                      width: 80,
                      height: u.priority.isNotEmpty ? 116 : 88,
                      alignment: Alignment.bottomCenter,
                      child: GestureDetector(
                        onTap: tappable
                            ? () => _showVictimNavSheet(u)
                            : null,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            if (u.priority.isNotEmpty)
                              _priorityBadge(u.priority),
                            if (u.onMyWay &&
                                u.role == UserRole.responder)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 1),
                                margin:
                                const EdgeInsets.only(bottom: 2),
                                decoration: BoxDecoration(
                                  color: Colors.greenAccent
                                      .withValues(alpha: 0.2),
                                  borderRadius:
                                  BorderRadius.circular(4),
                                  border: Border.all(
                                      color: Colors.greenAccent
                                          .withValues(alpha: 0.6)),
                                ),
                                child: const Text('On way',
                                    style: TextStyle(
                                        color: Colors.greenAccent,
                                        fontSize: 7,
                                        fontWeight: FontWeight.w800)),
                              ),
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: c,
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: Colors.white, width: 2),
                                boxShadow: [
                                  BoxShadow(
                                      color: c.withValues(alpha: 0.6),
                                      blurRadius: 8,
                                      spreadRadius: 2)
                                ],
                              ),
                              child: Icon(ico,
                                  color: Colors.white, size: 18),
                            ),
                            Container(
                              constraints:
                              const BoxConstraints(maxWidth: 76),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.bgCard.withValues(alpha: 0.9),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(u.displayName,
                                      style: const TextStyle(
                                          color: AppTheme.textPrimary,
                                          fontSize: 8,
                                          fontWeight: FontWeight.w700),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                      textAlign: TextAlign.center),
                                  Text(_lastSeen(u.timestamp),
                                      style: const TextStyle(
                                          color: AppTheme.textSecondary,
                                          fontSize: 7),
                                      textAlign: TextAlign.center),
                                ],
                              ),
                            ),
                            Container(
                                width: 2, height: 5, color: c),
                          ],
                        ),
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
                        style:
                        TextStyle(color: AppTheme.textSecondary)),
                  ],
                ),
              ),
            ),

          // ── Top gradient ─────────────────────────────────────────────────
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

          // ── Layer alert banner ────────────────────────────────────────────
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(
              bottom: false,
              child: LayerAlertBanner(layerStream: _repo.layerStream),
            ),
          ),

          // ── Broadcast banner ──────────────────────────────────────────────
          if (_latestBroadcast != null)
            Positioned(
              top: MediaQuery.of(context).padding.top + 60,
              left: 16,
              right: 16,
              child: GestureDetector(
                onTap: () => setState(() => _latestBroadcast = null),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [
                      BoxShadow(color: Colors.black38, blurRadius: 8)
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.campaign_rounded,
                          color: Colors.white, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_latestBroadcast!.senderName,
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 11)),
                            Text(_latestBroadcast!.message,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      const Icon(Icons.close,
                          color: Colors.white70, size: 16),
                    ],
                  ),
                ),
              ),
            ),

          // ── Demo mode ribbon ──────────────────────────────────────────────
          if (_isDemoMode)
            Positioned(
              top: 98, left: 0, right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFD54F).withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.science_rounded,
                          size: 12, color: Colors.black),
                      SizedBox(width: 4),
                      Text('DEMO MODE — 5 simulated users',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: Colors.black)),
                    ],
                  ),
                ),
              ),
            ),

          // ── Layer status ──────────────────────────────────────────────────
          Positioned(
            top: 100, left: 0, right: 0,
            child: Center(child: LayerStatusBar(layer: _currentLayer)),
          ),

          // ── Stats chips ───────────────────────────────────────────────────
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

          // ── Attribution ───────────────────────────────────────────────────
          Positioned(
            bottom: 290, right: 8,
            child: Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4)),
              child: const Text('© Stadia Maps © OSM',
                  style: TextStyle(color: Colors.white60, fontSize: 9)),
            ),
          ),

          // ── Timeline toggle button ────────────────────────────────────────
          Positioned(
            bottom: 290, left: 16,
            child: GestureDetector(
              onTap: () => setState(() => _showTimeline = !_showTimeline),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: _showTimeline
                      ? AppTheme.alertBlue
                      : AppTheme.bgCard.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white24),
                  boxShadow: const [
                    BoxShadow(color: Colors.black38, blurRadius: 6)
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.timeline_rounded,
                        color: _showTimeline
                            ? Colors.white
                            : AppTheme.textSecondary,
                        size: 18),
                    if (_timelineEvents.isNotEmpty) ...[
                      const SizedBox(width: 5),
                      Text('${_timelineEvents.length}',
                          style: TextStyle(
                              color: _showTimeline
                                  ? Colors.white
                                  : AppTheme.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                    ],
                  ],
                ),
              ),
            ),
          ),

          // ── Bottom action panel ───────────────────────────────────────────
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
                  // ── VICTIM ────────────────────────────────────────────────
                  if (role == UserRole.victim) ...[
                    AnimatedBuilder(
                      animation: _pulseScale,
                      builder: (_, child) => Transform.scale(
                          scale: _isSOS ? _pulseScale.value : 1.0,
                          child: child),
                      child: GestureDetector(
                        onTap: _isSOS
                            ? _cancelSOS
                            : _showSOSConfirmDialog,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 400),
                          width: 130,
                          height: 130,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: _isSOS
                                  ? [
                                AppTheme.deepRed,
                                const Color(0xFF7B0000)
                              ]
                                  : [
                                AppTheme.primaryRed,
                                AppTheme.deepRed
                              ],
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
                                    .withValues(alpha: _isSOS ? 0.8 : 0.5),
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
                        fontWeight: _isSOS
                            ? FontWeight.w700
                            : FontWeight.normal,
                      ),
                      child: Text(
                        _isSOS
                            ? '🆘 SOS ACTIVE — Your location is being shared'
                            : 'Tap SOS to alert all nearby responders',
                        textAlign: TextAlign.center,
                      ),
                    ),
                    if (!_isSOS)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          'Tap → confirm → 5s countdown with cancel',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: AppTheme.textSecondary, fontSize: 11),
                        ),
                      ),
                  ],

                  // ── RESPONDER ─────────────────────────────────────────────
                  if (role == UserRole.responder) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.bgCard,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: AppTheme.safeGreen.withValues(alpha: 0.5),
                            width: 1.5),
                        boxShadow: [
                          BoxShadow(
                              color: AppTheme.safeGreen.withValues(alpha: 0.1),
                              blurRadius: 20,
                              spreadRadius: 2)
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: AppTheme.safeGreen.withValues(alpha: 0.15),
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
                                  '${_users.where((u) => u.isSOS).length} SOS · '
                                      '${_users.where((u) => u.role == UserRole.victim).length} victims',
                                  style: const TextStyle(
                                      color: AppTheme.textSecondary,
                                      fontSize: 12),
                                ),
                                const Text(
                                  '📍 Tap a victim marker to navigate',
                                  style: TextStyle(
                                      color: AppTheme.textSecondary,
                                      fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          // "I'm on my way" toggle
                          GestureDetector(
                            onTap: () => _toggleOnMyWay(),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: _onMyWay
                                    ? Colors.greenAccent.withValues(alpha: 0.2)
                                    : AppTheme.bgSurface,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: _onMyWay
                                        ? Colors.greenAccent
                                        : Colors.white24),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.directions_run_rounded,
                                      color: _onMyWay
                                          ? Colors.greenAccent
                                          : AppTheme.textSecondary,
                                      size: 20),
                                  Text(
                                    _onMyWay ? 'On way' : 'Going?',
                                    style: TextStyle(
                                        color: _onMyWay
                                            ? Colors.greenAccent
                                            : AppTheme.textSecondary,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          AnimatedBuilder(
                            animation: _pulseController,
                            builder: (_, __) => Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppTheme.safeGreen,
                                boxShadow: [
                                  BoxShadow(
                                      color: AppTheme.safeGreen,
                                      blurRadius: 4 +
                                          _pulseController.value * 8,
                                      spreadRadius:
                                      _pulseController.value * 2)
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

          // ── SOS red overlay ───────────────────────────────────────────────
          if (_isSOS)
            IgnorePointer(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 500),
                opacity: 0.06,
                child: Container(color: AppTheme.primaryRed),
              ),
            ),

          // ── Timeline panel ────────────────────────────────────────────────
          if (_showTimeline)
            Positioned(
              bottom: 0, left: 0, right: 0,
              height: MediaQuery.of(context).size.height * 0.45,
              child: _buildTimelinePanel(),
            ),
        ],
      ),
    );
  }
}

// ── Stat chip widget ──────────────────────────────────────────────────────────
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
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
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
        builder: (_, child) => Opacity(
            opacity: 0.7 + pulseController!.value * 0.3, child: child),
        child: chip,
      );
    }
    return chip;
  }
}