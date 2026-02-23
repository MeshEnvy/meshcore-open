import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart';

class ImageUploadService {
  static const String _baseUrl = 'https://mas.meshenvy.org';

  final _picker = ImagePicker();

  /// Picks an image from the gallery and uploads it to the worker.
  /// Returns the image hash if successful, null otherwise.
  Future<String?> pickAndUploadImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        // We don't need to limit size here as the worker handles it,
        // but limiting to something reasonable can save user bandwidth/time.
        maxWidth: 4096,
        maxHeight: 4096,
        imageQuality: 85,
      );

      if (image == null) return null;

      final bytes = await image.readAsBytes();
      return await uploadImage(bytes, mimeType: image.mimeType);
    } catch (e) {
      debugPrint('Error picking image: $e');
      return null;
    }
  }

  /// Uploads raw image bytes to the worker.
  /// Returns the image hash if successful, null otherwise.
  Future<String?> uploadImage(Uint8List bytes, {String? mimeType}) async {
    try {
      final response = await http.post(
        Uri.parse(_baseUrl),
        body: bytes,
        headers: {'Content-Type': mimeType ?? 'image/jpeg'},
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);
        return data['hash'] as String?;
      } else {
        debugPrint('Upload failed with status: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('Error uploading image: $e');
      return null;
    }
  }

  /// Returns the full image URL for a given hash.
  static String getImageUrl(String hash) {
    return '$_baseUrl/$hash';
  }
}
