import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/message_service.dart';
import '../services/contact_service.dart';
import '../services/supabase_service.dart';

class ChatScreen extends StatefulWidget {
  final String senderPhone;
  final String senderPseudo;
  final String receiverPhone;
  final String receiverPseudo;

  const ChatScreen({
    super.key,
    required this.senderPhone,
    required this.senderPseudo,
    required this.receiverPhone,
    required this.receiverPseudo,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();

  List<Map<String, dynamic>> _messages = [];

  bool _isLoading = true;

  RealtimeChannel? _conversationChannel;

  static const Duration _disappearDelay = Duration(seconds: 20);

  final Map<dynamic, Timer> _messageTimers = {};

  String? _receiverAvatarUrl;

  @override
  void initState() {
    super.initState();

    _loadMessages();
    _loadReceiverAvatar();
    _subscribeToConversation();
  }

  Future<void> _loadReceiverAvatar() async {
    try {
      final user = await SupabaseService.client
          .from('users')
          .select('avatar_url')
          .eq('phone_number', widget.receiverPhone)
          .maybeSingle();

      if (!mounted) return;

      setState(() {
        _receiverAvatarUrl = user?['avatar_url']?.toString();
      });
    } catch (e) {
      debugPrint('Erreur récupération avatar conversation: $e');
    }
  }

  void _subscribeToConversation() {
    _conversationChannel = MessageService.subscribeToConversation(
      myPhone: widget.senderPhone,
      otherPhone: widget.receiverPhone,
      onNewMessage: (message) {
        if (message['sender_phone'] != widget.receiverPhone) {
          return;
        }

        if (!mounted) return;

        setState(() {
          _messages.add(message);
        });

        _scrollToBottom();
        _scheduleMessageDeletion(message);
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

    if (_conversationChannel != null) {
      MessageService.unsubscribe(_conversationChannel!);
    }

    super.dispose();
  }

  Future<void> _loadMessages() async {
    final messages = await MessageService.getConversation(
      userPhone1: widget.senderPhone,
      userPhone2: widget.receiverPhone,
    );

    if (mounted) {
      setState(() {
        _messages = messages;
        _isLoading = false;
      });

      _scrollToBottom();
    }

    for (final message in _messages) {
      _scheduleMessageDeletion(message);
    }
  }

  void _scheduleMessageDeletion(Map<String, dynamic> message) {
    if (message['sender_phone'] != widget.receiverPhone) {
      return;
    }

    final id = message['id'];

    if (_messageTimers.containsKey(id)) {
      return;
    }

    _messageTimers[id] = Timer(_disappearDelay, () => _deleteSingleMessage(id));
  }

  Future<void> _deleteSingleMessage(dynamic id) async {
    _messageTimers.remove(id);

    final deleted = await MessageService.deleteMessageById(id);

    if (!deleted) return;

    if (mounted) {
      setState(() {
        _messages.removeWhere((m) => m['id'] == id);
      });
    }

    if (_conversationChannel != null) {
      await MessageService.broadcastMessagesDeleted(
        channel: _conversationChannel!,
        ids: [id],
      );
    }
  }

  void _sendMessage() async {
    if (_messageController.text.trim().isEmpty) {
      return;
    }

    final content = _messageController.text.trim();

    _messageController.clear();

    await ContactService.ensureMutualContact(
      phoneA: widget.senderPhone,
      pseudoA: widget.senderPseudo,
      phoneB: widget.receiverPhone,
      pseudoB: widget.receiverPseudo,
    );

    await MessageService.sendMessage(
      senderPhone: widget.senderPhone,
      receiverPhone: widget.receiverPhone,
      content: content,
    );

    await _loadMessages();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            _buildHeaderAvatar(),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.receiverPseudo,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Text(
                    'En ligne',
                    style: TextStyle(fontSize: 12, color: Colors.green),
                  ),
                ],
              ),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
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

                          final isMe =
                              message['sender_phone'] == widget.senderPhone;

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

  Widget _buildHeaderAvatar() {
    return CircleAvatar(
      radius: 24,
      backgroundColor: const Color(0xFF2AABEE),
      backgroundImage:
          _receiverAvatarUrl != null && _receiverAvatarUrl!.isNotEmpty
          ? NetworkImage(_receiverAvatarUrl!)
          : null,
      child: _receiverAvatarUrl == null || _receiverAvatarUrl!.isEmpty
          ? Text(
              widget.receiverPseudo.isNotEmpty
                  ? widget.receiverPseudo[0].toUpperCase()
                  : '?',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            )
          : null,
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> message, bool isMe) {
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
                widget.receiverPseudo,
                style: const TextStyle(
                  color: Color(0xFF2AABEE),
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          Text(
            message['content']?.toString() ?? '',
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _formatTime(message['created_at'].toString()),
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 11,
                ),
              ),
              if (isMe) ...[
                const SizedBox(width: 4),
                Icon(
                  message['is_read'] == true ? Icons.done_all : Icons.done,
                  size: 14,
                  color: Colors.white.withOpacity(0.7),
                ),
              ],
            ],
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
          _buildReceiverMessageAvatar(),
          const SizedBox(width: 8),
          Flexible(child: bubble),
        ],
      ),
    );
  }

  Widget _buildReceiverMessageAvatar() {
    return CircleAvatar(
      radius: 24,
      backgroundColor: Colors.white,
      backgroundImage:
          _receiverAvatarUrl != null && _receiverAvatarUrl!.isNotEmpty
          ? NetworkImage(_receiverAvatarUrl!)
          : null,
      child: _receiverAvatarUrl == null || _receiverAvatarUrl!.isEmpty
          ? Text(
              widget.receiverPseudo.isNotEmpty
                  ? widget.receiverPseudo[0].toUpperCase()
                  : '?',
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
