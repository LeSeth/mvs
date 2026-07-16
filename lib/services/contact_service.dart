import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'supabase_service.dart';

class ContactService {
  // Vérifier si on est sur mobile
  static bool get isMobile => !kIsWeb;

  // Demander la permission d'accéder aux contacts
  static Future<bool> requestContactPermission() async {
    if (!isMobile) {
      // Sur Web, on ne peut pas accéder aux contacts
      return false;
    }

    final status = await Permission.contacts.request();
    return status.isGranted;
  }

  // Récupérer les contacts du téléphone
  static Future<List<Contact>> getPhoneContacts() async {
    if (!isMobile) {
      print('Contacts non disponibles sur Web');
      return [];
    }

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

    return phoneNumbers.toSet().toList();
  }

  // Nettoyer un numéro de téléphone -> renvoie 8 chiffres bruts (sans +226),
  // car c'est ce format qui est maintenant stocké et hashé en base.
  // Renvoie une chaîne vide si le numéro ne correspond pas à un numéro
  // burkinabè valide à 8 chiffres.
  static String _cleanPhoneNumber(String phone) {
    String cleaned = phone.replaceAll(RegExp(r'[^\d]'), '');

    if (cleaned.startsWith('226') && cleaned.length > 8) {
      cleaned = cleaned.substring(3);
    }

    if (cleaned.length == 8) {
      return cleaned;
    }

    return '';
  }

  // Synchroniser les contacts avec Supabase
  // Retourne le nombre de nouveaux contacts ajoutés, ou -1 en cas d'erreur
  // (permission refusée, pas de connexion, etc.) afin que l'UI puisse
  // donner un retour clair à l'utilisateur plutôt que d'échouer en silence.
  static Future<int> syncContacts(String userPhone) async {
    if (!isMobile) {
      print('Synchronisation contacts non disponible sur Web');
      return -1;
    }

    try {
      final hasPermission = await requestContactPermission();
      if (!hasPermission) {
        print('Permission contacts refusée');
        return -1;
      }

      final phoneContacts = await getPhoneContacts();
      final phoneNumbers = extractPhoneNumbers(phoneContacts);

      List<String> hashedNumbers = phoneNumbers
          .map((phone) => SupabaseService.hashPhoneNumber(phone))
          .toList();

      final registeredUsers = await SupabaseService.findUsersByPhoneHashes(
        hashedNumbers,
      );

      int newContactsCount = 0;
      final myHash = SupabaseService.hashPhoneNumber(userPhone);

      for (var user in registeredUsers) {
        if (user['phone_hash'] == myHash) {
          continue; // ne pas s'ajouter soi-même
        }

        final added = await addContactIfNotExists(
          userPhone: userPhone,
          contactPhoneHash: user['phone_hash'],
          contactPseudo: user['pseudo'],
        );
        if (added) newContactsCount++;
      }

      return newContactsCount;
    } catch (e) {
      print('Erreur synchronisation contacts: $e');
      return -1;
    }
  }

  // Ajoute un contact s'il n'existe pas déjà pour cet utilisateur.
  // Retourne true si un nouveau contact a été inséré.
  static Future<bool> addContactIfNotExists({
    required String userPhone,
    required String contactPhoneHash,
    required String contactPseudo,
  }) async {
    try {
      final existingContact = await SupabaseService.client
          .from('contacts')
          .select()
          .eq('user_phone', userPhone)
          .eq('contact_phone_hash', contactPhoneHash)
          .maybeSingle();

      if (existingContact == null) {
        await SupabaseService.client.from('contacts').insert({
          'user_phone': userPhone,
          'contact_phone_hash': contactPhoneHash,
          'contact_pseudo': contactPseudo,
        });
        return true;
      }
      return false;
    } catch (e) {
      print('Erreur ajout contact: $e');
      return false;
    }
  }

  // Garantit que [phoneA] et [phoneB] sont mutuellement dans les contacts
  // l'un de l'autre. Appelé à chaque envoi de message : c'est ce qui permet
  // à la conversation d'apparaître automatiquement dans la liste des
  // messages des DEUX personnes, même si elles ne se sont jamais
  // synchronisées via leurs contacts téléphone ou la recherche.
  static Future<void> ensureMutualContact({
    required String phoneA,
    required String pseudoA,
    required String phoneB,
    required String pseudoB,
  }) async {
    final hashA = SupabaseService.hashPhoneNumber(phoneA);
    final hashB = SupabaseService.hashPhoneNumber(phoneB);

    await addContactIfNotExists(
      userPhone: phoneA,
      contactPhoneHash: hashB,
      contactPseudo: pseudoB,
    );
    await addContactIfNotExists(
      userPhone: phoneB,
      contactPhoneHash: hashA,
      contactPseudo: pseudoA,
    );
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
