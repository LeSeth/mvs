import 'dart:io' as io show File;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

// Résultat d'un enregistrement terminé : les octets audio, la durée en
// millisecondes, et l'extension/type MIME à utiliser pour l'upload.
//
// L'extension diffère selon la plateforme car le navigateur ne sait
// produire que du WebM/Opus via MediaRecorder (le web ne supporte pas
// l'encodage AAC/.m4a utilisé sur mobile/desktop) :
// - mobile/desktop -> .m4a (AAC)
// - web            -> .webm (Opus)
class RecordedAudio {
  final Uint8List bytes;
  final int durationMs;
  final String extension;
  final String mimeType;

  RecordedAudio({
    required this.bytes,
    required this.durationMs,
    required this.extension,
    required this.mimeType,
  });
}

// Encapsule le package `record` : demande la permission micro, démarre et
// arrête l'enregistrement, et retourne des octets exploitables directement
// pour l'upload — que ce soit depuis un fichier temporaire (mobile/desktop)
// ou depuis le blob renvoyé par le navigateur (web). Une instance par
// écran (ChatScreen / GroupChatScreen), détruite avec lui.
class AudioRecorderService {
  final AudioRecorder _recorder = AudioRecorder();

  DateTime? _startedAt;

  bool get isRecording => _startedAt != null;

  Future<bool> hasPermission() => _recorder.hasPermission();

  // Démarre l'enregistrement après vérification de la permission.
  // Retourne false si la permission est refusée.
  Future<bool> start() async {
    if (isRecording) return true;

    final granted = await hasPermission();
    if (!granted) return false;

    if (kIsWeb) {
      // Sur le web, `record` gère l'enregistrement (et le blob résultant)
      // en interne via MediaRecorder ; le paramètre "path" est ignoré.
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.opus),
        path: '',
      );
    } else {
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/vocal_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000),
        path: path,
      );
    }

    _startedAt = DateTime.now();
    return true;
  }

  // Arrête l'enregistrement en cours et retourne les octets + la durée.
  // Retourne null si aucun enregistrement n'était en cours, ou si
  // l'enregistrement est trop court (< 800 ms, probable appui accidentel).
  Future<RecordedAudio?> stop() async {
    if (!isRecording) return null;

    final startedAt = _startedAt!;
    final result = await _recorder.stop();
    final durationMs = DateTime.now().difference(startedAt).inMilliseconds;

    _startedAt = null;

    if (result == null || durationMs < 800) {
      await _cleanupMobileFile(result);
      return null;
    }

    if (kIsWeb) {
      // Sur le web, `result` est une URL de blob (ex: "blob:http://...").
      // On la récupère en octets via une requête HTTP classique, que le
      // navigateur sait résoudre pour un blob local.
      try {
        final response = await http.get(Uri.parse(result));
        if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
          return null;
        }
        return RecordedAudio(
          bytes: response.bodyBytes,
          durationMs: durationMs,
          extension: 'webm',
          mimeType: 'audio/webm',
        );
      } catch (e) {
        return null;
      }
    }

    final file = io.File(result);
    if (!await file.exists()) return null;

    final bytes = await file.readAsBytes();
    await file.delete();

    return RecordedAudio(
      bytes: bytes,
      durationMs: durationMs,
      extension: 'm4a',
      mimeType: 'audio/mp4',
    );
  }

  // Annule l'enregistrement en cours et supprime le fichier temporaire
  // (mobile/desktop uniquement — sur le web, rien à nettoyer sur disque).
  Future<void> cancel() async {
    if (!isRecording) return;

    final result = await _recorder.stop();
    _startedAt = null;

    await _cleanupMobileFile(result);
  }

  Future<void> _cleanupMobileFile(String? path) async {
    if (kIsWeb || path == null) return;

    final file = io.File(path);
    if (await file.exists()) await file.delete();
  }

  void dispose() {
    _recorder.dispose();
  }
}
