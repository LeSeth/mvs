import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

// Contenu d'une bulle de message vocal : bouton lecture/pause, barre de
// progression et durée. Un lecteur par bulle, créé/détruit avec le widget,
// pour éviter que plusieurs messages vocaux jouent en même temps par
// accident dans une longue liste.
class AudioMessageBubble extends StatefulWidget {
  final String audioUrl;
  final int? durationMs;
  final Color accentColor;
  final Color foregroundColor;

  const AudioMessageBubble({
    super.key,
    required this.audioUrl,
    this.durationMs,
    this.accentColor = Colors.white,
    this.foregroundColor = Colors.white,
  });

  @override
  State<AudioMessageBubble> createState() => _AudioMessageBubbleState();
}

class _AudioMessageBubbleState extends State<AudioMessageBubble> {
  final _player = AudioPlayer();

  PlayerState _state = PlayerState.stopped;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();

    _duration = Duration(milliseconds: widget.durationMs ?? 0);

    _player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });

    _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });

    _player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _state = s);
    });

    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _position = Duration.zero);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_state == PlayerState.playing) {
      await _player.pause();
    } else {
      await _player.play(UrlSource(widget.audioUrl));
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final total = _duration.inMilliseconds > 0
        ? _duration
        : Duration(milliseconds: widget.durationMs ?? 0);

    final progress = total.inMilliseconds == 0
        ? 0.0
        : (_position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);

    final showPosition =
        _state == PlayerState.playing || _position > Duration.zero;

    return SizedBox(
      width: 200,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: Icon(
              _state == PlayerState.playing
                  ? Icons.pause_circle_filled
                  : Icons.play_circle_fill,
              color: widget.accentColor,
              size: 34,
            ),
            onPressed: _toggle,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 3,
                    backgroundColor: widget.foregroundColor.withOpacity(0.25),
                    valueColor: AlwaysStoppedAnimation(widget.accentColor),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatDuration(showPosition ? _position : total),
                  style: TextStyle(
                    color: widget.foregroundColor.withOpacity(0.8),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
