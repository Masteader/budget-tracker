import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Represents a queued offline operation with idempotency tracking and retry metadata.
class OfflineQueueItem {
  final String id;
  final String operationType; // 'receipt', 'chat', 'manual'
  final Map<String, dynamic> payload;
  final String householdId;
  final String idempotencyKey;
  final String status; // 'pending', 'syncing', 'failed'
  final int retryCount;
  final DateTime createdAt;
  final String? lastError;

  OfflineQueueItem({
    required this.id,
    required this.operationType,
    required this.payload,
    required this.householdId,
    required this.idempotencyKey,
    this.status = 'pending',
    this.retryCount = 0,
    required this.createdAt,
    this.lastError,
  });

  /// Computes a deterministic SHA-256 fingerprint for the given operation
  static String generateIdempotencyKey({
    required String operationType,
    required String householdId,
    required Map<String, dynamic> payload,
  }) {
    // Sort keys recursively for canonical JSON representation
    final sortedPayload = _canonicalizeMap(payload);
    final raw = '$operationType:$householdId:${jsonEncode(sortedPayload)}';
    return sha256.convert(utf8.encode(raw)).toString();
  }

  static Map<String, dynamic> _canonicalizeMap(Map<String, dynamic> map) {
    final sortedKeys = map.keys.toList()..sort();
    final result = <String, dynamic>{};
    for (final k in sortedKeys) {
      final v = map[k];
      if (v is Map<String, dynamic>) {
        result[k] = _canonicalizeMap(v);
      } else {
        result[k] = v;
      }
    }
    return result;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'operation_type': operationType,
      'payload': jsonEncode(payload),
      'household_id': householdId,
      'idempotency_key': idempotencyKey,
      'status': status,
      'retry_count': retryCount,
      'created_at': createdAt.toIso8601String(),
      'last_error': lastError,
    };
  }

  factory OfflineQueueItem.fromMap(Map<String, dynamic> map) {
    Map<String, dynamic> parsedPayload = {};
    if (map['payload'] != null) {
      if (map['payload'] is String) {
        try {
          parsedPayload = Map<String, dynamic>.from(jsonDecode(map['payload'] as String) as Map);
        } catch (_) {}
      } else if (map['payload'] is Map) {
        parsedPayload = Map<String, dynamic>.from(map['payload'] as Map);
      }
    }

    return OfflineQueueItem(
      id: map['id']?.toString() ?? '',
      operationType: map['operation_type'] as String? ?? 'receipt',
      payload: parsedPayload,
      householdId: map['household_id'] as String? ?? '',
      idempotencyKey: map['idempotency_key'] as String? ?? '',
      status: map['status'] as String? ?? 'pending',
      retryCount: (map['retry_count'] as num?)?.toInt() ?? 0,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      lastError: map['last_error'] as String?,
    );
  }

  OfflineQueueItem copyWith({
    String? id,
    String? operationType,
    Map<String, dynamic>? payload,
    String? householdId,
    String? idempotencyKey,
    String? status,
    int? retryCount,
    DateTime? createdAt,
    String? lastError,
  }) {
    return OfflineQueueItem(
      id: id ?? this.id,
      operationType: operationType ?? this.operationType,
      payload: payload ?? this.payload,
      householdId: householdId ?? this.householdId,
      idempotencyKey: idempotencyKey ?? this.idempotencyKey,
      status: status ?? this.status,
      retryCount: retryCount ?? this.retryCount,
      createdAt: createdAt ?? this.createdAt,
      lastError: lastError ?? this.lastError,
    );
  }
}
