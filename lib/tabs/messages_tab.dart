import 'dart:async';
import 'package:flutter/material.dart';
import '../services/contact_service.dart';
import '../services/message_service.dart';
import '../services/supabase_service.dart';
import '../screens/chat_screen.dart';

class MessagesTab extends StatefulWidget {
  final String phoneNumber;
  final String pseudo;
  final String userId;

  const MessagesTab({
    super.key,
    required this.phoneNumber,
    required this.pseudo,
    required this.userId,
  });

  @override
  State<MessagesTab> createState() => MessagesTabState();
}

// État rendu public (au lieu de _MessagesTabState) pour pouvoir être
// rafraîchi depuis l'extérieur via une GlobalKey (ex: après une nouvelle
// conversation lancée depuis le bouton flottant dans HomeScreen).
class MessagesTabState extends State<MessagesTab> {
  List<Map<String, dynamic>> _contacts = [];
  bool _isLoading = true;

  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  bool _searchLoading = false;

  @override
  void initState() {
    super.initState();
    _syncAndLoadContacts();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
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
        message = '$result nouveau${result > 1 ? "x" : ""} contact'
            '${result > 1 ? "s" : ""} ajouté${result > 1 ? "s" : ""} !';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
      );
    }
  }

  Future<void> _loadContacts() async {
    final contacts = await ContactService.getContacts(widget.phoneNumber);

    List<Map<String, dynamic>> contactsWithMessages = [];
    for (var contact in contacts) {
      // Trouver le vrai numéro via le hash
      final users = await SupabaseService.findUsersByPhoneHashes([
        contact['contact_phone_hash'],
      ]);
      String contactPhone = users.isNotEmpty
          ? users[0]['phone_number']
          : contact['contact_phone_hash'];

      final lastMessage = await MessageService.getLastMessage(
        userPhone1: widget.phoneNumber,
        userPhone2: contactPhone,
      );

      final unreadCount = await MessageService.getUnreadCount(
        userPhone: widget.phoneNumber,
        contactPhone: contactPhone,
      );

      contactsWithMessages.add({
        ...contact,
        'contact_phone': contactPhone,
        'last_message': lastMessage,
        'unread_count': unreadCount,
      });
    }

    if (mounted) {
      setState(() {
        _contacts = contactsWithMessages;
        _isLoading = false;
      });
    }
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
    // On s'assure que la personne fait partie de nos contacts pour qu'elle
    // apparaisse ensuite dans la liste des conversations.
    await ContactService.addContactIfNotExists(
      userPhone: widget.phoneNumber,
      contactPhoneHash: user['phone_hash'],
      contactPseudo: user['pseudo'],
    );

    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatScreen(
          senderPhone: widget.phoneNumber,
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
              fillColor: const Color(0xFF1F2C34),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Expanded(child: _isSearching ? _buildSearchResults() : _buildContactsList()),
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
          leading: CircleAvatar(
            radius: 24,
            backgroundColor: const Color(0xFF2AABEE),
            child: Text(
              pseudo.isNotEmpty ? pseudo[0].toUpperCase() : '?',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          title: Text(pseudo, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          subtitle: Text(
            isOnline ? 'En ligne' : 'Hors ligne',
            style: TextStyle(color: isOnline ? Colors.green : Colors.grey[500], fontSize: 12),
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

    if (_contacts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.contacts_outlined, size: 80, color: Colors.grey[700]),
            const SizedBox(height: 20),
            Text(
              'Aucun contact',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[500],
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Vos contacts V apparaîtront ici',
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => _syncAndLoadContacts(showFeedback: true),
              icon: const Icon(Icons.sync),
              label: const Text('Synchroniser les contacts'),
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
        itemCount: _contacts.length,
        itemBuilder: (context, index) {
          final contact = _contacts[index];
          return _buildContactItem(contact);
        },
      ),
    );
  }

  Widget _buildContactItem(Map<String, dynamic> contact) {
    final lastMessage = contact['last_message'];
    final unreadCount = contact['unread_count'] ?? 0;

    return Card(
      color: const Color(0xFF1F2C34),
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      elevation: 0,
      child: ListTile(
        leading: CircleAvatar(
          radius: 28,
          backgroundColor: const Color(0xFF2AABEE),
          child: Text(
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
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  color: Color(0xFF2AABEE),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$unreadCount',
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
          'Supprimer le contact',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Voulez-vous supprimer ${contact['contact_pseudo']} de vos contacts ?',
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
