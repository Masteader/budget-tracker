/// API Service Facade
/// Delegating to specialized domain clients:
/// - BaseApiClient (HMAC-SHA256 signatures, auth headers, HTTP base methods)
/// - BudgetApiClient (Salary cycles, burn-rate forecast, settlements, sub-allocations)
/// - TransactionApiClient (SMS ingestion webhook, offline queue hooks)
/// - ReceiptApiClient (Multi-page photo uploads, ZATCA QR analysis)
/// - ChatApiClient (Conversational expense parser, purchase simulation)
library;

import 'api/base_api_client.dart';
import 'api/budget_api_client.dart';
import 'api/chat_api_client.dart';
import 'api/receipt_api_client.dart';
import 'api/transaction_api_client.dart';

class ApiService {
  ApiService._();
  static final ApiService instance = ApiService._();

  final BaseApiClient base = BaseApiClient();
  late final BudgetApiClient budget = BudgetApiClient(baseClient: base);
  late final TransactionApiClient transaction = TransactionApiClient(baseClient: base);
  late final ReceiptApiClient receipt = ReceiptApiClient(baseClient: base);
  late final ChatApiClient chat = ChatApiClient(baseClient: base);

  // ── SMS & Transactions ───────────────────────────────────────────────────

  Future<Map<String, dynamic>> postSms({
    required String rawSms,
    required String sender,
    required String receivedAt,
    required String householdId,
    String? deviceId,
  }) =>
      transaction.postSms(
        rawSms: rawSms,
        sender: sender,
        receivedAt: receivedAt,
        householdId: householdId,
        deviceId: deviceId,
      );

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
    );
  }

  // ── Budgets & Cycles ─────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getSalaryCycleForecast(String householdId) =>
      budget.fetchSalaryCycleForecast(householdId: householdId);

  Future<Map<String, dynamic>> fetchSalaryCycleForecast({required String householdId}) =>
      budget.fetchSalaryCycleForecast(householdId: householdId);

  Future<Map<String, dynamic>> getSalaryCycles(String householdId) async {
    final list = await budget.fetchSalaryCycles(householdId: householdId);
    return {'status': 'success', 'cycles': list};
  }

  Future<List<Map<String, dynamic>>> fetchSalaryCycles({required String householdId}) =>
      budget.fetchSalaryCycles(householdId: householdId);

  Future<Map<String, dynamic>> getPartnerSettlement(String householdId, {double splitRatio = 0.50}) =>
      budget.fetchPartnerSettlement(householdId: householdId, splitRatio: splitRatio);

  Future<Map<String, dynamic>> fetchPartnerSettlement({required String householdId, double splitRatio = 0.5}) =>
      budget.fetchPartnerSettlement(householdId: householdId, splitRatio: splitRatio);

  Future<Map<String, dynamic>> getBudgetBreakdown(String householdId, {String? cycleKey}) =>
      budget.fetchBudgetBreakdown(householdId: householdId, cycleKey: cycleKey);

  Future<Map<String, dynamic>> fetchBudgetBreakdown({required String householdId, String? cycleKey}) =>
      budget.fetchBudgetBreakdown(householdId: householdId, cycleKey: cycleKey);

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
