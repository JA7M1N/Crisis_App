import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// BroadcastMessage — a single message from coordinator to all session members.
class BroadcastMessage {
  final String id;
  final String sessionId;
  final String senderName;
  final String text;
  final DateTime sentAt;
  final String type; // 'info' | 'warning' | 'critical'

  const BroadcastMessage({
    required this.id,
    required this.sessionId,
    required this.senderName,
    required this.text,
    required this.sentAt,
    this.type = 'info',
  });

  factory BroadcastMessage.fromSupabase(Map<dynamic, dynamic> row) {
    return BroadcastMessage(
      id: row['id']?.toString() ?? '',
      sessionId: row['session_id'] ?? '',
      senderName: row['sender_name'] ?? 'Coordinator',
      text: row['text'] ?? '',
      sentAt: DateTime.tryParse(row['sent_at'] ?? '') ?? DateTime.now(),
      type: row['type'] ?? 'info',
    );
  }

  Map<String, dynamic> toMap() => {
        'session_id': sessionId,
        'sender_name': senderName,
        'text': text,
        'sent_at': sentAt.toIso8601String(),
        'type': type,
      };
}

/// BroadcastService — coordinator sends text alerts to all session members.
///
/// ── Supabase SQL (run once) ──────────────────────────────────────────────
/// create table if not exists broadcast_messages (
///   id          uuid primary key default gen_random_uuid(),
///   session_id  text not null,
///   sender_name text not null default 'Coordinator',
///   text        text not null,
///   type        text not null default 'info',
///   sent_at     timestamptz not null default now()
/// );
/// alter table broadcast_messages enable row level security;
/// create policy "allow all" on broadcast_messages for all using (true) with check (true);
/// alter publication supabase_realtime add table broadcast_messages;
/// ────────────────────────────────────────────────────────────────────────

class BroadcastService {
  static final BroadcastService _instance = BroadcastService._internal();
  factory BroadcastService() => _instance;
  BroadcastService._internal();

  final SupabaseClient _client = Supabase.instance.client;
  static const _table = 'broadcast_messages';

  /// Send a broadcast to all users in a session.
  Future<void> sendBroadcast({
    required String sessionId,
    required String senderName,
    required String text,
    String type = 'info', // 'info' | 'warning' | 'critical'
  }) async {
    await _client.from(_table).insert({
      'session_id': sessionId,
      'sender_name': senderName,
      'text': text,
      'type': type,
      'sent_at': DateTime.now().toIso8601String(),
    });
    debugPrint('[Broadcast] Sent: "$text" → session $sessionId');
  }

  /// Stream incoming broadcasts for a session (used on victim/responder side).
  Stream<BroadcastMessage> streamBroadcasts(String sessionId) {
    final controller = StreamController<BroadcastMessage>.broadcast();

    final channel = _client
        .channel('broadcasts:$sessionId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: _table,
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'session_id',
            value: sessionId,
          ),
          callback: (payload) {
            final msg = BroadcastMessage.fromSupabase(payload.newRecord);
            if (!controller.isClosed) controller.add(msg);
          },
        )
        .subscribe();

    controller.onCancel = () {
      _client.removeChannel(channel);
      controller.close();
    };

    return controller.stream;
  }

  /// Fetch recent broadcasts (last 20) for a session — for history on join.
  Future<List<BroadcastMessage>> recentBroadcasts(String sessionId,
      {int limit = 20}) async {
    final data = await _client
        .from(_table)
        .select()
        .eq('session_id', sessionId)
        .order('sent_at', ascending: false)
        .limit(limit);
    return (data as List)
        .map((r) => BroadcastMessage.fromSupabase(r))
        .toList()
        .reversed
        .toList();
  }
}
