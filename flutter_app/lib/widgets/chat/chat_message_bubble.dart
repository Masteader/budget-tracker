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
  final bool isOffTopicWarning;
  final List<Map<String, dynamic>>? guidanceActions;

  ChatMessage({
    required this.isUser,
    required this.text,
    this.transactionData,
    this.isDuplicatePrompt = false,
    this.candidateData,
    this.simulationData,
    this.isPendingConfirmation = false,
    this.pendingData,
    this.isOffTopicWarning = false,
    this.guidanceActions,
  });
}

/// Renders either a user speech bubble or an assistant card with interactive modules.
class ChatMessageBubble extends StatelessWidget {
  final ChatMessage message;
  final PendingExpenseConfirmCallback? onConfirmPending;
  final VoidCallback? onCancelPending;
  final ValueChanged<String>? onEnrichCandidate;
  final ValueChanged<String>? onLogAsNewCandidate;
  final VoidCallback? onDiscardCandidate;
  final ValueChanged<String>? onActionTap;

  const ChatMessageBubble({
    super.key,
    required this.message,
    this.onConfirmPending,
    this.onCancelPending,
    this.onEnrichCandidate,
    this.onLogAsNewCandidate,
    this.onDiscardCandidate,
    this.onActionTap,
  });

  @override
  Widget build(BuildContext context) {
    if (message.isUser) {
      return Align(
        alignment: AlignmentDirectional.centerEnd,
        child: Container(
          margin: const EdgeInsetsDirectional.only(bottom: 12, start: 40),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: context.icedHeroGradient.colors,
            ),
            borderRadius: const BorderRadiusDirectional.only(
              topStart: Radius.circular(18),
              topEnd: Radius.circular(18),
              bottomStart: Radius.circular(18),
              bottomEnd: Radius.circular(4),
            ),
            boxShadow: [
              BoxShadow(
                color: (context.isDark ? Colors.black : context.primaryButtonBg).withValues(alpha: context.isDark ? 0.5 : 0.28),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(
              color: Colors.white.withValues(alpha: context.isDark ? 0.25 : 0.35),
              width: 1.0,
            ),
          ),
          child: Text(
            message.text,
            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
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
                color: message.isOffTopicWarning
                    ? (context.isDark ? const Color(0xFF2E1A0C) : const Color(0xFFFFF7ED))
                    : context.cardBg,
                borderRadius: const BorderRadiusDirectional.only(
                  topStart: Radius.circular(18),
                  topEnd: Radius.circular(18),
                  bottomEnd: Radius.circular(18),
                  bottomStart: Radius.circular(4),
                ),
                border: Border.all(
                  color: message.isOffTopicWarning
                      ? Colors.amber.shade700
                      : (context.isDark ? VelvetBurgundyColors.roseBorderDark : VelvetBurgundyColors.roseBorderLight),
                  width: message.isOffTopicWarning ? 1.5 : 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: (context.isDark ? Colors.black : context.primaryButtonBg).withValues(alpha: context.isDark ? 0.4 : 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: message.isOffTopicWarning
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.amber.shade700,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            message.text,
                            style: TextStyle(
                              color: message.isOffTopicWarning
                                  ? (context.isDark ? const Color(0xFFFED7AA) : const Color(0xFF9A3412))
                                  : context.textPrimary,
                              fontSize: 14,
                              height: 1.4,
                              fontFamilyFallback: VelvetBurgundyTheme.arabicFallback,
                            ),
                          ),
                        ),
                      ],
                    )
                  : Text(
                      message.text,
                      style: TextStyle(
                        color: context.textPrimary,
                        fontSize: 14,
                        height: 1.4,
                        fontFamilyFallback: VelvetBurgundyTheme.arabicFallback,
                      ),
                    ),
            ),
            if (message.guidanceActions != null && message.guidanceActions!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 4),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final action in message.guidanceActions!)
                      _buildGuidanceActionChip(context, action),
                  ],
                ),
              ),
            ],
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

  Widget _buildGuidanceActionChip(BuildContext context, Map<String, dynamic> action) {
    final lang = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
    final label = (lang == 'ar'
            ? action['label_ar']
            : (lang == 'ur' ? (action['label_ur'] ?? action['label_en']) : action['label_en'])) ??
        action['id'] ??
        '';
    final id = action['id'] as String? ?? '';
    final IconData icon;
    switch (id) {
      case 'open_tutor':
        icon = Icons.rocket_launch_rounded;
        break;
      case 'open_payday':
        icon = Icons.calendar_month_rounded;
        break;
      case 'open_budgets':
        icon = Icons.pie_chart_rounded;
        break;
      case 'open_accounts':
        icon = Icons.account_balance_wallet_rounded;
        break;
      case 'open_roles':
        icon = Icons.group_rounded;
        break;
      default:
        icon = Icons.arrow_forward_rounded;
    }

    return ActionChip(
      avatar: Icon(icon, size: 16, color: context.primaryButtonBg),
      label: Text(
        label.toString(),
        style: TextStyle(
          color: context.textPrimary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          fontFamilyFallback: VelvetBurgundyTheme.arabicFallback,
        ),
      ),
      backgroundColor: context.cardBg,
      side: BorderSide(
        color: context.isDark ? VelvetBurgundyColors.roseBorderDark : VelvetBurgundyColors.roseBorderLight,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      onPressed: onActionTap != null ? () => onActionTap!(id) : null,
    );
  }
}

