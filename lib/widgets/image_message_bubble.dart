import 'package:flutter/material.dart';

// Miniature d'un message image, avec ouverture en plein écran au tap
// (zoom via InteractiveViewer).
class ImageMessageBubble extends StatelessWidget {
  final String imageUrl;

  const ImageMessageBubble({super.key, required this.imageUrl});

  void _openFullScreen(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        pageBuilder: (context, _, __) => GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: Center(
              child: InteractiveViewer(
                child: Image.network(imageUrl, fit: BoxFit.contain),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _openFullScreen(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220, maxHeight: 220),
          child: Image.network(
            imageUrl,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return const SizedBox(
                width: 180,
                height: 180,
                child: Center(
                  child: CircularProgressIndicator(color: Color(0xFF2AABEE)),
                ),
              );
            },
            errorBuilder: (context, error, stackTrace) => const SizedBox(
              width: 180,
              height: 120,
              child: Center(
                child: Icon(Icons.broken_image, color: Colors.grey),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
