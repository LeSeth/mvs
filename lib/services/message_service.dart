import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

class MessageService {
  static Future<bool> sendMessage({
    required String senderPhone,
    required String receiverPhone,
    required String content,
  }) async {
    try {
      await SupabaseService.client.from('messages').insert({
        'sender_phone': senderPhone,
        'receiver_phone': receiverPhone,
        'content': content,
        'is_read': false,
        'created_at': DateTime.now().toIso8601String(),
      });
      return true;
    } catch (e) {
      print('Erreur envoi message: $e');
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> getConversation({
    required String userPhone1,
    required String userPhone2,
  }) async {
    try {
      final messages = await SupabaseService.client
          .from('messages')
          .select()
          .or(
            'and(sender_phone.eq.$userPhone1,receiver_phone.eq.$userPhone2),and(sender_phone.eq.$userPhone2,receiver_phone.eq.$userPhone1)',
          )
          .order('created_at', ascending: true);

      return List<Map<String, dynamic>>.from(messages);
    } catch (e) {
      print('Erreur récupération conversation: $e');
      return [];
    }
  }

  // Messages éphémères : dès que [receiverPhone] lit les messages envoyés
  // par [senderPhone], on les supprime DÉFINITIVEMENT de la base de données
  // (et pas seulement marqués comme lus). Retourne les lignes supprimées
  // (avec leur id) pour pouvoir les retirer aussi de l'écran local.
  static Future<List<Map<String, dynamic>>> deleteReadMessages({
    required String senderPhone,
    required String receiverPhone,
  }) async {
    try {
      final deleted = await SupabaseService.client
          .from('messages')
          .delete()
          .eq('sender_phone', senderPhone)
          .eq('receiver_phone', receiverPhone)
          .select('id');

      return List<Map<String, dynamic>>.from(deleted);
    } catch (e) {
      print('Erreur suppression des messages lus: $e');
      return [];
    }
  }

  static Future<Map<String, dynamic>?> getLastMessage({
    required String userPhone1,
    required String userPhone2,
  }) async {
    try {
      final message = await SupabaseService.client
          .from('messages')
          .select()
          .or(
            'and(sender_phone.eq.$userPhone1,receiver_phone.eq.$userPhone2),and(sender_phone.eq.$userPhone2,receiver_phone.eq.$userPhone1)',
          )
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      return message;
    } catch (e) {
      print('Erreur dernier message: $e');
      return null;
    }
  }

  static Future<int> getUnreadCount({
    required String userPhone,
    required String contactPhone,
  }) async {
    try {
      final count = await SupabaseService.client
          .from('messages')
          .select()
          .eq('sender_phone', contactPhone)
          .eq('receiver_phone', userPhone)
          .eq('is_read', false);

      return count.length;
    } catch (e) {
      return 0;
    }
  }

  // Écoute en temps réel, pour une conversation donnée entre [myPhone] et
  // [otherPhone] :
  //  - les nouveaux messages qui arrivent (onNewMessage)
  //  - les suppressions de messages "lus" côté en face (onMessagesDeleted),
  //    diffusées via un broadcast (pas besoin de config DB supplémentaire).
  // Un seul canal, nommé de façon stable (peu importe qui l'ouvre en
  // premier), est partagé par les deux participants de la conversation.
  static RealtimeChannel subscribeToConversation({
    required String myPhone,
    required String otherPhone,
    required void Function(Map<String, dynamic> message) onNewMessage,
    required void Function(List<dynamic> deletedIds) onMessagesDeleted,
  }) {
    final pair = [myPhone, otherPhone]..sort();
    final channelName = 'conv_${pair[0]}_${pair[1]}';

    final channel = SupabaseService.client.channel(channelName);

    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'receiver_phone',
            value: myPhone,
          ),
          callback: (payload) => onNewMessage(payload.newRecord),
        )
        .onBroadcast(
          event: 'messages_deleted',
          callback: (payload) {
            final ids = payload['ids'] as List<dynamic>? ?? [];
            onMessagesDeleted(ids);
          },
        )
        .subscribe();

    return channel;
  }

  // Diffuse aux autres abonnés du canal la liste des messages qui viennent
  // d'être lus et supprimés, pour qu'ils disparaissent aussi de leur écran
  // en temps réel s'ils ont la conversation ouverte.
  static Future<void> broadcastMessagesDeleted({
    required RealtimeChannel channel,
    required List<dynamic> ids,
  }) async {
    if (ids.isEmpty) return;
    await channel.sendBroadcastMessage(
      event: 'messages_deleted',
      payload: {'ids': ids},
    );
  }

  // Écoute en temps réel les nouveaux messages reçus par [myPhone].
  // Utilisé par la liste des conversations (badges/aperçus), qui n'a pas
  // besoin de savoir précisément QUELLE conversation a bougé.
  static RealtimeChannel subscribeToIncomingMessages({
    required String myPhone,
    required void Function(Map<String, dynamic> message) onInsert,
    required String channelName,
  }) {
    final channel = SupabaseService.client
        .channel(channelName)
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'receiver_phone',
            value: myPhone,
          ),
          callback: (payload) {
            onInsert(payload.newRecord);
          },
        )
        .subscribe();

    return channel;
  }

  static void unsubscribe(RealtimeChannel channel) {
    SupabaseService.client.removeChannel(channel);
  }
}
