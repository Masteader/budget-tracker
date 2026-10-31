/// API Service Facade
/// Delegating to specialized domain clients:
/// - BaseApiClient (HMAC-SHA256 signatures, auth headers, HTTP base methods)
/// - BudgetApiClient (Salary cycles, burn-rate forecast, settlements, sub-allocations)
/// - TransactionApiClient (Transaction ingestion and synchronization)
/// - ReceiptApiClient (Multi-page photo uploads, ZATCA QR analysis)
/// - ChatApiClient (Conversational expense parser, purchase simulation)
library;

import 'package:flutter/foundation.dart';
import 'api/base_api_client.dart';
import 'api/budget_api_client.dart';
import 'api/chat_api_client.dart';
import 'api/household_roles_api_client.dart';
import 'api/nafaqah_api_client.dart';
import 'api/receipt_api_client.dart';
import 'api/support_api_client.dart';
import 'api/transaction_api_client.dart';
import '../models/recurring_bill.dart';
import '../models/installment_plan.dart';
import '../models/models.dart';
import '../models/nafaqah.dart';

class ApiService {
  ApiService._() : base = BaseApiClient() {
    budget = BudgetApiClient(baseClient: base);
    transaction = TransactionApiClient(baseClient: base);
    receipt = ReceiptApiClient(baseClient: base);
    chat = ChatApiClient(baseClient: base);
    support = SupportApiClient(baseClient: base);
  }

  static ApiService _instance = ApiService._();
  static ApiService get instance => _instance;
  @visibleForTesting
  static set instance(ApiService value) => _instance = value;

  @visibleForTesting
  ApiService({
    BaseApiClient? base,
    BudgetApiClient? budget,
    TransactionApiClient? transaction,
    ReceiptApiClient? receipt,
    ChatApiClient? chat,
    SupportApiClient? support,
  }) : base = base ?? BaseApiClient() {
    this.budget = budget ?? BudgetApiClient(baseClient: this.base);
    this.transaction = transaction ?? TransactionApiClient(baseClient: this.base);
    this.receipt = receipt ?? ReceiptApiClient(baseClient: this.base);
    this.chat = chat ?? ChatApiClient(baseClient: this.base);
    this.support = support ?? SupportApiClient(baseClient: this.base);
  }

  final BaseApiClient base;
  late final BudgetApiClient budget;
  late final TransactionApiClient transaction;
  late final ReceiptApiClient receipt;
  late final ChatApiClient chat;
  late final SupportApiClient support;

  // ── Chat & Simulations ───────────────────────────────────────────────────

  Future<Map<String, dynamic>> postChatTransaction({
    required String message,
    required String householdId,
    String? userId,
    bool allowDuplicate = false,
    String? enrichTxId,
    bool previewOnly = true,
    String? merchant,
    String? spentBy,
    String? categoryCode,
    String? subCategory,
    String? paidBy,
    String? beneficiary,
    String? nafaqahClass,
    String? nafaqahSpouseId,
    String? idempotencyKey,
    DateTime? occurredAt,
    String? previewToken,
    double? amount,
    String? accountId,
  }) =>
      chat.postChatTransaction(
        message: message,
        householdId: householdId,
        userId: userId,
        allowDuplicate: allowDuplicate,
        enrichTxId: enrichTxId,
        previewOnly: previewOnly,
        merchant: merchant,
        spentBy: spentBy,
        categoryCode: categoryCode,
        subCategory: subCategory,
        paidBy: paidBy,
        beneficiary: beneficiary,
        nafaqahClass: nafaqahClass,
        nafaqahSpouseId: nafaqahSpouseId,
        idempotencyKey: idempotencyKey,
        occurredAt: occurredAt,
        previewToken: previewToken,
        amount: amount,
        accountId: accountId,
      );

  // ── Receipts & Invoices ──────────────────────────────────────────────────

  Future<Map<String, dynamic>> scanReceipt({
    List<String>? imagesBase64,
    String? imageBase64,
    String? qrCodeRaw,
    required String householdId,
    String? userId,
    bool allowDuplicate = false,
    String? enrichTxId,
    bool previewOnly = false,
    String? merchant,
    String? spentBy,
    String? receiptUrl,
    String? paidBy,
    String? beneficiary,
    String? nafaqahClass,
    String? nafaqahSpouseId,
    String? idempotencyKey,
    DateTime? occurredAt,
    String? previewToken,
    double? amount,
    String? categoryCode,
    String? accountId,
  }) {
    final list = imagesBase64 ?? (imageBase64 != null ? [imageBase64] : <String>[]);
    return receipt.scanReceipt(
      imagesBase64: list,
      qrCodeRaw: qrCodeRaw,
      householdId: householdId,
      userId: userId,
      allowDuplicate: allowDuplicate,
      enrichTxId: enrichTxId,
      previewOnly: previewOnly,
      merchant: merchant,
      spentBy: spentBy,
      receiptUrl: receiptUrl,
      paidBy: paidBy,
      beneficiary: beneficiary,
      nafaqahClass: nafaqahClass,
      nafaqahSpouseId: nafaqahSpouseId,
      idempotencyKey: idempotencyKey,
      occurredAt: occurredAt,
      previewToken: previewToken,
      amount: amount,
      categoryCode: categoryCode,
      accountId: accountId,
    );
  }

