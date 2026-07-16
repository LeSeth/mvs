import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/message_service.dart';
import '../services/contact_service.dart';

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

  // Délai avant qu'un message lu ne disparaisse définitivement (des deux
  // côtés + base de données), à partir du moment où il a été affiché.
  static const Duration _disappearDelay = Duration(seconds: 20);
  Timer? _deleteTimer;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _subscribeToConversation();
  }

  void _subscribeToConversation() {
    _conversationChannel = MessageService.subscribeToConversation(
      myPhone: widget.senderPhone,
      otherPhone: widget.receiverPhone,
      onNewMessage: (message) {
        // On ne traite que les messages venant de la personne avec qui
        // on discute actuellement dans cet écran.
        if (message['sender_phone'] != widget.receiverPhone) return;
        if (!mounted) return;

        setState(() {
          _messages.add(message);
        });
        _scrollToBottom();
        // On vient d'afficher ce message -> il disparaîtra dans 20s.
        _scheduleDeleteReadMessages();
      },
      onMessagesDeleted: (ids) {
        // L'autre personne vient de lire (et donc supprimer) des messages
        // que je lui ai envoyés : ils doivent disparaître de mon écran aussi.
        if (!mounted) return;
        setState(() {
          _messages.removeWhere((m) => ids.contains(m['id']));
        });
      },
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _deleteTimer?.cancel();
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
    // On vient d'afficher la conversation : les messages reçus sont donc
    // "ouverts" -> ils disparaîtront dans 20 secondes.
    _scheduleDeleteReadMessages();
  }

  // (Re)démarre le compte à rebours de 20s avant suppression définitive
  // des messages reçus et non encore lus. Si un nouveau message arrive
  // pendant que la conversation est ouverte, on redémarre le délai pour lui
  // laisser, à lui aussi, ses 20 secondes.
  void _scheduleDeleteReadMessages() {
    _deleteTimer?.cancel();
    _deleteTimer = Timer(_disappearDelay, _markAsReadAndDelete);
  }

  // Supprime définitivement (base de données + écran local + écran de
  // l'expéditeur s'il est ouvert) les messages que je viens de lire.
  Future<void> _markAsReadAndDelete() async {
    final deleted = await MessageService.deleteReadMessages(
      senderPhone: widget.receiverPhone, // l'autre personne, qui a envoyé
      receiverPhone: widget.senderPhone, // moi, qui viens de lire
    );

    if (deleted.isEmpty) return;

    final ids = deleted.map((m) => m['id']).toList();

    if (mounted) {
      setState(() {
        _messages.removeWhere((m) => ids.contains(m['id']));
      });
    }

    // Prévenir l'expéditeur en temps réel, si sa conversation est ouverte,
    // pour que le message disparaisse aussi de son côté.
    if (_conversationChannel != null) {
      await MessageService.broadcastMessagesDeleted(
        channel: _conversationChannel!,
        ids: ids,
      );
    }
  }

  void _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;

    String content = _messageController.text.trim();
    _messageController.clear();

    // S'assure que la conversation apparaîtra automatiquement dans la
    // liste des messages des DEUX personnes (pas seulement chez moi),
    // même si l'autre ne m'a jamais ajouté comme contact.
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.receiverPseudo,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Text(
              'En ligne',
              style: TextStyle(fontSize: 12, color: Colors.green),
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
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF2AABEE)),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    reverse: false,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      bool isMe = message['sender_phone'] == widget.senderPhone;
                      return _buildMessageBubble(message, isMe);
                    },
                  ),
          ),
          _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> message, bool isMe) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isMe ? const Color(0xFF2AABEE) : const Color(0xFF1F2C34),
          borderRadius: BorderRadius.circular(16),
        ),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.7,
        ),
        child: Column(
          crossAxisAlignment: isMe
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Text(
              message['content'],
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatTime(message['created_at']),
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
      ),
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
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } else {
      return '${dt.day}/${dt.month} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
  }
}
