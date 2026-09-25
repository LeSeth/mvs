import 'package:flutter/material.dart';
import '../services/contact_service.dart';
import '../services/group_service.dart';
import '../services/supabase_service.dart';
import 'group_chat_screen.dart';

// Permet de créer un groupe à partir de 2 personnes minimum : soi-même +
// au moins 1 contact sélectionné.
class CreateGroupScreen extends StatefulWidget {
  final String phoneNumber;
  final String pseudo;

  const CreateGroupScreen({
    super.key,
    required this.phoneNumber,
    required this.pseudo,
  });

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final TextEditingController _nameController = TextEditingController();

  List<Map<String, dynamic>> _contacts = [];

  final Set<String> _selectedPhones = {};

  bool _isLoading = true;
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    final contacts = await ContactService.getContacts(widget.phoneNumber);

    if (mounted) {
      setState(() {
        _contacts = contacts;
        _isLoading = false;
      });
    }
  }

  void _toggleSelection(String contactPhoneHash) {
    setState(() {
      if (_selectedPhones.contains(contactPhoneHash)) {
        _selectedPhones.remove(contactPhoneHash);
      } else {
        _selectedPhones.add(contactPhoneHash);
      }
    });
  }

  Future<void> _createGroup() async {
    final name = _nameController.text.trim();

    if (name.isEmpty) {
      _showSnack('Donnez un nom à votre groupe');
      return;
    }

    if (_selectedPhones.isEmpty) {
      _showSnack(
        'Un groupe nécessite au moins 2 personnes : sélectionnez au moins 1 contact',
      );
      return;
    }

    setState(() => _isCreating = true);

    try {
      final selectedContacts = _contacts
          .where((c) => _selectedPhones.contains(c['contact_phone_hash']))
          .toList();

      final hashes = selectedContacts
          .map((c) => c['contact_phone_hash'].toString())
          .toList();

      final resolvedUsers = await SupabaseService.findUsersByPhoneHashes(
        hashes,
      );

      final members = selectedContacts.map((c) {
        final match = resolvedUsers.firstWhere(
          (u) => u['phone_hash'] == c['contact_phone_hash'],
          orElse: () => <String, dynamic>{},
        );

        return {
          'phone_number': (match['phone_number'] ?? c['contact_phone_hash'])
              .toString(),
          'pseudo': c['contact_pseudo'].toString(),
        };
      }).toList();

      final groupId = await GroupService.createGroup(
        name: name,
        creatorPhone: widget.phoneNumber,
        creatorPseudo: widget.pseudo,
        members: members,
      );

      if (!mounted) return;

      setState(() => _isCreating = false);

      if (groupId == null) {
        _showSnack('Impossible de créer le groupe. Vérifiez votre connexion.');
        return;
      }

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => GroupChatScreen(
            groupId: groupId,
            groupName: name,
            myPhone: widget.phoneNumber,
            myPseudo: widget.pseudo,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() => _isCreating = false);

      _showSnack('Erreur lors de la création du groupe.');

      print('Erreur création groupe: $e');
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nouveau groupe'),
        actions: [
          TextButton(
            onPressed: _isCreating ? null : _createGroup,
            child: _isCreating
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'Créer',
                    style: TextStyle(
                      color: Color(0xFF2AABEE),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _nameController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Nom du groupe',
                labelStyle: TextStyle(color: Colors.grey[400]),
                prefixIcon: const Icon(Icons.group, color: Color(0xFF2AABEE)),
                filled: true,
                fillColor: const Color(0xFF1F2C34),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${_selectedPhones.length} sélectionné'
                '${_selectedPhones.length > 1 ? "s" : ""} '
                '(minimum 1, pour un groupe de 2 personnes)',
                style: TextStyle(color: Colors.grey[500], fontSize: 12),
              ),
            ),
          ),

          const SizedBox(height: 8),

          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF2AABEE)),
                  )
                : _contacts.isEmpty
                ? Center(
                    child: Text(
                      'Aucun contact disponible.\n'
                      'Synchronisez vos contacts depuis '
                      'l\'onglet Messages.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey[500]),
                    ),
                  )
                : ListView.builder(
                    itemCount: _contacts.length,
                    itemBuilder: (context, index) {
                      final contact = _contacts[index];

                      final hash = contact['contact_phone_hash'].toString();

                      final pseudo =
                          (contact['contact_pseudo'] as String?) ?? '';

                      final isSelected = _selectedPhones.contains(hash);

                      return CheckboxListTile(
                        value: isSelected,
                        onChanged: (_) {
                          _toggleSelection(hash);
                        },
                        activeColor: const Color(0xFF2AABEE),
                        secondary: CircleAvatar(
                          backgroundColor: const Color(0xFF2AABEE),
                          child: Text(
                            pseudo.isNotEmpty ? pseudo[0].toUpperCase() : '?',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        title: Text(
                          pseudo,
                          style: const TextStyle(color: Colors.white),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
