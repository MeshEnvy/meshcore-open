import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

class ImageUploadService {
  static const String _baseUrl = 'https://mas.meshenvy.org';
  static const int _maxDimension = 2048;

  final _picker = ImagePicker();

  /// Picks an image from the gallery and uploads it to the worker.
  /// Returns the image hash if successful, null otherwise.
  Future<String?> pickAndUploadImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        // Hint to the picker to already do some initial resizing if supported
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

  /// Processes and uploads raw image bytes to the worker.
  /// Resizes to max 2048px and converts to WebP.
  /// Returns the image hash if successful, null otherwise.
  Future<String?> uploadImage(Uint8List bytes, {String? mimeType}) async {
    try {
      // 1. Process image client-side: Resize and convert to WebP
      final processedBytes = await processImage(bytes);

      // 2. Upload processed image
      final response = await http.post(
        Uri.parse(_baseUrl),
        body: processedBytes,
        headers: {'Content-Type': 'image/jpeg'},
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

  /// Resizes an image to max 2048px and converts to WebP.
  static Future<Uint8List> processImage(Uint8List bytes) async {
    try {
      // Decode image
      img.Image? image = img.decodeImage(bytes);
      if (image == null) {
        debugPrint('Error: Could not decode image');
        return bytes;
      }

      // Resize if necessary
      if (image.width > _maxDimension || image.height > _maxDimension) {
        if (image.width > image.height) {
          image = img.copyResize(image, width: _maxDimension);
        } else {
          image = img.copyResize(image, height: _maxDimension);
        }
      }

      // Convert to JPEG for upload (pure Dart supports this; Cloudflare Worker will convert to WebP)
      return Uint8List.fromList(img.encodeJpg(image, quality: 85));
    } catch (e) {
      debugPrint('Error processing image: $e');
      return bytes; // Return original if processing fails
    }
  }

  /// Returns the full image URL for a given hash.
  static String getImageUrl(String hash) {
    return '$_baseUrl/$hash';
  }
}
