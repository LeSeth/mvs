import 'package:flutter/material.dart';
import '../tabs/messages_tab.dart';
import '../tabs/videos_tab.dart';
import '../tabs/statuts_tab.dart';
import '../tabs/parametres_tab.dart';
import 'login_screen.dart';
import '../services/supabase_service.dart';

class HomeScreen extends StatefulWidget {
  final String phoneNumber;
  final String pseudo;
  final String userId;

  const HomeScreen({
    super.key,
    required this.phoneNumber,
    required this.pseudo,
    required this.userId,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    SupabaseService.setOnlineStatus(widget.phoneNumber, false);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      SupabaseService.setOnlineStatus(widget.phoneNumber, false);
    } else if (state == AppLifecycleState.resumed) {
      SupabaseService.setOnlineStatus(widget.phoneNumber, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'V BF',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            Text(
              widget.pseudo,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.search), onPressed: () {}),
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () {
              _showOptionsMenu(context);
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF2AABEE),
          indicatorWeight: 3,
          labelColor: const Color(0xFF2AABEE),
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(text: 'Messages'),
            Tab(text: 'Vidéos'),
            Tab(text: 'Statuts'),
            Tab(text: 'Paramètres'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          MessagesTab(
            phoneNumber: widget.phoneNumber,
            pseudo: widget.pseudo,
            userId: widget.userId,
          ),
          const VideosTab(),
          const StatutsTab(),
          ParametresTab(phoneNumber: widget.phoneNumber, pseudo: widget.pseudo),
        ],
      ),
      floatingActionButton: null,
    );
  }

  void _showOptionsMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.group, color: Colors.white70),
                title: const Text(
                  'Nouveau groupe',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () => Navigator.pop(context),
              ),
              ListTile(
                leading: const Icon(Icons.campaign, color: Colors.white70),
                title: const Text(
                  'Nouvelle diffusion',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () => Navigator.pop(context),
              ),
              ListTile(
                leading: const Icon(Icons.phone, color: Colors.white70),
                title: const Text(
                  'Appels récents',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () => Navigator.pop(context),
              ),
              const Divider(color: Colors.grey),
              ListTile(
                leading: const Icon(Icons.info_outline, color: Colors.white70),
                title: const Text(
                  'À propos',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _showAboutDialog();
                },
              ),
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: const Text(
                  'Déconnexion',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () async {
                  await SupabaseService.logout(widget.phoneNumber);
                  if (context.mounted) {
                    Navigator.pop(context);
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const LoginScreen(),
                      ),
                      (route) => false,
                    );
                  }
                },
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1F2C34),
        title: const Row(
          children: [
            Icon(Icons.message_rounded, color: Color(0xFF2AABEE), size: 30),
            SizedBox(width: 10),
            Text('V BF', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '🇧🇫 Application de messagerie pour le Burkina Faso',
              style: TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 15),
            _buildInfoRow('Version', '1.0.0'),
            _buildInfoRow('Développeur', 'Équipe V BF'),
            _buildInfoRow('Pays', 'Burkina Faso'),
            _buildInfoRow('Indicatif', '+226'),
            const SizedBox(height: 15),
            const Text(
              'Connectez-vous avec vos amis et famille partout au Burkina Faso !',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Fermer',
              style: TextStyle(color: Color(0xFF2AABEE)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
