import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/theme/app_themes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// [home] inside a MaterialApp with the app's localizations for [lang].
Widget localizedApp(Widget home, {String lang = 'ar', bool dark = false, bool scaffold = true}) => MaterialApp(
      locale: Locale(lang),
      theme: dark ? AppThemes.darkTheme : AppThemes.lightTheme,
      supportedLocales: const [Locale('en'), Locale('ar'), Locale('ur')],
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: scaffold ? Scaffold(body: SingleChildScrollView(child: home)) : home,
    );
