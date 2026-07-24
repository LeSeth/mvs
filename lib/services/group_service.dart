import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

// Gère les groupes de discussion (à partir de 2 personnes : le créateur +
// au moins 1 autre membre). Contrairement aux messages 1-à-1, les messages
// de groupe ne sont PAS éphémères (pas de suppression automatique après
// lecture) : avec plusieurs participants, "lu par tout le monde" n'a pas de
// sens simple, donc on garde l'historique du groupe.
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

  static Future<List<Map<String, dynamic>>> getGroupMessages(
    String groupId,
  ) async {
    try {
      final messages = await _client
          .from('group_messages')
          .select()
          .eq('group_id', groupId)
          .order('created_at', ascending: true);

      return List<Map<String, dynamic>>.from(messages);
    } catch (e) {
      print('Erreur récupération messages groupe: $e');
      return [];
    }
  }

  static Future<Map<String, dynamic>?> getLastGroupMessage(
    String groupId,
  ) async {
    try {
      final messages = await _client
          .from('group_messages')
          .select()
          .eq('group_id', groupId)
          .order('created_at', ascending: false)
          .limit(1);

      if (messages.isEmpty) return null;
      return messages[0];
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

  // Écoute en temps réel les nouveaux messages d'un groupe précis.
  static RealtimeChannel subscribeToGroupMessages({
    required String groupId,
    required void Function(Map<String, dynamic> message) onInsert,
  }) {
    final channel = _client
        .channel('group_$groupId')
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
