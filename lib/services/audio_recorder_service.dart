import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

// Résultat d'un enregistrement terminé : le fichier local (.m4a) et sa
// durée en millisecondes.
class RecordedAudio {
  final File file;
  final int durationMs;

  RecordedAudio({required this.file, required this.durationMs});
}

// Encapsule le package `record` : demande la permission micro, démarre et
// arrête l'enregistrement dans un fichier temporaire (encodage AAC),
// calcule la durée. Une instance par écran (ChatScreen / GroupChatScreen),
// détruite avec lui.
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

    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/vocal_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000),
      path: path,
    );

    _startedAt = DateTime.now();
    return true;
  }

  // Arrête l'enregistrement en cours et retourne le fichier + sa durée.
  // Retourne null si aucun enregistrement n'était en cours, ou si
  // l'enregistrement est trop court (< 800 ms, probable appui accidentel) :
  // dans ce cas le fichier temporaire est supprimé.
  Future<RecordedAudio?> stop() async {
    if (!isRecording) return null;

    final startedAt = _startedAt!;
    final path = await _recorder.stop();
    final durationMs = DateTime.now().difference(startedAt).inMilliseconds;

    _startedAt = null;

    if (path == null) return null;

    final file = File(path);
    if (!await file.exists() || durationMs < 800) {
      if (await file.exists()) await file.delete();
      return null;
    }

    return RecordedAudio(file: file, durationMs: durationMs);
  }

  // Annule l'enregistrement en cours et supprime le fichier temporaire.
  Future<void> cancel() async {
    if (!isRecording) return;

    final path = await _recorder.stop();
    _startedAt = null;

    if (path != null) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
  }

  void dispose() {
    _recorder.dispose();
  }
}
