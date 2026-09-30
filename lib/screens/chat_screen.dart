import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/message_service.dart';
import '../services/contact_service.dart';
import '../services/supabase_service.dart';
import '../widgets/voice_record_button.dart';
import '../widgets/audio_message_bubble.dart';
import '../widgets/attachment_picker_button.dart';
import '../widgets/image_message_bubble.dart';
import '../widgets/file_message_bubble.dart';

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
  static const Duration _retryDelay = Duration(seconds: 5);

  // ---------------------------------------------------------------------
  // Disparition des messages reçus : file FIFO STRICTE.
  // Un seul minuteur tourne à la fois : celui du plus ancien message reçu
  // encore affiché. Le message suivant ne démarre son compte à rebours
  // que lorsque le précédent a réellement disparu (supprimé côté serveur
  // ou déjà absent). Ainsi un nouveau message ne peut jamais partir avant
  // un ancien.
  // ---------------------------------------------------------------------
  final List<dynamic> _expiryQueue = [];
  Timer? _expiryTimer;
  dynamic _activeExpiryId;
  bool _expiryBusy = false;

  // Ids déjà disparus pendant cette session : un rechargement (dont le
  // résultat peut être périmé) ne doit JAMAIS les faire réapparaître.
  final Set<dynamic> _removedIds = {};

  // Messages arrivés en temps réel pendant qu'un rechargement est en cours
  // (ils peuvent manquer dans le résultat du rechargement).
  int _loadsInFlight = 0;
  final Set<dynamic> _arrivedDuringLoad = {};

  String? _receiverAvatarUrl;

  bool _hasText = false;

  @override
  void initState() {
    super.initState();

    _loadMessages();
    _loadReceiverAvatar();
    _subscribeToConversation();

    _messageController.addListener(() {
      final hasText = _messageController.text.trim().isNotEmpty;
      if (hasText != _hasText) {
        setState(() => _hasText = hasText);
      }
    });
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

        final id = message['id'];

        // Déjà disparu ou déjà affiché (ex. déjà inclus par un rechargement).
        if (_removedIds.contains(id)) return;
        if (_messages.any((m) => m['id'] == id)) return;

        if (_loadsInFlight > 0) {
          _arrivedDuringLoad.add(id);
        }

        setState(() {
          _messages.add(message);
        });

        _scrollToBottom();
        _enqueueForExpiry(message);
      },
      onMessagesDeleted: (ids) {
        if (!mounted) return;

        for (final id in ids) {
          _removedIds.add(id);
          _expiryQueue.remove(id);

          // Le message dont le minuteur tournait a été supprimé ailleurs :
          // on arrête ce minuteur pour passer au suivant.
          if (id == _activeExpiryId && !_expiryBusy) {
            _expiryTimer?.cancel();
            _expiryTimer = null;
            _activeExpiryId = null;
          }
        }

        setState(() {
          _messages.removeWhere((m) => ids.contains(m['id']));
        });

        _startNextExpiry();
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

    _expiryTimer?.cancel();
    _expiryTimer = null;
    _expiryQueue.clear();

    if (_conversationChannel != null) {
      MessageService.unsubscribe(_conversationChannel!);
    }

    super.dispose();
  }

  Future<void> _loadMessages() async {
    _loadsInFlight++;

    final loaded = await MessageService.getConversation(
      userPhone1: widget.senderPhone,
      userPhone2: widget.receiverPhone,
    );

    _loadsInFlight--;

    if (!mounted) {
      if (_loadsInFlight == 0) _arrivedDuringLoad.clear();
      return;
    }

    // Fusion sûre : on écarte tout ce qui a déjà disparu (résultat périmé)
    // et on conserve les messages arrivés en direct pendant le chargement.
    final merged = <Map<String, dynamic>>[];
    final seen = <dynamic>{};

    for (final m in loaded) {
      final id = m['id'];
      if (_removedIds.contains(id)) continue;
      if (seen.add(id)) merged.add(m);
    }

    for (final m in _messages) {
      final id = m['id'];
      if (_removedIds.contains(id) || seen.contains(id)) continue;
      if (_arrivedDuringLoad.contains(id)) {
        seen.add(id);
        merged.add(m);
      }
    }

    if (_loadsInFlight == 0) _arrivedDuringLoad.clear();

    setState(() {
      _messages = merged;
      _isLoading = false;
    });

    _scrollToBottom();

    for (final message in merged) {
      _enqueueForExpiry(message);
    }
  }

  // Ajoute un message reçu à la fin de la file (jamais deux fois).
  void _enqueueForExpiry(Map<String, dynamic> message) {
    if (message['sender_phone'] != widget.receiverPhone) {
      return;
    }

    final id = message['id'];

    if (id == null || _removedIds.contains(id) || _expiryQueue.contains(id)) {
      return;
    }

    _expiryQueue.add(id);
    _startNextExpiry();
  }

  // Démarre le compte à rebours du message en tête de file, seulement si
  // aucun autre n'est en cours.
  void _startNextExpiry() {
    if (!mounted) return;
    if (_expiryTimer != null || _expiryBusy || _expiryQueue.isEmpty) return;

    final id = _expiryQueue.first;
    _activeExpiryId = id;
    _expiryTimer = Timer(_disappearDelay, () => _expireHead(id));
  }

  // Le message en tête de file arrive à échéance.
  Future<void> _expireHead(dynamic id) async {
    _expiryTimer = null;
    _expiryBusy = true;

    bool deletedByMe = false;
    bool gone = false;

    try {
      deletedByMe = await MessageService.deleteMessageById(id);
      gone = deletedByMe || await _isGoneFromServer(id);
    } catch (e) {
      debugPrint('Erreur disparition du message: $e');
      gone = false;
    }

    _expiryBusy = false;

    if (!mounted) return;

    if (!gone) {
      // Suppression impossible pour l'instant (réseau…) : on réessaie sur
      // le MÊME message, sans jamais laisser passer les suivants.
      _expiryTimer = Timer(_retryDelay, () => _expireHead(id));
      return;
    }

    _expiryQueue.remove(id);
    _removedIds.add(id);
    _activeExpiryId = null;

    setState(() {
      _messages.removeWhere((m) => m['id'] == id);
    });

    if (deletedByMe && _conversationChannel != null) {
      await MessageService.broadcastMessagesDeleted(
        channel: _conversationChannel!,
        ids: [id],
      );
    }

    // Seulement maintenant, le message suivant commence son compte à rebours.
    _startNextExpiry();
  }

  // Vrai si le message n'existe plus en base (déjà supprimé par ailleurs).
  Future<bool> _isGoneFromServer(dynamic id) async {
    try {
      final row = await SupabaseService.client
          .from('messages')
          .select('id')
          .eq('id', id)
          .maybeSingle();

      return row == null;
    } catch (_) {
      return false;
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

  Future<void> _sendAudioMessage(
    Uint8List bytes,
    int durationMs,
    String extension,
    String mimeType,
  ) async {
    final audioUrl = await SupabaseService.uploadVoiceMessage(
      senderPhone: widget.senderPhone,
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

    await ContactService.ensureMutualContact(
      phoneA: widget.senderPhone,
      pseudoA: widget.senderPseudo,
      phoneB: widget.receiverPhone,
      pseudoB: widget.receiverPseudo,
    );

    await MessageService.sendAudioMessage(
      senderPhone: widget.senderPhone,
      receiverPhone: widget.receiverPhone,
      audioUrl: audioUrl,
      audioDurationMs: durationMs,
    );

    await _loadMessages();
  }

  Future<void> _sendImageMessage(Uint8List bytes, String extension) async {
    final imageUrl = await SupabaseService.uploadChatImage(
      senderPhone: widget.senderPhone,
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

    await ContactService.ensureMutualContact(
      phoneA: widget.senderPhone,
      pseudoA: widget.senderPseudo,
      phoneB: widget.receiverPhone,
      pseudoB: widget.receiverPseudo,
    );

    await MessageService.sendImageMessage(
      senderPhone: widget.senderPhone,
      receiverPhone: widget.receiverPhone,
      imageUrl: imageUrl,
    );

    await _loadMessages();
  }

  Future<void> _sendFileMessage(
    Uint8List bytes,
    String fileName,
    int sizeBytes,
  ) async {
    final fileUrl = await SupabaseService.uploadChatFile(
      senderPhone: widget.senderPhone,
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

    await ContactService.ensureMutualContact(
      phoneA: widget.senderPhone,
      pseudoA: widget.senderPseudo,
      phoneB: widget.receiverPhone,
      pseudoB: widget.receiverPseudo,
    );

    await MessageService.sendFileMessage(
      senderPhone: widget.senderPhone,
      receiverPhone: widget.receiverPhone,
      fileUrl: fileUrl,
      fileName: fileName,
      fileSize: sizeBytes,
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
