enum UserRole { victim, responder, coordinator }

class UserModel {
  final String userId;
  final String sessionId;
  final String name;
  final UserRole role;
  final double lat;
  final double lng;
  final int timestamp;
  final bool isSOS;
  final String priority;    // AI triage: 'P0','P1','P2','P3',''
  final bool onMyWay;       // NEW: responder tapped "I'm on my way"
  final String onMyWayTo;   // NEW: userId of the victim being navigated to

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
    this.onMyWay = false,
    this.onMyWayTo = '',
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
      onMyWay: map['onMyWay'] ?? false,
      onMyWayTo: map['onMyWayTo'] ?? '',
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
      onMyWay: row['on_my_way'] ?? false,
      onMyWayTo: row['on_my_way_to'] ?? '',
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
      'onMyWay': onMyWay,
      'onMyWayTo': onMyWayTo,
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
    bool? onMyWay,
    String? onMyWayTo,
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
      onMyWay: onMyWay ?? this.onMyWay,
      onMyWayTo: onMyWayTo ?? this.onMyWayTo,
    );
  }

  String get displayName {
    if (name.isNotEmpty) return name;
    return 'User-${userId.length > 6 ? userId.substring(userId.length - 6) : userId}';
  }

  /// Seconds since last location update
  int get secondsSinceUpdate {
    final now = DateTime.now().millisecondsSinceEpoch;
    return ((now - timestamp) / 1000).round();
  }

  /// "X min ago" string
  String get lastSeenLabel {
    final secs = secondsSinceUpdate;
    if (secs < 10) return 'just now';
    if (secs < 60) return '${secs}s ago';
    final mins = (secs / 60).round();
    if (mins < 60) return '${mins}m ago';
    return '${(mins / 60).round()}h ago';
  }

  static UserRole _roleFromString(String role) {
    switch (role) {
      case 'responder':   return UserRole.responder;
      case 'coordinator': return UserRole.coordinator;
      default:            return UserRole.victim;
    }
  }
}
