import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/audio_service.dart';
import '../services/group_service.dart';
import '../services/supabase_service.dart';

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
  bool _isRecording = false;
  bool _isUploadingAudio = false;

  RealtimeChannel? _channel;

  static const Duration _disappearDelay = Duration(seconds: 20);

  final Map<dynamic, Timer> _messageTimers = {};

  late final String _myHash = SupabaseService.hashPhoneNumber(widget.myPhone);

  @override
  void initState() {
    super.initState();

    _loadMembers();
    _loadMessages();
    _subscribe();
  }

  Future<void> _loadMembers() async {
    try {
      final members = await GroupService.getGroupMembers(widget.groupId);

      if (!mounted) return;

      setState(() {
        _members = members;
      });
    } catch (e) {
      debugPrint('Erreur chargement membres: $e');
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

        final existingIndex = _messages.indexWhere(
          (item) => item['id'] == message['id'],
        );

        if (existingIndex != -1) {
          return;
        }

        setState(() {
          _messages.add(message);
        });

        _scrollToBottom();
        _scheduleMessageRead(message);
      },
      onDelete: (ids) {
        if (!mounted) return;

        setState(() {
          _messages.removeWhere((message) => ids.contains(message['id']));
        });

        for (final id in ids) {
          _messageTimers.remove(id)?.cancel();
        }
      },
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

  void _scheduleMessageRead(Map<String, dynamic> message) {
    final senderPhone = message['sender_phone']?.toString();

    if (senderPhone == _myHash) {
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

    final success = await GroupService.markMessageRead(
      messageId: id,
      phoneNumber: widget.myPhone,
    );

    if (!success) return;

    if (mounted) {
      setState(() {
        _messages.removeWhere((message) => message['id'] == id);
      });
    }
  }

  Future<void> _sendMessage() async {
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

    await _loadMessages();
  }

  Future<void> _toggleRecording() async {
    if (_isUploadingAudio) {
      return;
    }

    if (!_isRecording) {
      final path = await AudioService.startRecording();

      if (path == null) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Autorisation du microphone nécessaire.'),
          ),
        );

        return;
      }

      if (!mounted) return;

      setState(() {
        _isRecording = true;
      });

      return;
    }

    if (!mounted) return;

    setState(() {
      _isRecording = false;
      _isUploadingAudio = true;
    });

    final path = await AudioService.stopRecording();

    if (path == null) {
      if (!mounted) return;

      setState(() {
        _isUploadingAudio = false;
      });

      return;
    }

    final audioUrl = await AudioService.uploadAudio(
      localPath: path,
      folder: 'groups',
    );

    if (audioUrl == null) {
      if (!mounted) return;

      setState(() {
        _isUploadingAudio = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible d’envoyer le message vocal.')),
      );

      return;
    }

    await GroupService.sendVoiceMessage(
      groupId: widget.groupId,
      senderPhone: widget.myPhone,
      senderPseudo: widget.myPseudo,
      audioUrl: audioUrl,
    );

    if (!mounted) return;

    setState(() {
      _isUploadingAudio = false;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.groupName,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              '${_members.length} membre${_members.length > 1 ? 's' : ''}',
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
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
    final messageType = message['message_type']?.toString() ?? 'text';

    final isAudio = messageType == 'audio';

    final senderPseudo = message['sender_pseudo']?.toString() ?? 'Utilisateur';

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
        crossAxisAlignment: isMe
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
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
          if (isAudio)
            _buildAudioMessage(message)
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

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!isMe) ...[
              _buildMemberAvatar(senderPseudo),
              const SizedBox(width: 8),
            ],
            Flexible(child: bubble),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioMessage(Map<String, dynamic> message) {
    final audioUrl = message['media_url']?.toString();

    if (audioUrl == null || audioUrl.isEmpty) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.mic_off, color: Colors.white),
          SizedBox(width: 8),
          Text('Audio indisponible', style: TextStyle(color: Colors.white)),
        ],
      );
    }

    return VoiceMessagePlayer(
      audioUrl: audioUrl,
      isMe: message['sender_phone'] == _myHash,
    );
  }

  Widget _buildMemberAvatar(String pseudo) {
    return CircleAvatar(
      radius: 22,
      backgroundColor: Colors.white,
      child: Text(
        pseudo.isNotEmpty ? pseudo[0].toUpperCase() : '?',
        style: const TextStyle(
          color: Color(0xFF2AABEE),
          fontWeight: FontWeight.bold,
          fontSize: 17,
        ),
      ),
    );
  }

  Widget _buildMessageInput() {
    if (_isRecording) {
      return Container(
        padding: const EdgeInsets.all(8),
        color: const Color(0xFF1F2C34),
        child: Row(
          children: [
            const Expanded(
              child: Row(
                children: [
                  Icon(Icons.mic, color: Colors.red),
                  SizedBox(width: 10),
                  Text(
                    'Enregistrement...',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ],
              ),
            ),
            CircleAvatar(
              backgroundColor: Colors.red,
              child: IconButton(
                icon: const Icon(Icons.stop, color: Colors.white),
                onPressed: _toggleRecording,
              ),
            ),
          ],
        ),
      );
    }

    if (_isUploadingAudio) {
      return Container(
        padding: const EdgeInsets.all(12),
        color: const Color(0xFF1F2C34),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF2AABEE),
              ),
            ),
            SizedBox(width: 10),
            Text(
              'Envoi du message vocal...',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
      );
    }

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
                suffixIcon: IconButton(
                  icon: const Icon(Icons.mic, color: Color(0xFF2AABEE)),
                  onPressed: _toggleRecording,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            backgroundColor: const Color(0xFF2AABEE),
            child: IconButton(
              icon: const Icon(Icons.send, color: Colors.white),
              onPressed: _sendMessage,
            ),
          ),
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
