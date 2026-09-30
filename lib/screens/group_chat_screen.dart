import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/group_service.dart';
import '../services/supabase_service.dart';
import '../widgets/voice_record_button.dart';
import '../widgets/audio_message_bubble.dart';
import '../widgets/attachment_picker_button.dart';
import '../widgets/image_message_bubble.dart';
import '../widgets/file_message_bubble.dart';

class GroupChatScreen extends StatefulWidget {
  final String groupId;
  final String groupName;
  final String myPhone;
  final String myPseudo;

  const GroupChatScreen({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.myPhone,
    required this.myPseudo,
  });

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _renameController = TextEditingController();

  List<Map<String, dynamic>> _messages = [];
  List<Map<String, dynamic>> _members = [];

  bool _isLoading = true;
  bool _isCreator = false;

  String _groupName = '';
  String? _groupAvatarUrl;
  String? _creatorPhone;

  RealtimeChannel? _channel;

  static const Duration _disappearDelay = Duration(seconds: 20);
  final Map<dynamic, Timer> _messageTimers = {};

  late final String _myHash = SupabaseService.hashPhoneNumber(widget.myPhone);

  final Map<String, String?> _avatarsByHash = {};
  final Map<String, String?> _avatarsByPseudo = {};

  bool _hasText = false;

  // Feuille "Infos du groupe"
  // _infoRevision est incrémenté à chaque changement d'état du groupe
  // (nom, photo, membres) pour rafraîchir la feuille si elle est ouverte.
  final ValueNotifier<int> _infoRevision = ValueNotifier<int>(0);
  bool _infoOpen = false;
  bool _infoBusy = false;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();

    _loadGroupInfo();
    _loadMembers();
    _loadMessages();
    _loadAvatars();
    _subscribe();

