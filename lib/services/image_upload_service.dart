import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import '../models/channel.dart';
import '../models/contact.dart';
import '../models/protos/mas.pb.dart';
import '../utils/asset_encoder.dart';

class ImageUploadService {
  static const String _baseUrl = 'https://mas.meshenvy.org';
  static const int _maxDimension = 2048;

  final _picker = ImagePicker();

  /// Picks an image from the gallery and uploads it to the worker.
  /// Returns the image hash if successful, null otherwise.
  Future<String?> pickAndUploadImage({
    Channel? channel,
    Contact? contact,
    required Uint8List secretKey,
  }) async {
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
      return await uploadImage(
        bytes,
        mimeType: image.mimeType,
        channel: channel,
        contact: contact,
        secretKey: secretKey,
      );
    } catch (e) {
      debugPrint('Error picking image: $e');
      return null;
    }
  }

  /// Processes and uploads raw image bytes to the worker.
  /// Resizes to max 2048px and converts to WebP.
  /// Returns the image hash if successful, null otherwise.
  Future<String?> uploadImage(
    Uint8List bytes, {
    String? mimeType,
    Channel? channel,
    Contact? contact,
    required Uint8List secretKey,
    Uint8List? selfPublicKey,
  }) async {
    try {
      // 1. Process image client-side: Resize and convert to WebP
      final processedBytes = await processImage(bytes);

      // 2. Wrap in AssetBlob
      final assetType = channel != null ? AssetType.CHANNEL : AssetType.DM;
      final contentType = mimeType ?? 'image/jpeg';
      final fileName = 'upload_${DateTime.now().millisecondsSinceEpoch}.jpg';

      final recipientPks = <Uint8List>[];
      if (contact != null) {
        recipientPks.add(contact.publicKey);
      }
      if (selfPublicKey != null) {
        recipientPks.add(selfPublicKey);
      }

      final blobBytes = await AssetEncoder.encode(
        type: assetType,
        contentType: contentType,
        filename: fileName,
        rawData: processedBytes,
        secretKey: secretKey,
        recipientPublicKeys: recipientPks,
      );

      // 3. Upload processed image (as octet-stream for AssetBlob)
      final response = await http.post(
        Uri.parse(_baseUrl),
        body: blobBytes,
        headers: {'Content-Type': 'application/octet-stream'},
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint(
          'ImageUploadService: Upload successful, response: ${response.body}',
        );
        final data = json.decode(response.body);
        return data['hash'] as String?;
      } else {
        debugPrint(
          'ImageUploadService: Upload failed with status: ${response.statusCode}, body: ${response.body}',
        );
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
