import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sankatmitra/data/models/user_model.dart';
import 'package:sankatmitra/data/models/broadcast_message_model.dart';

/// SupabaseService — real-time backend.
///
/// SQL to run once in Supabase SQL Editor:
/// ─────────────────────────────────────────────────────
/// -- Add on_my_way column to existing table:
/// alter table session_users add column if not exists on_my_way boolean not null default false;
///
/// -- Broadcast messages table:
/// create table if not exists broadcast_messages (
///   id          uuid primary key default gen_random_uuid(),
///   session_id  text not null,
///   sender_name text not null,
///   message     text not null,
///   created_at  timestamptz not null default now()
/// );
/// alter table broadcast_messages enable row level security;
/// create policy "allow all" on broadcast_messages for all using (true) with check (true);
/// alter publication supabase_realtime add table broadcast_messages;
/// ─────────────────────────────────────────────────────

class SupabaseService {
  static final SupabaseService _instance = SupabaseService._internal();
  factory SupabaseService() => _instance;
  SupabaseService._internal();

  final SupabaseClient _client = Supabase.instance.client;
  static const _table = 'session_users';
  static const _broadcastTable = 'broadcast_messages';

  // ── User Location ──────────────────────────────────────────────────────────

  /// Upsert user location + name + priority + onMyWay
  Future<void> updateUserLocation({
    required String sessionId,
    required String userId,
    required String name,
    required double lat,
    required double lng,
    required UserRole role,
    bool isSOS = false,
    String priority = '',
    bool onMyWay = false,
  }) async {
    await _client.from(_table).upsert({
      'user_id': userId,
      'session_id': sessionId,
      'name': name,
      'role': role.name,
      'lat': lat,
      'lng': lng,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'is_sos': isSOS,
      'priority': priority,
      'on_my_way': onMyWay,
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'session_id,user_id');
  }

  /// Stream users in a session using Supabase Realtime
  Stream<List<UserModel>> streamSessionUsers(String sessionId) {
    final controller = StreamController<List<UserModel>>.broadcast();

    _fetchSessionUsers(sessionId).then((users) {
      if (!controller.isClosed) controller.add(users);
    });

    final channel = _client
        .channel('session:$sessionId')
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: _table,
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'session_id',
        value: sessionId,
      ),
      callback: (_) {
        _fetchSessionUsers(sessionId).then((users) {
          if (!controller.isClosed) controller.add(users);
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

  /// Stream ALL users across all sessions (coordinator view)
  Stream<List<UserModel>> streamAllUsers() {
    final controller = StreamController<List<UserModel>>.broadcast();

    _fetchAllUsers().then((users) {
      if (!controller.isClosed) controller.add(users);
    });

    final channel = _client
        .channel('all_sessions')
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: _table,
      callback: (_) {
        _fetchAllUsers().then((users) {
          if (!controller.isClosed) controller.add(users);
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

  Future<List<UserModel>> _fetchSessionUsers(String sessionId) async {
    final data = await _client
        .from(_table)
        .select()
        .eq('session_id', sessionId);
    return (data as List).map((row) => UserModel.fromSupabase(row)).toList();
  }

  Future<List<UserModel>> _fetchAllUsers() async {
    final data = await _client
        .from(_table)
        .select()
        .order('updated_at', ascending: false);
    return (data as List).map((row) => UserModel.fromSupabase(row)).toList();
  }

  Future<void> removeUser(String sessionId, String userId) async {
    await _client
        .from(_table)
        .delete()
        .eq('session_id', sessionId)
        .eq('user_id', userId);
  }

  // ── Broadcast Messages ─────────────────────────────────────────────────────

  /// Send a broadcast alert to all members of a session.
  Future<void> sendBroadcast({
    required String sessionId,
    required String senderName,
    required String message,
  }) async {
    await _client.from(_broadcastTable).insert({
      'session_id': sessionId,
      'sender_name': senderName,
      'message': message,
    });
  }

  /// Stream broadcast messages for a session, newest first.
  Stream<List<BroadcastMessage>> streamBroadcasts(String sessionId) {
    final controller = StreamController<List<BroadcastMessage>>.broadcast();

    _fetchBroadcasts(sessionId).then((msgs) {
      if (!controller.isClosed) controller.add(msgs);
    });

    final channel = _client
        .channel('broadcasts:$sessionId')
        .onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: _broadcastTable,
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'session_id',
        value: sessionId,
      ),
      callback: (_) {
        _fetchBroadcasts(sessionId).then((msgs) {
          if (!controller.isClosed) controller.add(msgs);
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

  Future<List<BroadcastMessage>> _fetchBroadcasts(String sessionId) async {
    final data = await _client
        .from(_broadcastTable)
        .select()
        .eq('session_id', sessionId)
        .order('created_at', ascending: false)
        .limit(20);
    return (data as List)
        .map((r) => BroadcastMessage.fromSupabase(r))
        .toList();
  }
}