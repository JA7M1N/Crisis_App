enum UserRole { victim, responder, coordinator }

class UserModel {
  final String userId;
  final String sessionId;
  final String name;        // NEW: display name / callsign
  final UserRole role;
  final double lat;
  final double lng;
  final int timestamp;
  final bool isSOS;
  final String priority;    // NEW: AI triage result — 'P0','P1','P2','P3',''

  const UserModel({
    required this.userId,
    required this.sessionId,
    this.name = '',
    required this.role,
    required this.lat,
    required this.lng,
    required this.timestamp,
    this.isSOS = false,
    this.priority = '',
  });

  factory UserModel.fromMap(String userId, Map<dynamic, dynamic> map) {
    return UserModel(
      userId: userId,
      sessionId: map['sessionId'] ?? '',
      name: map['name'] ?? '',
      role: _roleFromString(map['role'] ?? 'victim'),
      lat: (map['lat'] ?? 0.0).toDouble(),
      lng: (map['lng'] ?? 0.0).toDouble(),
      timestamp: map['timestamp'] ?? 0,
      isSOS: map['isSOS'] ?? false,
      priority: map['priority'] ?? '',
    );
  }

  factory UserModel.fromSupabase(Map<dynamic, dynamic> row) {
    return UserModel(
      userId: row['user_id'] ?? '',
      sessionId: row['session_id'] ?? '',
      name: row['name'] ?? '',
      role: _roleFromString(row['role'] ?? 'victim'),
      lat: (row['lat'] ?? 0.0).toDouble(),
      lng: (row['lng'] ?? 0.0).toDouble(),
      timestamp: row['timestamp'] ?? 0,
      isSOS: row['is_sos'] ?? false,
      priority: row['priority'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'sessionId': sessionId,
      'name': name,
      'role': role.name,
      'lat': lat,
      'lng': lng,
      'timestamp': timestamp,
      'isSOS': isSOS,
      'priority': priority,
    };
  }

  UserModel copyWith({
    String? userId,
    String? sessionId,
    String? name,
    UserRole? role,
    double? lat,
    double? lng,
    int? timestamp,
    bool? isSOS,
    String? priority,
  }) {
    return UserModel(
      userId: userId ?? this.userId,
      sessionId: sessionId ?? this.sessionId,
      name: name ?? this.name,
      role: role ?? this.role,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      timestamp: timestamp ?? this.timestamp,
      isSOS: isSOS ?? this.isSOS,
      priority: priority ?? this.priority,
    );
  }

  /// Human-readable display name — falls back to shortened userId
  String get displayName {
    if (name.isNotEmpty) return name;
    return 'User-${userId.length > 6 ? userId.substring(userId.length - 6) : userId}';
  }

  static UserRole _roleFromString(String role) {
    switch (role) {
      case 'responder': return UserRole.responder;
      case 'coordinator': return UserRole.coordinator;
      default: return UserRole.victim;
    }
  }
}