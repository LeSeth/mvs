import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/contact_service.dart';
import '../services/message_service.dart';
import '../services/supabase_service.dart';
import '../services/group_service.dart';
import '../services/expiry_store.dart';
import '../services/expiry_service.dart';
import '../services/conversation_cache.dart';
import '../screens/chat_screen.dart';
import '../screens/group_chat_screen.dart';
import '../screens/new_conversation_screen.dart';

class MessagesTab extends StatefulWidget {
  final String phoneNumber;
  final String pseudo;
  final String userId;
  final void Function(int totalUnread)? onUnreadCountChanged;

  const MessagesTab({
    super.key,
    required this.phoneNumber,
    required this.pseudo,
    required this.userId,
    this.onUnreadCountChanged,
  });

  @override
  State<MessagesTab> createState() => MessagesTabState();
}

// État rendu public (au lieu de _MessagesTabState) pour pouvoir être
// rafraîchi depuis l'extérieur via une GlobalKey (ex: après une nouvelle
// conversation lancée depuis le bouton flottant dans HomeScreen).
class MessagesTabState extends State<MessagesTab> {
  List<Map<String, dynamic>> _contacts = [];
  List<Map<String, dynamic>> _groups = [];
  List<Map<String, dynamic>> _combinedItems = [];
  bool _isLoading = true;

  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  bool _searchLoading = false;
  RealtimeChannel? _messagesChannel;
  RealtimeChannel? _groupMessagesChannel;
  RealtimeChannel? _groupMembershipsChannel;
  StreamSubscription<ExpiryEvent>? _expirySub;
  Timer? _expiryRefreshDebounce;

  // Apparition progressive des conversations : seulement au premier
  // affichage, pas à chaque défilement.
  bool _playEntrance = true;
  Timer? _entranceTimer;

