import 'package:flutter/material.dart';

class VideosTab extends StatelessWidget {
  const VideosTab({super.key});

  @override
  Widget build(BuildContext context) {
    final List<Map<String, String>> videos = [
      {
        'titre': 'Tutoriel Flutter - Partie 1',
        'duree': '15:30',
        'date': 'Hier',
        'taille': '245 MB',
      },
      {
        'titre': 'Vidéo vacances plage',
        'duree': '03:45',
        'date': '21/07/2024',
        'taille': '87 MB',
      },
      {
        'titre': 'Présentation projet',
        'duree': '22:10',
        'date': '15/07/2024',
        'taille': '340 MB',
      },
      {
        'titre': 'Mariage Sophie',
        'duree': '08:20',
        'date': '01/06/2024',
        'taille': '156 MB',
      },
    ];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: TextField(
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Rechercher des vidéos...',
              hintStyle: TextStyle(color: Colors.grey[500]),
              prefixIcon: Icon(Icons.search, color: Colors.grey[500]),
              filled: true,
              fillColor: const Color(0xFF1F2C34),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(30),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: videos.length,
            itemBuilder: (context, index) {
              final video = videos[index];
              return _buildVideoItem(video);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildVideoItem(Map<String, String> video) {
    return Card(
      color: const Color(0xFF1F2C34),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        leading: Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: const Color(0xFF2AABEE).withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.play_circle_fill,
            size: 40,
            color: Color(0xFF2AABEE),
          ),
        ),
        title: Text(
          video['titre']!,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        subtitle: Text(
          '${video['duree']} • ${video['taille']} • ${video['date']}',
          style: TextStyle(color: Colors.grey[400]),
        ),
        trailing: IconButton(
          icon: Icon(Icons.more_vert, color: Colors.grey[400]),
          onPressed: () {},
        ),
        onTap: () {},
      ),
    );
  }
}