  // ── Budgets & Cycles ─────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getSalaryCycleForecast(
    String householdId, {
    int? paydayDay,
  }) =>
      budget.fetchSalaryCycleForecast(
        householdId: householdId,
        paydayDay: paydayDay,
      );

  Future<Map<String, dynamic>> fetchSalaryCycleForecast({
    required String householdId,
    int? paydayDay,
  }) =>
      budget.fetchSalaryCycleForecast(
        householdId: householdId,
        paydayDay: paydayDay,
      );

  Future<Map<String, dynamic>> getSalaryCycles(
    String householdId, {
    int? paydayDay,
  }) async {
    final list = await budget.fetchSalaryCycles(
      householdId: householdId,
      paydayDay: paydayDay,
    );
    return {'status': 'success', 'cycles': list};
  }

  Future<Map<String, dynamic>> recalculateBudgets(String householdId, {String? cycleKey}) =>
      budget.recalculateBudgets(householdId: householdId, cycleKey: cycleKey);

  Future<List<Map<String, dynamic>>> fetchSalaryCycles({
    required String householdId,
    int? paydayDay,
  }) =>
      budget.fetchSalaryCycles(
        householdId: householdId,
        paydayDay: paydayDay,
      );

  Future<int> getHouseholdPayday(String householdId) =>
      budget.fetchHouseholdPayday(householdId: householdId);

  Future<bool> setHouseholdPayday(String householdId, int paydayDay) =>
      budget.updateHouseholdPayday(
        householdId: householdId,
        paydayDay: paydayDay,
      );

  Future<double> getHouseholdIncome(String householdId) =>
      budget.fetchHouseholdIncome(householdId: householdId);

  Future<bool> setHouseholdIncome(String householdId, double monthlyIncome) =>
      budget.updateHouseholdIncome(
        householdId: householdId,
        monthlyIncome: monthlyIncome,
      );

  Future<String> getHouseholdRolloverRule(String householdId) =>
      budget.fetchHouseholdRolloverRule(householdId: householdId);

  Future<bool> setHouseholdRolloverRule(String householdId, String rolloverRule) =>
      budget.updateHouseholdRolloverRule(
        householdId: householdId,
        rolloverRule: rolloverRule,
      );

  Future<Map<String, dynamic>> getHouseholdSavingsSummary(String householdId) =>
      budget.fetchHouseholdSavingsSummary(householdId: householdId);

  Future<Map<String, dynamic>> getPartnerSettlement(String householdId, {double splitRatio = 0.50}) =>
      budget.fetchPartnerSettlement(householdId: householdId, splitRatio: splitRatio);

  Future<Map<String, dynamic>> fetchPartnerSettlement({required String householdId, double splitRatio = 0.5}) =>
      budget.fetchPartnerSettlement(householdId: householdId, splitRatio: splitRatio);

  Future<SettlementV2Summary> getSettlementV2(String householdId, {String? cycleStart}) =>
      budget.fetchSettlementV2(householdId: householdId, cycleStart: cycleStart);

  Future<HouseholdInvite> createRoleInvite(String householdId, String role, {String? targetMemberId}) =>
      budget.createRoleInvite(householdId: householdId, role: role, targetMemberId: targetMemberId);

  Future<HouseholdInvite> inspectInviteCode(String code) =>
      budget.inspectInviteCode(code: code);

  Future<Map<String, dynamic>> claimMemberProfile(String inviteCode, String userId) =>
      budget.claimMemberProfile(inviteCode: inviteCode, userId: userId);

  Future<List<HouseholdMembership>> getUserHouseholds() =>
      budget.getUserHouseholds();

  Future<HouseholdMembership?> getHouseholdMembership(String householdId) =>
      budget.fetchHouseholdMembership(householdId);

  Future<bool> switchActiveHousehold(String householdId) =>
      budget.switchActiveHousehold(householdId);

  Future<Map<String, dynamic>> recordReimbursementPayment(ReimbursementRecordRequest request) =>
      budget.recordReimbursementPayment(request: request);

  // ── Members, co-admins and the primary admin (DB-16 / DB-18) ───────────────
  late final HouseholdRolesApiClient roles = HouseholdRolesApiClient(baseClient: base);

  Future<HouseholdRoster> getHouseholdMembers(String householdId) => roles.fetchMembers(householdId);

  Future<HouseholdRoster> promoteHouseholdAdmin(String householdId, String userId) =>
      roles.promoteToAdmin(householdId, userId);

  Future<HouseholdRoster> revokeHouseholdAdmin(String householdId, String userId) =>
      roles.revokeAdmin(householdId, userId);

  Future<HouseholdRoster> transferPrimaryAdmin(String householdId, String newPrimaryUserId) =>
      roles.transferPrimaryAdmin(householdId, newPrimaryUserId);

  Future<String> setHouseholdType(String householdId, String householdType) =>
      roles.setHouseholdType(householdId, householdType);

  Future<String> setMemberFinancialRole(String householdId, String userId, String financialRole) =>
      roles.setFinancialRole(householdId, userId, financialRole);

  // ── Family Nafaqah (husband-owes-wife ledger, wife allowance) ──────────────
  late final NafaqahApiClient nafaqah = NafaqahApiClient(baseClient: base);

  Future<NafaqahSummary> getNafaqahSummary(String householdId, {String? cycleKey}) =>
      nafaqah.fetchSummary(householdId: householdId, cycleKey: cycleKey);

  Future<NafaqahLedger> getNafaqahLedger(String householdId, {String? wifeUserId}) =>
      nafaqah.fetchLedger(householdId: householdId, wifeUserId: wifeUserId);

  Future<double> recordNafaqahReimbursement(
    String householdId, {
    required double amount,
    required String paymentMethod,
    String? wifeUserId,
    String? notes,
  }) =>
      nafaqah.recordReimbursement(
        householdId: householdId,
        amount: amount,
        paymentMethod: paymentMethod,
        wifeUserId: wifeUserId,
        notes: notes,
      );

  Future<AllowanceStatus> setWifeAllowance(
    String householdId, {
    required double amount,
    String? wifeUserId,
    String? cycleKey,
  }) =>
      nafaqah.setAllowance(householdId: householdId, amount: amount, wifeUserId: wifeUserId, cycleKey: cycleKey);

  /// Admins choose the household's Nafaqah provider (husband).
  Future<NafaqahProviderChange> setNafaqahProvider(String householdId, String userId) =>
      nafaqah.setProvider(householdId: householdId, userId: userId);

  Future<List<HouseholdDependent>> getDependents(String householdId) =>
      budget.fetchHouseholdDependents(householdId: householdId);

  Future<HouseholdDependent?> createDependent(
    String householdId,
    String name, {
    String? avatarIcon,
    String? relationship,
    double? monthlyAllowance,
  }) =>
      budget.createHouseholdDependent(
        householdId: householdId,
        name: name,
        avatarIcon: avatarIcon,
        relationship: relationship,
        monthlyAllowance: monthlyAllowance,
      );

  Future<bool> deleteDependent(String householdId, String dependentId) =>
      budget.deleteHouseholdDependent(householdId: householdId, dependentId: dependentId);

  Future<Map<String, dynamic>> getBudgetBreakdown(String householdId, {String? cycleKey}) =>
      budget.fetchBudgetBreakdown(householdId: householdId, cycleKey: cycleKey);

  Future<Map<String, dynamic>> fetchBudgetBreakdown({required String householdId, String? cycleKey}) =>
      budget.fetchBudgetBreakdown(householdId: householdId, cycleKey: cycleKey);

  Future<RecurringBillsSummary> getRecurringBills(String householdId, {String? asOfDate}) =>
      budget.fetchRecurringBills(householdId: householdId, asOfDate: asOfDate);

  Future<RecurringBillsSummary> fetchRecurringBills({required String householdId, String? asOfDate}) =>
      budget.fetchRecurringBills(householdId: householdId, asOfDate: asOfDate);

  Future<List<RecurringBillCandidate>> getRecurringBillCandidates(String householdId) =>
      budget.fetchRecurringBillCandidates(householdId: householdId);

  Future<void> toggleRecurringBill({
    required String householdId,
    required String categoryCode,
    required String subCode,
    required bool isRecurring,
    int? dueDay,
    String? customName,
  }) =>
      budget.toggleRecurringBill(
        householdId: householdId,
        categoryCode: categoryCode,
        subCode: subCode,
        isRecurring: isRecurring,
        dueDay: dueDay,
        customName: customName,
      );

  Future<List<InstallmentPlan>> getInstallments(String householdId) =>
      budget.fetchInstallments(householdId: householdId);

  Future<InstallmentPlan> updateInstallmentPlan(String planId, Map<String, dynamic> updateData) =>
      budget.updateInstallmentPlan(planId, updateData);

  Future<InstallmentPlan> createInstallmentPlan(Map<String, dynamic> planData) =>
      budget.createInstallmentPlan(planData);

  Future<InstallmentPlan?> payInstallment(String planId) =>
      budget.payInstallment(planId);

  Future<Map<String, dynamic>> simulateAffordability({
    required String householdId,
    required double targetAmount,
    String itemName = 'Item',
    String? categoryCode,
  }) =>
      budget.simulateAffordability(
        householdId: householdId,
        targetAmount: targetAmount,
        itemName: itemName,
        categoryCode: categoryCode,
      );

  Future<List<Map<String, dynamic>>> getGroceryPriceHistory(String householdId, {String? itemFilter}) =>
      budget.getGroceryPriceHistory(householdId, itemFilter: itemFilter);

  Future<Map<String, dynamic>> optimizeShoppingBasket(String householdId, List<String> items) =>
      budget.optimizeShoppingBasket(householdId, items);

  Future<ApiBinaryResponse> downloadStatementPdf(String householdId, {String? cycleKey}) =>
      budget.downloadStatementPdf(householdId, cycleKey: cycleKey);

  Future<Map<String, dynamic>> addBudgetCategory({
    required String householdId,
    required String code,
    required String category,
    required double allocatedAmount,
    bool isFlexible = true,
    List<String> keywords = const [],
  }) =>
      budget.addBudgetCategory(
        householdId: householdId,
        code: code,
        category: category,
        allocatedAmount: allocatedAmount,
        isFlexible: isFlexible,
        keywords: keywords,
      );

  Future<Map<String, dynamic>> archiveBudgetCategory(String householdId, String categoryCode) =>
      budget.archiveBudgetCategory(householdId, categoryCode);

  Future<Map<String, dynamic>> replaceCategory({
    required String householdId,
    required String oldCode,
    required String newName,
    String? newCode,
    String? cycleKey,
    bool updatePastTransactions = false,
  }) =>
      budget.replaceBudgetCategory(
        householdId: householdId,
        oldCode: oldCode,
        newName: newName,
        newCode: newCode,
        cycleKey: cycleKey,
        updatePastTransactions: updatePastTransactions,
      );

  Future<Map<String, dynamic>> saveSubAllocations({
    required String householdId,
    required String categoryCode,
    required Map<String, dynamic> subAllocations,
    String? cycleKey,
  }) =>
      budget.saveSubAllocations(
        householdId: householdId,
        categoryCode: categoryCode,
        subAllocations: subAllocations,
        cycleKey: cycleKey,
      );

  Future<Map<String, dynamic>> addSubCategory({
    required String householdId,
    required String parentCode,
    required String nameEn,
    required double allocatedAmount,
    String? subCode,
    String? cycleKey,
  }) =>
      budget.addSubCategory(
        householdId: householdId,
        parentCode: parentCode,
        nameEn: nameEn,
        allocatedAmount: allocatedAmount,
        subCode: subCode,
        cycleKey: cycleKey,
      );

  Future<List<Map<String, dynamic>>> getSubCategories(String parentCode) =>
      budget.getSubCategories(parentCode);

  Future<Map<String, dynamic>> renameSubCategory({
    required String parentCode,
    required String subCode,
    required String nameEn,
    String? nameAr,
    String? householdId,
  }) =>
      budget.renameSubCategory(
        parentCode: parentCode,
        subCode: subCode,
        nameEn: nameEn,
        nameAr: nameAr,
        householdId: householdId,
      );

  Future<Map<String, dynamic>> removeSubCategory({
    required String householdId,
    required String parentCode,
    required String subCode,
    String? cycleKey,
  }) =>
      budget.removeSubCategory(
        householdId: householdId,
        parentCode: parentCode,
        subCode: subCode,
        cycleKey: cycleKey,
      );

  Future<Map<String, List<CategoryItem>>> fetchHouseholdCategories(String householdId) =>
      budget.fetchHouseholdCategories(householdId: householdId);

  Future<bool> toggleCategoryStatus({
    required String householdId,
    required String categoryCode,
    required bool isActive,
  }) =>
      budget.toggleCategoryStatus(
        householdId: householdId,
        categoryCode: categoryCode,
        isActive: isActive,
      );

  Future<bool> createCustomCategory({
    required String householdId,
    required String code,
    required String category,
    List<String> keywords = const [],
    bool isFlexible = false,
    double allocatedAmount = 0.0,
  }) =>
      budget.createCustomCategory(
        householdId: householdId,
        code: code,
        category: category,
        keywords: keywords,
        isFlexible: isFlexible,
        allocatedAmount: allocatedAmount,
      );
}
