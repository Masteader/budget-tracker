import 'package:flutter/material.dart';
import '../../theme/app_themes.dart';

import '../transaction_item_breakdown_card.dart';
import 'duplicate_resolution_card.dart';
import 'pending_expense_confirmation_card.dart';
import 'purchase_simulation_card.dart';
import '../../l10n/app_localizations.dart';

/// Model representing a single message within the AI Transaction Chat.
class ChatMessage {
  final bool isUser;
  final String text;
  final Map<String, dynamic>? transactionData;
  final bool isDuplicatePrompt;
  final Map<String, dynamic>? candidateData;
  final Map<String, dynamic>? simulationData;
  final bool isPendingConfirmation;
  final Map<String, dynamic>? pendingData;

  ChatMessage({
    required this.isUser,
    required this.text,
    this.transactionData,
    this.isDuplicatePrompt = false,
    this.candidateData,
    this.simulationData,
    this.isPendingConfirmation = false,
    this.pendingData,
  });
}

/// Renders either a user speech bubble or an assistant card with interactive modules.
class ChatMessageBubble extends StatelessWidget {
  final ChatMessage message;
  final void Function(
    String confirmedMerchant,
    String confirmedCategoryCode,
    String? confirmedSubCategory,
    String confirmedPaidBy,
    String confirmedBeneficiary,
  )? onConfirmPending;
  final VoidCallback? onCancelPending;
  final ValueChanged<String>? onEnrichCandidate;
  final ValueChanged<String>? onLogAsNewCandidate;
  final VoidCallback? onDiscardCandidate;

  const ChatMessageBubble({
    super.key,
    required this.message,
    this.onConfirmPending,
    this.onCancelPending,
    this.onEnrichCandidate,
    this.onLogAsNewCandidate,
    this.onDiscardCandidate,
  });

  @override
  Widget build(BuildContext context) {
    if (message.isUser) {
      return Align(
        alignment: AlignmentDirectional.centerEnd,
        child: Container(
          margin: const EdgeInsetsDirectional.only(bottom: 12, start: 40),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: const BoxDecoration(
            color: Color(0xFF1F6FEB),
            borderRadius: BorderRadiusDirectional.only(
              topStart: Radius.circular(16),
              topEnd: Radius.circular(16),
              bottomStart: Radius.circular(16),
            ),
          ),
          child: Text(
            message.text,
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
        ),
      );
    }

    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        margin: const EdgeInsetsDirectional.only(bottom: 12, end: 30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: context.cardBg,
                borderRadius: const BorderRadiusDirectional.only(
                  topStart: Radius.circular(16),
                  topEnd: Radius.circular(16),
                  bottomEnd: Radius.circular(16),
                ),
                border: Border.all(color: context.borderColor),
              ),
              child: Text(
                message.text,
                style: TextStyle(color: context.textPrimary, fontSize: 14, height: 1.4),
              ),
            ),
            if (message.simulationData != null) ...[
              const SizedBox(height: 6),
              PurchaseSimulationCard(simulationData: message.simulationData!),
            ],
            if (message.isPendingConfirmation && message.pendingData != null && onConfirmPending != null) ...[
              const SizedBox(height: 8),
              PendingExpenseConfirmationCard(
                pendingData: message.pendingData!,
                onConfirm: onConfirmPending!,
                onCancel: onCancelPending ?? () {},
              ),
            ],
            if (message.transactionData != null) ...[
              const SizedBox(height: 6),
              TransactionItemBreakdownCard(
                merchant: message.transactionData!['merchant'] as String? ?? context.tr('merchant_generic'),
                amount: (message.transactionData!['amount'] as num?)?.toDouble() ?? 0.0,
                categoryCode: message.transactionData!['category_code'] as String?,
                source: 'chat',
                spentBy: (message.transactionData!['spent_by'] as String?) ?? 'me',
                items: (message.transactionData!['items'] as List?)
                        ?.map((e) => Map<String, dynamic>.from(e as Map))
                        .toList() ??
                    [],
                isReallocated: message.transactionData!['is_reallocated'] as bool? ?? false,
                initiallyExpanded: true,
              ),
            ],
            if (message.isDuplicatePrompt && message.candidateData != null && onEnrichCandidate != null) ...[
              const SizedBox(height: 8),
              DuplicateResolutionCard(
                candidateData: message.candidateData!,
                onEnrich: onEnrichCandidate!,
                onLogAsNew: onLogAsNewCandidate ?? (_) {},
                onDiscard: onDiscardCandidate,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
