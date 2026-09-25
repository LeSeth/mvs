import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

class GroupService {
  static SupabaseClient get _client => SupabaseService.client;

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
          .limit(20);

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
    String messageType = 'text',
    String? audioUrl,
    int? audioDurationMs,
  }) async {
    try {
      await _client.from('group_messages').insert({
        'group_id': groupId,
        'sender_phone': SupabaseService.hashPhoneNumber(senderPhone),
        'sender_pseudo': senderPseudo,
        'content': content,
        'message_type': messageType,
        'audio_url': audioUrl,
        'audio_duration_ms': audioDurationMs,
      });

      await _client
          .from('groups')
          .update({'last_message_at': DateTime.now().toIso8601String()})
          .eq('id', groupId);
    } catch (e) {
      print('Erreur envoi message groupe: $e');
    }
  }

  // Message vocal de groupe : [audioUrl] pointe vers le fichier déjà
  // uploadé dans le bucket Storage "voice_messages".
  static Future<void> sendGroupAudioMessage({
    required String groupId,
    required String senderPhone,
    required String senderPseudo,
    required String audioUrl,
    required int audioDurationMs,
  }) {
    return sendGroupMessage(
      groupId: groupId,
      senderPhone: senderPhone,
      senderPseudo: senderPseudo,
      content: '🎤 Message vocal',
      messageType: 'audio',
      audioUrl: audioUrl,
      audioDurationMs: audioDurationMs,
    );
  }

  static Future<bool> markMessageRead({
    required dynamic messageId,
    required String groupId,
    required String memberPhone,
    RealtimeChannel? channel,
  }) async {
    try {
      await _client
          .from('group_message_reads')
          .upsert(
            {'message_id': messageId, 'member_phone': memberPhone},
            onConflict: 'message_id,member_phone',
            ignoreDuplicates: true,
          );

      final message = await _client
          .from('group_messages')
          .select('sender_phone, audio_url')
          .eq('id', messageId)
          .maybeSingle();

      if (message == null) return true; // déjà supprimé entre-temps

      final senderPhoneHash = message['sender_phone'];
      final audioUrl = message['audio_url'] as String?;

      final members = await getGroupMembers(groupId);
      final requiredReaders = members
          .map((m) => m['member_phone'] as String)
          .where(
            (phone) =>
                SupabaseService.hashPhoneNumber(phone) != senderPhoneHash,
          )
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

        unawaited(SupabaseService.deleteVoiceMessage(audioUrl));

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

  static Future<Map<String, dynamic>?> getGroup(String groupId) async {
    try {
      final group = await _client
          .from('groups')
          .select()
          .eq('id', groupId)
          .maybeSingle();
      return group;
    } catch (e) {
      print('Erreur récupération groupe: $e');
      return null;
    }
  }

  static Future<bool> updateGroupName({
    required String groupId,
    required String requesterPhone,
    required String newName,
    RealtimeChannel? channel,
  }) async {
    try {
      final name = newName.trim();
      if (name.isEmpty) return false;

      final group = await getGroup(groupId);
      if (group == null || group['created_by'] != requesterPhone) {
        return false;
      }

      await _client.from('groups').update({'name': name}).eq('id', groupId);

      if (channel != null) {
        await channel.sendBroadcastMessage(
          event: 'group_updated',
          payload: {'name': name},
        );
      }
      return true;
    } catch (e) {
      print('Erreur modification nom groupe: $e');
      return false;
    }
  }

  static Future<bool> deleteGroup({
    required String groupId,
    required String requesterPhone,
    RealtimeChannel? channel,
  }) async {
    try {
      final group = await getGroup(groupId);
      if (group == null || group['created_by'] != requesterPhone) {
        return false;
      }

      final messages = await _client
          .from('group_messages')
          .select('id, audio_url')
          .eq('group_id', groupId);
      final messageIds = messages.map((m) => m['id']).toList();
      final audioUrls = messages
          .map((m) => m['audio_url'] as String?)
          .where((u) => u != null && u.isNotEmpty)
          .toList();

      if (messageIds.isNotEmpty) {
        await _client
            .from('group_message_reads')
            .delete()
            .inFilter('message_id', messageIds);
        await _client.from('group_messages').delete().eq('group_id', groupId);
      }

      for (final url in audioUrls) {
        unawaited(SupabaseService.deleteVoiceMessage(url));
      }

      await _client.from('group_members').delete().eq('group_id', groupId);
      await _client.from('groups').delete().eq('id', groupId);

      if (channel != null) {
        await channel.sendBroadcastMessage(
          event: 'group_deleted',
          payload: {'group_id': groupId},
        );
      }
      return true;
    } catch (e) {
      print('Erreur suppression groupe: $e');
      return false;
    }
  }

  static Future<bool> removeMember({
    required String groupId,
    required String requesterPhone,
    required String memberPhone,
    RealtimeChannel? channel,
  }) async {
    try {
      if (requesterPhone == memberPhone) return false;

      final group = await getGroup(groupId);
      if (group == null || group['created_by'] != requesterPhone) {
        return false;
      }

      final member = await _client
          .from('group_members')
          .select('member_phone')
          .eq('group_id', groupId)
          .eq('member_phone', memberPhone)
          .maybeSingle();
      if (member == null) return false;

      final messages = await _client
          .from('group_messages')
          .select('id')
          .eq('group_id', groupId);
      final messageIds = messages.map((m) => m['id']).toList();

      if (messageIds.isNotEmpty) {
        await _client
            .from('group_message_reads')
            .delete()
            .eq('member_phone', memberPhone)
            .inFilter('message_id', messageIds);
      }

      await _client
          .from('group_members')
          .delete()
          .eq('group_id', groupId)
          .eq('member_phone', memberPhone);

      if (channel != null) {
        await channel.sendBroadcastMessage(
          event: 'group_member_removed',
          payload: {'member_phone': memberPhone},
        );
      }
      return true;
    } catch (e) {
      print('Erreur suppression membre: $e');
      return false;
    }
  }

  static RealtimeChannel subscribeToGroupMessages({
    required String groupId,
    required void Function(Map<String, dynamic> message) onInsert,
    required void Function(List<dynamic> deletedIds) onMessagesDeleted,
    void Function(String name)? onGroupUpdated,
    void Function()? onGroupDeleted,
    void Function(String memberPhone)? onMemberRemoved,
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
        .onBroadcast(
          event: 'group_updated',
          callback: (payload) {
            final name = payload['name']?.toString();
            if (name != null && name.isNotEmpty) onGroupUpdated?.call(name);
          },
        )
        .onBroadcast(
          event: 'group_deleted',
          callback: (_) => onGroupDeleted?.call(),
        )
        .onBroadcast(
          event: 'group_member_removed',
          callback: (payload) {
            final phone = payload['member_phone']?.toString();
            if (phone != null && phone.isNotEmpty) {
              onMemberRemoved?.call(phone);
            }
          },
        )
        .subscribe();

    return channel;
  }

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

  static RealtimeChannel subscribeToMyGroupMemberships({
    required String myPhone,
    required void Function() onNewMembership,
    required String channelName,
  }) {
    final channel = _client
        .channel(channelName)
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'group_members',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'member_phone',
            value: myPhone,
          ),
          callback: (payload) => onNewMembership(),
        )
        .subscribe();

    return channel;
  }

  static void unsubscribe(RealtimeChannel channel) {
    _client.removeChannel(channel);
  }
}
