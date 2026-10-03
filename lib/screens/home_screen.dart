import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../tabs/messages_tab.dart';
import '../tabs/videos_tab.dart';
import '../tabs/statuts_tab.dart';
import '../tabs/parametres_tab.dart';
import '../widgets/animated_chat_background.dart';
import 'login_screen.dart';
import 'new_conversation_screen.dart';
import 'create_group_screen.dart';
import '../services/supabase_service.dart';
import '../services/auth_storage.dart';

const Color _kBlue = Color(0xFF2AABEE);
const Color _kViolet = Color(0xFF8E5CF7);
const Color _kPink = Color(0xFFFF4D8D);
const Color _kBg = Color(0xFF0E1621);

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
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabController;
  late final AnimationController _ringCtrl;
  final GlobalKey<MessagesTabState> _messagesTabKey =
      GlobalKey<MessagesTabState>();
  int _totalUnread = 0;
  int _lastTabIndex = 0;

  // Photo de profil de l'utilisateur (affichée dans la barre du haut).
  String? _avatarUrl;

  String get _avatarCacheKey => 'my_avatar_${widget.userId}';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      // Quand on quitte l'onglet Paramètres, la photo a pu changer :
      // on la recharge pour que la page d'accueil soit toujours à jour.
      final index = _tabController.index;
      if (index != _lastTabIndex) {
        if (_lastTabIndex == 3) _loadMyAvatar();
        _lastTabIndex = index;
      }

      // Le FAB "nouvelle conversation" ne doit apparaître que sur l'onglet Messages
      setState(() {});
    });

    // Anneau de couleur qui tourne autour de la photo.
    _ringCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();

    WidgetsBinding.instance.addObserver(this);
    _loadMyAvatar();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _ringCtrl.dispose();
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
      _loadMyAvatar();
    }
  }

  // Affiche d'abord la dernière photo connue (enregistrée sur le téléphone),
  // puis la met à jour depuis le serveur. Une coupure de connexion ne fait
  // jamais disparaître la photo.
  Future<void> _loadMyAvatar() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_avatarCacheKey);

      if (cached != null && mounted && cached != (_avatarUrl ?? '')) {
        setState(() => _avatarUrl = cached.isEmpty ? null : cached);
      }
    } catch (_) {}

    try {
      final row = await SupabaseService.client
          .from('users')
          .select('avatar_url')
          .eq('id', widget.userId)
          .maybeSingle()
          .timeout(const Duration(seconds: 15));

      if (row == null) return;

      final url = row['avatar_url']?.toString() ?? '';

      if (mounted && url != (_avatarUrl ?? '')) {
        setState(() => _avatarUrl = url.isEmpty ? null : url);
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_avatarCacheKey, url);
    } catch (e) {
      // Pas de connexion : on garde la photo déjà affichée.
      debugPrint('Photo de profil : réseau indisponible ($e)');
    }
  }

  // Photo de l'utilisateur dans un anneau animé ; la première lettre du
  // pseudo ne sert plus que de repli (pas de photo, chargement, hors ligne).
  Widget _buildMyAvatar() {
    final initial = widget.pseudo.isNotEmpty
        ? widget.pseudo[0].toUpperCase()
        : '?';

    final letter = Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_kBlue, _kViolet],
        ),
      ),
      child: Text(
        initial,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
    );

    final hasPhoto = _avatarUrl != null && _avatarUrl!.isNotEmpty;

    return GestureDetector(
      onTap: () => _tabController.animateTo(3), // ouvre Paramètres
      child: SizedBox(
        width: 42,
        height: 42,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Anneau dégradé qui tourne
            RotationTransition(
              turns: _ringCtrl,
              child: Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: SweepGradient(
                    colors: [_kBlue, _kViolet, _kPink, _kBlue],
                  ),
                ),
              ),
            ),
            // Liseré sombre entre l'anneau et la photo
            Container(
              width: 38,
              height: 38,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: _kBg,
              ),
            ),
            // Photo de profil
            ClipOval(
              child: SizedBox(
                width: 34,
                height: 34,
                child: hasPhoto
                    ? Image.network(
                        _avatarUrl!,
                        key: ValueKey<String>(_avatarUrl!),
                        width: 34,
                        height: 34,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => letter,
                        loadingBuilder: (context, child, progress) =>
                            progress == null ? child : letter,
                      )
                    : letter,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Center(child: _buildMyAvatar()),
        ),
        leadingWidth: 58,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ShaderMask(
              shaderCallback: (rect) => const LinearGradient(
                colors: [Colors.white, Color(0xFFBFE6FF)],
              ).createShader(rect),
              child: const Text(
                'V BF',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
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
        // Fine ligne lumineuse sous la barre
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _kBlue.withValues(alpha: 0),
                  _kBlue.withValues(alpha: 0.6),
                  _kViolet.withValues(alpha: 0.6),
                  _kPink.withValues(alpha: 0.6),
                  _kPink.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          // Arrière-plan animé, derrière tous les onglets
          const Positioned.fill(child: AnimatedChatBackground()),
          TabBarView(
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
        ],
      ),
      floatingActionButton: _tabController.index == 0
          ? Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_kBlue, _kViolet],
                ),
                boxShadow: [
                  BoxShadow(
                    color: _kViolet.withValues(alpha: 0.45),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: FloatingActionButton(
                backgroundColor: Colors.transparent,
                elevation: 0,
                focusElevation: 0,
                hoverElevation: 0,
                highlightElevation: 0,
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
              ),
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
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
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
                final color = isSelected ? _kBlue : Colors.grey;

                return Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => _tabController.animateTo(index),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                      margin: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: isSelected
                            ? LinearGradient(
                                colors: [
                                  _kBlue.withValues(alpha: 0.18),
                                  _kViolet.withValues(alpha: 0.18),
                                ],
                              )
                            : null,
                      ),
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
                                      color: _kPink,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Text(
                                      _totalUnread > 99
                                          ? '99+'
                                          : '$_totalUnread',
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
                          const SizedBox(height: 3),
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
            Icon(Icons.message_rounded, color: _kBlue, size: 30),
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
            child: const Text('Fermer', style: TextStyle(color: _kBlue)),
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
