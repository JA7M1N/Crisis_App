enum UserRole { victim, responder, coordinator }

class UserModel {
  final String userId;
  final String sessionId;
  final UserRole role;
  final double lat;
  final double lng;
  final int timestamp;
  final bool isSOS;

  const UserModel({
    required this.userId,
    required this.sessionId,
    required this.role,
    required this.lat,
    required this.lng,
    required this.timestamp,
    this.isSOS = false,
  });

  factory UserModel.fromMap(String userId, Map<dynamic, dynamic> map) {
    return UserModel(
      userId: userId,
      sessionId: map['sessionId'] ?? '',
      role: _roleFromString(map['role'] ?? 'victim'),
      lat: (map['lat'] ?? 0.0).toDouble(),
      lng: (map['lng'] ?? 0.0).toDouble(),
      timestamp: map['timestamp'] ?? 0,
      isSOS: map['isSOS'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'sessionId': sessionId,
      'role': role.name,
      'lat': lat,
      'lng': lng,
      'timestamp': timestamp,
      'isSOS': isSOS,
    };
  }

  UserModel copyWith({
    String? userId,
    String? sessionId,
    UserRole? role,
    double? lat,
    double? lng,
    int? timestamp,
    bool? isSOS,
  }) {
    return UserModel(
      userId: userId ?? this.userId,
      sessionId: sessionId ?? this.sessionId,
      role: role ?? this.role,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      timestamp: timestamp ?? this.timestamp,
      isSOS: isSOS ?? this.isSOS,
    );
  }

  static UserRole _roleFromString(String role) {
    switch (role) {
      case 'responder':
        return UserRole.responder;
      case 'coordinator':
        return UserRole.coordinator;
      default:
        return UserRole.victim;
    }
  }
}
