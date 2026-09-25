import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../services/audio_recorder_service.dart';

// Bouton d'enregistrement de message vocal, partagé entre le chat privé
// et le chat de groupe.
//
// Comportement : un tap démarre l'enregistrement (après demande de
// permission micro), un second tap arrête l'enregistrement et déclenche
// [onRecorded]. Pendant l'enregistrement, un chronomètre s'affiche ainsi
// qu'un bouton d'annulation (corbeille).
class VoiceRecordButton extends StatefulWidget {
  final void Function(File file, int durationMs) onRecorded;

  const VoiceRecordButton({super.key, required this.onRecorded});

  @override
  State<VoiceRecordButton> createState() => _VoiceRecordButtonState();
}

class _VoiceRecordButtonState extends State<VoiceRecordButton> {
  final _recorderService = AudioRecorderService();

  bool _isRecording = false;
  Duration _elapsed = Duration.zero;
  Timer? _ticker;

  @override
  void dispose() {
    _ticker?.cancel();
    if (_isRecording) {
      _recorderService.cancel();
    }
    _recorderService.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    final started = await _recorderService.start();

    if (!started) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Autorisation du micro refusée.')),
        );
      }
      return;
    }

    setState(() {
      _isRecording = true;
      _elapsed = Duration.zero;
    });

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed += const Duration(seconds: 1));
    });
  }

  Future<void> _stopAndSend() async {
    _ticker?.cancel();
    _ticker = null;

    final result = await _recorderService.stop();

    if (mounted) setState(() => _isRecording = false);

    if (result != null) {
      widget.onRecorded(result.file, result.durationMs);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enregistrement trop court.')),
      );
    }
  }

  Future<void> _cancelRecording() async {
    _ticker?.cancel();
    _ticker = null;

    await _recorderService.cancel();

    if (mounted) setState(() => _isRecording = false);
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    if (!_isRecording) {
      return CircleAvatar(
        backgroundColor: const Color(0xFF2AABEE),
        child: IconButton(
          icon: const Icon(Icons.mic, color: Colors.white),
          onPressed: _startRecording,
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
          onPressed: _cancelRecording,
          tooltip: 'Annuler',
        ),
        const Icon(Icons.fiber_manual_record, color: Colors.red, size: 14),
        const SizedBox(width: 6),
        Text(
          _formatDuration(_elapsed),
          style: const TextStyle(color: Colors.white),
        ),
        const SizedBox(width: 8),
        CircleAvatar(
          backgroundColor: const Color(0xFF2AABEE),
          child: IconButton(
            icon: const Icon(Icons.send, color: Colors.white),
            onPressed: _stopAndSend,
            tooltip: 'Envoyer',
          ),
        ),
      ],
    );
  }
}
