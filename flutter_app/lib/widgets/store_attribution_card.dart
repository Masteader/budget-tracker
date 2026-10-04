import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Reusable store name input & 'Spent by who?' selector card.
/// Ensures consistent UX across receipt scanner, chat confirmation, and manual entry.
class StoreAttributionCard extends StatelessWidget {
  final TextEditingController merchantController;
  final String selectedSpentBy;
  final ValueChanged<String> onSpentByChanged;
  final ValueChanged<String>? onMerchantChanged;
  final String title;
  final bool compact;

  const StoreAttributionCard({
    super.key,
    required this.merchantController,
    required this.selectedSpentBy,
    required this.onSpentByChanged,
    this.onMerchantChanged,
    this.title = 'Store & Attribution Details',
    this.compact = false,
  });

  Widget _buildSpentByOption({
    required String key,
    required String label,
    required IconData icon,
    required Color activeColor,
  }) {
    final isSelected = selectedSpentBy.toLowerCase() == key;
    return Expanded(
      child: GestureDetector(
        onTap: () => onSpentByChanged(key),
        child: Container(
          padding: EdgeInsets.symmetric(vertical: compact ? 8 : 10),
          decoration: BoxDecoration(
            color: isSelected ? activeColor.withValues(alpha: 0.18) : const Color(0xFF0D1117),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? activeColor : const Color(0xFF30363D),
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: compact ? 16 : 18, color: isSelected ? activeColor : const Color(0xFF8B949E)),
              const SizedBox(height: 3),
              Text(
                label,
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? Colors.white : const Color(0xFF8B949E),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: compact ? 8 : 14),
      padding: EdgeInsets.all(compact ? 12 : 14),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.storefront_outlined, color: Color(0xFF00C896), size: 18),
              const SizedBox(width: 8),
              Text(
                title,
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w700,
                  fontSize: compact ? 12 : 13,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 8 : 12),
          TextField(
            controller: merchantController,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            onChanged: onMerchantChanged,
            decoration: InputDecoration(
              labelText: 'Store Name / Merchant',
              labelStyle: const TextStyle(color: Color(0xFF8B949E), fontSize: 11),
              prefixIcon: const Icon(Icons.store_outlined, color: Color(0xFF00C896), size: 18),
              filled: true,
              fillColor: const Color(0xFF0D1117),
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: compact ? 10 : 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF30363D)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF30363D)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF00C896)),
              ),
            ),
          ),
          SizedBox(height: compact ? 10 : 14),
          Text(
            'SPENT BY WHO?',
            style: GoogleFonts.outfit(
              fontSize: 10,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF8B949E),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _buildSpentByOption(
                key: 'me',
                label: 'Me',
                icon: Icons.person_outline,
                activeColor: const Color(0xFF58A6FF),
              ),
              const SizedBox(width: 6),
              _buildSpentByOption(
                key: 'partner',
                label: 'Partner',
                icon: Icons.favorite_outline,
                activeColor: const Color(0xFFBC8CFF),
              ),
              const SizedBox(width: 6),
              _buildSpentByOption(
                key: 'both',
                label: 'Both (Shared)',
                icon: Icons.group_outlined,
                activeColor: const Color(0xFF00C896),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
