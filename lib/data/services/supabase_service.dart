import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sankatmitra/data/models/user_model.dart';

/// SupabaseService — real-time backend replacing Firebase.
///
/// SQL to run in Supabase SQL Editor (one-time setup):
/// ─────────────────────────────────────────────────────
/// create table if not exists session_users (
///   user_id     text not null,
///   session_id  text not null,
///   name        text not null default '',
///   role        text not null default 'victim',
///   lat         double precision not null default 0,
///   lng         double precision not null default 0,
///   timestamp   bigint not null,
///   is_sos      boolean not null default false,
///   priority    text not null default '',
///   updated_at  timestamptz not null default now(),
///   primary key (session_id, user_id)
/// );
/// alter table session_users enable row level security;
/// create policy "allow all" on session_users for all using (true) with check (true);
/// alter publication supabase_realtime add table session_users;
/// ─────────────────────────────────────────────────────

class SupabaseService {
  static final SupabaseService _instance = SupabaseService._internal();
  factory SupabaseService() => _instance;
  SupabaseService._internal();

  final SupabaseClient _client = Supabase.instance.client;
  static const _table = 'session_users';

  /// Upsert user location + name + priority
  Future<void> updateUserLocation({
    required String sessionId,
    required String userId,
    required String name,
    required double lat,
    required double lng,
    required UserRole role,
    bool isSOS = false,
    String priority = '',
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
}