  @override
  void initState() {
    super.initState();
    // 1) Affichage IMMÉDIAT de la liste enregistrée sur le téléphone
    //    (visible même sans connexion, comme WhatsApp).
    // 2) Mise à jour réseau ensuite, sans jamais effacer ce qui est affiché
    //    si la connexion est absente ou lente.
    _entranceTimer = Timer(const Duration(milliseconds: 1800), () {
      _playEntrance = false;
    });

    _showCachedThenSync();

    // Service de disparition (global) : reprend les files laissées en cours
    // et les synchronisations serveur en attente, dès l'ouverture de l'app,
    // sans qu'aucune conversation n'ait besoin d'être ouverte.
    ExpiryService.instance.start(widget.phoneNumber);

    // Quand un message disparaît (même conversation fermée), l'aperçu et le
    // compteur sont rafraîchis (regroupés pour ne pas recharger à chaque fois).
    _expirySub = ExpiryService.instance.onExpired.listen((_) {
      _expiryRefreshDebounce?.cancel();
      _expiryRefreshDebounce = Timer(const Duration(seconds: 1), () {
        if (mounted) _loadContacts();
      });
    });
    _searchController.addListener(_onSearchChanged);
    _messagesChannel = MessageService.subscribeToIncomingMessages(
      myPhone: widget.phoneNumber,
      channelName: 'messages_list_${widget.phoneNumber}',
      onInsert: (_) {
        // Un nouveau message est arrivé : on rafraîchit la liste des
        // conversations (aperçu du dernier message + badge non lus).
        if (mounted) _loadContacts();
      },
    );
    _groupMessagesChannel = GroupService.subscribeToAllGroupMessages(
      channelName: 'group_messages_list_${widget.phoneNumber}',
      onInsert: (message) {
        // On ne peut pas filtrer côté serveur "mes groupes uniquement" ;
        // on vérifie donc côté client si ce message concerne un groupe
        // dont je suis membre avant de rafraîchir.
        final isMyGroup = _groups.any((g) => g['id'] == message['group_id']);
        if (mounted && isMyGroup) _loadContacts();
      },
    );
    // Dès que je suis ajouté à un NOUVEAU groupe, je suis notifié
    // instantanément (au lieu d'attendre par hasard qu'un autre événement
    // déclenche un rechargement de la liste).
    _groupMembershipsChannel = GroupService.subscribeToMyGroupMemberships(
      myPhone: widget.phoneNumber,
      channelName: 'group_memberships_${widget.phoneNumber}',
      onNewMembership: () {
        if (mounted) _loadContacts();
      },
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _expiryRefreshDebounce?.cancel();
    _entranceTimer?.cancel();
    _expirySub?.cancel();
    _searchController.dispose();
    if (_messagesChannel != null) {
      MessageService.unsubscribe(_messagesChannel!);
    }
    if (_groupMessagesChannel != null) {
      GroupService.unsubscribe(_groupMessagesChannel!);
    }
    if (_groupMembershipsChannel != null) {
      GroupService.unsubscribe(_groupMembershipsChannel!);
    }
    super.dispose();
  }

  // Méthode publique : permet à HomeScreen de forcer un rafraîchissement
  // (par exemple après avoir démarré une nouvelle conversation).
  Future<void> refreshContacts() => _loadContacts();

  Future<void> _syncAndLoadContacts({bool showFeedback = false}) async {
    // Synchroniser les contacts du téléphone
    final result = await ContactService.syncContacts(widget.phoneNumber);
    // Charger les contacts
    await _loadContacts();

    if (showFeedback && mounted) {
      String message;
      if (result < 0) {
        message =
            'Synchronisation impossible : vérifiez la permission "Contacts" '
            'dans les paramètres du téléphone et votre connexion Internet.';
      } else if (result == 0) {
        message = 'Aucun nouveau contact trouvé sur l\'application.';
      } else {
        message =
            '$result nouveau${result > 1 ? "x" : ""} contact'
            '${result > 1 ? "s" : ""} ajouté${result > 1 ? "s" : ""} !';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
      );
    }
  }

  // Affiche la liste locale tout de suite, puis lance la synchronisation.
  Future<void> _showCachedThenSync() async {
    await _showCachedList();
    await _syncAndLoadContacts();
  }

  Future<void> _showCachedList() async {
    final cached = await ConversationCache.load(widget.phoneNumber);

    if (!mounted || cached.isEmpty) return;

    // Un chargement réseau a déjà abouti entre-temps : il est plus récent.
    if (!_isLoading) return;

    final items = await _applyLocalExpiry(cached);

    if (!mounted || !_isLoading) return;

    setState(() {
      _combinedItems = items;
      _contacts = items.where((i) => i['type'] == 'direct').toList();
      _groups = items.where((i) => i['type'] == 'group').toList();
      _isLoading = false;
    });

    _notifyUnread(_contacts);
  }

  void _notifyUnread(List<Map<String, dynamic>> contacts) {
    final totalUnread = contacts.fold<int>(
      0,
      (sum, c) => sum + (c['unread_count'] as int? ?? 0),
    );
    widget.onUnreadCountChanged?.call(totalUnread);
  }

  // Clés locales des messages déjà disparus de l'écran mais dont la
  // suppression / lecture n'est pas encore confirmée côté serveur.
  String _directPendingKey(String contactPhone) =>
      'pending_msg_deletes_${widget.phoneNumber}_$contactPhone';

  String _groupPendingKey(String groupId) =>
      'pending_group_reads_${widget.phoneNumber}_$groupId';

  // Retire de l'aperçu les messages déjà disparus chez moi (utile surtout
  // pour la liste enregistrée, affichée sans réseau).
  Future<List<Map<String, dynamic>>> _applyLocalExpiry(
    List<Map<String, dynamic>> items,
  ) async {
    final result = <Map<String, dynamic>>[];

    for (final item in items) {
      final last = item['last_message'];
      final String? key = item['type'] == 'group'
          ? (item['id'] != null
                ? _groupPendingKey(item['id'].toString())
                : null)
          : (item['contact_phone'] != null
                ? _directPendingKey(item['contact_phone'].toString())
                : null);

      if (last is Map && key != null) {
        final pending = await ExpiryStore.load(key);

        if (pending.contains(last['id']?.toString())) {
          result.add({...item, 'last_message': null, 'unread_count': 0});
          continue;
        }
      }

      result.add(item);
    }

    return result;
  }

  // Dernier message d'une conversation 1-à-1, en ignorant ceux déjà
  // disparus chez moi (même si le serveur ne l'a pas encore confirmé).
  Future<Map<String, dynamic>?> _lastDirectMessage(
    String contactPhone,
    Set<String> pending,
  ) async {
    final last = await MessageService.getLastMessage(
      userPhone1: widget.phoneNumber,
      userPhone2: contactPhone,
    );

    if (last == null || !pending.contains(last['id']?.toString())) {
      return last;
    }

    return null;
  }

  // Messages non lus d'un contact : ouvrir la conversation = lire, donc on
  // ne compte ni les messages déjà ouverts (compte à rebours en cours), ni
  // ceux déjà disparus chez moi.
  Future<int> _unreadDirect(String contactPhone, Set<String> pending) async {
    final opened = <String>{
      ...pending,
      ...ExpiryService.instance.queuedIds(_directPendingKey(contactPhone)),
    };

    try {
      final rows = await SupabaseService.client
          .from('messages')
          .select('id')
          .eq('sender_phone', contactPhone)
          .eq('receiver_phone', widget.phoneNumber)
          .eq('is_read', false);

      return rows.where((r) => !opened.contains(r['id']?.toString())).length;
    } catch (_) {
      return 0;
    }
  }

  // Dernier message visible d'un groupe, sans ceux déjà lus chez moi mais
  // pas encore confirmés côté serveur.
  Future<Map<String, dynamic>?> _lastGroupMessage(
    String groupId,
    Set<String> pending,
  ) async {
    if (pending.isEmpty) {
      return GroupService.getLastGroupMessage(groupId, widget.phoneNumber);
    }

    try {
      final reads = await SupabaseService.client
          .from('group_message_reads')
          .select('message_id')
          .eq('member_phone', widget.phoneNumber);

      final readIds = reads.map((r) => r['message_id'].toString()).toSet();

      final messages = await SupabaseService.client
          .from('group_messages')
          .select()
          .eq('group_id', groupId)
          .order('created_at', ascending: false)
          .limit(20);

      for (final m in messages) {
        final id = m['id'].toString();
        if (!readIds.contains(id) && !pending.contains(id)) {
          return Map<String, dynamic>.from(m);
        }
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  // Récupère les conversations 1-à-1 en LANÇANT une erreur si le réseau
  // échoue (les services habituels renvoient une liste vide, ce qui ne
  // permet pas de distinguer « aucune conversation » de « pas de connexion »).
  Future<List<Map<String, dynamic>>> _fetchContactsStrict() async {
    final contacts = await SupabaseService.client
        .from('contacts')
        .select()
        .eq('user_phone', widget.phoneNumber)
        .not('last_message_at', 'is', null)
        .order('last_message_at', ascending: false)
        .timeout(const Duration(seconds: 15));

    return List<Map<String, dynamic>>.from(contacts);
  }

  Future<List<Map<String, dynamic>>> _fetchGroupsStrict() async {
    final memberships = await SupabaseService.client
        .from('group_members')
        .select('group_id')
        .eq('member_phone', widget.phoneNumber)
        .timeout(const Duration(seconds: 15));

    final groupIds = memberships.map((m) => m['group_id']).toList();

    if (groupIds.isEmpty) return [];

    final groups = await SupabaseService.client
        .from('groups')
        .select()
        .inFilter('id', groupIds)
        .order('last_message_at', ascending: false)
        .timeout(const Duration(seconds: 15));

    return List<Map<String, dynamic>>.from(groups);
  }

  bool _loadingContacts = false;
  bool _reloadRequested = false;

  Future<void> _loadContacts() async {
    // Un seul chargement à la fois ; si un autre est demandé pendant ce
    // temps (nouveau message, retour d'une conversation…), on en refait un
    // juste après pour ne rien rater.
    if (_loadingContacts) {
      _reloadRequested = true;
      return;
    }

    _loadingContacts = true;

    try {
      await _loadContactsOnce();
    } finally {
      _loadingContacts = false;
    }

    if (_reloadRequested && mounted) {
      _reloadRequested = false;
      await _loadContacts();
    }
  }

  Future<void> _loadContactsOnce() async {
    // Ce qui est actuellement affiché (liste locale ou dernier chargement) :
    // sert de repli pour toute donnée que le réseau ne peut pas fournir.
    final previousByContactHash = <String, Map<String, dynamic>>{
      for (final c in _contacts)
        if (c['contact_phone_hash'] != null)
          c['contact_phone_hash'].toString(): c,
    };
    final previousGroupsById = <String, Map<String, dynamic>>{
      for (final g in _groups)
        if (g['id'] != null) g['id'].toString(): g,
    };

    List<Map<String, dynamic>> contacts;
    List<Map<String, dynamic>> groups;

    try {
      contacts = await _fetchContactsStrict();
      groups = await _fetchGroupsStrict();
    } catch (e) {
      // Pas de connexion (ou trop lente) : on GARDE la liste affichée.
      debugPrint('Liste des conversations : réseau indisponible ($e)');

      if (mounted && _isLoading) {
        setState(() => _isLoading = false);
      }

      return;
    }

    // Photos de profil des contacts : une seule requête pour toute la liste.
    final avatarsByHash = await _fetchAvatarsByHash(
      contacts
          .map((c) => c['contact_phone_hash']?.toString() ?? '')
          .where((h) => h.isNotEmpty)
          .toSet()
          .toList(),
    );

    List<Map<String, dynamic>> contactsWithMessages = [];
    for (var contact in contacts) {
      final hash = contact['contact_phone_hash']?.toString() ?? '';
      final previous = previousByContactHash[hash];

      // Trouver le vrai numéro via le hash (repli : valeur déjà connue, pour
      // ne jamais remplacer un vrai numéro par son hash si le réseau flanche).
      final users = await SupabaseService.findUsersByPhoneHashes([
        contact['contact_phone_hash'],
      ]);

      String contactPhone;
      if (users.isNotEmpty) {
        contactPhone = users[0]['phone_number'];
      } else if (previous != null && previous['contact_phone'] != null) {
        contactPhone = previous['contact_phone'].toString();
      } else {
        contactPhone = contact['contact_phone_hash'];
      }

      final pending = await ExpiryStore.load(_directPendingKey(contactPhone));

      final lastMessage = await _lastDirectMessage(contactPhone, pending);
      final unreadCount = await _unreadDirect(contactPhone, pending);

      contactsWithMessages.add({
        ...contact,
        'contact_phone': contactPhone,
        'contact_avatar_url': avatarsByHash.containsKey(hash)
            ? avatarsByHash[hash]
            : previous?['contact_avatar_url'],
        'last_message': lastMessage,
        'unread_count': unreadCount,
      });
    }

    // Groupes dont je suis membre
    List<Map<String, dynamic>> groupsWithMessages = [];
    for (var group in groups) {
      final groupId = group['id'].toString();
      final pending = await ExpiryStore.load(_groupPendingKey(groupId));

      final lastMessage = await _lastGroupMessage(groupId, pending);
      groupsWithMessages.add({...group, 'last_message': lastMessage});
    }

    // Fusionne conversations 1-à-1 et groupes dans une seule liste,
    // triée par activité la plus récente (comme une vraie messagerie).
    final combined = <Map<String, dynamic>>[
      ...contactsWithMessages.map((c) => {'type': 'direct', ...c}),
      ...groupsWithMessages.map((g) => {'type': 'group', ...g}),
    ];
    combined.sort((a, b) {
      final aTime = a['last_message_at'];
      final bTime = b['last_message_at'];
      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      return DateTime.parse(bTime).compareTo(DateTime.parse(aTime));
    });

    // Enregistre la liste sur le téléphone : elle reste visible hors ligne.
    await ConversationCache.save(widget.phoneNumber, combined);

    if (mounted) {
      setState(() {
        _contacts = contactsWithMessages;
        _groups = groupsWithMessages;
        _combinedItems = combined;
        _isLoading = false;
      });
    }

    _notifyUnread(contactsWithMessages);
  }

  Future<Map<String, String?>> _fetchAvatarsByHash(List<String> hashes) async {
    if (hashes.isEmpty) return {};

    try {
      final users = await SupabaseService.client
          .from('users')
          .select('phone_hash, avatar_url')
          .inFilter('phone_hash', hashes);

      final Map<String, String?> byHash = {};

      for (final user in users) {
        final hash = user['phone_hash']?.toString();

        if (hash != null && hash.isNotEmpty) {
          byHash[hash] = user['avatar_url']?.toString();
        }
      }

      return byHash;
    } catch (e) {
      debugPrint('Erreur récupération avatars conversations: $e');
      return {};
    }
  }

  // Avatar d'une ligne de conversation : photo si disponible, sinon repli
  // (initiale du contact ou icône de groupe).
  Widget _buildConversationAvatar({
    required String? avatarUrl,
    required Color backgroundColor,
    required Widget fallback,
    double radius = 28,
  }) {
    final hasUrl = avatarUrl != null && avatarUrl.isNotEmpty;

    if (!hasUrl) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: backgroundColor,
        child: fallback,
      );
    }

    // Sans connexion, l'image ne peut pas se charger : on affiche alors
    // l'initiale / l'icône au lieu d'un cercle vide.
    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor,
      child: ClipOval(
        child: Image.network(
          avatarUrl,
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => Center(child: fallback),
        ),
      ),
    );
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();

    setState(() {
      _isSearching = query.isNotEmpty;
    });

    _debounce?.cancel();
    if (query.isEmpty) {
      setState(() => _searchResults = []);
      return;
    }

    // Petit délai pour éviter une requête à chaque frappe
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      setState(() => _searchLoading = true);
      final results = await SupabaseService.searchUsersByPseudo(
        query,
        excludePhoneNumber: widget.phoneNumber,
      );
      if (mounted) {
        setState(() {
          _searchResults = results;
          _searchLoading = false;
        });
      }
    });
  }

  Future<void> _openChatWithUser(Map<String, dynamic> user) async {
    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatScreen(
          senderPhone: widget.phoneNumber,
          senderPseudo: widget.pseudo,
          receiverPhone: user['phone_number'],
          receiverPseudo: user['pseudo'],
        ),
      ),
    );

    _searchController.clear();
    if (mounted) {
      setState(() => _isSearching = false);
    }
    _loadContacts();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: TextField(
            controller: _searchController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Rechercher un pseudo...',
              hintStyle: TextStyle(color: Colors.grey[500]),
              prefixIcon: Icon(Icons.search, color: Colors.grey[500]),
              suffixIcon: _isSearching
                  ? IconButton(
                      icon: Icon(Icons.close, color: Colors.grey[500]),
                      onPressed: () => _searchController.clear(),
                    )
                  : null,
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.07),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide(
                  color: Colors.white.withValues(alpha: 0.10),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: const BorderSide(color: Color(0xFF2AABEE)),
              ),
            ),
          ),
        ),
        Expanded(
          child: _isSearching ? _buildSearchResults() : _buildContactsList(),
        ),
      ],
    );
  }

  Widget _buildSearchResults() {
    if (_searchLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF2AABEE)),
      );
    }

    if (_searchResults.isEmpty) {
      return Center(
        child: Text(
          'Aucun utilisateur trouvé',
          style: TextStyle(color: Colors.grey[500]),
        ),
      );
    }

    return ListView.builder(
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final user = _searchResults[index];
        final pseudo = (user['pseudo'] as String?) ?? '';
        final isOnline = user['is_online'] == true;

        return ListTile(
          leading: _buildConversationAvatar(
            avatarUrl: user['avatar_url']?.toString(),
            backgroundColor: const Color(0xFF2AABEE),
            radius: 24,
            fallback: Text(
              pseudo.isNotEmpty ? pseudo[0].toUpperCase() : '?',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          title: Text(
            pseudo,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          subtitle: Text(
            isOnline ? 'En ligne' : 'Hors ligne',
            style: TextStyle(
              color: isOnline ? Colors.green : Colors.grey[500],
              fontSize: 12,
            ),
          ),
          onTap: () => _openChatWithUser(user),
        );
      },
    );
  }

  Widget _buildContactsList() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF2AABEE)),
      );
    }

    if (_combinedItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('💬', style: TextStyle(fontSize: 64)),
            const SizedBox(height: 20),
            Text(
              'Aucune conversation',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[500],
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Vos discussions apparaîtront ici une fois qu\'un\nmessage aura été échangé',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
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
                _loadContacts();
              },
              icon: const Icon(Icons.chat),
              label: const Text('Démarrer une conversation'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2AABEE),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _syncAndLoadContacts(showFeedback: true),
      child: ListView.builder(
        itemCount: _combinedItems.length,
        itemBuilder: (context, index) {
          final item = _combinedItems[index];
          if (item['type'] == 'group') {
            return _buildGroupItem(item, index);
          }
          return _buildContactItem(item, index);
        },
      ),
    );
  }

  // Carte de conversation « verre » : translucide pour laisser voir le fond
  // animé, avec apparition progressive au premier affichage.
  Widget _glassTile({required int index, required Widget child}) {
    final tile = Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Material(type: MaterialType.transparency, child: child),
      ),
    );

    if (!_playEntrance || index > 9) return tile;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: 450 + index * 70),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(28 * (1 - v), 0),
          child: child,
        ),
      ),
      child: tile,
    );
  }

  Widget _buildGroupItem(Map<String, dynamic> group, int index) {
    final lastMessage = group['last_message'];

    return _glassTile(
      index: index,
      child: ListTile(
        leading: _buildConversationAvatar(
          avatarUrl: group['avatar_url']?.toString(),
          backgroundColor: const Color(0xFF6C63FF),
          fallback: const Icon(Icons.group, color: Colors.white),
        ),
        title: Text(
          group['name'] ?? '',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        subtitle: lastMessage != null
            ? Text(
                '${lastMessage['sender_pseudo']}: ${lastMessage['content']}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.grey[400], fontSize: 14),
              )
            : Text(
                'Groupe créé',
                style: TextStyle(color: Colors.grey[600], fontSize: 14),
              ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => GroupChatScreen(
                groupId: group['id'].toString(),
                groupName: group['name'],
                myPhone: widget.phoneNumber,
                myPseudo: widget.pseudo,
              ),
            ),
          ).then((_) => _loadContacts());
        },
      ),
    );
  }

  Widget _buildContactItem(Map<String, dynamic> contact, int index) {
    final lastMessage = contact['last_message'];
    final unreadCount = contact['unread_count'] ?? 0;

    return _glassTile(
      index: index,
      child: ListTile(
        leading: _buildConversationAvatar(
          avatarUrl: contact['contact_avatar_url']?.toString(),
          backgroundColor: const Color(0xFF2AABEE),
          fallback: Text(
            (contact['contact_pseudo'] as String?)?.isNotEmpty == true
                ? contact['contact_pseudo'][0].toUpperCase()
                : '?',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
        ),
        title: Text(
          contact['contact_pseudo'],
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        subtitle: lastMessage != null
            ? Text(
                lastMessage['content'],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.grey[400], fontSize: 14),
              )
            : Text(
                'Dites bonjour !',
                style: TextStyle(color: Colors.grey[600], fontSize: 14),
              ),
        trailing: unreadCount > 0
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                constraints: const BoxConstraints(minWidth: 26),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2AABEE), Color(0xFF8E5CF7)],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF8E5CF7).withValues(alpha: 0.45),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Text(
                  '$unreadCount',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            : null,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ChatScreen(
                senderPhone: widget.phoneNumber,
                senderPseudo: widget.pseudo,
                receiverPhone: contact['contact_phone'],
                receiverPseudo: contact['contact_pseudo'],
              ),
            ),
          ).then((_) => _loadContacts());
        },
        onLongPress: () {
          _showDeleteContactDialog(contact);
        },
      ),
    );
  }

  void _showDeleteContactDialog(Map<String, dynamic> contact) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1F2C34),
        title: const Text(
          'Supprimer la conversation',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Voulez-vous supprimer la conversation avec ${contact['contact_pseudo']} ?',
          style: const TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () async {
              await ContactService.deleteContact(contact['id']);
              Navigator.pop(context);
              _loadContacts();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
  }
}
