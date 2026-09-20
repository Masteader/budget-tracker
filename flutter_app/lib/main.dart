/// App entry point. Initialises Supabase, starts the SMS service,
/// and routes to Auth or Home based on session state.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/auth/login_screen.dart';
import 'screens/home/dashboard_screen.dart';
import 'screens/onboarding/household_screen.dart';
import 'services/sms_service.dart';
import 'supabase_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Supabase
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);

  // SMS bridge
  SmsService.instance.init();

  runApp(const BudgetTrackerApp());
}

final supabase = Supabase.instance.client;

// ─── Theme ────────────────────────────────────────────────────────────────────

final _colorScheme = ColorScheme.fromSeed(
  seedColor: const Color(0xFF00C896), // Emerald green brand color
  brightness: Brightness.dark,
);

ThemeData get _theme => ThemeData(
      useMaterial3: true,
      colorScheme: _colorScheme,
      textTheme: GoogleFonts.outfitTextTheme().apply(
        bodyColor: Colors.white,
        displayColor: Colors.white,
      ),
      scaffoldBackgroundColor: const Color(0xFF0D1117),
      appBarTheme: AppBarTheme(
        backgroundColor: const Color(0xFF0D1117),
        foregroundColor: Colors.white,
        elevation: 0,
        titleTextStyle: GoogleFonts.outfit(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFF161B22),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF21262D),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        hintStyle: const TextStyle(color: Color(0xFF8B949E)),
      ),
    );

// ─── Root App ─────────────────────────────────────────────────────────────────

class BudgetTrackerApp extends StatelessWidget {
  const BudgetTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Budget Tracker',
      debugShowCheckedModeBanner: false,
      theme: _theme,
      home: const _AuthGate(),
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: supabase.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = snapshot.data?.session;

        if (session == null) {
          return const LoginScreen();
        }

        // Check if user has joined a household
        return FutureBuilder<Map<String, dynamic>>(
          future: supabase
              .from('users')
              .select('household_id')
              .eq('id', session.user.id)
              .single(),
          builder: (context, profileSnap) {
            if (profileSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            final householdId = profileSnap.data?['household_id'];
            if (householdId == null) {
              return const HouseholdScreen();
            }
            return const DashboardScreen();
          },
        );
      },
    );
  }
}
