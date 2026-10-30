import 'salary_cycle_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/account.dart';

/// Service managing accounts, transfers, multi-source income records, and budget linkages.
class AccountService {
  final SupabaseClient? _customClient;
  AccountService({SupabaseClient? client}) : _customClient = client;
  static AccountService instance = AccountService();

  SupabaseClient get _client => _customClient ?? Supabase.instance.client;

  /// Stream of accounts for the given household (and owner/shared pool).
  Stream<List<Account>> streamAccounts(String householdId) {
    return _client
        .from('accounts')
        .stream(primaryKey: ['id'])
        .eq('household_id', householdId)
        .order('created_at', ascending: true)
        .map((list) => list
            .map((map) => Account.fromMap(map))
            .where((a) => !a.isArchived)
            .toList());
  }

  /// Fetch active accounts for the household.
  Future<List<Account>> getAccounts(String householdId) async {
    final res = await _client
        .from('accounts')
        .select()
        .eq('household_id', householdId)
        .eq('is_archived', false)
        .order('created_at', ascending: true);

    return (res as List).map((map) => Account.fromMap(map)).toList();
  }

  /// Create a new account.
  Future<Account> createAccount({
    required String householdId,
    required String name,
    required AccountType accountType,
    String currency = 'SAR',
    double initialBalance = 0.0,
    bool isSharedPool = false,
    String colorHex = '#F0A3BC',
    String iconName = 'account_balance_rounded',
  }) async {
    final userId = _client.auth.currentUser?.id ?? '';
    final insertData = {
      'household_id': householdId,
      'owner_user_id': userId,
      'name': name.trim(),
      'account_type': accountType.value,
      'currency': currency,
      'balance': initialBalance,
      'is_shared_pool': isSharedPool,
      'color_hex': colorHex,
      'icon_name': iconName,
      'is_archived': false,
    };

    final res = await _client.from('accounts').insert(insertData).select().single();
    final acc = Account.fromMap(res);

    if (initialBalance > 0) {
      try {
        final cycleKey = SalaryCycleService.cycleKeyForInstant(DateTime.now());
        await logIncome(
          householdId: householdId,
          accountId: acc.id,
          cycleKey: cycleKey,
          sourceType: IncomeSourceType.other,
          title: 'Opening Balance - ${name.trim()}',
          baseAmount: initialBalance,
          notes: 'Initial account balance recorded upon account creation',
        );
        return acc.copyWith(balance: initialBalance);
      } catch (e) {
        try {
          await updateBalance(acc.id, initialBalance);
        } catch (_) {}
        return acc.copyWith(balance: initialBalance);
      }
    }
    return acc;
  }

