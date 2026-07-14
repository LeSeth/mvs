import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'home_screen.dart';
import '../services/supabase_service.dart';
import '../services/contact_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _pseudoController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _pseudoController.dispose();
    super.dispose();
  }

  void _submitForm() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      // IMPORTANT : pas d'espace après l'indicatif, pour que le format
      // corresponde exactement à celui utilisé lors du hash des contacts
      // (sinon la synchronisation ne retrouve jamais aucun contact).
      String fullNumber = '+226${_phoneController.text.trim()}';
      String pseudo = _pseudoController.text.trim();

      try {
        final user = await SupabaseService.createOrLoginUser(
          phoneNumber: fullNumber,
          pseudo: pseudo,
        );

        if (mounted) {
          setState(() => _isLoading = false);

          if (user != null) {
            // Synchroniser les contacts seulement sur mobile
            // (la demande de permission est gérée à l'intérieur de syncContacts)
            if (!kIsWeb) {
              ContactService.syncContacts(fullNumber);
            }

            if (!mounted) return;

            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(
                builder: (context) => HomeScreen(
                  phoneNumber: fullNumber,
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
        backgroundColor: const Color(0xFF1F2C34),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: Text(message, style: const TextStyle(color: Colors.grey)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK', style: TextStyle(color: Color(0xFF2AABEE))),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _submitForm();
            },
            child: const Text(
              'Réessayer',
              style: TextStyle(color: Color(0xFF2AABEE)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E1621),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: kIsWeb ? 40 : 60),

                  Container(
                    width: kIsWeb ? 100 : 120,
                    height: kIsWeb ? 100 : 120,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2AABEE),
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF2AABEE).withOpacity(0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.message_rounded,
                      size: 60,
                      color: Colors.white,
                    ),
                  ),

                  const SizedBox(height: 40),

                  const Text(
                    'V Burkina',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),

                  const SizedBox(height: 8),

                  const Text('🇧🇫', style: TextStyle(fontSize: 40)),

                  const SizedBox(height: 12),

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
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.orange.withOpacity(0.3),
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

                  const SizedBox(height: 30),

                  TextFormField(
                    controller: _pseudoController,
                    style: const TextStyle(color: Colors.white, fontSize: 18),
                    decoration: InputDecoration(
                      labelText: 'Pseudo',
                      labelStyle: TextStyle(color: Colors.grey[400]),
                      hintText: 'Votre pseudo',
                      hintStyle: TextStyle(color: Colors.grey[600]),
                      prefixIcon: const Icon(
                        Icons.person,
                        color: Color(0xFF2AABEE),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey[700]!),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey[700]!),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Color(0xFF2AABEE),
                          width: 2,
                        ),
                      ),
                      filled: true,
                      fillColor: const Color(0xFF1F2C34),
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

                  const SizedBox(height: 20),

                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    maxLength: 8,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: const TextStyle(color: Colors.white, fontSize: 18),
                    decoration: InputDecoration(
                      labelText: 'Numéro de téléphone',
                      labelStyle: TextStyle(color: Colors.grey[400]),
                      hintText: '70 12 34 56',
                      hintStyle: TextStyle(color: Colors.grey[600]),
                      prefixText: '+226 ',
                      prefixStyle: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: Color(0xFF2AABEE),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey[700]!),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey[700]!),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Color(0xFF2AABEE),
                          width: 2,
                        ),
                      ),
                      counterText: '',
                      filled: true,
                      fillColor: const Color(0xFF1F2C34),
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

                  const SizedBox(height: 30),

                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _submitForm,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2AABEE),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 3,
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
                          : const Text(
                              'Se connecter',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),

                  const SizedBox(height: 30),

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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
