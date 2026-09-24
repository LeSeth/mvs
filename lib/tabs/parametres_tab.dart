import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/supabase_service.dart';

class ParametresTab extends StatefulWidget {
  final String pseudo;
  final String userId;

  const ParametresTab({super.key, required this.pseudo, required this.userId});

  @override
  State<ParametresTab> createState() => _ParametresTabState();
}

class _ParametresTabState extends State<ParametresTab> {
  final ImagePicker _picker = ImagePicker();

  String? _avatarUrl;
  bool _isLoadingAvatar = true;
  bool _isUploading = false;

  // Avatars Notionists : hommes et femmes
  final List<String> _predefinedAvatars = [
    'https://api.dicebear.com/9.x/notionists/png?seed=Alex',
    'https://api.dicebear.com/9.x/notionists/png?seed=Sarah',
    'https://api.dicebear.com/9.x/notionists/png?seed=David',
    'https://api.dicebear.com/9.x/notionists/png?seed=Emma',
    'https://api.dicebear.com/9.x/notionists/png?seed=Michael',
    'https://api.dicebear.com/9.x/notionists/png?seed=Sophia',
    'https://api.dicebear.com/9.x/notionists/png?seed=Daniel',
    'https://api.dicebear.com/9.x/notionists/png?seed=Olivia',
    'https://api.dicebear.com/9.x/notionists/png?seed=James',
    'https://api.dicebear.com/9.x/notionists/png?seed=Amelia',
    'https://api.dicebear.com/9.x/notionists/png?seed=Lucas',
    'https://api.dicebear.com/9.x/notionists/png?seed=Isabella',
    'https://api.dicebear.com/9.x/notionists/png?seed=Thomas',
    'https://api.dicebear.com/9.x/notionists/png?seed=Mia',
    'https://api.dicebear.com/9.x/notionists/png?seed=William',
    'https://api.dicebear.com/9.x/notionists/png?seed=Charlotte',
    'https://api.dicebear.com/9.x/notionists/png?seed=Henry',
    'https://api.dicebear.com/9.x/notionists/png?seed=Grace',
    'https://api.dicebear.com/9.x/notionists/png?seed=Samuel',
    'https://api.dicebear.com/9.x/notionists/png?seed=Chloe',
  ];

  @override
  void initState() {
    super.initState();
    _loadAvatar();
  }

  Future<void> _loadAvatar() async {
    final avatarUrl = await SupabaseService.getAvatarUrl(widget.userId);

    if (!mounted) return;

    setState(() {
      _avatarUrl = avatarUrl;
      _isLoadingAvatar = false;
    });
  }

  Future<void> _showAvatarOptions() async {
    if (_isUploading) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1F2C34),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              const Text(
                'Photo de profil',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 15),

              ListTile(
                leading: const Icon(Icons.face, color: Color(0xFF2AABEE)),
                title: const Text(
                  'Choisir un avatar',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showPredefinedAvatars();
                },
              ),

              ListTile(
                leading: const Icon(
                  Icons.photo_library,
                  color: Color(0xFF2AABEE),
                ),
                title: const Text(
                  'Choisir une photo',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pickAvatar(ImageSource.gallery);
                },
              ),

              ListTile(
                leading: const Icon(Icons.camera_alt, color: Color(0xFF2AABEE)),
                title: const Text(
                  'Prendre une photo',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pickAvatar(ImageSource.camera);
                },
              ),

              if (_avatarUrl != null && _avatarUrl!.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text(
                    'Supprimer la photo',
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _deleteAvatar();
                  },
                ),

              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  // ============================================================
  // CHOIX DES AVATARS PRÉDÉFINIS
  // ============================================================

