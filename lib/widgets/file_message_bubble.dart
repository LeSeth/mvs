import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

// Bulle d'un message fichier : icône selon l'extension, nom, taille
// formatée, et ouverture dans une app externe au tap.
class FileMessageBubble extends StatelessWidget {
  final String fileUrl;
  final String fileName;
  final int? fileSize;
  final Color foregroundColor;

  const FileMessageBubble({
    super.key,
    required this.fileUrl,
    required this.fileName,
    this.fileSize,
    this.foregroundColor = Colors.white,
  });

  IconData get _icon {
    final ext = fileName.toLowerCase().split('.').last;
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'xls':
      case 'xlsx':
        return Icons.grid_on;
      case 'ppt':
      case 'pptx':
        return Icons.slideshow;
      case 'zip':
      case 'rar':
        return Icons.folder_zip;
      default:
        return Icons.insert_drive_file;
    }
  }

  String get _sizeLabel {
    final size = fileSize;
    if (size == null) return '';
    if (size < 1024) return '$size o';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(0)} Ko';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} Mo';
  }

  Future<void> _open(BuildContext context) async {
    final uri = Uri.tryParse(fileUrl);
    if (uri == null) return;

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);

    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Impossible d'ouvrir ce fichier.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _open(context),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 220,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(_icon, color: foregroundColor, size: 32),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: foregroundColor, fontSize: 14),
                  ),
                  if (_sizeLabel.isNotEmpty)
                    Text(
                      _sizeLabel,
                      style: TextStyle(
                        color: foregroundColor.withOpacity(0.7),
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
            Icon(
              Icons.file_download_outlined,
              color: foregroundColor.withOpacity(0.8),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
