import 'package:flutter/material.dart';
import '../tabs/messages_tab.dart';
import '../tabs/videos_tab.dart';
import '../tabs/statuts_tab.dart';
import '../tabs/parametres_tab.dart';
import 'login_screen.dart';
import 'new_conversation_screen.dart';
import 'create_group_screen.dart';
import '../services/supabase_service.dart';
import '../services/auth_storage.dart';

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
  final GlobalKey<MessagesTabState> _messagesTabKey =
      GlobalKey<MessagesTabState>();
  int _totalUnread = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      // Le FAB "nouvelle conversation" ne doit apparaître que sur l'onglet Messages
      setState(() {});
    });
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
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: GestureDetector(
            onTap: () => _tabController.animateTo(3), // ouvre Paramètres
            child: CircleAvatar(
              radius: 18,
              backgroundColor: const Color(0xFF2AABEE),
              child: Text(
                widget.pseudo.isNotEmpty ? widget.pseudo[0].toUpperCase() : '?',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
        leadingWidth: 56,
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
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () {
              _showOptionsMenu(context);
            },
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          MessagesTab(
            key: _messagesTabKey,
            phoneNumber: widget.phoneNumber,
            pseudo: widget.pseudo,
            userId: widget.userId,
            onUnreadCountChanged: (count) {
              if (mounted) setState(() => _totalUnread = count);
            },
          ),
          const VideosTab(),
          const StatutsTab(),
          ParametresTab(pseudo: widget.pseudo, userId: widget.userId),
        ],
      ),
      floatingActionButton: _tabController.index == 0
          ? FloatingActionButton(
              backgroundColor: const Color(0xFF2AABEE),
              child: const Icon(Icons.chat, color: Colors.white),
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => NewConversationScreen(
                      phoneNumber: widget.phoneNumber,
                      pseudo: widget.pseudo,
                    ),
                  ),
                );
                // Rafraîchit la liste des conversations au retour
                _messagesTabKey.currentState?.refreshContacts();
              },
            )
          : null,
      bottomNavigationBar: _buildBottomNavBar(),
    );
  }

  // Barre de navigation façon Telegram : icône + libellé pour chaque
  // onglet, avec un badge de messages non lus sur "Messages".
  Widget _buildBottomNavBar() {
    final items = [
      (
        icon: Icons.chat_bubble_outline,
        activeIcon: Icons.chat_bubble,
        label: 'Messages',
      ),
      (
        icon: Icons.videocam_outlined,
        activeIcon: Icons.videocam,
        label: 'Vidéos',
      ),
      (
        icon: Icons.photo_camera_outlined,
        activeIcon: Icons.photo_camera,
        label: 'Statuts',
      ),
      (
        icon: Icons.settings_outlined,
        activeIcon: Icons.settings,
        label: 'Paramètres',
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1F2C34),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.25),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 58,
            child: Row(
              children: List.generate(items.length, (index) {
                final item = items[index];
                final isSelected = _tabController.index == index;
                final color = isSelected
                    ? const Color(0xFF2AABEE)
                    : Colors.grey;

                return Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => _tabController.animateTo(index),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Icon(
                              isSelected ? item.activeIcon : item.icon,
                              color: color,
                              size: 24,
                            ),
                            if (index == 0 && _totalUnread > 0)
                              Positioned(
                                right: -8,
                                top: -4,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 1,
                                  ),
                                  constraints: const BoxConstraints(
                                    minWidth: 16,
                                    minHeight: 16,
                                  ),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF2AABEE),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(
                                    _totalUnread > 99 ? '99+' : '$_totalUnread',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.label,
                          style: TextStyle(
                            color: color,
                            fontSize: 11,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
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
                onTap: () async {
                  Navigator.pop(context);
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => CreateGroupScreen(
                        phoneNumber: widget.phoneNumber,
                        pseudo: widget.pseudo,
                      ),
                    ),
                  );
                  _messagesTabKey.currentState?.refreshContacts();
                },
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
                  await AuthStorage.clearSession();
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
