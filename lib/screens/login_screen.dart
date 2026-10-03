import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'home_screen.dart';
import '../services/supabase_service.dart';
import '../services/contact_service.dart';
import '../services/auth_storage.dart';

// ---------------------------------------------------------------------
// Palette « réseau social »
// ---------------------------------------------------------------------
const Color _kBlue = Color(0xFF2AABEE);
const Color _kViolet = Color(0xFF8E5CF7);
const Color _kPink = Color(0xFFFF4D8D);
const Color _kBg = Color(0xFF0E1621);
const Color _kField = Color(0xFF1F2C34);

// Emojis qui montent doucement à l'arrière-plan.
class _Floater {
  final String emoji;
  final double x; // position horizontale (0 à 1)
  final double size;
  final int cycles; // nombre de montées par boucle (vitesse)
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
  _Floater('💬', 0.06, 30, 3, 0.00, 14),
  _Floater('❤️', 0.22, 24, 2, 0.35, 10),
  _Floater('😍', 0.40, 34, 4, 0.70, 16),
  _Floater('🔥', 0.58, 28, 3, 0.15, 12),
  _Floater('🎉', 0.76, 32, 2, 0.55, 18),
  _Floater('😂', 0.90, 26, 4, 0.90, 10),
  _Floater('🇧🇫', 0.14, 36, 2, 0.80, 8),
  _Floater('👍', 0.32, 24, 3, 0.50, 12),
  _Floater('✨', 0.50, 22, 4, 0.25, 14),
  _Floater('🥳', 0.68, 30, 3, 0.95, 12),
  _Floater('😎', 0.84, 28, 2, 0.10, 16),
  _Floater('💖', 0.03, 22, 4, 0.60, 10),
  _Floater('📸', 0.47, 26, 2, 0.05, 12),
  _Floater('🎥', 0.95, 24, 3, 0.45, 8),
];

// Visages qui se succèdent sur la mascotte.
const List<String> _mascotEmojis = ['😀', '😍', '🥳', '😎', '🤩', '😂', '🥰'];

