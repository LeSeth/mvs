import 'package:flutter/material.dart';
import '../services/contact_service.dart';
import '../services/supabase_service.dart';
import 'chat_screen.dart';

// Écran ouvert par le bouton flottant : affiche les contacts synchronisés
// de l'utilisateur pour qu'il choisisse avec qui démarrer une conversation.
class NewConversationScreen extends StatefulWidget {
  final String phoneNumber;
  final String pseudo;

  const NewConversationScreen({
    super.key,
    required this.phoneNumber,
    required this.pseudo,
  });

  @override
  State<NewConversationScreen> createState() => _NewConversationScreenState();
}

class _NewConversationScreenState extends State<NewConversationScreen> {
  List<Map<String, dynamic>> _contacts = [];
  List<Map<String, dynamic>> _filteredContacts = [];
  bool _isLoading = true;
  final TextEditingController _filterController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadContacts();
    _filterController.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    setState(() => _isLoading = true);

    final contacts = await ContactService.getContacts(widget.phoneNumber);
    List<Map<String, dynamic>> resolved = [];

    for (var contact in contacts) {
      final users = await SupabaseService.findUsersByPhoneHashes([
        contact['contact_phone_hash'],
      ]);
      if (users.isNotEmpty) {
        resolved.add({
          'pseudo': contact['contact_pseudo'],
          'phone_number': users[0]['phone_number'],
          'phone_hash': contact['contact_phone_hash'],
          'is_online': users[0]['is_online'] == true,
        });
      }
    }

    if (mounted) {
      setState(() {
        _contacts = resolved;
        _filteredContacts = resolved;
        _isLoading = false;
      });
    }
  }

  void _applyFilter() {
    final query = _filterController.text.trim().toLowerCase();
    setState(() {
      _filteredContacts = query.isEmpty
          ? _contacts
          : _contacts
                .where(
                  (c) => (c['pseudo'] as String? ?? '').toLowerCase().contains(
                    query,
                  ),
                )
                .toList();
    });
  }

  Future<void> _startConversation(Map<String, dynamic> contact) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatScreen(
          senderPhone: widget.phoneNumber,
          senderPseudo: widget.pseudo,
          receiverPhone: contact['phone_number'],
          receiverPseudo: contact['pseudo'],
        ),
      ),
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nouvelle conversation')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _filterController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Filtrer mes contacts...',
                hintStyle: TextStyle(color: Colors.grey[500]),
                prefixIcon: Icon(Icons.search, color: Colors.grey[500]),
                filled: true,
                fillColor: const Color(0xFF1F2C34),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF2AABEE)),
                  )
                : _filteredContacts.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    itemCount: _filteredContacts.length,
                    itemBuilder: (context, index) {
                      final contact = _filteredContacts[index];
                      final pseudo = (contact['pseudo'] as String?) ?? '';
                      final isOnline = contact['is_online'] == true;

                      return ListTile(
                        leading: CircleAvatar(
                          radius: 26,
                          backgroundColor: const Color(0xFF2AABEE),
                          child: Text(
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
                        onTap: () => _startConversation(contact),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_search, size: 70, color: Colors.grey[700]),
            const SizedBox(height: 16),
            Text(
              'Aucun contact disponible',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[500],
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Synchronisez vos contacts depuis l\'onglet Messages, ou utilisez '
              'la barre de recherche par pseudo pour trouver quelqu\'un.',
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
