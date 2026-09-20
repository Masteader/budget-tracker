/// Household onboarding: create a new household or join one with an invite code.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../main.dart';

class HouseholdScreen extends StatefulWidget {
  const HouseholdScreen({super.key});

  @override
  State<HouseholdScreen> createState() => _HouseholdScreenState();
}

class _HouseholdScreenState extends State<HouseholdScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  final _createNameCtrl = TextEditingController();
  final _joinCodeCtrl   = TextEditingController();
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    _createNameCtrl.dispose();
    _joinCodeCtrl.dispose();
    super.dispose();
  }

  Future<void> _createHousehold() async {
    final name = _createNameCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() => _loading = true);
    try {
      Map<String, dynamic> hh;
      try {
        final res = await supabase.rpc(
          'create_household_and_claim',
          params: {'p_name': name},
        );
        hh = Map<String, dynamic>.from(res as Map);
      } catch (_) {
        final uid = supabase.auth.currentUser!.id;
        final res = await supabase
            .from('households')
            .insert({'name': name})
            .select()
            .single();
        hh = res;
        await supabase
            .from('users')
            .update({'household_id': hh['id'], 'role': 'admin'})
            .eq('id', uid);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Household "${hh['name']}" created! Code: ${hh['invite_code']}')),
        );
      }
    } on PostgrestException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _joinHousehold() async {
    final code = _joinCodeCtrl.text.trim().toUpperCase();
    if (code.length != 8) {
      _showError('Invite code must be 8 characters.');
      return;
    }
    setState(() => _loading = true);
    try {
      try {
        await supabase.rpc(
          'join_household_by_code',
          params: {'p_invite_code': code},
        );
      } catch (_) {
        final uid = supabase.auth.currentUser!.id;
        final hh = await supabase
            .from('households')
            .select()
            .eq('invite_code', code)
            .single();
        await supabase
            .from('users')
            .update({'household_id': hh['id'], 'role': 'member'})
            .eq('id', uid);
      }
    } on PostgrestException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.redAccent));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 32),
              Text('Your Household',
                  style: GoogleFonts.outfit(
                      fontSize: 28, fontWeight: FontWeight.w700, color: Colors.white)),
              const SizedBox(height: 8),
              const Text('Create a new household or join one.',
                  style: TextStyle(color: Color(0xFF8B949E))),
              const SizedBox(height: 32),

              // Tab bar
              TabBar(
                controller: _tab,
                indicatorColor: const Color(0xFF00C896),
                labelColor: const Color(0xFF00C896),
                unselectedLabelColor: const Color(0xFF8B949E),
                tabs: const [Tab(text: 'Create'), Tab(text: 'Join')],
              ),
              const SizedBox(height: 28),

              Expanded(
                child: TabBarView(
                  controller: _tab,
                  children: [
                    // ── Create ───────────────────────────────────────────
                    Column(
                      children: [
                        TextField(
                          controller: _createNameCtrl,
                          decoration: const InputDecoration(
                            hintText: 'Household name (e.g. Al-Rashidi Family)',
                            prefixIcon: Icon(Icons.home_outlined),
                          ),
                        ),
                        const SizedBox(height: 24),
                        _BigButton(
                          label: 'Create Household',
                          icon: Icons.add_home_outlined,
                          loading: _loading,
                          onTap: _createHousehold,
                        ),
                      ],
                    ),

                    // ── Join ─────────────────────────────────────────────
                    Column(
                      children: [
                        TextField(
                          controller: _joinCodeCtrl,
                          textCapitalization: TextCapitalization.characters,
                          maxLength: 8,
                          decoration: const InputDecoration(
                            hintText: '8-character invite code',
                            prefixIcon: Icon(Icons.qr_code_outlined),
                          ),
                        ),
                        const SizedBox(height: 24),
                        _BigButton(
                          label: 'Join Household',
                          icon: Icons.group_add_outlined,
                          loading: _loading,
                          onTap: _joinHousehold,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BigButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool loading;
  final VoidCallback onTap;

  const _BigButton({
    required this.label,
    required this.icon,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        icon: loading
            ? const SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Icon(icon),
        label: Text(label,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        onPressed: loading ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF00C896),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}
