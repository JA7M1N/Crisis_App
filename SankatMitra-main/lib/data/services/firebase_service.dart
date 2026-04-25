import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:sankatmitra/data/models/user_model.dart';

class FirebaseService {
  static final FirebaseService _instance = FirebaseService._internal();
  factory FirebaseService() => _instance;
  FirebaseService._internal();

  final FirebaseDatabase _db = FirebaseDatabase.instance;

  /// Push or update user location under sessions/{sessionId}/users/{userId}
  Future<void> updateUserLocation({
    required String sessionId,
    required String userId,
    required double lat,
    required double lng,
    required UserRole role,
    bool isSOS = false,
  }) async {
    try {
      final ref = _db.ref('sessions/$sessionId/users/$userId');
      await ref.set({
        'sessionId': sessionId,
        'role': role.name,
        'lat': lat,
        'lng': lng,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'isSOS': isSOS,
      });
    } catch (e) {
      rethrow;
    }
  }

  /// Stream all users in a session
  Stream<List<UserModel>> streamSessionUsers(String sessionId) {
    final ref = _db.ref('sessions/$sessionId/users');
    return ref.onValue.map((event) {
      final data = event.snapshot.value;
      if (data == null) return <UserModel>[];
      final map = data as Map<dynamic, dynamic>;
      return map.entries
          .map((e) => UserModel.fromMap(e.key as String, e.value as Map))
          .toList();
    });
  }

  /// Stream all active sessions (for coordinator)
  Stream<List<UserModel>> streamAllUsers() {
    final ref = _db.ref('sessions');
    return ref.onValue.map((event) {
      final data = event.snapshot.value;
      if (data == null) return <UserModel>[];
      final sessions = data as Map<dynamic, dynamic>;
      final users = <UserModel>[];
      sessions.forEach((sessionId, sessionData) {
        if (sessionData is Map && sessionData['users'] != null) {
          final usersMap = sessionData['users'] as Map<dynamic, dynamic>;
          usersMap.forEach((userId, userData) {
            if (userData is Map) {
              users.add(UserModel.fromMap(userId as String, userData));
            }
          });
        }
      });
      return users;
    });
  }

  /// Remove user from session on disconnect
  void onDisconnectRemove(String sessionId, String userId) {
    final ref = _db.ref('sessions/$sessionId/users/$userId');
    ref.onDisconnect().remove();
  }

  /// Remove user manually
  Future<void> removeUser(String sessionId, String userId) async {
    await _db.ref('sessions/$sessionId/users/$userId').remove();
  }
}
