class AuditLogEntry {
  final String id;
  final String action;
  final String actorUid;
  final String actorRole;
  final String organizationId;
  final String targetId;
  final String description;
  final DateTime timestamp;
  final Map<String, dynamic> metadata;

  const AuditLogEntry({
    required this.id,
    required this.action,
    required this.actorUid,
    required this.actorRole,
    required this.organizationId,
    required this.targetId,
    required this.description,
    required this.timestamp,
    this.metadata = const {},
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'action': action,
        'actorUid': actorUid,
        'actorRole': actorRole,
        'organizationId': organizationId,
        'targetId': targetId,
        'description': description,
        'timestamp': timestamp.toIso8601String(),
        'metadata': metadata,
      };

  factory AuditLogEntry.fromJson(Map<String, dynamic> json) => AuditLogEntry(
        id: json['id'] as String? ?? '',
        action: json['action'] as String? ?? 'general_event',
        actorUid: json['actorUid'] as String? ?? '',
        actorRole: json['actorRole'] as String? ?? 'user',
        organizationId: json['organizationId'] as String? ?? '',
        targetId: json['targetId'] as String? ?? '',
        description: json['description'] as String? ?? '',
        timestamp: json['timestamp'] != null
            ? DateTime.tryParse(json['timestamp'].toString()) ?? DateTime.now()
            : DateTime.now(),
        metadata: json['metadata'] is Map
            ? Map<String, dynamic>.from(json['metadata'] as Map)
            : const {},
      );
}
