import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Stockage LOCAL de la liste des conversations (contacts + groupes), pour
/// qu'elle reste visible sans connexion, comme sur WhatsApp.
///
/// La liste est enregistrée après chaque chargement réussi, et relue
/// instantanément à l'ouverture de l'application. Le réseau ne fait que
/// la mettre à jour ensuite.
class ConversationCache {
  static String _key(String myPhone) => 'conversation_list_$myPhone';

  static Future<List<Map<String, dynamic>>> load(String myPhone) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(myPhone));

      if (raw == null || raw.isEmpty) return [];

      final decoded = jsonDecode(raw);

      if (decoded is! List) return [];

      return decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(
    String myPhone,
    List<Map<String, dynamic>> items,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key(myPhone), jsonEncode(items));
    } catch (_) {}
  }
}
