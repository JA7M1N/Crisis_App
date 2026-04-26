import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sankatmitra/core/theme/app_theme.dart';
import 'package:sankatmitra/core/routes/app_router.dart';
import 'package:sankatmitra/data/models/user_model.dart';
import 'package:sankatmitra/data/services/geo_session_service.dart';

class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _slideAnim;

  UserRole? _selectedRole;
  final _nameController = TextEditingController();

  // Auto-detected session
  GeoSessionResult? _geoSession;
  bool _detectingLocation = true;
  bool _isLoading = false;

  // Manual override — user can tap to change if needed
  bool _showManualOverride = false;
  final _manualSessionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _slideAnim = Tween<double>(begin: 60, end: 0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
    _animController.forward();
    _loadSavedName();
    _detectLocation();
  }

  Future<void> _loadSavedName() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('user_name') ?? '';
    if (saved.isNotEmpty) _nameController.text = saved;
  }

  Future<void> _detectLocation() async {
    setState(() => _detectingLocation = true);
    final result = await GeoSessionService().detectSession();
    if (mounted) {
      setState(() {
        _geoSession = result;
        _detectingLocation = false;
        _manualSessionController.text = result.sessionId;
      });
    }
  }

  String get _activeSessionId {
    if (_showManualOverride && _manualSessionController.text.trim().isNotEmpty) {
      return _manualSessionController.text.trim().toUpperCase();
    }
    return _geoSession?.sessionId ?? 'GLOBAL-CRISIS';
  }

  @override
  void dispose() {
    _animController.dispose();
    _nameController.dispose();
    _manualSessionController.dispose();
    super.dispose();
  }

  Future<void> _proceed() async {
    if (_selectedRole == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFF2C2C2E),
          content: Text('Please select your role to continue',
              style: TextStyle(color: Colors.white)),
        ),
      );
      return;
    }
    if (_detectingLocation) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFF2C2C2E),
          content: Text('Detecting your location, please wait...',
              style: TextStyle(color: Colors.white)),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id') ?? const Uuid().v4();
    await prefs.setString('user_id', userId);
    await prefs.setString('session_id', _activeSessionId);

    final name = _nameController.text.trim();
    await prefs.setString('user_name', name);

    final displayName = name.isNotEmpty
        ? name
        : 'User-${userId.substring(userId.length - 6)}';

    final user = UserModel(
      userId: userId,
      sessionId: _activeSessionId,
      name: displayName,
      role: _selectedRole!,
      lat: _geoSession?.lat ?? 0,
      lng: _geoSession?.lng ?? 0,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (_selectedRole == UserRole.coordinator) {
      Navigator.pushNamed(context, AppRouter.dashboard, arguments: user);
    } else {
      Navigator.pushNamed(context, AppRouter.home, arguments: user);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _slideAnim,
          builder: (_, child) => Transform.translate(
            offset: Offset(0, _slideAnim.value),
            child: Opacity(opacity: _animController.value, child: child),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),

                // ── Header ───────────────────────────────────────────────────
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryRed.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.crisis_alert_rounded,
                          color: AppTheme.primaryRed, size: 28),
                    ),
                    const SizedBox(width: 12),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('SankatMitra',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.textPrimary,
                              letterSpacing: 1.5,
                            )),
                        Text('Who are you in this situation?',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                            )),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 28),

                // ── AUTO SESSION CARD ────────────────────────────────────────
                _buildAutoSessionCard(),
                const SizedBox(height: 28),

                // ── Name field ───────────────────────────────────────────────
                _fieldLabel('YOUR NAME / CALLSIGN'),
                const SizedBox(height: 8),
                TextField(
                  controller: _nameController,
                  style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w600),
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    hintText: 'e.g. Jaymi or Alpha-1',
                    hintStyle:
                        const TextStyle(color: AppTheme.textSecondary),
                    filled: true,
                    fillColor: AppTheme.bgCard,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                          color: Color(0x33FFFFFF), width: 1),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                          color: AppTheme.primaryRed, width: 1.5),
                    ),
                    prefixIcon: const Icon(Icons.badge_outlined,
                        color: AppTheme.textSecondary),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Shows on the live map and coordinator dashboard',
                  style:
                      TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 28),

                // ── Role cards ───────────────────────────────────────────────
                _fieldLabel('SELECT YOUR ROLE'),
                const SizedBox(height: 12),
                _RoleCard(
                  role: UserRole.victim,
                  selected: _selectedRole == UserRole.victim,
                  icon: Icons.person_pin_circle_outlined,
                  title: 'Victim',
                  subtitle: 'I need emergency help',
                  description:
                      'Share your real-time location. Trigger SOS with one tap.',
                  color: AppTheme.primaryRed,
                  onTap: () =>
                      setState(() => _selectedRole = UserRole.victim),
                ),
                const SizedBox(height: 12),
                _RoleCard(
                  role: UserRole.responder,
                  selected: _selectedRole == UserRole.responder,
                  icon: Icons.emergency_rounded,
                  title: 'Responder',
                  subtitle: 'I am here to help',
                  description:
                      'See victims on a live map. Navigate to those in need.',
                  color: AppTheme.safeGreen,
                  onTap: () =>
                      setState(() => _selectedRole = UserRole.responder),
                ),
                const SizedBox(height: 12),
                _RoleCard(
                  role: UserRole.coordinator,
                  selected: _selectedRole == UserRole.coordinator,
                  icon: Icons.dashboard_rounded,
                  title: 'Coordinator',
                  subtitle: 'Command & Control',
                  description:
                      'Monitor all active users across all sessions.',
                  color: AppTheme.alertBlue,
                  onTap: () =>
                      setState(() => _selectedRole = UserRole.coordinator),
                ),

                const SizedBox(height: 36),

                // ── Join button ──────────────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  height: 58,
                  child: ElevatedButton(
                    onPressed:
                        (_isLoading || _detectingLocation) ? null : _proceed,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _selectedRole == null
                          ? AppTheme.bgCard
                          : AppTheme.primaryRed,
                      disabledBackgroundColor: AppTheme.bgCard,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (_detectingLocation) ...[
                                const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2),
                                ),
                                const SizedBox(width: 10),
                                const Text('Detecting location...',
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white70)),
                              ] else ...[
                                const Text('JOIN CRISIS NETWORK',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.5,
                                    )),
                                const SizedBox(width: 8),
                                const Icon(Icons.arrow_forward_rounded),
                              ],
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Auto Session Detection Card ──────────────────────────────────────────
  Widget _buildAutoSessionCard() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _detectingLocation
            ? AppTheme.bgCard
            : AppTheme.safeGreen.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _detectingLocation
              ? Colors.white12
              : AppTheme.safeGreen.withValues(alpha: 0.4),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Icon
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _detectingLocation
                      ? AppTheme.alertBlue.withValues(alpha: 0.12)
                      : AppTheme.safeGreen.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: _detectingLocation
                    ? const Padding(
                        padding: EdgeInsets.all(10),
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppTheme.alertBlue),
                      )
                    : const Icon(Icons.location_on_rounded,
                        color: AppTheme.safeGreen, size: 20),
              ),
              const SizedBox(width: 12),

              // Text
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _detectingLocation
                          ? 'Detecting your location...'
                          : 'Auto-joined your local crisis network',
                      style: TextStyle(
                        color: _detectingLocation
                            ? AppTheme.textSecondary
                            : AppTheme.safeGreen,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _detectingLocation
                          ? 'Finding nearby responders in your area'
                          : _geoSession?.displayLabel ?? '',
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),

              // Retry button
              if (!_detectingLocation)
                GestureDetector(
                  onTap: () {
                    GeoSessionService().clearCache();
                    _detectLocation();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppTheme.bgSurface,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.refresh_rounded,
                        color: AppTheme.textSecondary, size: 16),
                  ),
                ),
            ],
          ),

          // Session ID pill
          if (!_detectingLocation && _geoSession != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppTheme.bgSurface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.tag_rounded,
                          color: AppTheme.textSecondary, size: 12),
                      const SizedBox(width: 4),
                      Text(
                        _activeSessionId,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Copy session ID
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(
                        ClipboardData(text: _activeSessionId));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: AppTheme.bgCard,
                        content: Row(
                          children: [
                            const Icon(Icons.check_circle_rounded,
                                color: AppTheme.safeGreen, size: 16),
                            const SizedBox(width: 8),
                            Text(
                              '"$_activeSessionId" copied!',
                              style: const TextStyle(
                                  color: AppTheme.textPrimary),
                            ),
                          ],
                        ),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppTheme.alertBlue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color:
                              AppTheme.alertBlue.withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.copy_rounded,
                            color: AppTheme.alertBlue, size: 12),
                        SizedBox(width: 4),
                        Text('Share',
                            style: TextStyle(
                                color: AppTheme.alertBlue,
                                fontSize: 11,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                // Manual override toggle
                GestureDetector(
                  onTap: () => setState(
                      () => _showManualOverride = !_showManualOverride),
                  child: Text(
                    _showManualOverride ? 'Use auto' : 'Change',
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 11,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),

            // Manual override field
            if (_showManualOverride) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _manualSessionController,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  fontSize: 13,
                ),
                textCapitalization: TextCapitalization.characters,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Enter custom session ID',
                  hintStyle: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 12),
                  filled: true,
                  fillColor: AppTheme.bgSurface,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                        color: AppTheme.alertBlue, width: 1.5),
                  ),
                  prefixIcon: const Icon(Icons.edit_rounded,
                      color: AppTheme.textSecondary, size: 16),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Use this to join a specific session across different locations',
                style:
                    TextStyle(fontSize: 11, color: AppTheme.textSecondary),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _fieldLabel(String label) => Text(label,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: AppTheme.textSecondary,
        letterSpacing: 1.5,
      ));
}

// ── Role card widget ──────────────────────────────────────────────────────────
class _RoleCard extends StatelessWidget {
  final UserRole role;
  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final String description;
  final Color color;
  final VoidCallback onTap;

  const _RoleCard({
    required this.role,
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: selected
            ? color.withValues(alpha: 0.12)
            : AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected ? color : const Color(0x22FFFFFF),
          width: selected ? 2 : 1,
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                    color: color.withValues(alpha: 0.2),
                    blurRadius: 16,
                    spreadRadius: 1)
              ]
            : [],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: selected
                                ? color
                                : AppTheme.textPrimary,
                          )),
                      Text(subtitle,
                          style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.textSecondary,
                              fontWeight: FontWeight.w500)),
                      const SizedBox(height: 3),
                      Text(description,
                          style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.textSecondary
                                  .withValues(alpha: 0.7))),
                    ],
                  ),
                ),
                if (selected)
                  Icon(Icons.check_circle_rounded,
                      color: color, size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
