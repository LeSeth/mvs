import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/group_service.dart';

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

  @override
  void initState() {
    super.initState();
    _loadMembers();
    _loadMessages();
    _subscribe();
  }

  Future<void> _loadMembers() async {
    final members = await GroupService.getGroupMembers(widget.groupId);
    if (mounted) setState(() => _members = members);
  }

  Future<void> _loadMessages() async {
    final messages = await GroupService.getGroupMessages(widget.groupId);
    if (mounted) {
      setState(() {
        _messages = messages;
        _isLoading = false;
      });
      _scrollToBottom();
    }
  }

  void _subscribe() {
    _channel = GroupService.subscribeToGroupMessages(
      groupId: widget.groupId,
      onInsert: (message) {
        if (!mounted) return;
        setState(() => _messages.add(message));
        _scrollToBottom();
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
    if (_channel != null) GroupService.unsubscribe(_channel!);
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
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF2AABEE)),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      final isMe = message['sender_phone'] == widget.myPhone;
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Nom de l'expéditeur (utile en groupe, contrairement au 1-à-1)
            if (!isMe)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  message['sender_pseudo'] ?? '',
                  style: const TextStyle(
                    color: Color(0xFF2AABEE),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            Text(
              message['content'],
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              _formatTime(message['created_at']),
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 11,
              ),
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
              return ListTile(
                leading: CircleAvatar(
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
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } else {
      return '${dt.day}/${dt.month} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
  }
}