// Emojis projetés quand on touche la mascotte.
const List<String> _burstEmojis = [
  '❤️',
  '🔥',
  '🎉',
  '😍',
  '✨',
  '💬',
  '🥳',
  '💖',
  '👍',
  '😂',
];

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _pseudoController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  // --- Suggestions de pseudo pendant la saisie ---
  Timer? _pseudoDebounce;
  bool _checkingPseudo = false;
  bool? _pseudoAvailable; // null = pas encore vérifié
  List<String> _pseudoSuggestions = [];

  bool _phoneComplete = false;

  // --- Animations ---
  late final AnimationController _bgCtrl; // boucle de 24 s (fond, emojis)
  late final AnimationController _introCtrl; // entrée en scène
  late final AnimationController _burstCtrl; // explosion d'emojis
  late final CurvedAnimation _mascotAnim;
  late final CurvedAnimation _headerAnim;
  late final CurvedAnimation _formAnim;
  late final CurvedAnimation _footerAnim;
  late final List<CurvedAnimation> _pillAnims;

  final ValueNotifier<int> _mascotIndex = ValueNotifier<int>(0);
  Timer? _mascotTimer;

  @override
  void initState() {
    super.initState();
    _pseudoController.addListener(_onPseudoChanged);
    _phoneController.addListener(_onPhoneChanged);

    _bgCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    )..repeat();

    _introCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..forward();

    _burstCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );

    _mascotAnim = CurvedAnimation(
      parent: _introCtrl,
      curve: const Interval(0.0, 0.55, curve: Curves.elasticOut),
    );
    _headerAnim = CurvedAnimation(
      parent: _introCtrl,
      curve: const Interval(0.15, 0.55, curve: Curves.easeOutCubic),
    );
    _formAnim = CurvedAnimation(
      parent: _introCtrl,
      curve: const Interval(0.35, 0.8, curve: Curves.easeOutCubic),
    );
    _footerAnim = CurvedAnimation(
      parent: _introCtrl,
      curve: const Interval(0.6, 1.0, curve: Curves.easeOutCubic),
    );
    _pillAnims = List.generate(
      3,
      (i) => CurvedAnimation(
        parent: _introCtrl,
        curve: Interval(0.4 + i * 0.1, 0.7 + i * 0.1, curve: Curves.elasticOut),
      ),
    );

    _mascotTimer = Timer.periodic(const Duration(milliseconds: 2200), (_) {
      _mascotIndex.value = (_mascotIndex.value + 1) % _mascotEmojis.length;
    });
  }

  @override
  void dispose() {
    _pseudoDebounce?.cancel();
    _mascotTimer?.cancel();
    _pseudoController.removeListener(_onPseudoChanged);
    _phoneController.removeListener(_onPhoneChanged);
    _phoneController.dispose();
    _pseudoController.dispose();

    _mascotAnim.dispose();
    _headerAnim.dispose();
    _formAnim.dispose();
    _footerAnim.dispose();
    for (final a in _pillAnims) {
      a.dispose();
    }
    _bgCtrl.dispose();
    _introCtrl.dispose();
    _burstCtrl.dispose();
    _mascotIndex.dispose();
    super.dispose();
  }

  void _onPhoneChanged() {
    final complete = _phoneController.text.length == 8;
    if (complete != _phoneComplete) {
      setState(() => _phoneComplete = complete);
    }
  }

  void _onPseudoChanged() {
    final query = _pseudoController.text.trim();

    _pseudoDebounce?.cancel();

    if (query.length < 3) {
      setState(() {
        _pseudoAvailable = null;
        _pseudoSuggestions = [];
        _checkingPseudo = false;
      });
      return;
    }

    _pseudoDebounce = Timer(const Duration(milliseconds: 500), () async {
      if (!mounted) return;
      setState(() => _checkingPseudo = true);

      final results = await SupabaseService.searchUsersByPseudo(query);
      final existingLower = results
          .map((u) => (u['pseudo'] as String? ?? '').toLowerCase())
          .toSet();
      final isTaken = existingLower.contains(query.toLowerCase());

      final suggestions = isTaken
          ? _generateSuggestions(query, existingLower)
          : <String>[];

      if (mounted) {
        setState(() {
          _pseudoAvailable = !isTaken;
          _pseudoSuggestions = suggestions;
          _checkingPseudo = false;
        });
      }
    });
  }

  // Génère quelques variantes disponibles autour du pseudo souhaité
  List<String> _generateSuggestions(String base, Set<String> taken) {
    final random = Random();
    final candidates = <String>{
      '${base}_bf',
      '$base${DateTime.now().year % 100}',
      '${base}_${random.nextInt(90) + 10}',
      '${base}officiel',
      '$base${random.nextInt(900) + 100}',
      '${base}_pro',
    };

    return candidates
        .where((c) => !taken.contains(c.toLowerCase()))
        .take(3)
        .toList();
  }

  void _applySuggestion(String suggestion) {
    _pseudoController.text = suggestion;
    _pseudoController.selection = TextSelection.fromPosition(
      TextPosition(offset: suggestion.length),
    );
  }

  void _submitForm() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      // On ne stocke QUE les 8 chiffres saisis, sans l'indicatif +226.
      // Ce même format (8 chiffres nettoyés) est utilisé partout : hash,
      // contacts, messages — donc tout reste cohérent.
      String localNumber = _phoneController.text.trim();
      String pseudo = _pseudoController.text.trim();

      try {
        final user = await SupabaseService.createOrLoginUser(
          phoneNumber: localNumber,
          pseudo: pseudo,
        );

        if (mounted) {
          setState(() => _isLoading = false);

          if (user != null) {
            // Sauvegarder la session localement pour rester connecté même
            // après fermeture de l'app ou redémarrage du téléphone.
            await AuthStorage.saveSession(
              phoneNumber: localNumber,
              pseudo: pseudo,
              userId: user['id'].toString(),
            );

            // Synchroniser les contacts seulement sur mobile
            // (la demande de permission est gérée à l'intérieur de syncContacts)
            if (!kIsWeb) {
              ContactService.syncContacts(localNumber);
            }

            if (!mounted) return;

            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(
                builder: (context) => HomeScreen(
                  phoneNumber: localNumber,
                  pseudo: pseudo,
                  userId: user['id'].toString(),
                ),
              ),
              (route) => false,
            );
          } else {
            _showErrorDialog(
              'Erreur de connexion',
              'Impossible de se connecter au serveur. Vérifiez votre connexion Internet et réessayez.',
            );
          }
        }
      } on PhoneNumberTakenException catch (e) {
        if (mounted) {
          setState(() => _isLoading = false);
          _showErrorDialog('Numéro déjà utilisé', e.message);
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isLoading = false);
          _showErrorDialog(
            'Erreur de connexion',
            'Vérifiez que vous avez une connexion Internet active.\n\nSi le problème persiste, réessayez plus tard.',
          );
        }
      }
    }
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _kField,
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: Text(message, style: const TextStyle(color: Colors.grey)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK', style: TextStyle(color: _kBlue)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _submitForm();
            },
            child: const Text('Réessayer', style: TextStyle(color: _kBlue)),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Mascotte : touchez-la pour faire exploser des emojis
  // ---------------------------------------------------------------------
  void _burst() {
    HapticFeedback.lightImpact();
    _mascotIndex.value = (_mascotIndex.value + 1) % _mascotEmojis.length;
    _burstCtrl.forward(from: 0);
  }

  Widget _buildMascot() {
    return GestureDetector(
      onTap: _burst,
      behavior: HitTestBehavior.opaque,
      child: ScaleTransition(
        scale: _mascotAnim,
        child: SizedBox(
          width: 230,
          height: 190,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              // Halo qui respire + tuile principale
              AnimatedBuilder(
                animation: _bgCtrl,
                builder: (context, _) {
                  final pulse = sin(_bgCtrl.value * 2 * pi * 6);
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 170 + 14 * pulse,
                        height: 170 + 14 * pulse,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              _kViolet.withValues(alpha: 0.35),
                              _kViolet.withValues(alpha: 0),
                            ],
                          ),
                        ),
                      ),
                      Transform.scale(
                        scale: 1 + 0.03 * pulse,
                        child: Container(
                          width: kIsWeb ? 104 : 116,
                          height: kIsWeb ? 104 : 116,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(34),
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [_kBlue, _kViolet, _kPink],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: _kBlue.withValues(alpha: 0.4),
                                blurRadius: 28,
                                offset: const Offset(0, 12),
                              ),
                            ],
                          ),
                          child: Center(
                            child: ValueListenableBuilder<int>(
                              valueListenable: _mascotIndex,
                              builder: (context, index, _) {
                                return AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 450),
                                  transitionBuilder: (child, anim) {
                                    return ScaleTransition(
                                      scale: anim,
                                      child: RotationTransition(
                                        turns: Tween<double>(
                                          begin: -0.08,
                                          end: 0.0,
                                        ).animate(anim),
                                        child: child,
                                      ),
                                    );
                                  },
                                  child: Text(
                                    _mascotEmojis[index],
                                    key: ValueKey<int>(index),
                                    style: const TextStyle(fontSize: 58),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),

              // Bulles de réactions qui flottent autour
              _badge('❤️', const Alignment(-0.78, -0.65), 0.0),
              _badge('💬', const Alignment(0.82, -0.45), 2.0),
              _badge('🔥', const Alignment(0.62, 0.8), 4.0),

              // Explosion d'emojis au toucher
              IgnorePointer(
                child: AnimatedBuilder(
                  animation: _burstCtrl,
                  builder: (context, _) {
                    final v = _burstCtrl.value;
                    if (v == 0 || v == 1) return const SizedBox.shrink();

                    final e = Curves.easeOutCubic.transform(v);
                    final n = _burstEmojis.length;

                    return Stack(
                      alignment: Alignment.center,
                      clipBehavior: Clip.none,
                      children: List.generate(n, (i) {
                        final angle = (i / n) * 2 * pi - pi / 2;
                        final dist = 40 + 95 * e;

                        return Transform.translate(
                          offset: Offset(cos(angle) * dist, sin(angle) * dist),
                          child: Opacity(
                            opacity: (1 - v).clamp(0.0, 1.0).toDouble(),
                            child: Text(
                              _burstEmojis[i],
                              style: TextStyle(fontSize: 20 + 10 * (1 - v)),
                            ),
                          ),
                        );
                      }),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badge(String emoji, Alignment alignment, double phase) {
    return Align(
      alignment: alignment,
      child: AnimatedBuilder(
        animation: _bgCtrl,
        builder: (context, child) {
          final bob = sin(_bgCtrl.value * 2 * pi * 6 + phase) * 6;
          return Transform.translate(offset: Offset(0, bob), child: child);
        },
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.08),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child: Center(
            child: Text(emoji, style: const TextStyle(fontSize: 20)),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Fond animé
  // ---------------------------------------------------------------------
  Widget _blob(Alignment alignment, Color color, double size) {
    return Align(
      alignment: alignment,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }

  Widget _buildBlobs() {
    return AnimatedBuilder(
      animation: _bgCtrl,
      builder: (context, _) {
        final t = _bgCtrl.value * 2 * pi;
        return Stack(
          children: [
            _blob(
              Alignment(-0.9 + 0.25 * sin(t), -0.8 + 0.2 * cos(t)),
              _kBlue,
              360,
            ),
            _blob(
              Alignment(0.95 + 0.15 * cos(t), -0.1 + 0.3 * sin(t)),
              _kViolet,
              340,
            ),
            _blob(
              Alignment(-0.3 + 0.3 * sin(t * 2), 1.0 + 0.1 * cos(t)),
              _kPink,
              320,
            ),
          ],
        );
      },
    );
  }

  Widget _buildFloaters(Size size) {
    return AnimatedBuilder(
      animation: _bgCtrl,
      builder: (context, _) {
        final t = _bgCtrl.value;
        final children = <Widget>[];

        for (final f in _floaters) {
          final p = (t * f.cycles + f.offset) % 1.0;
          final wave = sin((p * 2 + f.offset) * 2 * pi);
          final top = size.height * (1.05 - 1.2 * p);
          final left = f.x * size.width + wave * f.sway;
          final opacity = sin(p * pi).clamp(0.0, 1.0).toDouble() * 0.5;

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

  // ---------------------------------------------------------------------
  // Éléments d'interface
  // ---------------------------------------------------------------------
  Widget _stagger(Animation<double> anim, Widget child) {
    return FadeTransition(
      opacity: anim,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.12),
          end: Offset.zero,
        ).animate(anim),
        child: child,
      ),
    );
  }

  Widget _pill(String text, Animation<double> anim) {
    return ScaleTransition(
      scale: anim,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  // Emoji qui change selon l'état du champ.
  Widget _emojiPrefix(String emoji) {
    return SizedBox(
      width: 52,
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, anim) =>
              ScaleTransition(scale: anim, child: child),
          child: Text(
            emoji,
            key: ValueKey<String>(emoji),
            style: const TextStyle(fontSize: 22),
          ),
        ),
      ),
    );
  }

  String get _pseudoEmoji {
    if (_checkingPseudo) return '🤔';
    if (_pseudoAvailable == true) return '🥳';
    if (_pseudoAvailable == false) return '😅';
    return '😎';
  }

  InputDecoration _decoration({
    required String label,
    required String hint,
    required Widget prefixIcon,
    String? prefixText,
    TextStyle? prefixStyle,
    bool hideCounter = false,
  }) {
    OutlineInputBorder border(Color color, [double width = 1]) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: color, width: width),
      );
    }

    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: Colors.grey[400]),
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey[600]),
      prefixIcon: prefixIcon,
      prefixText: prefixText,
      prefixStyle: prefixStyle,
      counterText: hideCounter ? '' : null,
      border: border(Colors.grey[700]!),
      enabledBorder: border(Colors.white.withValues(alpha: 0.12)),
      focusedBorder: border(_kBlue, 2),
      errorBorder: border(Colors.redAccent),
      focusedErrorBorder: border(Colors.redAccent, 2),
      filled: true,
      fillColor: _kField,
    );
  }

  Widget _buildPseudoFeedback() {
    if (_checkingPseudo) {
      return Padding(
        padding: const EdgeInsets.only(top: 8, left: 4),
        child: Row(
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.grey[500],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Vérification du pseudo...',
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
            ),
          ],
        ),
      );
    }

    if (_pseudoAvailable == false) {
      return Padding(
        padding: const EdgeInsets.only(top: 8, left: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ce pseudo est déjà pris 😅',
              style: TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
            if (_pseudoSuggestions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _pseudoSuggestions.map((s) {
                  return ActionChip(
                    label: Text(s),
                    backgroundColor: _kField,
                    labelStyle: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                    ),
                    side: const BorderSide(color: _kBlue),
                    onPressed: () => _applySuggestion(s),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      );
    }

    if (_pseudoAvailable == true) {
      return const Padding(
        padding: EdgeInsets.only(top: 8, left: 4),
        child: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 14),
            SizedBox(width: 6),
            Text(
              'Pseudo disponible 🎉',
              style: TextStyle(color: Colors.green, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildSubmitButton() {
    return AnimatedBuilder(
      animation: _bgCtrl,
      builder: (context, child) {
        final glow = 18 + 8 * sin(_bgCtrl.value * 2 * pi * 6);
        return Container(
          width: double.infinity,
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(colors: [_kBlue, _kViolet, _kPink]),
            boxShadow: [
              BoxShadow(
                color: _kViolet.withValues(alpha: 0.45),
                blurRadius: glow,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: child,
        );
      },
      child: ElevatedButton(
        onPressed: _isLoading ? null : _submitForm,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          foregroundColor: Colors.white,
          disabledForegroundColor: Colors.white70,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: _isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Se connecter',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 8),
                  AnimatedBuilder(
                    animation: _bgCtrl,
                    builder: (context, child) {
                      final dy = -3 * sin(_bgCtrl.value * 2 * pi * 12);
                      return Transform.translate(
                        offset: Offset(0, dy),
                        child: child,
                      );
                    },
                    child: const Text('🚀', style: TextStyle(fontSize: 20)),
                  ),
                ],
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    return Scaffold(
      backgroundColor: _kBg,
      body: Stack(
        children: [
          // Dégradé de fond
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF111B2B), _kBg, Color(0xFF0A0F18)],
                ),
              ),
            ),
          ),

          // Halos de couleur qui dérivent doucement
          if (!reduceMotion)
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(child: _buildBlobs()),
              ),
            ),

          // Emojis qui montent à l'arrière-plan
          if (!reduceMotion)
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: LayoutBuilder(
                    builder: (context, constraints) => _buildFloaters(
                      Size(constraints.maxWidth, constraints.maxHeight),
                    ),
                  ),
                ),
              ),
            ),

          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _buildMascot(),

                      _stagger(
                        _headerAnim,
                        Column(
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ShaderMask(
                                  shaderCallback: (rect) =>
                                      const LinearGradient(
                                        colors: [
                                          Colors.white,
                                          Color(0xFFBFE6FF),
                                        ],
                                      ).createShader(rect),
                                  child: const Text(
                                    'V Burkina',
                                    style: TextStyle(
                                      fontSize: 34,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.5,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                AnimatedBuilder(
                                  animation: _bgCtrl,
                                  builder: (context, child) {
                                    final angle =
                                        0.16 * sin(_bgCtrl.value * 2 * pi * 12);
                                    return Transform.rotate(
                                      angle: angle,
                                      alignment: Alignment.bottomLeft,
                                      child: child,
                                    );
                                  },
                                  child: const Text(
                                    '🇧🇫',
                                    style: TextStyle(fontSize: 34),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 10),

                            Text(
                              kIsWeb
                                  ? 'Connectez-vous à votre compte'
                                  : 'Créez votre compte\npour commencer',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[400],
                                height: 1.5,
                              ),
                            ),

                            // Message spécifique Web
                            if (kIsWeb) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.orange.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(
                                      Icons.info_outline,
                                      color: Colors.orange,
                                      size: 20,
                                    ),
                                    SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Version Web : La synchronisation des contacts n\'est pas disponible',
                                        style: TextStyle(
                                          color: Colors.orange,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _pill('💬 Messages', _pillAnims[0]),
                          _pill('🎥 Vidéos', _pillAnims[1]),
                          _pill('📸 Statuts', _pillAnims[2]),
                        ],
                      ),

                      const SizedBox(height: 26),

                      _stagger(
                        _formAnim,
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.10),
                            ),
                          ),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              children: [
                                TextFormField(
                                  controller: _pseudoController,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                  ),
                                  decoration: _decoration(
                                    label: 'Pseudo',
                                    hint: 'Votre pseudo',
                                    prefixIcon: _emojiPrefix(_pseudoEmoji),
                                  ),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Veuillez entrer un pseudo';
                                    }
                                    if (value.length < 3) {
                                      return 'Le pseudo doit contenir au moins 3 caractères';
                                    }
                                    return null;
                                  },
                                ),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: AnimatedSize(
                                    duration: const Duration(milliseconds: 250),
                                    alignment: Alignment.topLeft,
                                    child: _buildPseudoFeedback(),
                                  ),
                                ),

                                const SizedBox(height: 18),

                                TextFormField(
                                  controller: _phoneController,
                                  keyboardType: TextInputType.phone,
                                  maxLength: 8,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                  ),
                                  decoration: _decoration(
                                    label: 'Numéro de téléphone',
                                    hint: '70 12 34 56',
                                    prefixIcon: _emojiPrefix(
                                      _phoneComplete ? '✅' : '📱',
                                    ),
                                    prefixText: '+226 ',
                                    prefixStyle: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                      color: _kBlue,
                                    ),
                                    hideCounter: true,
                                  ),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Veuillez entrer votre numéro';
                                    }
                                    if (value.length != 8) {
                                      return 'Le numéro doit contenir 8 chiffres';
                                    }
                                    return null;
                                  },
                                ),

                                const SizedBox(height: 24),

                                _buildSubmitButton(),
                              ],
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 26),

                      _stagger(
                        _footerAnim,
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Text(
                            'En continuant, vous acceptez nos conditions '
                            'd\'utilisation et notre politique de confidentialité',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                              height: 1.5,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
