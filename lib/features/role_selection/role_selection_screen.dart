import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sankatmitra/core/theme/app_theme.dart';
import 'package:sankatmitra/core/routes/app_router.dart';
import 'package:sankatmitra/data/models/user_model.dart';

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
  final _sessionController = TextEditingController();
  final _nameController = TextEditingController();   // NEW: callsign field
  bool _isLoading = false;

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
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final savedSession = prefs.getString('session_id');
    final savedName = prefs.getString('user_name') ?? '';
    if (savedSession != null) {
      _sessionController.text = savedSession;
    } else {
      _sessionController.text =
          const Uuid().v4().substring(0, 8).toUpperCase();
    }
    if (savedName.isNotEmpty) _nameController.text = savedName;
  }

  @override
  void dispose() {
    _animController.dispose();
    _sessionController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _proceed() async {
    if (_selectedRole == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select your role to continue')),
      );
      return;
    }
    setState(() => _isLoading = true);

    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id') ?? const Uuid().v4();
    await prefs.setString('user_id', userId);
    await prefs.setString('session_id', _sessionController.text.trim());

    // Save name
    final name = _nameController.text.trim();
    await prefs.setString('user_name', name);

    final user = UserModel(
      userId: userId,
      sessionId: _sessionController.text.trim(),
      name: name.isNotEmpty ? name : 'User-${userId.substring(userId.length - 6)}',
      role: _selectedRole!,
      lat: 0,
      lng: 0,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (_selectedRole == UserRole.coordinator) {
      Navigator.pushNamed(context, AppRouter.dashboard);
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
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryRed.withOpacity(0.15),
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
                const SizedBox(height: 32),

                // ── NEW: Name / Callsign field ──────────────────────────────
                _FieldLabel(label: 'YOUR NAME / CALLSIGN'),
                const SizedBox(height: 8),
                TextField(
                  controller: _nameController,
                  style: const TextStyle(
                      color: AppTheme.textPrimary, fontWeight: FontWeight.w600),
                  textCapitalization: TextCapitalization.words,
                  decoration: _inputDecoration(
                    hint: 'e.g. Jaymi or Alpha-1',
                    icon: Icons.badge_outlined,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Shows on the live map and coordinator dashboard',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 24),

                // Role cards
                _RoleCard(
                  role: UserRole.victim,
                  selected: _selectedRole == UserRole.victim,
                  icon: Icons.person_pin_circle_outlined,
                  title: 'Victim',
                  subtitle: 'I need emergency help',
                  description:
                  'Share your real-time location with responders. Trigger SOS with one tap.',
                  color: AppTheme.primaryRed,
                  onTap: () => setState(() => _selectedRole = UserRole.victim),
                ),
                const SizedBox(height: 16),
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
                const SizedBox(height: 16),
                _RoleCard(
                  role: UserRole.coordinator,
                  selected: _selectedRole == UserRole.coordinator,
                  icon: Icons.dashboard_rounded,
                  title: 'Coordinator',
                  subtitle: 'Command & Control',
                  description:
                  'Monitor all active users across all sessions on a single dashboard.',
                  color: AppTheme.alertBlue,
                  onTap: () =>
                      setState(() => _selectedRole = UserRole.coordinator),
                ),

                const SizedBox(height: 28),

                // Session ID field
                _FieldLabel(label: 'SESSION ID'),
                const SizedBox(height: 8),
                TextField(
                  controller: _sessionController,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2,
                  ),
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    hintText: 'e.g. ABC12345',
                    hintStyle: const TextStyle(
                        color: AppTheme.textSecondary, letterSpacing: 1),
                    filled: true,
                    fillColor: AppTheme.bgCard,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                      const BorderSide(color: Color(0x33FFFFFF), width: 1),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                      const BorderSide(color: AppTheme.primaryRed, width: 1.5),
                    ),
                    prefixIcon: const Icon(Icons.tag_rounded,
                        color: AppTheme.textSecondary),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.refresh_rounded,
                              color: AppTheme.textSecondary),
                          onPressed: () {
                            _sessionController.text = const Uuid()
                                .v4()
                                .substring(0, 8)
                                .toUpperCase();
                          },
                          tooltip: 'Generate new ID',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Share this ID with others to join the same session',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),

                const SizedBox(height: 36),

                // Proceed button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _proceed,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _selectedRole == null
                          ? AppTheme.bgCard
                          : AppTheme.primaryRed,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('JOIN CRISIS NETWORK',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.5,
                            )),
                        SizedBox(width: 8),
                        Icon(Icons.arrow_forward_rounded),
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

  InputDecoration _inputDecoration({required String hint, required IconData icon}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppTheme.textSecondary),
      filled: true,
      fillColor: AppTheme.bgCard,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0x33FFFFFF), width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.primaryRed, width: 1.5),
      ),
      prefixIcon: Icon(icon, color: AppTheme.textSecondary),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String label;
  const _FieldLabel({required this.label});
  @override
  Widget build(BuildContext context) {
    return Text(label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppTheme.textSecondary,
          letterSpacing: 1.5,
        ));
  }
}

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
        color: selected ? color.withOpacity(0.12) : AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected ? color : const Color(0x22FFFFFF),
          width: selected ? 2 : 1,
        ),
        boxShadow: selected
            ? [BoxShadow(color: color.withOpacity(0.25), blurRadius: 20, spreadRadius: 2)]
            : [],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 52, height: 52,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: color, size: 26),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w800,
                            color: selected ? color : AppTheme.textPrimary,
                          )),
                      Text(subtitle,
                          style: const TextStyle(
                            fontSize: 12, color: AppTheme.textSecondary,
                            fontWeight: FontWeight.w500,
                          )),
                      const SizedBox(height: 4),
                      Text(description,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary.withOpacity(0.7),
                          )),
                    ],
                  ),
                ),
                if (selected)
                  Icon(Icons.check_circle_rounded, color: color, size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }
}