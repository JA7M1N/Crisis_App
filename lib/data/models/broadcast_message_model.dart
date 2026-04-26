class BroadcastMessage {
  final String id;
  final String sessionId;
  final String senderName;
  final String message;
  final DateTime createdAt;

  const BroadcastMessage({
    required this.id,
    required this.sessionId,
    required this.senderName,
    required this.message,
    required this.createdAt,
  });

  factory BroadcastMessage.fromSupabase(Map<dynamic, dynamic> row) {
    return BroadcastMessage(
      id: row['id'] ?? '',
      sessionId: row['session_id'] ?? '',
      senderName: row['sender_name'] ?? 'Coordinator',
      message: row['message'] ?? '',
      createdAt: DateTime.tryParse(row['created_at'] ?? '') ?? DateTime.now(),
    );
  }

  /// Relative time label e.g. "just now", "3 min ago"
  String get timeLabel {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes == 1) return '1 min ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    return '${diff.inHours}h ago';
  }
}