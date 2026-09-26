import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/group_service.dart';
import '../services/supabase_service.dart';
import '../widgets/voice_record_button.dart';
import '../widgets/audio_message_bubble.dart';

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

  List<Map<String, dynamic>> _messages = [];
  List<Map<String, dynamic>> _members = [];

  bool _isLoading = true;

  RealtimeChannel? _channel;

  static const Duration _disappearDelay = Duration(seconds: 20);
  final Map<dynamic, Timer> _messageTimers = {};

  late final String _myHash = SupabaseService.hashPhoneNumber(widget.myPhone);

  final Map<String, String?> _avatarsByHash = {};
  final Map<String, String?> _avatarsByPseudo = {};

  bool _hasText = false;

  @override
  void initState() {
    super.initState();

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

  Future<void> _loadMembers() async {
    final members = await GroupService.getGroupMembers(widget.groupId);

    if (mounted) {
      setState(() {
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

      setState(() {
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
    );
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

    for (final timer in _messageTimers.values) {
      timer.cancel();
    }

    _messageTimers.clear();

    if (_channel != null) {
      GroupService.unsubscribe(_channel!);
    }

    super.dispose();
  }

  void _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;

    final content = _messageController.text.trim();

    _messageController.clear();

    await GroupService.sendGroupMessage(
      groupId: widget.groupId,
      senderPhone: widget.myPhone,
      senderPseudo: widget.myPseudo,
      content: content,
    );
  }

  Future<void> _sendAudioMessage(File file, int durationMs) async {
    try {
      final bytes = await file.readAsBytes();

      final audioUrl = await SupabaseService.uploadVoiceMessage(
        senderPhone: widget.myPhone,
        bytes: bytes,
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
    } finally {
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.groupName,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              '${_members.length} membre${_members.length > 1 ? "s" : ""}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: _showMembersSheet,
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

  void _showMembersSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1F2C34),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '${_members.length} membre${_members.length > 1 ? "s" : ""}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            ..._members.map((m) {
              final pseudo = (m['member_pseudo'] as String?) ?? '';

              final avatarUrl = _avatarsByPseudo[pseudo];

              return ListTile(
                leading: _buildSmallAvatar(
                  avatarUrl: avatarUrl,
                  pseudo: pseudo,
                ),
                title: Text(
                  pseudo,
                  style: const TextStyle(color: Colors.white),
                ),
              );
            }),
            const SizedBox(height: 12),
          ],
        ),
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