  void _showPredefinedAvatars() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1F2C34),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return FractionallySizedBox(
          heightFactor: 0.80,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                children: [
                  // Petite barre en haut
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade600,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),

                  const Text(
                    'Choisir un avatar',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 15),

                  // La grille prend uniquement l'espace disponible
                  Expanded(
                    child: GridView.builder(
                      padding: const EdgeInsets.only(bottom: 10),
                      itemCount: _predefinedAvatars.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 4,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 1,
                          ),
                      itemBuilder: (context, index) {
                        final avatar = _predefinedAvatars[index];

                        return GestureDetector(
                          onTap: () {
                            Navigator.pop(sheetContext);
                            _selectPredefinedAvatar(avatar);
                          },
                          child: ClipOval(
                            child: Container(
                              color: const Color(0xFF2AABEE),
                              child: Image.network(
                                avatar,
                                fit: BoxFit.cover,
                                loadingBuilder:
                                    (context, child, loadingProgress) {
                                      if (loadingProgress == null) {
                                        return child;
                                      }

                                      return const Center(
                                        child: SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        ),
                                      );
                                    },
                                errorBuilder: (context, error, stackTrace) {
                                  return const Icon(
                                    Icons.person,
                                    color: Colors.white,
                                    size: 40,
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ============================================================
  // ENREGISTRER UN AVATAR PRÉDÉFINI
  // ============================================================

  Future<void> _selectPredefinedAvatar(String avatarUrl) async {
    if (_isUploading) return;

    setState(() {
      _isUploading = true;
    });

    try {
      await SupabaseService.client
          .from('users')
          .update({'avatar_url': avatarUrl})
          .eq('id', widget.userId);

      if (!mounted) return;

      setState(() {
        _avatarUrl = avatarUrl;
        _isUploading = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Avatar mis à jour')));
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isUploading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible de mettre l’avatar à jour')),
      );
    }
  }

  // ============================================================
  // PHOTO GALERIE / CAMERA
  // ============================================================

  Future<void> _pickAvatar(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 800,
        maxHeight: 800,
      );

      if (image == null) return;

      final Uint8List bytes = await image.readAsBytes();

      if (!mounted) return;

      setState(() {
        _isUploading = true;
      });

      final extension = image.path.toLowerCase().endsWith('.png')
          ? 'png'
          : 'jpg';

      final url = await SupabaseService.uploadAvatar(
        userId: widget.userId,
        bytes: bytes,
        extension: extension,
      );

      if (!mounted) return;

      setState(() {
        _avatarUrl = url;
        _isUploading = false;
      });

      if (url != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photo de profil mise à jour')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossible de mettre la photo à jour')),
        );
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isUploading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Erreur lors de la sélection de la photo'),
        ),
      );
    }
  }

  // ============================================================
  // SUPPRIMER L'AVATAR
  // ============================================================

  Future<void> _deleteAvatar() async {
    setState(() {
      _isUploading = true;
    });

    final success = await SupabaseService.removeAvatar(widget.userId);

    if (!mounted) return;

    setState(() {
      _isUploading = false;

      if (success) {
        _avatarUrl = null;
      }
    });

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Photo de profil supprimée')),
      );
    }
  }

  // ============================================================
  // AVATAR ACTUEL
  // ============================================================

  Widget _buildAvatar() {
    if (_isLoadingAvatar) {
      return const CircleAvatar(
        radius: 35,
        backgroundColor: Color(0xFF2AABEE),
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
        ),
      );
    }

    if (_avatarUrl != null && _avatarUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: 35,
        backgroundColor: const Color(0xFF2AABEE),
        backgroundImage: NetworkImage(_avatarUrl!),
      );
    }

    return CircleAvatar(
      radius: 35,
      backgroundColor: const Color(0xFF2AABEE),
      child: Text(
        widget.pseudo.isNotEmpty ? widget.pseudo[0].toUpperCase() : '?',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 28,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  // ============================================================
  // PROFIL
  // ============================================================

  Widget _buildProfileSection() {
    return Card(
      color: const Color(0xFF1F2C34),
      margin: const EdgeInsets.all(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _showAvatarOptions,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  _buildAvatar(),

                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      width: 25,
                      height: 25,
                      decoration: const BoxDecoration(
                        color: Color(0xFF2AABEE),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.camera_alt,
                        color: Colors.white,
                        size: 14,
                      ),
                    ),
                  ),

                  if (_isUploading)
                    Positioned.fill(
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),

              const SizedBox(width: 16),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.pseudo,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Appuyer pour modifier la photo',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ],
                ),
              ),

              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // ÉCRAN PARAMÈTRES
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 20),

        _buildProfileSection(),

        const SizedBox(height: 10),

        _buildSettingsItem(Icons.key, 'Compte', 'Sécurité, changer de numéro'),

        _buildSettingsItem(
          Icons.lock,
          'Confidentialité',
          'Dernière visite, photo de profil',
        ),

        _buildSettingsItem(
          Icons.chat,
          'Discussions',
          'Thème, fond d\'écran, historique',
        ),

        _buildSettingsItem(
          Icons.notifications,
          'Notifications',
          'Messages, groupes, appels',
        ),

        _buildSettingsItem(
          Icons.storage,
          'Stockage et données',
          'Utilisation réseau',
        ),

        _buildSettingsItem(Icons.help, 'Aide', 'FAQ, nous contacter'),

        _buildSettingsItem(Icons.info, 'À propos', 'Version 1.0.0'),
      ],
    );
  }

  Widget _buildSettingsItem(IconData icon, String titre, String sousTitre) {
    return Card(
      color: const Color(0xFF1F2C34),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF2AABEE)),
        title: Text(
          titre,
          style: const TextStyle(
            fontWeight: FontWeight.w500,
            color: Colors.white,
          ),
        ),
        subtitle: Text(
          sousTitre,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: () {},
      ),
    );
  }
}
