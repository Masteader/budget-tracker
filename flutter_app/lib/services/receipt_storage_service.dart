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
}
