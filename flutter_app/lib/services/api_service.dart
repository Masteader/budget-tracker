/// API Service Facade
/// Delegating to specialized domain clients:
/// - BaseApiClient (HMAC-SHA256 signatures, auth headers, HTTP base methods)
/// - BudgetApiClient (Salary cycles, burn-rate forecast, settlements, sub-allocations)
/// - TransactionApiClient (Transaction ingestion and synchronization)
/// - ReceiptApiClient (Multi-page photo uploads, ZATCA QR analysis)
/// - ChatApiClient (Conversational expense parser, purchase simulation)
library;

import 'api/base_api_client.dart';
import 'api/budget_api_client.dart';
import 'api/chat_api_client.dart';
import 'api/receipt_api_client.dart';
import 'api/support_api_client.dart';
import 'api/transaction_api_client.dart';
import '../models/recurring_bill.dart';
import '../models/installment_plan.dart';

class ApiService {
  ApiService._();
  static final ApiService instance = ApiService._();

  final BaseApiClient base = BaseApiClient();
  late final BudgetApiClient budget = BudgetApiClient(baseClient: base);
  late final TransactionApiClient transaction = TransactionApiClient(baseClient: base);
  late final ReceiptApiClient receipt = ReceiptApiClient(baseClient: base);
  late final ChatApiClient chat = ChatApiClient(baseClient: base);
  late final SupportApiClient support = SupportApiClient(baseClient: base);

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
      );

  Future<Map<String, dynamic>> simulatePurchase({
    required String message,
    required String householdId,
    double? customAmount,
    String? customCategory,
  }) =>
      chat.simulatePurchase(
        message: message,
        householdId: householdId,
        customAmount: customAmount,
        customCategory: customCategory,
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

  Future<Map<String, dynamic>> getPartnerSettlement(String householdId, {double splitRatio = 0.50}) =>
      budget.fetchPartnerSettlement(householdId: householdId, splitRatio: splitRatio);

  Future<Map<String, dynamic>> fetchPartnerSettlement({required String householdId, double splitRatio = 0.5}) =>
      budget.fetchPartnerSettlement(householdId: householdId, splitRatio: splitRatio);

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

  String getStatementPdfUrl(String householdId, {String? cycleKey}) =>
      budget.getStatementPdfUrl(householdId, cycleKey: cycleKey);

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

  Future<Map<String, dynamic>> saveSubAllocations({
    required String householdId,
    required String categoryCode,
    required Map<String, double> subAllocations,
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
  }) =>
      budget.renameSubCategory(
        parentCode: parentCode,
        subCode: subCode,
        nameEn: nameEn,
        nameAr: nameAr,
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
}
