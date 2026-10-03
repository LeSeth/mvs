import 'dart:math';

import 'package:flutter/material.dart';

const Color _kBlue = Color(0xFF2AABEE);
const Color _kViolet = Color(0xFF8E5CF7);
const Color _kPink = Color(0xFFFF4D8D);

// Emojis qui montent très doucement derrière les conversations
// (opacité faible : la liste reste parfaitement lisible).
class _Floater {
  final String emoji;
  final double x; // position horizontale (0 à 1)
  final double size;
  final int cycles; // montées par boucle (vitesse)
  final double offset; // décalage de départ (0 à 1)
  final double sway; // amplitude du balancement

  const _Floater(
    this.emoji,
    this.x,
    this.size,
    this.cycles,
    this.offset,
    this.sway,
  );
}

const List<_Floater> _floaters = [
  _Floater('💬', 0.08, 26, 1, 0.00, 14),
  _Floater('❤️', 0.24, 20, 2, 0.40, 10),
  _Floater('😍', 0.42, 28, 1, 0.70, 16),
  _Floater('🔥', 0.60, 22, 2, 0.15, 12),
  _Floater('🎉', 0.78, 26, 1, 0.55, 18),
  _Floater('✨', 0.92, 20, 3, 0.85, 10),
  _Floater('🇧🇫', 0.16, 28, 1, 0.80, 8),
  _Floater('👍', 0.34, 20, 2, 0.60, 12),
  _Floater('🥳', 0.52, 24, 1, 0.30, 12),
  _Floater('💖', 0.70, 20, 2, 0.95, 10),
  _Floater('📸', 0.86, 22, 1, 0.20, 12),
  _Floater('🎥', 0.04, 20, 2, 0.65, 8),
];

class _Dot {
  final double x;
  final double y;
  final double r;
  final double phase;
  final int speed; // scintillements par boucle
  final Color color;

  const _Dot(this.x, this.y, this.r, this.phase, this.speed, this.color);
}

/// Fond animé de la page d'accueil : dégradé profond, halos de couleur qui
/// dérivent, petites étoiles qui scintillent et emojis qui montent.
/// À placer derrière le contenu (par exemple dans un Stack).
class AnimatedChatBackground extends StatefulWidget {
  const AnimatedChatBackground({super.key});

  @override
  State<AnimatedChatBackground> createState() => _AnimatedChatBackgroundState();
}

class _AnimatedChatBackgroundState extends State<AnimatedChatBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final List<_Dot> _dots;

  @override
  void initState() {
    super.initState();

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 36),
    )..repeat();

    final random = Random(11);
    const colors = [Colors.white, _kBlue, _kViolet, _kPink];

    _dots = List.generate(30, (_) {
      return _Dot(
        random.nextDouble(),
        random.nextDouble(),
        0.8 + random.nextDouble() * 1.8,
        random.nextDouble(),
        4 + random.nextInt(9),
        colors[random.nextInt(colors.length)],
      );
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Widget _blob(Alignment alignment, Color color, double size, double alpha) {
    return Align(
      alignment: alignment,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: alpha),
              color.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBlobs() {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = _ctrl.value * 2 * pi;
        return Stack(
          children: [
            _blob(
              Alignment(-0.95 + 0.25 * sin(t), -0.85 + 0.2 * cos(t)),
              _kBlue,
              380,
              0.24,
            ),
            _blob(
              Alignment(1.0 + 0.1 * cos(t), -0.15 + 0.35 * sin(t)),
              _kViolet,
              360,
              0.22,
            ),
            _blob(
              Alignment(-0.25 + 0.35 * sin(t * 2), 1.0 + 0.1 * cos(t)),
              _kPink,
              340,
              0.18,
            ),
          ],
        );
      },
    );
  }

  Widget _buildFloaters(Size size) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = _ctrl.value;
        final children = <Widget>[];

        for (final f in _floaters) {
          final p = (t * f.cycles + f.offset) % 1.0;
          final wave = sin((p * 2 + f.offset) * 2 * pi);
          final top = size.height * (1.05 - 1.2 * p);
          final left = f.x * size.width + wave * f.sway;
          final opacity = sin(p * pi).clamp(0.0, 1.0).toDouble() * 0.2;

          children.add(
            Positioned(
              left: left,
              top: top,
              child: Opacity(
                opacity: opacity,
                child: Transform.rotate(
                  angle: wave * 0.25,
                  child: Text(f.emoji, style: TextStyle(fontSize: f.size)),
                ),
              ),
            ),
          );
        }

        return Stack(children: children);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Dégradé de fond
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF111B2B),
                  Color(0xFF0E1621),
                  Color(0xFF0A0F18),
                ],
              ),
            ),
          ),

          // Halos de couleur qui dérivent
          RepaintBoundary(
            child: reduceMotion
                ? Stack(
                    children: [
                      _blob(const Alignment(-0.95, -0.85), _kBlue, 380, 0.24),
                      _blob(const Alignment(1.0, -0.15), _kViolet, 360, 0.22),
                      _blob(const Alignment(-0.25, 1.0), _kPink, 340, 0.18),
                    ],
                  )
                : _buildBlobs(),
          ),

          if (!reduceMotion) ...[
            // Étoiles qui scintillent
            RepaintBoundary(
              child: CustomPaint(painter: _SparklePainter(_ctrl, _dots)),
            ),

            // Emojis qui montent
            RepaintBoundary(
              child: LayoutBuilder(
                builder: (context, constraints) => _buildFloaters(
                  Size(constraints.maxWidth, constraints.maxHeight),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SparklePainter extends CustomPainter {
  final Animation<double> anim;
  final List<_Dot> dots;

  _SparklePainter(this.anim, this.dots) : super(repaint: anim);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();

    for (final d in dots) {
      final tw = 0.5 + 0.5 * sin((anim.value * d.speed + d.phase) * 2 * pi);
      final drift = 5 * sin((anim.value * 2 + d.phase) * 2 * pi);

      paint.color = d.color.withValues(alpha: 0.08 + 0.34 * tw);

      canvas.drawCircle(
        Offset(d.x * size.width, d.y * size.height + drift),
        d.r * (0.8 + 0.4 * tw),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SparklePainter oldDelegate) =>
      oldDelegate.dots != dots;
}
