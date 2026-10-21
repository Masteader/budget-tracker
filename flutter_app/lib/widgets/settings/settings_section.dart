import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_themes.dart';

/// A foldable group of Settings (UX-15): the title (and an optional one-line
/// summary) is always visible; the cards inside show when it is opened. The
/// open / closed state survives scrolling via a [PageStorageKey].
class SettingsSection extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final bool initiallyExpanded;
  final List<Widget> children;

  const SettingsSection({
    super.key,
    required this.title,
    required this.icon,
    required this.children,
    this.subtitle,
    this.initiallyExpanded = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: PageStorageKey<String>('settings_section_$title'),
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsetsDirectional.only(start: 4, end: 8),
          childrenPadding: const EdgeInsets.only(bottom: 8),
          minTileHeight: 48,
          shape: const Border(),
          collapsedShape: const Border(),
          iconColor: context.accentText,
          collapsedIconColor: context.textSecondary,
          leading: Icon(icon, size: 20, color: context.accentText),
          title: Text(
            title,
            style: GoogleFonts.outfit(
              fontSize: 13,
              letterSpacing: 0.6,
              fontWeight: FontWeight.w700,
              color: context.textSecondary,
            ),
          ),
          subtitle: subtitle == null
              ? null
              : Text(subtitle!, style: TextStyle(fontSize: 12, color: context.textSecondary)),
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}
