import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/image_upload_service.dart';

class ImageMessage extends StatelessWidget {
  final String hash;
  final Color backgroundColor;
  final Color fallbackTextColor;
  final double maxSize;
  final Uint8List? localBytes;

  const ImageMessage({
    super.key,
    required this.hash,
    required this.backgroundColor,
    required this.fallbackTextColor,
    this.maxSize = 250,
    this.localBytes,
  });

  @override
  Widget build(BuildContext context) {
    final imageUrl = ImageUploadService.getImageUrl(hash);

    return GestureDetector(
      onTap: () => _showFullScreenImage(context, imageUrl),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          color: backgroundColor,
          constraints: BoxConstraints(maxWidth: maxSize, maxHeight: maxSize),
          child: localBytes != null
              ? Image.memory(localBytes!, fit: BoxFit.contain)
              : CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.contain,
                  placeholder: (context, url) => Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          fallbackTextColor.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                  ),
                  errorWidget: (context, url, error) => Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.broken_image,
                          color: fallbackTextColor,
                          size: 32,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Failed to load image',
                          style: TextStyle(
                            color: fallbackTextColor,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  void _showFullScreenImage(BuildContext context, String imageUrl) {
    showDialog(
      context: context,
      builder: (context) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: Center(
                child: localBytes != null
                    ? Image.memory(localBytes!, fit: BoxFit.contain)
                    : CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.contain,
                        placeholder: (context, url) =>
                            const CircularProgressIndicator(),
                      ),
              ),
            ),
            Positioned(
              top: 40,
              right: 20,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
