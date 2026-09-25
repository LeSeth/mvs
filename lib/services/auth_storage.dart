import 'package:shared_preferences/shared_preferences.dart';

// Persiste la session localement sur l'appareil (SharedPreferences),
// pour que l'utilisateur reste connecté même après avoir fermé
// l'application ou redémarré/éteint le téléphone.
class AuthStorage {
  static const String _keyPhone = 'auth_phone_number';
  static const String _keyPseudo = 'auth_pseudo';
  static const String _keyUserId = 'auth_user_id';

  static Future<void> saveSession({
    required String phoneNumber,
    required String pseudo,
    required String userId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPhone, phoneNumber);
    await prefs.setString(_keyPseudo, pseudo);
    await prefs.setString(_keyUserId, userId);
  }

  // Retourne la session enregistrée, ou null si l'utilisateur ne s'est
  // jamais connecté (ou s'est déconnecté depuis).
  static Future<Map<String, String>?> loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString(_keyPhone);
    final pseudo = prefs.getString(_keyPseudo);
    final userId = prefs.getString(_keyUserId);

    if (phone == null || pseudo == null || userId == null) {
      return null;
    }

    return {'phoneNumber': phone, 'pseudo': pseudo, 'userId': userId};
  }

  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyPhone);
    await prefs.remove(_keyPseudo);
    await prefs.remove(_keyUserId);
  }
}
