import 'dart:async';
import 'package:flutter/material.dart';
import 'package:sankatmitra/core/theme/app_theme.dart';
import 'package:sankatmitra/data/services/incident_timeline_service.dart';

/// IncidentTimelinePanel — shows a scrollable list of session events.
///
/// Usage in coordinator_dashboard.dart:
///   Add a tab or a bottom sheet that shows:
///   IncidentTimelinePanel(sessionId: mySessionId)

class IncidentTimelinePanel extends StatefulWidget {
  final String sessionId;
  const IncidentTimelinePanel({super.key, required this.sessionId});

  @override
  State<IncidentTimelinePanel> createState() => _IncidentTimelinePanelState();
}

class _IncidentTimelinePanelState extends State<IncidentTimelinePanel> {
  final IncidentTimelineService _service = IncidentTimelineService();
  StreamSubscription<List<TimelineEvent>>? _sub;
  List<TimelineEvent> _events = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _sub = _service.streamTimeline(widget.sessionId).listen((events) {
      if (mounted) {
        setState(() {
          _events = events;
          _loading = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Color _color(String hex) {
    final h = hex.replaceFirst('#', '');
    return Color(int.parse('FF$h', radix: 16));
  }

  IconData _icon(String iconKey) {
    switch (iconKey) {
      case 'sos':              return Icons.sos_rounded;
      case 'check_circle':     return Icons.check_circle_outline_rounded;
      case 'wifi_off':         return Icons.wifi_off_rounded;
      case 'emergency':        return Icons.emergency_rounded;
      case 'person_add':       return Icons.person_add_rounded;
      default:                 return Icons.info_outline_rounded;
    }
  }

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.alertBlue),
      );
    }

    if (_events.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.timeline_rounded,
                color: AppTheme.textSecondary.withOpacity(0.3), size: 48),
            const SizedBox(height: 12),
            const Text('No events yet',
                style: TextStyle(
                    color: AppTheme.textSecondary, fontSize: 14)),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: _events.length,
      separatorBuilder: (_, __) => const SizedBox(height: 0),
      itemBuilder: (_, i) {
        final event = _events[_events.length - 1 - i]; // newest first
        final color = _color(event.colorHex);
        final isLast = i == _events.length - 1;

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Timeline spine ───────────────────────────────────────
              SizedBox(
                width: 32,
                child: Column(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.15),
                        shape: BoxShape.circle,
                        border: Border.all(color: color.withOpacity(0.6)),
                      ),
                      child: Icon(_icon(event.iconKey), color: color, size: 14),
                    ),
                    if (!isLast)
                      Expanded(
                        child: Container(
                          width: 1.5,
                          color: Colors.white10,
                          margin: const EdgeInsets.symmetric(vertical: 2),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),

              // ── Event card ───────────────────────────────────────────
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              event.detail,
                              style: const TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _relativeTime(event.timestamp),
                            style: const TextStyle(
                                color: AppTheme.textSecondary, fontSize: 10),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatFullTime(event.timestamp),
                        style: const TextStyle(
                            color: AppTheme.textSecondary, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatFullTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

/// ── Bottom sheet launcher ─────────────────────────────────────────────────
void showTimelineBottomSheet(BuildContext context, String sessionId) {
  showModalBottomSheet(
    context: context,
    backgroundColor: AppTheme.bgCard,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      minChildSize: 0.3,
      expand: false,
      builder: (_, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            child: Row(
              children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: AppTheme.alertBlue.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.timeline_rounded,
                      color: AppTheme.alertBlue, size: 18),
                ),
                const SizedBox(width: 12),
                const Text('Incident Timeline',
                    style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(child: IncidentTimelinePanel(sessionId: sessionId)),
        ],
      ),
    ),
  );
}
