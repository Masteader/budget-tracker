import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class ReceiptStorageService {
  final SupabaseClient? _client;
  static const String bucketName = 'receipts';

  ReceiptStorageService({SupabaseClient? client}) : _client = client;

  SupabaseClient get _supabase => _client ?? Supabase.instance.client;

  static String generateStoragePath(String householdId, String originalFileName) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final uuid = const Uuid().v4().substring(0, 8);
    final ext = originalFileName.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
    return '$householdId/${timestamp}_$uuid.$ext';
  }

  /// Uploads a receipt image to Supabase Storage and returns its public URL.
  /// Gracefully catches exceptions and returns null so financial saves are never blocked.
  Future<String?> uploadReceipt({
    required File imageFile,
    required String householdId,
  }) async {
    try {
      if (!await imageFile.exists()) {
        debugPrint('[ReceiptStorageService] Image file does not exist: ${imageFile.path}');
        return null;
      }

      final Uint8List bytes = await imageFile.readAsBytes();
      if (bytes.isEmpty) return null;

      final path = generateStoragePath(householdId, imageFile.path);

      await _supabase.storage.from(bucketName).uploadBinary(
        path,
        bytes,
        fileOptions: const FileOptions(
          contentType: 'image/jpeg',
          upsert: true,
        ),
      );

      final publicUrl = _supabase.storage.from(bucketName).getPublicUrl(path);
      debugPrint('[ReceiptStorageService] Uploaded receipt to: $publicUrl');
      return publicUrl;
    } catch (e) {
      debugPrint('[ReceiptStorageService] Failed to upload receipt image: $e');
      return null;
    }
  }

  /// Extracts relative storage path inside the bucket from a public URL or raw path.
  /// Handles:
  /// - https://.../storage/v1/object/public/receipts/hh-123/img.jpg -> hh-123/img.jpg
  /// - hh-123/img.jpg -> hh-123/img.jpg
  static String? extractStoragePath(String receiptUrl) {
    final trimmed = receiptUrl.trim();
    if (trimmed.isEmpty) return null;
    try {
      if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
        return trimmed;
      }
      final uri = Uri.parse(trimmed);
      final segments = uri.pathSegments;
      final idx = segments.indexOf(bucketName);
      if (idx != -1 && idx + 1 < segments.length) {
        return segments.sublist(idx + 1).join('/');
      }
    } catch (e) {
      debugPrint('[ReceiptStorageService] Error extracting storage path: $e');
    }
    return null;
  }

  /// Deletes a receipt image from Supabase Storage by its public URL or storage path.
  /// Gracefully catches exceptions and returns false if removal fails so app workflow continues.
  Future<bool> deleteReceiptByUrl(String receiptUrl) async {
    try {
      final path = extractStoragePath(receiptUrl);
      if (path == null) return false;

      await _supabase.storage.from(bucketName).remove([path]);
      debugPrint('[ReceiptStorageService] Deleted receipt from storage: $path');
      return true;
    } catch (e) {
      debugPrint('[ReceiptStorageService] Failed to delete receipt from storage: $e');
      return false;
    }
  }
}
