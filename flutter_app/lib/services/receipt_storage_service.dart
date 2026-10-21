import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class ReceiptStorageService {
  final SupabaseClient? _client;
  static const String bucketName = 'receipts';

  // In-memory cache for signed URLs to minimize Supabase Storage API requests
  static final Map<String, ({String url, DateTime expiresAt})> _signedUrlCache = {};

  ReceiptStorageService({SupabaseClient? client}) : _client = client;

  SupabaseClient? get _supabase {
    if (_client != null) return _client;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  /// Number of cached signed URLs (exposed for tests).
  @visibleForTesting
  static int get cachedSignedUrlCount => _signedUrlCache.length;

  /// Drops every cached signed URL (they are bearer links to receipts).
  static void clearSignedUrlCache() => _signedUrlCache.clear();

  static String generateStoragePath(String householdId, String originalFileName) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final uuid = const Uuid().v4().substring(0, 8);
    final ext = originalFileName.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
    return '$householdId/${timestamp}_$uuid.$ext';
  }

  /// Uploads a receipt image to Supabase Storage and returns its relative storage path.
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

      final client = _supabase;
      if (client == null) {
        debugPrint('[ReceiptStorageService] Supabase client unavailable for upload.');
        return null;
      }

      final path = generateStoragePath(householdId, imageFile.path);

      await client.storage.from(bucketName).uploadBinary(
        path,
        bytes,
        fileOptions: const FileOptions(
          contentType: 'image/jpeg',
          upsert: true,
        ),
      );

      debugPrint('[ReceiptStorageService] Uploaded receipt to storage path: $path');
      return path;
    } catch (e) {
      debugPrint('[ReceiptStorageService] Failed to upload receipt image: $e');
      return null;
    }
  }

  /// Extracts relative storage path inside the bucket from a public URL, signed URL, or raw path.
  /// Handles:
  /// - https://.../storage/v1/object/public/receipts/hh-123/img.jpg -> hh-123/img.jpg
  /// - https://.../storage/v1/object/sign/receipts/hh-123/img.jpg?token=... -> hh-123/img.jpg
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

  /// Obtains a short-lived signed URL for viewing a receipt image.
  /// Works with storage paths (`hh-123/file.jpg`) and legacy URLs.
  /// Uses an in-memory TTL cache to minimize network calls.
  Future<String?> getSignedReceiptUrl(
    String? receiptPathOrUrl, {
    int expiresInSeconds = 3600,
  }) async {
    if (receiptPathOrUrl == null) return null;
    final trimmed = receiptPathOrUrl.trim();
    if (trimmed.isEmpty) return null;

    // Stored signed URLs (legacy rows) are re-signed from their storage path:
    // their embedded token has a fixed expiry and would eventually 400.
    final path = extractStoragePath(trimmed);
    // If not a path belonging to our receipts bucket, return the original URL
    if (path == null) {
      return trimmed.startsWith('http') ? trimmed : null;
    }

    // Check memory cache
    final cached = _signedUrlCache[path];
    final now = DateTime.now();
    if (cached != null && cached.expiresAt.isAfter(now.add(const Duration(minutes: 5)))) {
      return cached.url;
    }

    final client = _supabase;
    if (client == null) {
      // No Supabase client (tests, before init): return the original if it is a full URL, or null
      return trimmed.startsWith('http') ? trimmed : null;
    }

    try {
      final signedUrl = await client.storage.from(bucketName).createSignedUrl(
        path,
        expiresInSeconds,
      );
      _signedUrlCache.removeWhere((_, entry) => !entry.expiresAt.isAfter(now));
      _signedUrlCache[path] = (
        url: signedUrl,
        expiresAt: now.add(Duration(seconds: expiresInSeconds)),
      );
      return signedUrl;
    } catch (e) {
      debugPrint('[ReceiptStorageService] Failed to create signed URL: $e');
      // The bucket is private: a stored public/expired URL cannot work, and a
      // relative path is not a URL. Let the viewer show its error state.
      return null;
    }
  }

  /// Deletes a receipt image from Supabase Storage by its public URL, signed URL, or storage path.
  /// Gracefully catches exceptions and returns false if removal fails so app workflow continues.
  Future<bool> deleteReceiptByUrl(String receiptUrl) async {
    try {
      final path = extractStoragePath(receiptUrl);
      if (path == null) return false;

      final client = _supabase;
      if (client == null) return false;

      await client.storage.from(bucketName).remove([path]);
      _signedUrlCache.remove(path);
      debugPrint('[ReceiptStorageService] Deleted receipt from storage: $path');
      return true;
    } catch (e) {
      debugPrint('[ReceiptStorageService] Failed to delete receipt from storage: $e');
      return false;
    }
  }
}
