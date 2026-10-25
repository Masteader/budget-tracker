import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/velvet_burgundy_theme.dart';

class GlassDockItem {
  final IconData outlineIcon;
  final IconData filledIcon;
  final String label;

  const GlassDockItem({
    required this.outlineIcon,
    required this.filledIcon,
    required this.label,
  });
}

/// Classic modern glassmorphic floating bottom navigation dock.
/// Features a frosted glass capsule (30px radius, blur 24px, 1.5px specular rim),
/// active dot indicators, and an elevated 3D Velvet Burgundy center orb.
class GlassmorphicBottomDock extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;
  final VoidCallback? onCenterOrbPressed;
  final List<GlassDockItem>? customItems;
  final bool showCenterOrb;

  const GlassmorphicBottomDock({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
    this.onCenterOrbPressed,
    this.customItems,
    this.showCenterOrb = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final defaultItems = [
      const GlassDockItem(
        outlineIcon: Icons.home_outlined,
        filledIcon: Icons.home_rounded,
        label: 'الرئيسية',
      ),
      const GlassDockItem(
        outlineIcon: Icons.receipt_long_outlined,
        filledIcon: Icons.receipt_long_rounded,
        label: 'العمليات',
      ),
      const GlassDockItem(
        outlineIcon: Icons.pie_chart_outline_rounded,
        filledIcon: Icons.pie_chart_rounded,
        label: 'الميزانية',
      ),
      const GlassDockItem(
        outlineIcon: Icons.person_outline_rounded,
        filledIcon: Icons.person_rounded,
        label: 'حسابي',
      ),
    ];

    final items = customItems ?? defaultItems;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      height: 72,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          // Frosted Glass Capsule
          ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(
                height: 66,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1E0B12).withValues(alpha: 0.78)
                      : Colors.white.withValues(alpha: 0.82),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.18)
                        : Colors.white.withValues(alpha: 0.95),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isDark
                          ? Colors.black.withValues(alpha: 0.6)
                          : const Color(0xFF4A0E1E).withValues(alpha: 0.14),
                      blurRadius: 36,
                      offset: const Offset(0, 18),
                      spreadRadius: -4,
                    ),
                    BoxShadow(
                      color: const Color(0xFF4A0E1E).withValues(alpha: 0.06),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    // Item 0 (Home)
                    _buildNavItem(context, 0, items[0], isDark),
                    // Item 1 (Transactions)
                    _buildNavItem(context, 1, items[1], isDark),
                    // Center spacer for the elevated orb
                    if (showCenterOrb) const SizedBox(width: 56),
                    // Item 2 (Budgets)
                    _buildNavItem(context, 2, items[2], isDark),
                    // Item 3 (Profile / Settings)
                    _buildNavItem(context, 3, items[3], isDark),
                  ],
                ),
              ),
            ),
          ),

          // Elevated Center 3D Burgundy Orb
          if (showCenterOrb)
            Positioned(
              top: -8,
              child: _ElevatedCenterOrb(
                isDark: isDark,
                onPressed: onCenterOrbPressed ?? () => onItemSelected(99),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNavItem(
    BuildContext context,
    int index,
    GlassDockItem item,
    bool isDark,
  ) {
    // Map index 2 and 3 if center orb is present in 5-tab scheme
    // If the caller uses 0=Home, 1=Transactions, 2=AI, 3=Budgets, 4=Settings
    // then index 2 in 4-item list corresponds to targetIndex 3, and 3 to 4.
    final targetIndex = (customItems == null && index >= 2) ? index + 1 : index;
    final isSelected = selectedIndex == targetIndex || selectedIndex == index;

    final activeColor = isDark
        ? VelvetBurgundyColors.roseGoldGlow
        : VelvetBurgundyColors.primaryLight;
    final inactiveColor = isDark
        ? const Color(0xFF8E757F)
        : const Color(0xFF9E8E94);

    return Expanded(
      child: InkWell(
        onTap: () => onItemSelected(targetIndex),
        borderRadius: BorderRadius.circular(24),
        splashColor: activeColor.withValues(alpha: 0.1),
        highlightColor: Colors.transparent,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isSelected ? item.filledIcon : item.outlineIcon,
              color: isSelected ? activeColor : inactiveColor,
              size: 22,
            ),
            const SizedBox(height: 2),
            Text(
              item.label,
              style: GoogleFonts.outfit(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? activeColor : inactiveColor,
              ).copyWith(fontFamilyFallback: VelvetBurgundyTheme.arabicFallback),
            ),
            const SizedBox(height: 3),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: isSelected ? 4 : 0,
              height: isSelected ? 4 : 0,
              decoration: BoxDecoration(
                color: isSelected ? activeColor : Colors.transparent,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ElevatedCenterOrb extends StatefulWidget {
  final bool isDark;
  final VoidCallback onPressed;

  const _ElevatedCenterOrb({
    required this.isDark,
    required this.onPressed,
  });

  @override
  State<_ElevatedCenterOrb> createState() => _ElevatedCenterOrbState();
}

class _ElevatedCenterOrbState extends State<_ElevatedCenterOrb> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onPressed,
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 0.90 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: widget.isDark
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF6E162F), Color(0xFF29040D)],
                  )
                : const RadialGradient(
                    center: Alignment(-0.3, -0.3),
                    radius: 0.85,
                    colors: [
                      Color(0xFF8A243D),
                      Color(0xFF571324),
                      Color(0xFF25030A),
                    ],
                  ),
            boxShadow: [
              BoxShadow(
                color: (widget.isDark ? Colors.black : const Color(0xFF4A0E1E))
                    .withValues(alpha: widget.isDark ? 0.7 : 0.55),
                blurRadius: 24,
                offset: const Offset(0, 12),
                spreadRadius: -2,
              ),
              BoxShadow(
                color: const Color(0xFF4A0E1E).withValues(alpha: 0.3),
                blurRadius: 10,
                offset: const Offset(0, 6),
              ),
            ],
            border: Border.all(
              color: Colors.white.withValues(alpha: widget.isDark ? 0.3 : 0.45),
              width: 2.0,
            ),
          ),
          child: const Center(
            child: Icon(
              Icons.add_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
        ),
      ),
    );
  }
}
