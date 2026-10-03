import 'package:shared_preferences/shared_preferences.dart';

/// Mémoire LOCALE (sur le téléphone) des messages déjà « ouverts » dont la
/// disparition n'est pas encore confirmée côté serveur.
///
/// Le minuteur des messages ne dépend jamais du réseau : à l'échéance, le
/// message disparaît de l'écran et son id est inscrit ici. La synchronisation
/// avec le serveur (suppression / lecture) se fait ensuite en arrière-plan,
/// avec réessais. Tant qu'elle n'est pas confirmée, l'id reste ici, donc le
/// message ne peut pas réapparaître, même après fermeture/réouverture de la
/// conversation ou coupure de connexion.
class ExpiryStore {
  static Future<Set<String>> load(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getStringList(key) ?? const <String>[]).toSet();
    } catch (_) {
      return <String>{};
    }
  }

  static Future<void> add(String key, dynamic id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ids = (prefs.getStringList(key) ?? const <String>[]).toSet();
      if (ids.add(id.toString())) {
        await prefs.setStringList(key, ids.toList());
      }
    } catch (_) {}
  }

  static Future<void> remove(String key, dynamic id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ids = (prefs.getStringList(key) ?? const <String>[]).toSet();
      if (ids.remove(id.toString())) {
        if (ids.isEmpty) {
          await prefs.remove(key);
        } else {
          await prefs.setStringList(key, ids.toList());
        }
      }
    } catch (_) {}
  }
}
