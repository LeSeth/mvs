import 'package:flutter/material.dart';
import '../services/message_service.dart';

class ChatScreen extends StatefulWidget {
  final String senderPhone;
  final String receiverPhone;
  final String receiverPseudo;

  const ChatScreen({
    super.key,
    required this.senderPhone,
    required this.receiverPhone,
    required this.receiverPseudo,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _markMessagesAsRead();
  }

  @override
  void dispose() {
    _messageController.dispose();
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
    }
  }

  Future<void> _markMessagesAsRead() async {
    await MessageService.markAsRead(
      senderPhone: widget.receiverPhone,
      receiverPhone: widget.senderPhone,
    );
  }

  void _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;

    String content = _messageController.text.trim();
    _messageController.clear();

    await MessageService.sendMessage(
      senderPhone: widget.senderPhone,
      receiverPhone: widget.receiverPhone,
      content: content,
    );

    _loadMessages();
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
