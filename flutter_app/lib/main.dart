/// App entry point. Initialises Supabase, starts the offline sync engine,
/// and routes to Auth or Home based on session state.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/app_localizations.dart';
import 'providers/budget_provider.dart';
import 'providers/locale_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/transaction_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home/dashboard_screen.dart';
import 'screens/onboarding/household_screen.dart';
import 'services/offline_sync_service.dart';
import 'supabase_config.dart';
import 'theme/app_themes.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Supabase
  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabasePublishableKey,
  );

  // Offline SQLite Queue & Sync Engine
  OfflineSyncService.instance.initialize();

  runApp(const BudgetTrackerApp());
}

final supabase = Supabase.instance.client;

// ─── Root App ─────────────────────────────────────────────────────────────────

class BudgetTrackerApp extends StatelessWidget {
  const BudgetTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => TransactionProvider()),
        ChangeNotifierProvider(create: (_) => BudgetProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()..init()),
        ChangeNotifierProvider(create: (_) => LocaleProvider()..init()),
      ],
      child: Consumer2<ThemeProvider, LocaleProvider>(
        builder: (context, themeProvider, localeProvider, child) {
          return MaterialApp(
            title: 'Budget Tracker',
            debugShowCheckedModeBanner: false,
            theme: AppThemes.lightTheme,
            darkTheme: AppThemes.darkTheme,
            themeMode: themeProvider.themeMode,
            locale: localeProvider.currentLocale,
            supportedLocales: LocaleProvider.supportedLocales,
            localizationsDelegates: const [
              AppLocalizationsDelegate(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const _AuthGate(),
          );
        },
      ),
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
            final householdId = profileSnap.data?['household_id'] as String?;
            if (householdId == null) {
              return const HouseholdScreen();
            }

            // Populate centralized state providers
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) {
                context.read<TransactionProvider>().init(householdId);
                context.read<BudgetProvider>().init(householdId);
              }
            });

            return const DashboardScreen();
          },
        );
      },
    );
  }
}
