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

  static Future<void> markAsRead({
    required String senderPhone,
    required String receiverPhone,
  }) async {
    try {
      await SupabaseService.client
          .from('messages')
          .update({'is_read': true})
          .eq('sender_phone', senderPhone)
          .eq('receiver_phone', receiverPhone)
          .eq('is_read', false);
    } catch (e) {
      print('Erreur marquage lecture: $e');
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
}
