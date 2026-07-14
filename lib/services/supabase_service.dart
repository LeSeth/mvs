import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

class SupabaseService {
  static const String _url = 'https://azbsjltcltepkdteoeqr.supabase.co';
  static const String _anonKey =
      'sb_publishable_kO-1KBpI1t4NSItKmWsrFA_zyymGJGa';

  static late SupabaseClient _client;

  static Future<void> init() async {
    await Supabase.initialize(url: _url, anonKey: _anonKey);
    _client = Supabase.instance.client;
  }

  static SupabaseClient get client => _client;

  // Hasher un numéro de téléphone
  static String hashPhoneNumber(String phoneNumber) {
    final bytes = utf8.encode(phoneNumber);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  // Créer ou connecter un utilisateur
  static Future<Map<String, dynamic>?> createOrLoginUser({
    required String phoneNumber,
    required String pseudo,
  }) async {
    try {
      final phoneHash = hashPhoneNumber(phoneNumber);

      final existingUser = await _client
          .from('users')
          .select()
          .eq('phone_number', phoneNumber)
          .maybeSingle();

      if (existingUser != null) {
        await _client
            .from('users')
            .update({
              'last_login': DateTime.now().toIso8601String(),
              'is_online': true,
              'phone_hash': phoneHash,
            })
            .eq('phone_number', phoneNumber);

        return existingUser;
      } else {
        final newUser = await _client
            .from('users')
            .insert({
              'phone_number': phoneNumber,
              'pseudo': pseudo,
              'phone_hash': phoneHash,
              'created_at': DateTime.now().toIso8601String(),
              'last_login': DateTime.now().toIso8601String(),
              'is_online': true,
            })
            .select()
            .single();

        return newUser;
      }
    } catch (e) {
      print('Erreur Supabase: $e');
      return null;
    }
  }

  // Récupérer tous les utilisateurs
  static Future<List<Map<String, dynamic>>> getAllUsers() async {
    try {
      final users = await _client
          .from('users')
          .select('id, pseudo, phone_number, phone_hash, is_online, last_login')
          .order('is_online', ascending: false);
      return List<Map<String, dynamic>>.from(users);
    } catch (e) {
      print('Erreur récupération utilisateurs: $e');
      return [];
    }
  }

  // Trouver des utilisateurs par leurs numéros hashés
  static Future<List<Map<String, dynamic>>> findUsersByPhoneHashes(
    List<String> hashes,
  ) async {
    try {
      if (hashes.isEmpty) return [];

      final users = await _client
          .from('users')
          .select('id, pseudo, phone_number, phone_hash, is_online, last_login')
          .inFilter('phone_hash', hashes);

      return List<Map<String, dynamic>>.from(users);
    } catch (e) {
      print('Erreur recherche utilisateurs: $e');
      return [];
    }
  }

  // Rechercher des utilisateurs par pseudo (recherche globale, insensible à la casse)
  static Future<List<Map<String, dynamic>>> searchUsersByPseudo(
    String query, {
    String? excludePhoneNumber,
  }) async {
    try {
      if (query.trim().isEmpty) return [];

      final users = await _client
          .from('users')
          .select('id, pseudo, phone_number, phone_hash, is_online')
          .ilike('pseudo', '%${query.trim()}%')
          .limit(20);

      List<Map<String, dynamic>> results = List<Map<String, dynamic>>.from(
        users,
      );

      if (excludePhoneNumber != null) {
        results = results
            .where((u) => u['phone_number'] != excludePhoneNumber)
            .toList();
      }

      return results;
    } catch (e) {
      print('Erreur recherche pseudo: $e');
      return [];
    }
  }

  static Future<void> setOnlineStatus(String phoneNumber, bool isOnline) async {
    try {
      await _client
          .from('users')
          .update({
            'is_online': isOnline,
            'last_login': DateTime.now().toIso8601String(),
          })
          .eq('phone_number', phoneNumber);
    } catch (e) {
      print('Erreur statut: $e');
    }
  }

  static Future<void> logout(String phoneNumber) async {
    try {
      await _client
          .from('users')
          .update({'is_online': false})
          .eq('phone_number', phoneNumber);
    } catch (e) {
      print('Erreur déconnexion: $e');
    }
  }
}
