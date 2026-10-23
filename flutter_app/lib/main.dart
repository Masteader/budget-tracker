/// App entry point. Validates build configuration, initialises Supabase,
/// starts the offline sync engine, and routes to Auth or Home based on
/// session state.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/app_localizations.dart';
import 'providers/budget_provider.dart';
import 'providers/household_role_provider.dart';
import 'providers/installment_provider.dart';
import 'providers/locale_provider.dart';
import 'providers/recurring_bills_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/transaction_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home/dashboard_screen.dart';
import 'screens/onboarding/household_screen.dart';
import 'services/household_resolver.dart';
import 'services/notifications/reminder_preferences.dart';
import 'services/notifications/reminder_service.dart';
import 'services/offline_sync_service.dart';
import 'services/receipt_storage_service.dart';
import 'services/salary_cycle_service.dart';
import 'errors/config_error_app.dart';
import 'services/secure_session_storage.dart';
import 'supabase_config.dart';
import 'theme/app_themes.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Fail fast with an explicit list of missing/invalid --dart-define flags
    // rather than starting against an unknown or production backend.
    ensureValidClientConfig(isRelease: kReleaseMode);

    // Lock to portrait
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

    // Supabase
    // MOB-19: the session (refresh token) lives in the Keystore/Keychain, not
    // in plaintext SharedPreferences; an existing session is migrated once.
    try {
      Supabase.instance.client;
    } catch (_) {
      await Supabase.initialize(
        url: supabaseUrl,
        publishableKey: supabasePublishableKey,
        authOptions: FlutterAuthClientOptions(
          localStorage: SecureSessionLocalStorage(
            persistSessionKey: SecureSessionLocalStorage.sessionKeyFor(supabaseUrl),
          ),
        ),
      );
    }

    // Household payday for client-side salary-cycle arithmetic.
    await SalaryCycleService.loadCachedPayday();

    // Per-type reminder switches (local).
    await ReminderPreferences.instance.load();

    // Offline SQLite Queue & Sync Engine
    OfflineSyncService.instance.initialize();

    runApp(const BudgetTrackerApp());
  } catch (error, stackTrace) {
    debugPrint('Fatal Budget Tracker startup initialization error: $error\n$stackTrace');
    final problems = validateClientConfig(
      supabaseUrl: supabaseUrl,
      supabaseKey: supabasePublishableKey,
      fastapiBaseUrl: fastapiBaseUrl,
      isRelease: kReleaseMode,
    );
    runApp(
      ConfigErrorApp(
        error: error,
        stackTrace: stackTrace,
        problems: problems,
        onRetry: () => main(),
      ),
    );
  }
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
        ChangeNotifierProvider(create: (_) => RecurringBillsProvider()),
        ChangeNotifierProvider(create: (_) => InstallmentProvider()),
        ChangeNotifierProvider(create: (_) => HouseholdRoleProvider()),
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
            home: const AuthGate(),
          );
        },
      ),
    );
  }
}

Future<String?> _fetchHouseholdFromSupabase(String userId) async {
  final row = await supabase.from('users').select('household_id').eq('id', userId).maybeSingle();
  return row?['household_id'] as String?;
}

/// Routes between login, household onboarding and the dashboard.
///
/// * The household lookup runs once per signed-in user, not on every auth
///   event: Supabase emits `tokenRefreshed` roughly hourly and rebuilding the
///   lookup used to tear down and recreate the whole dashboard each time.
/// * The lookup is offline-first ([HouseholdResolver]); a network failure
///   with nothing cached shows a retry state, never the onboarding screen.
/// * Household-scoped providers are initialised once per household and reset
///   on sign-out, so a second account on the same device never sees the
///   previous account's data.
class AuthGate extends StatefulWidget {
  final Stream<AuthState>? authStates;
  final HouseholdResolver? resolver;
  final WidgetBuilder? loginBuilder;
  final WidgetBuilder? onboardingBuilder;
  final WidgetBuilder? homeBuilder;
  final void Function(BuildContext context, String householdId)? onHouseholdReady;
  final void Function(BuildContext context)? onSignedOut;

  const AuthGate({
    super.key,
    this.authStates,
    this.resolver,
    this.loginBuilder,
    this.onboardingBuilder,
    this.homeBuilder,
    this.onHouseholdReady,
    this.onSignedOut,
  });

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final Stream<AuthState> _authStates = widget.authStates ?? supabase.auth.onAuthStateChange;
  late final HouseholdResolver _resolver =
      widget.resolver ?? const HouseholdResolver(fetchRemote: _fetchHouseholdFromSupabase);

  String? _userId;
  Future<String?>? _householdFuture;
  String? _initializedHouseholdId;

  void _ensureLookup(String userId) {
    if (_userId == userId && _householdFuture != null) return;
    _userId = userId;
    _householdFuture = _resolver.resolve(userId);
  }

  void _retry() {
    final userId = _userId;
    if (userId == null) return;
    final lookup = _resolver.resolve(userId);
    setState(() {
      _householdFuture = lookup;
    });
  }

  void _handleSignedOut(BuildContext context) {
    if (_userId == null && _initializedHouseholdId == null) return;
    _userId = null;
    _householdFuture = null;
    _initializedHouseholdId = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      final onSignedOut = widget.onSignedOut;
      if (onSignedOut != null) {
        onSignedOut(context);
      } else {
        context.read<TransactionProvider>().reset();
        context.read<BudgetProvider>().reset();
        context.read<HouseholdRoleProvider>().reset();
        context.read<RecurringBillsProvider>().reset();
        context.read<InstallmentProvider>().reset();
        ReceiptStorageService.clearSignedUrlCache();
        // Another account may sign in next: no reminder of this household stays.
        ReminderService.instance.cancelAll();
      }
    });
  }

  void _handleHouseholdReady(BuildContext context, String householdId) {
    if (_initializedHouseholdId == householdId) return;
    _initializedHouseholdId = householdId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      final onReady = widget.onHouseholdReady;
      if (onReady != null) {
        onReady(context, householdId);
      } else {
        context.read<TransactionProvider>().init(householdId);
        context.read<BudgetProvider>().init(householdId);
        context.read<HouseholdRoleProvider>().load(householdId);
        // Bills and plans feed the reminders even before their cards build.
        context.read<RecurringBillsProvider>().init(householdId);
        context.read<InstallmentProvider>().init(householdId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: _authStates,
      builder: (context, snapshot) {
        final session = snapshot.data?.session;

        if (session == null) {
          _handleSignedOut(context);
          return (widget.loginBuilder ?? (_) => const LoginScreen())(context);
        }

        _ensureLookup(session.user.id);
        return FutureBuilder<String?>(
          future: _householdFuture,
          builder: (context, profileSnap) {
            if (profileSnap.connectionState != ConnectionState.done) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            if (profileSnap.hasError) {
              return Scaffold(
                body: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_off_rounded, size: 48),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _retry,
                        icon: const Icon(Icons.refresh_rounded),
                        label: Text(context.tr('try_again')),
                      ),
                    ],
                  ),
                ),
              );
            }

            final householdId = profileSnap.data;
            if (householdId == null) {
              return (widget.onboardingBuilder ?? (_) => const HouseholdScreen())(context);
            }

            _handleHouseholdReady(context, householdId);
            return (widget.homeBuilder ?? (_) => const DashboardScreen())(context);
          },
        );
      },
    );
  }
}
