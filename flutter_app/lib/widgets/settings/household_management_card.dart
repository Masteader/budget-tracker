import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Card for managing household membership, invite code, and household switching.
class HouseholdManagementCard extends StatelessWidget {
  final String householdName;
  final String inviteCode;
  final String userRole;
  final List<Map<String, dynamic>> members;
  final VoidCallback onCopyInviteCode;
  final VoidCallback onLeaveHousehold;
  final VoidCallback onSwitchHousehold;
  final VoidCallback onCreateHousehold;

  const HouseholdManagementCard({
    super.key,
    required this.householdName,
    required this.inviteCode,
    required this.userRole,
    required this.members,
    required this.onCopyInviteCode,
    required this.onLeaveHousehold,
    required this.onSwitchHousehold,
    required this.onCreateHousehold,
  });

  @override
  Widget build(BuildContext context) {
    final isAdmin = userRole.toLowerCase() == 'admin';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Name & Role Badge
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF00C896).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.home_work_rounded, color: Color(0xFF00C896), size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      householdName,
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${members.length} Active Member${members.length == 1 ? '' : 's'}',
                      style: const TextStyle(color: Color(0xFF8B949E), fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isAdmin
                      ? const Color(0xFF00C896).withValues(alpha: 0.15)
                      : const Color(0xFF58A6FF).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isAdmin ? const Color(0xFF00C896) : const Color(0xFF58A6FF),
                    width: 0.8,
                  ),
                ),
                child: Text(
                  isAdmin ? 'Admin' : 'Member',
                  style: TextStyle(
                    color: isAdmin ? const Color(0xFF00C896) : const Color(0xFF58A6FF),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
          const Divider(color: Color(0xFF21262D), height: 1),
          const SizedBox(height: 14),

          // Invite Code Section
          Text(
            'HOUSEHOLD INVITE CODE',
            style: GoogleFonts.outfit(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF8B949E),
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF0D1117),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF30363D)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    inviteCode,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                      color: const Color(0xFF00C896),
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFF30363D)),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                  icon: const Icon(Icons.copy_rounded, size: 14),
                  label: const Text('Copy Code', style: TextStyle(fontSize: 11)),
                  onPressed: onCopyInviteCode,
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Members Section
          Text(
            'MEMBERS',
            style: GoogleFonts.outfit(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF8B949E),
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 6),
          ...members.map((m) {
            final email = m['email'] as String? ?? 'User';
            final role = m['role'] as String? ?? 'member';
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.person_outline_rounded, size: 16, color: Color(0xFF8B949E)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      email,
                      style: const TextStyle(color: Color(0xFFC9D1D9), fontSize: 13),
                    ),
                  ),
                  Text(
                    role.toUpperCase(),
                    style: const TextStyle(color: Color(0xFF8B949E), fontSize: 10, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            );
          }),

          const SizedBox(height: 18),
          const Divider(color: Color(0xFF21262D), height: 1),
          const SizedBox(height: 14),

          // Action Buttons: Join Another, Create New, Leave
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFF30363D)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  icon: const Icon(Icons.group_add_outlined, size: 16),
                  label: const Text('Join with Code', style: TextStyle(fontSize: 12)),
                  onPressed: onSwitchHousehold,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00C896),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('New Household', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  onPressed: onCreateHousehold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFF85149),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              ),
              icon: const Icon(Icons.logout_rounded, size: 15),
              label: const Text('Leave Household', style: TextStyle(fontSize: 12)),
              onPressed: onLeaveHousehold,
            ),
          ),
        ],
      ),
    );
  }
}
