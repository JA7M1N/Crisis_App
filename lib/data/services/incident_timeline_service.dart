import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sankatmitra/data/services/connectivity_service.dart';

/// A single event in the incident timeline.
class TimelineEvent {
  final String id;
  final String sessionId;
  final String type;       // 'sos_triggered' | 'layer_switch' | 'responder_arrived' | 'sos_cancelled' | 'user_joined'
  final String actorName;  // name of user who caused the event
  final String detail;     // human-readable description
  final DateTime timestamp;

  const TimelineEvent({
    required this.id,
    required this.sessionId,
    required this.type,
    required this.actorName,
    required this.detail,
    required this.timestamp,
  });

  factory TimelineEvent.fromSupabase(Map<dynamic, dynamic> row) {
    return TimelineEvent(
      id: row['id']?.toString() ?? '',
      sessionId: row['session_id'] ?? '',
      type: row['type'] ?? '',
      actorName: row['actor_name'] ?? '',
      detail: row['detail'] ?? '',
      timestamp: DateTime.tryParse(row['timestamp'] ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'session_id': sessionId,
        'type': type,
        'actor_name': actorName,
        'detail': detail,
        'timestamp': timestamp.toIso8601String(),
      };

  /// Icon name for display
  String get iconKey {
    switch (type) {
      case 'sos_triggered':     return 'sos';
      case 'sos_cancelled':     return 'check_circle';
      case 'layer_switch':      return 'wifi_off';
      case 'responder_arrived': return 'emergency';
      case 'user_joined':       return 'person_add';
      default:                  return 'info';
    }
  }

  String get colorHex {
    switch (type) {
      case 'sos_triggered':     return '#FF3B30';
      case 'sos_cancelled':     return '#34C759';
      case 'layer_switch':      return '#FF9500';
      case 'responder_arrived': return '#30D158';
      case 'user_joined':       return '#0A84FF';
      default:                  return '#8E8E93';
    }
  }
}

/// IncidentTimelineService — logs key events for the coordinator's timeline view.
///
/// ── Supabase SQL (run once) ──────────────────────────────────────────────
/// create table if not exists incident_timeline (
///   id          uuid primary key default gen_random_uuid(),
///   session_id  text not null,
///   type        text not null,
///   actor_name  text not null default '',
///   detail      text not null default '',
///   timestamp   timestamptz not null default now()
/// );
/// alter table incident_timeline enable row level security;
/// create policy "allow all" on incident_timeline for all using (true) with check (true);
/// alter publication supabase_realtime add table incident_timeline;
/// ────────────────────────────────────────────────────────────────────────

class IncidentTimelineService {
  static final IncidentTimelineService _instance =
      IncidentTimelineService._internal();
  factory IncidentTimelineService() => _instance;
  IncidentTimelineService._internal();

  final SupabaseClient _client = Supabase.instance.client;
  static const _table = 'incident_timeline';

  /// Log any event.
  Future<void> log({
    required String sessionId,
    required String type,
    required String actorName,
    required String detail,
  }) async {
    try {
      await _client.from(_table).insert({
        'session_id': sessionId,
        'type': type,
        'actor_name': actorName,
        'detail': detail,
        'timestamp': DateTime.now().toIso8601String(),
      });
      debugPrint('[Timeline] $type — $detail');
    } catch (e) {
      debugPrint('[Timeline] Failed to log: $e');
    }
  }

  // ── Convenience helpers ──────────────────────────────────────────────

  Future<void> logSOS({
    required String sessionId,
    required String actorName,
    String description = '',
  }) =>
      log(
        sessionId: sessionId,
        type: 'sos_triggered',
        actorName: actorName,
        detail: description.isEmpty
            ? '$actorName triggered SOS'
            : '$actorName triggered SOS: $description',
      );

  Future<void> logSOSCancelled({
    required String sessionId,
    required String actorName,
  }) =>
      log(
        sessionId: sessionId,
        type: 'sos_cancelled',
        actorName: actorName,
        detail: '$actorName cancelled SOS',
      );

  Future<void> logLayerSwitch({
    required String sessionId,
    required String actorName,
    required ConnectivityLayer layer,
  }) {
    final layerName = _layerName(layer);
    return log(
      sessionId: sessionId,
      type: 'layer_switch',
      actorName: actorName,
      detail: 'Network degraded → switched to $layerName',
    );
  }

  Future<void> logResponderArrival({
    required String sessionId,
    required String actorName,
    required String targetName,
  }) =>
      log(
        sessionId: sessionId,
        type: 'responder_arrived',
        actorName: actorName,
        detail: '$actorName is navigating to $targetName',
      );

  Future<void> logUserJoined({
    required String sessionId,
    required String actorName,
    required String role,
  }) =>
      log(
        sessionId: sessionId,
        type: 'user_joined',
        actorName: actorName,
        detail: '$actorName joined as $role',
      );

  String _layerName(ConnectivityLayer layer) {
    switch (layer) {
      case ConnectivityLayer.cloud:     return 'Cloud';
      case ConnectivityLayer.bluetooth: return 'Bluetooth P2P';
      case ConnectivityLayer.sms:       return 'SMS Fallback';
    }
  }

  // ── Stream & Fetch ───────────────────────────────────────────────────

  Stream<List<TimelineEvent>> streamTimeline(String sessionId) {
    final controller = StreamController<List<TimelineEvent>>.broadcast();

    _fetchTimeline(sessionId).then((events) {
      if (!controller.isClosed) controller.add(events);
    });

    final channel = _client
        .channel('timeline:$sessionId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: _table,
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'session_id',
            value: sessionId,
          ),
          callback: (_) {
            _fetchTimeline(sessionId).then((events) {
              if (!controller.isClosed) controller.add(events);
            });
          },
        )
        .subscribe();

    controller.onCancel = () {
      _client.removeChannel(channel);
      controller.close();
    };

    return controller.stream;
  }

  Future<List<TimelineEvent>> _fetchTimeline(String sessionId) async {
    final data = await _client
        .from(_table)
        .select()
        .eq('session_id', sessionId)
        .order('timestamp', ascending: true);
    return (data as List).map((r) => TimelineEvent.fromSupabase(r)).toList();
  }
}
