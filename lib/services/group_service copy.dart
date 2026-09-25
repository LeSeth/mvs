import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

// Gère les groupes de discussion (à partir de 2 personnes : le créateur +
// au moins 1 autre membre). Les messages de groupe disparaissent comme en
// 1-à-1, mais par membre : chaque message disparaît individuellement de
// l'écran d'un membre dès que CE membre l'a lu (+ 20s). Il n'est supprimé
// de la base (et donc de chez TOUT LE MONDE, y compris l'expéditeur) que
// lorsque TOUS les autres membres du groupe l'ont lu.
class GroupService {
  static SupabaseClient get _client => SupabaseService.client;

  // Crée un groupe et y ajoute le créateur + les membres choisis.
  // [members] doit contenir au moins 1 personne (donc groupe de 2 min).
  static Future<Map<String, dynamic>?> createGroup({
    required String name,
    required String creatorPhone,
    required String creatorPseudo,
    required List<Map<String, String>> members,
  }) async {
    try {
      if (members.isEmpty) {
        print('Un groupe doit contenir au moins 2 personnes');
        return null;
      }

      final group = await _client
          .from('groups')
          .insert({
            'name': name,
            'created_by': creatorPhone,
            'last_message_at': DateTime.now().toIso8601String(),
          })
          .select()
          .single();

      final groupId = group['id'];

      final rows = [
        {
          'group_id': groupId,
          'member_phone': creatorPhone,
          'member_pseudo': creatorPseudo,
        },
        ...members.map(
          (m) => {
            'group_id': groupId,
            'member_phone': m['phone'],
            'member_pseudo': m['pseudo'],
          },
        ),
      ];

      await _client.from('group_members').insert(rows);

      return group;
    } catch (e) {
      print('Erreur création groupe: $e');
      return null;
    }
  }

