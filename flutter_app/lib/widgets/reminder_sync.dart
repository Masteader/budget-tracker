/// Keeps the scheduled reminders in step with the signed-in household.
///
/// Placed around the home screen: it reschedules on login (first build),
/// household switch, payday change, language change, reminder switches and
/// whenever the recurring bills or installment plans change. Sign-out
/// cancels everything (AuthGate).
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../models/installment_plan.dart';
import '../models/recurring_bill.dart';
import '../providers/installment_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/recurring_bills_provider.dart';
import '../services/api_service.dart';
import '../services/notifications/reminder_preferences.dart';
import '../services/notifications/reminder_service.dart';
import '../services/salary_cycle_service.dart';

typedef PaydayFetcher = Future<int?> Function(String householdId);

Future<int?> _fetchPaydayFromApi(String householdId) async {
  final day = await ApiService.instance.getHouseholdPayday(householdId);
  return day >= 1 && day <= 31 ? day : null;
}

class ReminderSync extends StatefulWidget {
  final Widget child;
  final ReminderService? service;
  final ReminderPreferences? preferences;
  final PaydayFetcher fetchPayday;
  final Duration debounce;

  const ReminderSync({
    super.key,
    required this.child,
    this.service,
    this.preferences,
    this.fetchPayday = _fetchPaydayFromApi,
    this.debounce = const Duration(milliseconds: 800),
  });

  @override
  State<ReminderSync> createState() => _ReminderSyncState();
}

class _ReminderSyncState extends State<ReminderSync> {
  Timer? _debounce;
  String? _paydayHousehold;

  ReminderService get _service => widget.service ?? ReminderService.instance;
  ReminderPreferences get _prefs => widget.preferences ?? ReminderPreferences.instance;

  @override
  void initState() {
    super.initState();
    _prefs.addListener(_schedule);
    SalaryCycleService.paydayListenable.addListener(_schedule);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _prefs.removeListener(_schedule);
    SalaryCycleService.paydayListenable.removeListener(_schedule);
    super.dispose();
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(widget.debounce, _sync);
  }

  Future<void> _sync() async {
    if (!mounted) return;
    final installments = context.read<InstallmentProvider>();
    final billsProvider = context.read<RecurringBillsProvider>();
    final hid = installments.householdId ?? billsProvider.householdId;
    if (hid == null || hid.isEmpty) return;

    // The payday of this household (a switch may change it).
    if (_paydayHousehold != hid) {
      _paydayHousehold = hid;
      try {
        final day = await widget.fetchPayday(hid);
        // Listeners re-run this sync with the new payday.
        if (day != null && day != SalaryCycleService.paydayDay) {
          await SalaryCycleService.cachePayday(day);
          return;
        }
      } catch (_) {
        // Offline: the cached payday is used.
      }
      if (!mounted) return;
    }

    // Only data that belongs to this household.
    final List<RecurringBillItem> bills =
        billsProvider.householdId == hid ? (billsProvider.summary?.bills ?? const []) : const [];
    final List<InstallmentPlan> plans = installments.householdId == hid ? installments.plans : const [];
    final enabled = _prefs.enabledTypes;
    if (enabled.isEmpty) {
      await _service.cancelAll();
      return;
    }
    await _service.reschedule(
      householdId: hid,
      paydayDay: SalaryCycleService.paydayDay,
      bills: bills,
      plans: plans,
      enabled: enabled,
      locale: context.read<LocaleProvider>().currentLocale,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Depend on everything the reminders are built from.
    context.watch<RecurringBillsProvider>();
    context.watch<InstallmentProvider>();
    context.watch<LocaleProvider>();
    _schedule();
    return widget.child;
  }
}
