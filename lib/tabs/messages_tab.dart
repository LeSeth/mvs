import 'package:flutter/material.dart';
import '../services/contact_service.dart';
import '../services/message_service.dart';
import '../services/supabase_service.dart'; // ← Ajouter cet import
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
  State<MessagesTab> createState() => _MessagesTabState();
}

class _MessagesTabState extends State<MessagesTab> {
  List<Map<String, dynamic>> _contacts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _syncAndLoadContacts();
  }

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

  @override
  Widget build(BuildContext context) {
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