  // Groupes dont [userPhone] est membre, triés par dernier message.
  static Future<List<Map<String, dynamic>>> getUserGroups(
    String userPhone,
  ) async {
    try {
      final memberships = await _client
          .from('group_members')
          .select('group_id')
          .eq('member_phone', userPhone);

      final groupIds = memberships.map((m) => m['group_id']).toList();
      if (groupIds.isEmpty) return [];

      final groups = await _client
          .from('groups')
          .select()
          .inFilter('id', groupIds)
          .order('last_message_at', ascending: false);

      return List<Map<String, dynamic>>.from(groups);
    } catch (e) {
      print('Erreur récupération groupes: $e');
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> getGroupMembers(
    String groupId,
  ) async {
    try {
      final members = await _client
          .from('group_members')
          .select()
          .eq('group_id', groupId)
          .order('joined_at');

      return List<Map<String, dynamic>>.from(members);
    } catch (e) {
      print('Erreur récupération membres: $e');
      return [];
    }
  }

  // Messages du groupe visibles pour [memberPhone] : on exclut ceux que ce
  // membre a déjà lus (même s'ils existent encore en base pour d'autres
  // membres qui n'ont pas encore lu), sinon ils réapparaîtraient à tort en
  // rouvrant la conversation.
  static Future<List<Map<String, dynamic>>> getGroupMessages(
    String groupId,
    String memberPhone,
  ) async {
    try {
      final messages = await _client
          .from('group_messages')
          .select()
          .eq('group_id', groupId)
          .order('created_at', ascending: true);

      final reads = await _client
          .from('group_message_reads')
          .select('message_id')
          .eq('member_phone', memberPhone);
      final readIds = reads.map((r) => r['message_id']).toSet();

      return List<Map<String, dynamic>>.from(
        messages,
      ).where((m) => !readIds.contains(m['id'])).toList();
    } catch (e) {
      print('Erreur récupération messages groupe: $e');
      return [];
    }
  }

  static Future<Map<String, dynamic>?> getLastGroupMessage(
    String groupId,
    String memberPhone,
  ) async {
    try {
      final reads = await _client
          .from('group_message_reads')
          .select('message_id')
          .eq('member_phone', memberPhone);
      final readIds = reads.map((r) => r['message_id']).toSet();

      final messages = await _client
          .from('group_messages')
          .select()
          .eq('group_id', groupId)
          .order('created_at', ascending: false)
          .limit(20); // marge pour retrouver le 1er non-lu par ce membre

      final visible = List<Map<String, dynamic>>.from(
        messages,
      ).where((m) => !readIds.contains(m['id']));

      return visible.isEmpty ? null : visible.first;
    } catch (e) {
      return null;
    }
  }

  static Future<void> sendGroupMessage({
    required String groupId,
    required String senderPhone,
    required String senderPseudo,
    required String content,
  }) async {
    try {
      await _client.from('group_messages').insert({
        'group_id': groupId,
        'sender_phone': senderPhone,
        'sender_pseudo': senderPseudo,
        'content': content,
      });

      await _client
          .from('groups')
          .update({'last_message_at': DateTime.now().toIso8601String()})
          .eq('id', groupId);
    } catch (e) {
      print('Erreur envoi message groupe: $e');
    }
  }

  // Enregistre que [memberPhone] a lu le message [messageId]. Si, après
  // cette lecture, TOUS les autres membres du groupe (hors expéditeur)
  // l'ont désormais lu, le message est supprimé définitivement de la base
  // et un broadcast est envoyé pour qu'il disparaisse aussi de tout écran
  // encore ouvert (y compris celui de l'expéditeur).
  // Retourne true si le message a été supprimé de la base.
  static Future<bool> markMessageRead({
    required dynamic messageId,
    required String groupId,
    required String memberPhone,
    RealtimeChannel? channel,
  }) async {
    try {
      // Enregistrer la lecture (upsert : ignore si déjà lu par ce membre)
      await _client
          .from('group_message_reads')
          .upsert(
            {'message_id': messageId, 'member_phone': memberPhone},
            onConflict: 'message_id,member_phone',
            ignoreDuplicates: true,
          );

      final message = await _client
          .from('group_messages')
          .select('sender_phone')
          .eq('id', messageId)
          .maybeSingle();

      if (message == null) return true; // déjà supprimé entre-temps

      final senderPhone = message['sender_phone'];

      final members = await getGroupMembers(groupId);
      final requiredReaders = members
          .map((m) => m['member_phone'] as String)
          .where((phone) => phone != senderPhone)
          .toSet();

      final reads = await _client
          .from('group_message_reads')
          .select('member_phone')
          .eq('message_id', messageId);
      final readBy = reads.map((r) => r['member_phone'] as String).toSet();

      final allRead =
          requiredReaders.isNotEmpty &&
          requiredReaders.every((phone) => readBy.contains(phone));

      if (allRead) {
        await _client.from('group_messages').delete().eq('id', messageId);

        if (channel != null) {
          await channel.sendBroadcastMessage(
            event: 'group_messages_deleted',
            payload: {
              'ids': [messageId],
            },
          );
        }
        return true;
      }

      return false;
    } catch (e) {
      print('Erreur marquage lecture groupe: $e');
      return false;
    }
  }

  // Écoute en temps réel, pour un groupe précis :
  //  - les nouveaux messages (onInsert)
  //  - les suppressions de messages "lus par tous" (onMessagesDeleted),
  //    diffusées via un broadcast (pas besoin de config DB supplémentaire).
  static RealtimeChannel subscribeToGroupMessages({
    required String groupId,
    required void Function(Map<String, dynamic> message) onInsert,
    required void Function(List<dynamic> deletedIds) onMessagesDeleted,
  }) {
    final channel = _client.channel('group_$groupId');

    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'group_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'group_id',
            value: groupId,
          ),
          callback: (payload) => onInsert(payload.newRecord),
        )
        .onBroadcast(
          event: 'group_messages_deleted',
          callback: (payload) {
            final ids = payload['ids'] as List<dynamic>? ?? [];
            onMessagesDeleted(ids);
          },
        )
        .subscribe();

    return channel;
  }

  // Écoute TOUS les nouveaux messages de groupe (pas de filtre possible sur
  // "je suis membre de ce groupe" côté Postgres), et laisse l'appelant
  // filtrer côté client selon ses groupes. Utilisé par la liste des
  // conversations pour se rafraîchir automatiquement.
  static RealtimeChannel subscribeToAllGroupMessages({
    required String channelName,
    required void Function(Map<String, dynamic> message) onInsert,
  }) {
    final channel = _client
        .channel(channelName)
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'group_messages',
          callback: (payload) => onInsert(payload.newRecord),
        )
        .subscribe();

    return channel;
  }

  static void unsubscribe(RealtimeChannel channel) {
    _client.removeChannel(channel);
  }
}
