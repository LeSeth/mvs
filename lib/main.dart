import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'services/supabase_service.dart';
import 'services/auth_storage.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialiser Supabase
  await SupabaseService.init();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'V BF',
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF1F2C34),
        scaffoldBackgroundColor: const Color(0xFF0E1621),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1F2C34),
          foregroundColor: Colors.white,
          elevation: 1,
        ),
        cardColor: const Color(0xFF1F2C34),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Color(0xFF1F2C34),
        ),
        // Adapter pour mobile
        textTheme: ThemeData.dark().textTheme.copyWith(
          bodyLarge: const TextStyle(fontSize: 16),
          bodyMedium: const TextStyle(fontSize: 14),
        ),
      ),
      home: const StartupScreen(),
      // Adapter la taille selon la plateforme
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: kIsWeb
                ? const TextScaler.linear(1.0)
                : MediaQuery.of(context).textScaler,
          ),
          child: child!,
        );
      },
    );
  }
}

// Écran affiché brièvement au démarrage : vérifie si une session est déjà
// enregistrée localement (SharedPreferences) pour reconnecter automatiquement
// l'utilisateur, même après avoir fermé l'app ou redémarré le téléphone.
class StartupScreen extends StatefulWidget {
  const StartupScreen({super.key});

  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen> {
  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    final session = await AuthStorage.loadSession();

    if (!mounted) return;

    if (session != null) {
      // Session trouvée : on reconnecte directement, sans repasser par
      // l'écran de connexion.
      SupabaseService.setOnlineStatus(session['phoneNumber']!, true);

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => HomeScreen(
            phoneNumber: session['phoneNumber']!,
            pseudo: session['pseudo']!,
            userId: session['userId']!,
          ),
        ),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF0E1621),
      body: Center(
        child: CircularProgressIndicator(color: Color(0xFF2AABEE)),
      ),
    );
  }
}
