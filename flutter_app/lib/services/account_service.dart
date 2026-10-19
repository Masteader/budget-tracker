import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/account.dart';

/// Service managing accounts, transfers, multi-source income records, and budget linkages.
class AccountService {
  final SupabaseClient? _customClient;
  AccountService({SupabaseClient? client}) : _customClient = client;
  static final AccountService instance = AccountService();

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
    String colorHex = '#00E5BF',
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
    return Account.fromMap(res);
  }

  /// Update account details (name, color, icon, etc.).
  Future<void> updateAccount(Account account) async {
    await _client.from('accounts').update({
      'name': account.name,
      'account_type': account.accountType.value,
      'currency': account.currency,
      'color_hex': account.colorHex,
      'icon_name': account.iconName,
      'updated_at': DateTime.now().toIso8601String(),
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
      'updated_at': DateTime.now().toIso8601String(),
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
      'p_received_at': (receivedAt ?? DateTime.now()).toIso8601String(),
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

  /// Get total committed budgets per account for a cycle.
  Future<Map<String, double>> getCommittedBudgetsByAccount(String householdId, String cycleKey) async {
    final res = await _client
        .from('budgets')
        .select('account_id, allocated_amount, is_active')
        .eq('household_id', householdId)
        .eq('cycle_key', cycleKey);

    final Map<String, double> map = {};
    for (final row in (res as List)) {
      if (row['is_active'] == false) continue;
      final accId = row['account_id'] as String?;
      if (accId != null && accId.isNotEmpty) {
        final amount = (row['allocated_amount'] as num?)?.toDouble() ?? 0.0;
        map[accId] = (map[accId] ?? 0.0) + amount;
      }
    }
    return map;
  }
}
