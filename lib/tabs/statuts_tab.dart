import 'package:flutter/material.dart';

class StatutsTab extends StatelessWidget {
  const StatutsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildMyStatusSection(),
        const Divider(color: Colors.grey),
        const Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            'Mises à jour récentes',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              _buildStatusItem('Marie Kaboré', 'Il y a 25 minutes', true),
              _buildStatusItem('Thomas Ouédraogo', 'Il y a 1 heure', true),
              _buildStatusItem('Alice Ilboudo', 'Il y a 3 heures', false),
              _buildStatusItem('Collègues Bureau', 'Il y a 5 heures', true),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMyStatusSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              const Text(
                'Mon statut',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.camera_alt, color: Color(0xFF2AABEE)),
                onPressed: () {},
              ),
              IconButton(
                icon: const Icon(Icons.edit, color: Color(0xFF2AABEE)),
                onPressed: () {},
              ),
            ],
          ),
        ),
        ListTile(
          leading: Stack(
            children: [
              const CircleAvatar(
                radius: 28,
                backgroundColor: Color(0xFF2AABEE),
                child: CircleAvatar(
                  radius: 26,
                  backgroundColor: Color(0xFF1F2C34),
                  child: Icon(Icons.person, size: 30, color: Colors.white),
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    color: Color(0xFF2AABEE),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.add, color: Colors.white, size: 18),
                ),
              ),
            ],
          ),
          title: const Text(
            'Ajouter à mon statut',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
          ),
          subtitle: const Text(
            'Appuyez pour ajouter un statut',
            style: TextStyle(color: Colors.grey),
          ),
          onTap: () {},
        ),
      ],
    );
  }

  Widget _buildStatusItem(String nom, String temps, bool nonVu) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: nonVu ? const Color(0xFF2AABEE) : Colors.grey,
            width: 3,
          ),
        ),
        child: const CircleAvatar(
          radius: 26,
          backgroundColor: Color(0xFF1F2C34),
          child: Icon(Icons.person, color: Colors.white),
        ),
      ),
      title: Text(
        nom,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      subtitle: Text(temps, style: const TextStyle(color: Colors.grey)),
      onTap: () {},
    );
  }
}
