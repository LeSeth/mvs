import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

// Bouton trombone partagé entre le chat privé et le chat de groupe.
// Ouvre une feuille avec 3 choix : Galerie, Appareil photo, Fichier.
// Limite volontaire de 20 Mo par pièce jointe (coût des données mobiles).
class AttachmentPickerButton extends StatelessWidget {
  final void Function(Uint8List bytes, String extension) onImagePicked;
  final void Function(Uint8List bytes, String fileName, int sizeBytes)
  onFilePicked;

  static const int _maxSizeBytes = 20 * 1024 * 1024;

  const AttachmentPickerButton({
    super.key,
    required this.onImagePicked,
    required this.onFilePicked,
  });

  Future<void> _pickImage(BuildContext context, ImageSource source) async {
    Navigator.pop(context);

    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1600,
        maxHeight: 1600,
      );

      if (image == null) return;

      final bytes = await image.readAsBytes();

      if (bytes.lengthInBytes > _maxSizeBytes) {
        _showTooLarge(context);
        return;
      }

      final extension = image.path.toLowerCase().endsWith('.png')
          ? 'png'
          : 'jpg';

      onImagePicked(bytes, extension);
    } catch (e) {
      debugPrint('Erreur sélection image: $e');
    }
  }

  Future<void> _pickFile(BuildContext context) async {
    Navigator.pop(context);

    try {
      final result = await FilePicker.platform.pickFiles(withData: true);
      if (result == null || result.files.isEmpty) return;

      final picked = result.files.single;
      final bytes = picked.bytes;

      if (bytes == null) return;

      if (bytes.lengthInBytes > _maxSizeBytes) {
        _showTooLarge(context);
        return;
      }

      onFilePicked(bytes, picked.name, bytes.lengthInBytes);
    } catch (e) {
      debugPrint('Erreur sélection fichier: $e');
    }
  }

  void _showTooLarge(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Fichier trop volumineux (max 20 Mo).')),
    );
  }

  void _showSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1F2C34),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(
                Icons.photo_library,
                color: Color(0xFF2AABEE),
              ),
              title: const Text(
                'Galerie',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () => _pickImage(sheetContext, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Color(0xFF2AABEE)),
              title: const Text(
                'Appareil photo',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () => _pickImage(sheetContext, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(
                Icons.insert_drive_file,
                color: Color(0xFF2AABEE),
              ),
              title: const Text(
                'Fichier',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () => _pickFile(sheetContext),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.attach_file, color: Colors.grey),
      onPressed: () => _showSheet(context),
    );
  }
}