  /// Update account details (name, color, icon, etc.).
  Future<void> updateAccount(Account account) async {
    await _client.from('accounts').update({
      'name': account.name,
      'account_type': account.accountType.value,
      'currency': account.currency,
      'color_hex': account.colorHex,
      'icon_name': account.iconName,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', account.id);
  }

  /// Update or reconcile account balance via secure RPC.
  Future<void> updateBalance(String accountId, double newBalance) async {
    await _client.rpc('reconcile_account_balance', params: {
      'p_account_id': accountId,
      'p_new_balance': newBalance,
    });
  }

  /// Archive an account (soft delete).
  Future<void> archiveAccount(String accountId) async {
    await _client.from('accounts').update({
      'is_archived': true,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', accountId);
  }

  /// Execute an inter-account fund transfer via atomic database RPC.
  Future<AccountTransfer> transferFunds({
    required String householdId,
    required String fromAccountId,
    required String toAccountId,
    required double amount,
    double fee = 0.0,
    String? notes,
  }) async {
    final res = await _client.rpc('transfer_between_accounts', params: {
      'p_household_id': householdId,
      'p_from_account_id': fromAccountId,
      'p_to_account_id': toAccountId,
      'p_amount': amount,
      'p_fee': fee,
      'p_notes': notes,
    });

    return AccountTransfer.fromMap(Map<String, dynamic>.from(res as Map));
  }

  /// Log received multi-source income via atomic database RPC.
  Future<IncomeRecord> logIncome({
    required String householdId,
    required String accountId,
    required String cycleKey,
    required IncomeSourceType sourceType,
    required String title,
    required double baseAmount,
    double overtime = 0.0,
    double bonus = 0.0,
    double deductions = 0.0,
    DateTime? receivedAt,
    String? notes,
  }) async {
    final res = await _client.rpc('record_income', params: {
      'p_household_id': householdId,
      'p_account_id': accountId,
      'p_cycle_key': cycleKey,
      'p_source_type': sourceType.value,
      'p_title': title.trim(),
      'p_base_amount': baseAmount,
      'p_overtime': overtime,
      'p_bonus': bonus,
      'p_deductions': deductions,
      'p_received_at': (receivedAt ?? DateTime.now()).toUtc().toIso8601String(),
      'p_notes': notes,
    });

    return IncomeRecord.fromMap(Map<String, dynamic>.from(res as Map));
  }

  /// Fetch income records for a specific cycle.
  Future<List<IncomeRecord>> getCycleIncome(String householdId, String cycleKey) async {
    final res = await _client
        .from('income_records')
        .select()
        .eq('household_id', householdId)
        .eq('cycle_key', cycleKey)
        .order('received_at', ascending: false);

    return (res as List).map((map) => IncomeRecord.fromMap(map)).toList();
  }

  /// Link a budget category to an account.
  Future<void> linkBudgetAccount(String budgetId, String? accountId) async {
    await _client.from('budgets').update({
      'account_id': accountId,
    }).eq('id', budgetId);
  }

  /// Link a budget category to an account, creating the budget row if one doesn't exist yet.
  Future<void> linkCategoryAccount({
    required String householdId,
    required String categoryCode,
    required String cycleKey,
    required String? accountId,
  }) async {
    final existing = await _client
        .from('budgets')
        .select('id')
        .eq('household_id', householdId)
        .eq('category_code', categoryCode)
        .eq('cycle_key', cycleKey)
        .maybeSingle();

    if (existing != null) {
      await _client.from('budgets').update({
        'account_id': accountId,
      }).eq('id', existing['id']);
    } else {
      await _client.from('budgets').insert({
        'household_id': householdId,
        'category_code': categoryCode,
        'cycle_key': cycleKey,
        'month': '${cycleKey.length >= 7 ? cycleKey.substring(0, 7) : cycleKey}-01',
        'allocated_amount': 0.0,
        'spent_amount': 0.0,
        'remaining_amount': 0.0,
        'account_id': accountId,
        'is_active': true,
      });
    }
  }

  /// Get total remaining unspent committed budgets per account for a cycle.
  /// Deducts already spent amounts from allocated amounts so that
  /// only remaining unspent commitments are counted against current balance.
  Future<Map<String, double>> getCommittedBudgetsByAccount(String householdId, String cycleKey) async {
    final res = await _client
        .from('budgets')
        .select('account_id, category_code, allocated_amount, spent_amount, cycle_key, month, is_active')
        .eq('household_id', householdId);

    // Also fetch transaction spending to ensure real-time accuracy even if DB trigger is delayed
    Map<String, double> categorySpendMap = {};
    try {
      final txRes = await _client
          .from('transactions')
          .select('category_code, amount, cycle_key, is_settlement, nafaqah_class')
          .eq('household_id', householdId);

      for (final tx in (txRes as List)) {
        if (tx['is_settlement'] == true) continue;
        if (tx['nafaqah_class'] == 'wife_personal') continue;
        final k = tx['cycle_key'] as String?;
        if (k == cycleKey) {
          final cat = tx['category_code'] as String?;
          final amt = (tx['amount'] as num?)?.toDouble() ?? 0.0;
          if (cat != null && cat.isNotEmpty) {
            categorySpendMap[cat] = (categorySpendMap[cat] ?? 0.0) + amt;
          }
        }
      }
    } catch (_) {}

    final Map<String, double> map = {};
    for (final row in (res as List)) {
      if (row['is_active'] == false) continue;
      final k = row['cycle_key'] as String?;
      final m = row['month'] as String? ?? '';
      final matches = (k != null && k.isNotEmpty)
          ? k == cycleKey
          : (m.startsWith(cycleKey) || m.startsWith(cycleKey.replaceAll('-', '')));
      if (!matches) continue;

      final accId = row['account_id'] as String?;
      if (accId != null && accId.isNotEmpty) {
        final cat = row['category_code'] as String?;
        final allocated = (row['allocated_amount'] as num?)?.toDouble() ?? 0.0;
        final dbSpent = (row['spent_amount'] as num?)?.toDouble() ?? 0.0;
        final txSpent = (cat != null && categorySpendMap.containsKey(cat)) ? categorySpendMap[cat]! : 0.0;
        final actualSpent = txSpent > dbSpent ? txSpent : dbSpent;
        final unspent = (allocated - actualSpent).clamp(0.0, double.infinity);
        map[accId] = (map[accId] ?? 0.0) + unspent;
      }
    }
    return map;
  }

  /// Automatically links any unlinked transactions to the category's budget account
  /// or primary operating account, and adjusts the account balance if it was not deducted yet.
  Future<void> reconcileUnlinkedTransactions(String householdId) async {
    try {
      final accounts = await getAccounts(householdId);
      if (accounts.isEmpty) return;

      final unlinked = await _client
          .from('transactions')
          .select('id, amount, category_code')
          .eq('household_id', householdId)
          .isFilter('account_id', null);

      if (unlinked.isEmpty) return;

      final defaultAcc = accounts.where((a) => a.accountType.isOperatingPool).firstOrNull ?? accounts.first;

      for (final row in (unlinked as List)) {
        final txId = row['id'] as String?;
        final txAmt = (row['amount'] as num?)?.toDouble() ?? 0.0;
        final catCode = row['category_code'] as String?;
        if (txId == null) continue;

        String targetAccId = defaultAcc.id;
        if (catCode != null && catCode.isNotEmpty) {
          try {
            final bRes = await _client
                .from('budgets')
                .select('account_id')
                .eq('household_id', householdId)
                .eq('category_code', catCode)
                .eq('is_active', true)
                .not('account_id', 'is', null)
                .limit(1)
                .maybeSingle();
            if (bRes != null && bRes['account_id'] != null) {
              targetAccId = bRes['account_id'] as String;
            }
          } catch (_) {}
        }

        // Check target account balance before linking
        final targetAccBefore = (await getAccounts(householdId)).where((a) => a.id == targetAccId).firstOrNull;

        // Link the transaction
        await _client.from('transactions').update({'account_id': targetAccId}).eq('id', txId);

        // Check target account balance after linking
        final targetAccAfter = (await getAccounts(householdId)).where((a) => a.id == targetAccId).firstOrNull;

        if (targetAccBefore != null && targetAccAfter != null) {
          // If the database trigger did not decrement the balance, deduct it directly
          if ((targetAccAfter.balance - targetAccBefore.balance).abs() < 0.001) {
            final newBal = (targetAccBefore.balance - txAmt).clamp(0.0, double.infinity);
            await updateBalance(targetAccId, newBal);
          }
        }
      }
    } catch (_) {}
  }
}
