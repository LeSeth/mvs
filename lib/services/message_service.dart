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

  // Messages éphémères : supprime DÉFINITIVEMENT un seul message précis de
  // la base de données (pas tous les messages non lus d'un coup), pour que
  // chaque message ait son propre délai indépendant (FIFO : le plus ancien
  // affiché disparaît avant les autres). Retourne true si effectivement
  // supprimé.
  static Future<bool> deleteMessageById(dynamic id) async {
    try {
      final deleted = await SupabaseService.client
          .from('messages')
          .delete()
          .eq('id', id)
          .select('id');

      return deleted.isNotEmpty;
    } catch (e) {
      print('Erreur suppression du message: $e');
      return false;
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
  //    détectées de DEUX façons complémentaires :
  //     1) directement via Postgres Changes DELETE sur la table (fiable,
  //        ne dépend d'aucune config supplémentaire côté broadcast),
  //     2) via un broadcast (utile si Postgres Changes DELETE est en
  //        retard ou indisponible). Les deux mènent au même résultat,
  //        donc pas de souci si les deux se déclenchent (idempotent).
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
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'sender_phone',
            value: myPhone,
          ),
          callback: (payload) {
            // Nécessite "REPLICA IDENTITY FULL" sur la table messages
            // pour que oldRecord contienne bien receiver_phone (sinon
            // seul l'id est disponible).
            final oldRecord = payload.oldRecord;
            final receiver = oldRecord['receiver_phone'];
            if (receiver == null || receiver == otherPhone) {
              final id = oldRecord['id'];
              if (id != null) onMessagesDeleted([id]);
            }
          },
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
  // en temps réel s'ils ont la conversation ouverte. Complémentaire à la
  // détection Postgres Changes DELETE ci-dessus (best effort : les erreurs
  // ne doivent pas empêcher la suppression, déjà faite en base).
  static Future<void> broadcastMessagesDeleted({
    required RealtimeChannel channel,
    required List<dynamic> ids,
  }) async {
    if (ids.isEmpty) return;
    try {
      await channel.sendBroadcastMessage(
        event: 'messages_deleted',
        payload: {'ids': ids},
      );
    } catch (e) {
      print('Erreur diffusion suppression (broadcast): $e');
    }
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
