import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sankatmitra/core/theme/app_theme.dart';
import 'package:sankatmitra/data/services/broadcast_service.dart';

/// BroadcastBanner — slides down whenever a coordinator broadcast arrives.
///
/// Usage (in HomeScreen body Stack):
///   Positioned(
///     top: 0, left: 0, right: 0,
///     child: SafeArea(
///       bottom: false,
///       child: BroadcastBanner(sessionId: widget.user!.sessionId),
///     ),
///   ),

class BroadcastBanner extends StatefulWidget {
  final String sessionId;
  const BroadcastBanner({super.key, required this.sessionId});

  @override
  State<BroadcastBanner> createState() => _BroadcastBannerState();
}

class _BroadcastBannerState extends State<BroadcastBanner>
    with SingleTickerProviderStateMixin {
  final BroadcastService _service = BroadcastService();
  StreamSubscription<BroadcastMessage>? _sub;

  late AnimationController _slideController;
  late Animation<Offset> _slideAnim;

  BroadcastMessage? _current;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350));
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, -1.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOut));

    _sub = _service.streamBroadcasts(widget.sessionId).listen(_onMessage);
  }

  void _onMessage(BroadcastMessage msg) {
    HapticFeedback.mediumImpact();
    setState(() => _current = msg);
    _slideController.forward(from: 0);
    _dismissTimer?.cancel();
    _dismissTimer = Timer(const Duration(seconds: 6), _dismiss);
  }

  void _dismiss() {
    _slideController.reverse();
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'critical': return AppTheme.primaryRed;
      case 'warning':  return AppTheme.accentOrange;
      default:         return AppTheme.alertBlue;
    }
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'critical': return Icons.campaign_rounded;
      case 'warning':  return Icons.warning_amber_rounded;
      default:         return Icons.notifications_rounded;
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _dismissTimer?.cancel();
    _slideController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_current == null) return const SizedBox.shrink();
    final color = _typeColor(_current!.type);

    return SlideTransition(
      position: _slideAnim,
      child: GestureDetector(
        onTap: _dismiss,
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.bgCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withOpacity(0.7), width: 1.5),
            boxShadow: [
              BoxShadow(
                  color: color.withOpacity(0.3),
                  blurRadius: 20,
                  spreadRadius: 2)
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(_typeIcon(_current!.type), color: color, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          _current!.senderName.toUpperCase(),
                          style: TextStyle(
                              color: color,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.5),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _formatTime(_current!.sentAt),
                          style: const TextStyle(
                              color: AppTheme.textSecondary, fontSize: 10),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _current!.text,
                      style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.close_rounded,
                  color: AppTheme.textSecondary, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

/// ── Coordinator Compose Sheet ────────────────────────────────────────────
/// Call [showBroadcastComposer(context, sessionId, senderName)] from the
/// coordinator dashboard to open the compose bottom sheet.

Future<void> showBroadcastComposer(
  BuildContext context, {
  required String sessionId,
  required String senderName,
}) async {
  final controller = TextEditingController();
  String selectedType = 'info';

  await showModalBottomSheet(
    context: context,
    backgroundColor: AppTheme.bgCard,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setSheet) {
          return Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
                left: 24, right: 24, top: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: AppTheme.alertBlue.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.campaign_rounded,
                          color: AppTheme.alertBlue, size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Text('Broadcast to All',
                        style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w800)),
                  ],
                ),
                const SizedBox(height: 20),

                // Type selector
                const Text('ALERT TYPE',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textSecondary,
                        letterSpacing: 1.5)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (final t in ['info', 'warning', 'critical'])
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setSheet(() => selectedType = t),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: EdgeInsets.only(right: t != 'critical' ? 8 : 0),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: selectedType == t
                                  ? _typeColorStatic(t).withOpacity(0.2)
                                  : AppTheme.bgSurface,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: selectedType == t
                                      ? _typeColorStatic(t)
                                      : Colors.white12),
                            ),
                            child: Text(
                              t.toUpperCase(),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: selectedType == t
                                      ? _typeColorStatic(t)
                                      : AppTheme.textSecondary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),

                // Message field
                const Text('MESSAGE',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textSecondary,
                        letterSpacing: 1.5)),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  style: const TextStyle(
                      color: AppTheme.textPrimary, fontSize: 14),
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText:
                        'e.g. Evacuate zone B immediately. Move to north exit.',
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
                          const BorderSide(color: AppTheme.alertBlue, width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Send button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final text = controller.text.trim();
                      if (text.isEmpty) return;
                      await BroadcastService().sendBroadcast(
                        sessionId: sessionId,
                        senderName: senderName,
                        text: text,
                        type: selectedType,
                      );
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    icon: const Icon(Icons.send_rounded, size: 18),
                    label: const Text('SEND BROADCAST',
                        style: TextStyle(
                            fontWeight: FontWeight.w900, letterSpacing: 1)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.alertBlue,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          );
        },
      );
    },
  );
  controller.dispose();
}

Color _typeColorStatic(String type) {
  switch (type) {
    case 'critical': return AppTheme.primaryRed;
    case 'warning':  return AppTheme.accentOrange;
    default:         return AppTheme.alertBlue;
  }
}