    _messageController.addListener(() {
      final hasText = _messageController.text.trim().isNotEmpty;

      if (hasText != _hasText) {
        setState(() => _hasText = hasText);
      }
    });
  }

  // setState + rafraîchissement de la feuille d'infos.
  void _setInfo(VoidCallback fn) {
    if (!mounted) return;

    setState(fn);

    _infoRevision.value++;
  }

  Future<void> _loadGroupInfo() async {
    final group = await GroupService.getGroup(widget.groupId);

    if (!mounted || group == null) return;

    _setInfo(() {
      _groupName = group['name']?.toString() ?? widget.groupName;
      _groupAvatarUrl = group['avatar_url']?.toString();
      _creatorPhone = group['created_by']?.toString();
      _isCreator = _creatorPhone == widget.myPhone;
    });
  }

  Future<void> _loadMembers() async {
    final members = await GroupService.getGroupMembers(widget.groupId);

    if (mounted) {
      _setInfo(() {
        _members = members;
      });
    }
  }

  Future<void> _loadAvatars() async {
    try {
      final users = await SupabaseService.client
          .from('users')
          .select('phone_hash, pseudo, avatar_url');

      if (!mounted) return;

      final Map<String, String?> byHash = {};
      final Map<String, String?> byPseudo = {};

      for (final user in users) {
        final hash = user['phone_hash']?.toString();
        final pseudo = user['pseudo']?.toString();
        final avatar = user['avatar_url']?.toString();

        if (hash != null && hash.isNotEmpty) {
          byHash[hash] = avatar;
        }

        if (pseudo != null && pseudo.isNotEmpty) {
          byPseudo[pseudo] = avatar;
        }
      }

      _setInfo(() {
        _avatarsByHash
          ..clear()
          ..addAll(byHash);

        _avatarsByPseudo
          ..clear()
          ..addAll(byPseudo);
      });
    } catch (e) {
      debugPrint('Erreur récupération avatars groupe: $e');
    }
  }

  Future<void> _loadMessages() async {
    final messages = await GroupService.getGroupMessages(
      widget.groupId,
      widget.myPhone,
    );

    if (mounted) {
      setState(() {
        _messages = messages;
        _isLoading = false;
      });

      _scrollToBottom();
    }

    for (final message in _messages) {
      _scheduleMessageRead(message);
    }
  }

  void _subscribe() {
    _channel = GroupService.subscribeToGroupMessages(
      groupId: widget.groupId,
      onInsert: (message) {
        if (!mounted) return;

        setState(() {
          _messages.add(message);
        });

        _scrollToBottom();
        _scheduleMessageRead(message);
      },
      onMessagesDeleted: (ids) {
        if (!mounted) return;

        setState(() {
          _messages.removeWhere((m) => ids.contains(m['id']));
        });

        for (final id in ids) {
          _messageTimers.remove(id)?.cancel();
        }
      },
      onGroupUpdated: (name, avatarUrl) {
        if (!mounted) return;

        _setInfo(() {
          if (name != null && name.isNotEmpty) {
            _groupName = name;
          }

          if (avatarUrl != null) {
            _groupAvatarUrl = avatarUrl;
          }
        });
      },
      onGroupDeleted: () {
        if (!mounted) return;

        _leaveGroup('Ce groupe a été supprimé par son créateur.');
      },
      onMemberRemoved: (memberPhone) {
        if (!mounted) return;

        if (memberPhone == widget.myPhone) {
          _leaveGroup('Vous avez été retiré du groupe.');
        } else {
          _loadMembers();
        }
      },
    );
  }

  // Sortie forcée de l'écran (groupe supprimé ou retrait du membre).
  // Ferme d'abord la feuille d'infos et ses dialogues s'ils sont ouverts :
  // la fermeture du chat est alors faite par _openGroupInfo.
  void _leaveGroup(String message) {
    if (_leaving) return;

    _leaving = true;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));

    if (_infoOpen) {
      final chatRoute = ModalRoute.of(context);

      Navigator.of(context).popUntil((route) => route == chatRoute);
    } else {
      Navigator.of(context).pop();
    }
  }

  void _scheduleMessageRead(Map<String, dynamic> message) {
    if (message['sender_phone'] == _myHash) {
      return;
    }

    final id = message['id'];

    if (_messageTimers.containsKey(id)) {
      return;
    }

    _messageTimers[id] = Timer(
      _disappearDelay,
      () => _markSingleMessageRead(id),
    );
  }

  Future<void> _markSingleMessageRead(dynamic id) async {
    _messageTimers.remove(id);

    if (mounted) {
      setState(() {
        _messages.removeWhere((m) => m['id'] == id);
      });
    }

    await GroupService.markMessageRead(
      messageId: id,
      groupId: widget.groupId,
      memberPhone: widget.myPhone,
      channel: _channel,
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;

      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _renameController.dispose();
    _infoRevision.dispose();

    for (final timer in _messageTimers.values) {
      timer.cancel();
    }

    _messageTimers.clear();

    if (_channel != null) {
      GroupService.unsubscribe(_channel!);
    }

    super.dispose();
  }

  // =========================
  // INFOS DU GROUPE
  // =========================

  Future<void> _openGroupInfo() async {
    if (_infoOpen) return;

    _infoOpen = true;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, scrollController) => _buildInfoSheet(scrollController),
      ),
    );

    _infoOpen = false;

    if (_leaving && mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _runInfoAction(Future<void> Function() action) async {
    if (_infoBusy) return;

    _infoBusy = true;
    _infoRevision.value++;

    try {
      await action();
    } finally {
      _infoBusy = false;

      if (mounted) _infoRevision.value++;
    }
  }

  void _snack(String text) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _changeGroupPhoto() async {
    if (!_isCreator || _infoBusy) return;

    final picker = ImagePicker();

    final image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1200,
    );

    if (image == null) return;

    await _runInfoAction(() async {
      final bytes = await image.readAsBytes();

      final extension = image.path.split('.').last.toLowerCase();

      final safeExtension = extension == 'png' ? 'png' : 'jpg';

      final avatarUrl = await SupabaseService.uploadGroupAvatar(
        senderPhone: widget.myPhone,
        groupId: widget.groupId,
        bytes: bytes,
        extension: safeExtension,
      );

      if (avatarUrl == null) {
        _snack("Échec de l'envoi de la photo.");

        return;
      }

      final success = await GroupService.updateGroupAvatar(
        groupId: widget.groupId,
        requesterPhone: widget.myPhone,
        avatarUrl: avatarUrl,
        channel: _channel,
      );

      if (success) {
        _setInfo(() {
          _groupAvatarUrl = avatarUrl;
        });
      } else {
        _snack('Impossible de modifier la photo du groupe.');
      }
    });
  }

  Future<void> _renameGroup() async {
    if (!_isCreator || _infoBusy) return;

    _renameController.text = _groupName.isEmpty ? widget.groupName : _groupName;

    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) {
        void submit() {
          final value = _renameController.text.trim();

          if (value.isEmpty) return;

          Navigator.pop(ctx, value);
        }

        return AlertDialog(
          backgroundColor: const Color(0xFF1F2C34),
          title: const Text(
            'Modifier le nom du groupe',
            style: TextStyle(color: Colors.white),
          ),
          content: TextField(
            controller: _renameController,
            autofocus: true,
            maxLength: 40,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Nom du groupe',
              hintStyle: TextStyle(color: Colors.grey[500]),
              counterStyle: const TextStyle(color: Colors.grey),
            ),
            onSubmitted: (_) => submit(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler'),
            ),
            TextButton(onPressed: submit, child: const Text('Enregistrer')),
          ],
        );
      },
    );

    if (newName == null || newName == _groupName || !mounted) return;

    await _runInfoAction(() async {
      final success = await GroupService.updateGroupName(
        groupId: widget.groupId,
        requesterPhone: widget.myPhone,
        newName: newName,
        channel: _channel,
      );

      if (success) {
        _setInfo(() {
          _groupName = newName;
        });
      } else {
        _snack('Impossible de modifier le nom du groupe.');
      }
    });
  }

  Future<void> _confirmRemoveMember(String memberPhone, String pseudo) async {
    if (!_isCreator || _infoBusy) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1F2C34),
        title: const Text(
          'Retirer ce membre ?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          '$pseudo sera retiré du groupe.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Retirer', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    await _runInfoAction(() async {
      final success = await GroupService.removeMember(
        groupId: widget.groupId,
        requesterPhone: widget.myPhone,
        memberPhone: memberPhone,
        channel: _channel,
      );

      if (success) {
        await _loadMembers();
      } else {
        _snack('Impossible de retirer ce membre.');
      }
    });
  }

  Future<void> _confirmDeleteGroup() async {
    if (!_isCreator || _infoBusy) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1F2C34),
        title: const Text(
          'Supprimer le groupe ?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Le groupe, ses membres et tous ses messages seront supprimés '
          'définitivement pour tout le monde.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    await _runInfoAction(() async {
      final success = await GroupService.deleteGroup(
        groupId: widget.groupId,
        requesterPhone: widget.myPhone,
        channel: _channel,
      );

      if (success) {
        // Ferme la feuille ; _openGroupInfo ferme ensuite le chat.
        _leaving = true;

        if (mounted) Navigator.of(context).pop();
      } else {
        _snack('Impossible de supprimer le groupe.');
      }
    });
  }

  Widget _buildInfoSheet(ScrollController scrollController) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0E1621),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ValueListenableBuilder<int>(
        valueListenable: _infoRevision,
        builder: (context, _, __) {
          final members = [..._members]
            ..sort((a, b) {
              final aCreator = a['member_phone'] == _creatorPhone ? 0 : 1;
              final bCreator = b['member_phone'] == _creatorPhone ? 0 : 1;

              return aCreator.compareTo(bCreator);
            });

          final hasAvatar =
              _groupAvatarUrl != null && _groupAvatarUrl!.isNotEmpty;

          final displayName = _groupName.isEmpty
              ? widget.groupName
              : _groupName;

          return Stack(
            children: [
              ListView(
                controller: scrollController,
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 10, bottom: 8),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: Column(
                      children: [
                        GestureDetector(
                          onTap: _isCreator && !_infoBusy
                              ? _changeGroupPhoto
                              : null,
                          child: Stack(
                            children: [
                              CircleAvatar(
                                radius: 55,
                                backgroundColor: Colors.white,
                                backgroundImage: hasAvatar
                                    ? NetworkImage(_groupAvatarUrl!)
                                    : null,
                                child: hasAvatar
                                    ? null
                                    : const Icon(
                                        Icons.group,
                                        size: 55,
                                        color: Color(0xFF2AABEE),
                                      ),
                              ),
                              if (_isCreator)
                                Positioned(
                                  right: 0,
                                  bottom: 0,
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF2AABEE),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.camera_alt,
                                      size: 18,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (_isCreator)
                          TextButton.icon(
                            onPressed: _infoBusy ? null : _changeGroupPhoto,
                            icon: const Icon(
                              Icons.image_outlined,
                              color: Color(0xFF2AABEE),
                            ),
                            label: const Text(
                              'Changer la photo',
                              style: TextStyle(color: Color(0xFF2AABEE)),
                            ),
                          ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(
                              child: Text(
                                displayName,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (_isCreator)
                              IconButton(
                                tooltip: 'Modifier le nom',
                                icon: const Icon(
                                  Icons.edit,
                                  color: Color(0xFF2AABEE),
                                  size: 20,
                                ),
                                onPressed: _infoBusy ? null : _renameGroup,
                              ),
                          ],
                        ),
                        Text(
                          'Groupe · ${members.length} membre'
                          '${members.length > 1 ? "s" : ""}',
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(color: Colors.white12, height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Text(
                      '👥 ${members.length} membre'
                      '${members.length > 1 ? "s" : ""}',
                      style: const TextStyle(
                        color: Color(0xFF2AABEE),
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  ...members.map(_buildInfoMemberTile),
                  if (_isCreator) ...[
                    const SizedBox(height: 16),
                    const Divider(color: Colors.white12, height: 1),
                    ListTile(
                      leading: const Icon(
                        Icons.delete_outline,
                        color: Colors.red,
                      ),
                      title: const Text(
                        'Supprimer le groupe',
                        style: TextStyle(color: Colors.red),
                      ),
                      onTap: _infoBusy ? null : _confirmDeleteGroup,
                    ),
                  ],
                ],
              ),
              if (_infoBusy)
                const Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: LinearProgressIndicator(
                    minHeight: 2,
                    color: Color(0xFF2AABEE),
                    backgroundColor: Colors.transparent,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildInfoMemberTile(Map<String, dynamic> m) {
    final phone = m['member_phone']?.toString() ?? '';
    final pseudo = m['member_pseudo']?.toString() ?? '';

    final isMe = phone == widget.myPhone;
    final isGroupCreator = phone == _creatorPhone;

    final canRemove = _isCreator && !isMe && !isGroupCreator;

    return ListTile(
      leading: _buildSmallAvatar(
        avatarUrl: _avatarsByPseudo[pseudo],
        pseudo: pseudo,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              pseudo,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white),
            ),
          ),
          if (isMe) const Text(' (Vous)', style: TextStyle(color: Colors.grey)),
        ],
      ),
      subtitle: isGroupCreator
          ? const Text(
              'Créateur du groupe',
              style: TextStyle(color: Color(0xFF2AABEE), fontSize: 12),
            )
          : null,
      trailing: canRemove
          ? IconButton(
              tooltip: 'Retirer du groupe',
              icon: const Icon(Icons.person_remove_outlined, color: Colors.red),
              onPressed: _infoBusy
                  ? null
                  : () => _confirmRemoveMember(phone, pseudo),
            )
          : null,
    );
  }

  Widget _buildGroupAvatar() {
    return CircleAvatar(
      radius: 21,
      backgroundColor: Colors.white,
      backgroundImage: _groupAvatarUrl != null && _groupAvatarUrl!.isNotEmpty
          ? NetworkImage(_groupAvatarUrl!)
          : null,
      child: _groupAvatarUrl == null || _groupAvatarUrl!.isEmpty
          ? const Icon(Icons.group, color: Color(0xFF2AABEE))
          : null,
    );
  }

  void _sendMessage() async {
    if (_messageController.text.trim().isEmpty) {
      return;
    }

    final content = _messageController.text.trim();

    _messageController.clear();

    await GroupService.sendGroupMessage(
      groupId: widget.groupId,
      senderPhone: widget.myPhone,
      senderPseudo: widget.myPseudo,
      content: content,
    );
  }

  Future<void> _sendAudioMessage(
    Uint8List bytes,
    int durationMs,
    String extension,
    String mimeType,
  ) async {
    final audioUrl = await SupabaseService.uploadVoiceMessage(
      senderPhone: widget.myPhone,
      bytes: bytes,
      extension: extension,
      mimeType: mimeType,
    );

    if (audioUrl == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Échec de l'envoi du message vocal.")),
        );
      }

      return;
    }

    await GroupService.sendGroupAudioMessage(
      groupId: widget.groupId,
      senderPhone: widget.myPhone,
      senderPseudo: widget.myPseudo,
      audioUrl: audioUrl,
      audioDurationMs: durationMs,
    );
  }

  Future<void> _sendImageMessage(Uint8List bytes, String extension) async {
    final imageUrl = await SupabaseService.uploadChatImage(
      senderPhone: widget.myPhone,
      bytes: bytes,
      extension: extension,
    );

    if (imageUrl == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Échec de l'envoi de l'image.")),
        );
      }

      return;
    }

    await GroupService.sendGroupImageMessage(
      groupId: widget.groupId,
      senderPhone: widget.myPhone,
      senderPseudo: widget.myPseudo,
      imageUrl: imageUrl,
    );
  }

  Future<void> _sendFileMessage(
    Uint8List bytes,
    String fileName,
    int sizeBytes,
  ) async {
    final fileUrl = await SupabaseService.uploadChatFile(
      senderPhone: widget.myPhone,
      bytes: bytes,
      fileName: fileName,
    );

    if (fileUrl == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Échec de l'envoi du fichier.")),
        );
      }

      return;
    }

    await GroupService.sendGroupFileMessage(
      groupId: widget.groupId,
      senderPhone: widget.myPhone,
      senderPseudo: widget.myPseudo,
      fileUrl: fileUrl,
      fileName: fileName,
      fileSize: sizeBytes,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _openGroupInfo,
          child: Row(
            children: [
              _buildGroupAvatar(),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _groupName.isEmpty ? widget.groupName : _groupName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${_members.length} membre'
                      '${_members.length > 1 ? "s" : ""}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: _openGroupInfo,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset('assets/chat_wallpaper.png', fit: BoxFit.cover),
                _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFF2AABEE),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(12),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final message = _messages[index];

                          final isMe = message['sender_phone'] == _myHash;

                          return _buildMessageBubble(message, isMe);
                        },
                      ),
              ],
            ),
          ),
          _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> message, bool isMe) {
    final senderPseudo = message['sender_pseudo']?.toString() ?? '';

    final senderHash = message['sender_phone']?.toString();

    final avatarUrl = senderHash != null ? _avatarsByHash[senderHash] : null;

    final bubble = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isMe ? const Color(0xFF2AABEE) : const Color(0xFF1F2C34),
        borderRadius: BorderRadius.circular(16),
      ),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.72,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMe)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                senderPseudo,
                style: const TextStyle(
                  color: Color(0xFF2AABEE),
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          if (message['message_type'] == 'audio' &&
              message['audio_url'] != null)
            AudioMessageBubble(
              audioUrl: message['audio_url'].toString(),
              durationMs: message['audio_duration_ms'] as int?,
            )
          else if (message['message_type'] == 'image' &&
              message['image_url'] != null)
            ImageMessageBubble(imageUrl: message['image_url'].toString())
          else if (message['message_type'] == 'file' &&
              message['file_url'] != null)
            FileMessageBubble(
              fileUrl: message['file_url'].toString(),
              fileName: message['file_name']?.toString() ?? 'Fichier',
              fileSize: message['file_size'] as int?,
            )
          else
            Text(
              message['content']?.toString() ?? '',
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          const SizedBox(height: 4),
          Text(
            _formatTime(message['created_at'].toString()),
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );

    if (isMe) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          child: bubble,
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _buildSmallAvatar(avatarUrl: avatarUrl, pseudo: senderPseudo),
          const SizedBox(width: 8),
          Flexible(child: bubble),
        ],
      ),
    );
  }

  Widget _buildSmallAvatar({
    required String? avatarUrl,
    required String pseudo,
  }) {
    return CircleAvatar(
      radius: 24,
      backgroundColor: Colors.white,
      backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
          ? NetworkImage(avatarUrl)
          : null,
      child: avatarUrl == null || avatarUrl.isEmpty
          ? Text(
              pseudo.isNotEmpty ? pseudo[0].toUpperCase() : '?',
              style: const TextStyle(
                color: Color(0xFF2AABEE),
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            )
          : null,
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.all(8),
      color: const Color(0xFF1F2C34),
      child: Row(
        children: [
          AttachmentPickerButton(
            onImagePicked: _sendImageMessage,
            onFilePicked: _sendFileMessage,
          ),
          Expanded(
            child: TextField(
              controller: _messageController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Écrivez un message...',
                hintStyle: TextStyle(color: Colors.grey[500]),
                filled: true,
                fillColor: const Color(0xFF0E1621),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _hasText
              ? CircleAvatar(
                  backgroundColor: const Color(0xFF2AABEE),
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white),
                    onPressed: _sendMessage,
                  ),
                )
              : VoiceRecordButton(onRecorded: _sendAudioMessage),
        ],
      ),
    );
  }

  String _formatTime(String dateTime) {
    final dt = DateTime.parse(dateTime);

    final now = DateTime.now();

    if (dt.day == now.day && dt.month == now.month && dt.year == now.year) {
      return '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}';
    }

    return '${dt.day}/${dt.month} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }
}
