import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'services/supabase_service.dart';
import 'screens/login_screen.dart';

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
      home: const LoginScreen(),
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
