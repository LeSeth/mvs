import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PhoneNumberTakenException implements Exception {
  final String message;

  PhoneNumberTakenException([
    this.message =
        'Ce numéro de téléphone est déjà utilisé par un compte existant.',
  ]);
}

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

  static String hashPhoneNumber(String phoneNumber) {
    final bytes = utf8.encode(phoneNumber);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

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
        if (existingUser['pseudo'] != pseudo) {
          throw PhoneNumberTakenException();
        }

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
    } on PhoneNumberTakenException {
      rethrow;
    } catch (e) {
      print('Erreur Supabase: $e');
      return null;
    }
  }

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
      print('Erreur recherche utilisateurs: $e');
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

  // =========================
  // AVATAR
  // =========================

  static Future<String?> getAvatarUrl(String userId) async {
    try {
      final result = await _client
          .from('users')
          .select('avatar_url')
          .eq('id', userId)
          .maybeSingle();

      return result?['avatar_url'] as String?;
    } catch (e) {
      print('Erreur récupération avatar: $e');
      return null;
    }
  }

  static Future<String?> uploadAvatar({
    required String userId,
    required Uint8List bytes,
    required String extension,
  }) async {
    try {
      final path =
          '$userId/avatar_${DateTime.now().millisecondsSinceEpoch}.$extension';

      await _client.storage
          .from('avatars')
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              contentType: extension.toLowerCase() == 'png'
                  ? 'image/png'
                  : 'image/jpeg',
              upsert: true,
            ),
          );

      final publicUrl = _client.storage.from('avatars').getPublicUrl(path);

      await _client
          .from('users')
          .update({'avatar_url': publicUrl})
          .eq('id', userId);

      return publicUrl;
    } catch (e) {
      print('Erreur upload avatar: $e');
      return null;
    }
  }

  static Future<bool> removeAvatar(String userId) async {
    try {
      await _client.from('users').update({'avatar_url': null}).eq('id', userId);

      return true;
    } catch (e) {
      print('Erreur suppression avatar: $e');
      return false;
    }
  }

  // =========================
  // MESSAGES VOCAUX
  // =========================
  // Bucket Supabase Storage dédié "voice_messages" (public, comme
  // "avatars"). Un fichier par message, rangé sous le numéro de
  // l'expéditeur pour rester cohérent avec le reste du projet.

  static const String _voiceBucket = 'voice_messages';

  static Future<String?> uploadVoiceMessage({
    required String senderPhone,
    required Uint8List bytes,
  }) async {
    try {
      final path =
          '$senderPhone/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _client.storage
          .from(_voiceBucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'audio/mp4',
              upsert: false,
            ),
          );

      return _client.storage.from(_voiceBucket).getPublicUrl(path);
    } catch (e) {
      print('Erreur upload message vocal: $e');
      return null;
    }
  }

  // Best effort : supprime le fichier audio du storage quand le message
  // éphémère correspondant disparaît de la base (lu, ou groupe/membre
  // supprimé). N'importe quelle erreur ici (fichier déjà absent, réseau...)
  // est ignorée : le message en base est déjà supprimé, c'est ce qui
  // compte pour le caractère éphémère.
  static Future<void> deleteVoiceMessage(String? audioUrl) async {
    if (audioUrl == null || audioUrl.isEmpty) return;

    try {
      const marker = '/$_voiceBucket/';
      final index = audioUrl.indexOf(marker);
      if (index == -1) return;

      final path = audioUrl.substring(index + marker.length);
      await _client.storage.from(_voiceBucket).remove([path]);
    } catch (e) {
      print('Erreur suppression fichier vocal: $e');
    }
  }
}
