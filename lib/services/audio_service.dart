import 'dart:io';
import 'package:flutter/material.dart';

import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'supabase_service.dart';

class AudioService {
  static final AudioRecorder recorder = AudioRecorder();

  static bool _isRecording = false;

  static bool get isRecording => _isRecording;

  /// Démarre l'enregistrement vocal.
  static Future<String?> startRecording() async {
    try {
      final hasPermission = await recorder.hasPermission();

      if (!hasPermission) {
        return null;
      }

      final directory = await getTemporaryDirectory();

      final path =
          '${directory.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: path,
      );

      _isRecording = true;

      return path;
    } catch (e) {
      print('Erreur démarrage enregistrement vocal: $e');
      _isRecording = false;
      return null;
    }
  }

  /// Arrête l'enregistrement vocal.
  static Future<String?> stopRecording() async {
    try {
      final path = await recorder.stop();

      _isRecording = false;

      return path;
    } catch (e) {
      print('Erreur arrêt enregistrement vocal: $e');
      _isRecording = false;
      return null;
    }
  }

  /// Envoie le fichier audio vers Supabase Storage.
  static Future<String?> uploadAudio({
    required String localPath,
    required String folder,
  }) async {
    try {
      final file = File(localPath);

      if (!await file.exists()) {
        return null;
      }

      final bytes = await file.readAsBytes();

      final filePath =
          '$folder/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await SupabaseService.client.storage
          .from('chat_audio')
          .uploadBinary(
            filePath,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'audio/mp4',
              upsert: false,
            ),
          );

      final publicUrl = SupabaseService.client.storage
          .from('chat_audio')
          .getPublicUrl(filePath);

      return publicUrl;
    } catch (e) {
      print('Erreur upload audio: $e');
      return null;
    }
  }
}

/// Lecteur d'un message vocal.
class VoiceMessagePlayer extends StatefulWidget {
  final String audioUrl;
  final bool isMe;

  const VoiceMessagePlayer({
    super.key,
    required this.audioUrl,
    required this.isMe,
  });

  @override
  State<VoiceMessagePlayer> createState() => _VoiceMessagePlayerState();
}

class _VoiceMessagePlayerState extends State<VoiceMessagePlayer> {
  final AudioPlayer _player = AudioPlayer();

  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();

    _player.onDurationChanged.listen((duration) {
      if (!mounted) return;

      setState(() {
        _duration = duration;
      });
    });

    _player.onPositionChanged.listen((position) {
      if (!mounted) return;

      setState(() {
        _position = position;
      });
    });

    _player.onPlayerComplete.listen((_) {
      if (!mounted) return;

      setState(() {
        _isPlaying = false;
        _position = Duration.zero;
      });
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    try {
      if (_isPlaying) {
        await _player.pause();

        if (!mounted) return;

        setState(() {
          _isPlaying = false;
        });

        return;
      }

      await _player.play(UrlSource(widget.audioUrl));

      if (!mounted) return;

      setState(() {
        _isPlaying = true;
      });
    } catch (e) {
      print('Erreur lecture audio: $e');
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');

    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final maxDuration = _duration.inMilliseconds > 0
        ? _duration.inMilliseconds.toDouble()
        : 1.0;

    final currentPosition = _position.inMilliseconds
        .clamp(0, _duration.inMilliseconds)
        .toDouble();

    return SizedBox(
      width: 230,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: _togglePlay,
            icon: Icon(
              _isPlaying ? Icons.pause : Icons.play_arrow,
              color: Colors.white,
            ),
          ),
          Expanded(
            child: Slider(
              value: currentPosition,
              max: maxDuration,
              onChanged: _duration.inMilliseconds == 0
                  ? null
                  : (value) async {
                      await _player.seek(Duration(milliseconds: value.toInt()));
                    },
            ),
          ),
          Text(
            _formatDuration(_isPlaying ? _position : _duration),
            style: const TextStyle(color: Colors.white, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
