import 'package:flutter/material.dart';

class ParametresTab extends StatelessWidget {
  final String phoneNumber;
  final String pseudo;

  const ParametresTab({
    super.key,
    required this.phoneNumber,
    required this.pseudo,
  });

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

  Widget _buildProfileSection() {
    return Card(
      color: const Color(0xFF1F2C34),
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const CircleAvatar(
              radius: 35,
              backgroundColor: Color(0xFF2AABEE),
              child: Icon(Icons.person, size: 40, color: Colors.white),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pseudo,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatPhoneForDisplay(phoneNumber),
                    style: const TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.qr_code_scanner, color: Color(0xFF2AABEE)),
              onPressed: () {},
            ),
          ],
        ),
      ),
    );
  }

  // Formate "+22670123456" en "+226 70 12 34 56" pour l'affichage uniquement
  String _formatPhoneForDisplay(String phone) {
    if (!phone.startsWith('+226') || phone.length != 12) return phone;
    final digits = phone.substring(4); // les 8 chiffres
    final buffer = StringBuffer('+226 ');
    for (int i = 0; i < digits.length; i += 2) {
      buffer.write(digits.substring(i, i + 2));
      if (i + 2 < digits.length) buffer.write(' ');
    }
    return buffer.toString();
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
