import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'supabase_service.dart';

class ContactService {
  // Demander la permission d'accéder aux contacts
  static Future<bool> requestContactPermission() async {
    final status = await Permission.contacts.request();
    return status.isGranted;
  }

  // Récupérer les contacts du téléphone
  static Future<List<Contact>> getPhoneContacts() async {
    try {
      if (await FlutterContacts.requestPermission()) {
        return await FlutterContacts.getContacts(
          withProperties: true,
          withPhoto: false,
        );
      }
      return [];
    } catch (e) {
      print('Erreur récupération contacts: $e');
      return [];
    }
  }

  // Extraire les numéros de téléphone des contacts
  static List<String> extractPhoneNumbers(List<Contact> contacts) {
    List<String> phoneNumbers = [];

    for (var contact in contacts) {
      for (var phone in contact.phones) {
        String cleanedNumber = _cleanPhoneNumber(phone.number);
        if (cleanedNumber.isNotEmpty) {
          phoneNumbers.add(cleanedNumber);
        }
      }
    }

    return phoneNumbers.toSet().toList(); // Éviter les doublons
  }

  // Nettoyer un numéro de téléphone
  static String _cleanPhoneNumber(String phone) {
    // Enlever tous les caractères non numériques
    String cleaned = phone.replaceAll(RegExp(r'[^\d]'), '');

    // Si le numéro commence par 226, enlever le préfixe
    if (cleaned.startsWith('226') && cleaned.length > 8) {
      cleaned = cleaned.substring(3);
    }

    // Ajouter le préfixe +226 si nécessaire
    if (cleaned.length == 8) {
      return '+226$cleaned';
    }

    return cleaned;
  }

  // Synchroniser les contacts avec Supabase
  static Future<void> syncContacts(String userPhone) async {
    try {
      // 1. Récupérer les contacts du téléphone
      final phoneContacts = await getPhoneContacts();
      final phoneNumbers = extractPhoneNumbers(phoneContacts);

      // 2. Hasher tous les numéros des contacts
      List<String> hashedNumbers = phoneNumbers
          .map((phone) => SupabaseService.hashPhoneNumber(phone))
          .toList();

      // 3. Chercher ces hashs dans Supabase
      final registeredUsers = await SupabaseService.findUsersByPhoneHashes(
        hashedNumbers,
      );

      // 4. Créer les liens de contact
      for (var user in registeredUsers) {
        // Vérifier si le contact existe déjà
        final existingContact = await SupabaseService.client
            .from('contacts')
            .select()
            .eq('user_phone', userPhone)
            .eq('contact_phone_hash', user['phone_hash'])
            .maybeSingle();

        if (existingContact == null &&
            user['phone_hash'] != SupabaseService.hashPhoneNumber(userPhone)) {
          await SupabaseService.client.from('contacts').insert({
            'user_phone': userPhone,
            'contact_phone_hash': user['phone_hash'],
            'contact_pseudo': user['pseudo'],
          });
        }
      }
    } catch (e) {
      print('Erreur synchronisation contacts: $e');
    }
  }

  // Récupérer les contacts synchronisés
  static Future<List<Map<String, dynamic>>> getContacts(
    String userPhone,
  ) async {
    try {
      final contacts = await SupabaseService.client
          .from('contacts')
          .select()
          .eq('user_phone', userPhone)
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(contacts);
    } catch (e) {
      print('Erreur récupération contacts: $e');
      return [];
    }
  }

  // Supprimer un contact
  static Future<void> deleteContact(int contactId) async {
    try {
      await SupabaseService.client
          .from('contacts')
          .delete()
          .eq('id', contactId);
    } catch (e) {
      print('Erreur suppression contact: $e');
    }
  }
}
