import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/widgets/three_d_surface_card.dart';
import '../core/widgets/three_d_icon_puck.dart';
import '../services/zatca_decoder.dart';
import '../services/receipt_storage_service.dart';
import '../theme/app_themes.dart';
import '../l10n/app_localizations.dart';
import 'app_snackbar.dart';
import 'receipt_photo_viewer_dialog.dart';

class TransactionItemBreakdownCard extends StatelessWidget {
  final String merchant;
  final double amount;
  final String currency;
  final String? categoryCode;
  final String source;
  final String spentBy;
  final List<Map<String, dynamic>> items;
  final bool isReallocated;
  final bool initiallyExpanded;
  final String? receiptUrl;
  final String? qrCodeRaw;
  final bool isInstallment;
  final String? installmentBadgeText;
  final String? installmentProvider;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  /// Shown instead of the edit/delete actions when the signed-in user may not
  /// change this transaction (another member's entry and the user is no admin).
  final String? lockedNote;

  /// Replaces the roommate "me / partner / shared" badge, e.g. the family
  /// Nafaqah badge ("Owed to Sara", UX-04).
  final Widget? attributionBadge;

  /// When set, the row shows its time (the feed groups rows by day, UX-11).
  final DateTime? timestamp;

  const TransactionItemBreakdownCard({
    super.key,
    required this.merchant,
    required this.amount,
    this.currency = 'SAR',
    this.categoryCode,
    this.source = 'chat',
    this.spentBy = 'both',
    this.items = const [],
    this.isReallocated = false,
    this.initiallyExpanded = false,
    this.receiptUrl,
    this.qrCodeRaw,
    this.isInstallment = false,
    this.installmentBadgeText,
    this.installmentProvider,
    this.onEdit,
    this.onDelete,
    this.lockedNote,
    this.attributionBadge,
    this.timestamp,
  });

  IconData get _sourceIcon {
    switch (source) {
      case 'chat':
        return Icons.chat_bubble_outline;
      case 'receipt_scan':
        return Icons.document_scanner_outlined;
      case 'manual':
        return Icons.edit_note;
      case 'direct':
      default:
        return Icons.receipt_outlined;
    }
  }

  String _getSourceLabel(BuildContext context) {
    switch (source) {
      case 'chat':
        return context.tr('ai_chat_entry');
      case 'receipt_scan':
        return context.tr('invoice_scan');
      case 'manual':
        return context.tr('manual_log');
      case 'direct':
      default:
        return context.tr('direct_entry');
    }
  }

  Widget _buildSpentByBadge(BuildContext context, String who, {bool detailed = false}) {
    Color bg;
    Color fg;
    IconData icon;
    String label;

    switch (who.toLowerCase()) {
      case 'partner':
        bg = (context.isDark ? const Color(0xFF5E1327) : const Color(0xFFFDF2F4));
        fg = context.isDark ? const Color(0xFFF0A3BC) : const Color(0xFF9E1B42);
        icon = Icons.favorite_outline;
        label = detailed ? context.tr('paid_by_partner') : context.tr('partner');
        break;
      case 'me':
        bg = (context.isDark ? const Color(0xFF381423) : const Color(0xFFF7E6EB));
        fg = context.isDark ? const Color(0xFFE598B0) : const Color(0xFF4A0E1E);
        icon = Icons.person_outline;
        label = detailed ? context.tr('paid_by_me') : context.tr('me');
        break;
      case 'both':
      default:
        bg = (context.isDark ? const Color(0xFF2E1520) : const Color(0xFFF2ECEE));
        fg = context.isDark ? const Color(0xFFC7AEB6) : const Color(0xFF59454C);
        icon = Icons.people_alt_outlined;
        label = detailed ? context.tr('both_shared') : context.tr('both');
        break;
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: detailed ? 10 : 6, vertical: detailed ? 4 : 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: fg.withValues(alpha: 0.35), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: detailed ? 14 : 11, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.outfit(
              color: fg,
              fontSize: detailed ? 12 : 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstallmentBadge(BuildContext context, String label, String provider) {
    final isTamara = provider.toLowerCase().contains('tamara');
    final isTabby = provider.toLowerCase().contains('tabby');
    final color = isTamara
        ? const Color(0xFFE11D48)
        : (isTabby
            ? const Color(0xFFD97706)
            : context.accentText);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.45), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.credit_score_rounded, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.outfit(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: ThreeDSurfaceCard(
        borderRadius: 20,
        padding: EdgeInsets.zero,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: initiallyExpanded,
            iconColor: context.isDark ? VelvetBurgundyColors.roseGoldGlow : VelvetBurgundyColors.primaryLight,
            collapsedIconColor: context.textSecondary,
            shape: const Border(),
            collapsedShape: const Border(),
            leading: ThreeDIconPuck(
              size: 42,
              isSquircle: true,
              icon: _sourceIcon,
              iconSize: 20,
              iconColor: context.isDark ? VelvetBurgundyColors.roseGoldGlow : Colors.white,
            ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  context.trMerchant(merchant),
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: context.textPrimary,
                  ),
                ),
              ),
              // Neutral ink: red is kept for real warnings (UX-11).
              Text(
                context.money(amount, currency),
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: context.textPrimary,
                ),
              ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (timestamp != null)
                  Text(
                    context.fmtDate(timestamp!.toLocal(), 'h:mm a'),
                    key: const ValueKey('tx_row_time'),
                    style: TextStyle(color: context.textSecondary, fontSize: 12),
                  ),
                if (isInstallment)
                  _buildInstallmentBadge(
                    context,
                    installmentBadgeText ?? context.tr('tib_installment'),
                    installmentProvider ?? 'Tamara',
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: context.scaffoldBg,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _getSourceLabel(context),
                    style: TextStyle(color: context.textSecondary, fontSize: 11),
                  ),
                ),
                attributionBadge ?? _buildSpentByBadge(context, spentBy),
                if (categoryCode != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: context.accentText.withValues(alpha: context.isDark ? 0.12 : 0.08),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: context.accentText.withValues(alpha: context.isDark ? 0.25 : 0.35),
                        width: 0.7,
                      ),
                    ),
                    child: Text(
                      context.trCat(categoryCode!),
                      style: TextStyle(
                        color: context.accentText,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                if (isReallocated)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      context.tr('reallocated'),
                      style: const TextStyle(
                        color: Colors.orange,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                if (receiptUrl != null && receiptUrl!.isNotEmpty)
                  InkWell(
                    onTap: () => ReceiptPhotoViewerDialog.show(
                      context,
                      receiptUrl: receiptUrl!,
                      merchant: merchant,
                      amount: amount,
                    ),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF58A6FF).withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF58A6FF).withValues(alpha: 0.4), width: 0.8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.receipt_long_rounded, size: 11, color: Color(0xFF58A6FF)),
                          const SizedBox(width: 4),
                          Text(
                            context.tr('view_receipt'),
                            style: const TextStyle(
                              color: Color(0xFF58A6FF),
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (qrCodeRaw != null && qrCodeRaw!.isNotEmpty)
                  InkWell(
                    onTap: () => _showZatcaDialog(context, qrCodeRaw!),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: context.accentText.withValues(alpha: context.isDark ? 0.14 : 0.08),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: context.accentText.withValues(alpha: context.isDark ? 0.35 : 0.3),
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.qr_code_2_rounded,
                            size: 11,
                            color: context.accentText,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            context.tr('tib_zatca_qr'),
                            style: TextStyle(
                              color: context.accentText,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          children: [
            Divider(color: context.borderColor, height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Attribution banner
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: context.scaffoldBg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: context.borderColor, width: 0.8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          context.tr('attributed_to'),
                          style: GoogleFonts.outfit(
                            color: context.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Flexible(child: attributionBadge ?? _buildSpentByBadge(context, spentBy, detailed: true)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Itemized items section
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        context.tr('exact_line_items'),
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          letterSpacing: 1,
                          fontWeight: FontWeight.w700,
                          color: context.textSecondary,
                        ),
                      ),
                      Text(
                        items.isNotEmpty
                            ? context.trPlural('items_count', items.length)
                            : context.tr('single_expense'),
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          color: context.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  if (items.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: context.subtleCardBg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: context.borderColor),
                      ),
                      child: Column(
                        children: [
                          ...items.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final it = entry.value;
                            final name = it['name'] ?? context.tr('sim_item');
                            final qty = (it['quantity'] as num?)?.toDouble() ?? 1.0;
                            final price = (it['price'] as num?)?.toDouble() ?? 0.0;
                            return Padding(
                              padding: EdgeInsets.only(
                                top: idx > 0 ? 6 : 0,
                                bottom: idx < items.length - 1 ? 6 : 0,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: context.accentText,
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      '${qty > 1 ? '${qty.toStringAsFixed(0)}x ' : ''}$name',
                                      style: GoogleFonts.outfit(
                                        color: context.textPrimary,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    context.money(price, currency),
                                    style: GoogleFonts.outfit(
                                      color: context.textPrimary,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Divider(color: context.borderColor, height: 1),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                context.tr('total_breakdown'),
                                style: GoogleFonts.outfit(
                                  color: context.textSecondary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                context.money(amount, currency),
                                style: GoogleFonts.outfit(
                                  color: context.accentText,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: context.subtleCardBg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: context.borderColor),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.receipt_outlined, size: 18, color: context.textSecondary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '1x ${context.trMerchant(merchant)} (${context.money(amount, currency)})\n${context.tr('no_line_items_desc')}',
                              style: TextStyle(color: context.textSecondary, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (receiptUrl != null && receiptUrl!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          context.tr('receipt_photo'),
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            letterSpacing: 1,
                            fontWeight: FontWeight.w700,
                            color: context.textSecondary,
                          ),
                        ),
                        Text(
                          context.tr('tap_to_zoom'),
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            color: const Color(0xFF58A6FF),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () => ReceiptPhotoViewerDialog.show(
                        context,
                        receiptUrl: receiptUrl!,
                        merchant: merchant,
                        amount: amount,
                      ),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        height: 120,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: context.subtleCardBg,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: context.borderColor),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              FutureBuilder<String?>(
                                future: ReceiptStorageService().getSignedReceiptUrl(receiptUrl!),
                                builder: (ctx, snapshot) {
                                  final resolvedUrl = snapshot.data;
                                  if (resolvedUrl == null ||
                                      (!resolvedUrl.startsWith('http://') && !resolvedUrl.startsWith('https://'))) {
                                    return Center(
                                      child: Icon(Icons.receipt_long_rounded, color: context.textSecondary, size: 32),
                                    );
                                  }
                                  return Image.network(
                                    resolvedUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (ctx, _, __) => Center(
                                      child: Icon(Icons.broken_image_outlined, color: context.textSecondary, size: 32),
                                    ),
                                  );
                                },
                              ),
                              Container(
                                color: Colors.black.withValues(alpha: 0.25),
                              ),
                              PositionedDirectional(
                                end: 8,
                                bottom: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: context.cardBg.withValues(alpha: 0.85),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: context.borderColor),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.zoom_in, color: Color(0xFF58A6FF), size: 14),
                                      const SizedBox(width: 4),
                                      Text(
                                        context.tr('view_full'),
                                        style: TextStyle(color: context.textPrimary, fontSize: 10, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (qrCodeRaw != null && qrCodeRaw!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          context.tr('zatca_qr_code_data'),
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            letterSpacing: 1,
                            fontWeight: FontWeight.w700,
                            color: context.accentText,
                          ),
                        ),
                        InkWell(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: qrCodeRaw!));
                            AppSnackBar.showSuccess(
                              context,
                              context.tr('tib_qr_copied'),
                              title: context.tr('set_copied'),
                              duration: const Duration(seconds: 2),
                            );
                          },
                          child: Row(
                            children: [
                              Icon(
                                Icons.copy_rounded,
                                size: 12,
                                color: context.accentText,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                context.tr('copy_base64'),
                                style: GoogleFonts.outfit(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: context.accentText,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: context.subtleCardBg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: context.borderColor),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Builder(
                            builder: (ctx) {
                              final decoded = ZatcaDecoder.decodeTlv(qrCodeRaw!);
                              if (decoded == null) return const SizedBox.shrink();
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (decoded['seller'] != null)
                                      Text(
                                        '${context.tr('seller_merchant')} ${decoded['seller']}',
                                        style: GoogleFonts.outfit(color: context.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                                      ),
                                    if (decoded['vat_number'] != null)
                                      Text(
                                        '${context.tr('vat_registration')} ${decoded['vat_number']}',
                                        style: GoogleFonts.outfit(color: context.textSecondary, fontSize: 11),
                                      ),
                                    if (decoded['timestamp'] != null)
                                      Text(
                                        '${context.tr('invoice_date')} ${decoded['timestamp']}',
                                        style: GoogleFonts.outfit(color: context.textSecondary, fontSize: 11),
                                      ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 6),
                                      child: Divider(color: context.borderColor, height: 1),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                          Text(
                            context.tr('tib_raw_tlv'),
                            style: GoogleFonts.outfit(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: context.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          SelectableText(
                            qrCodeRaw!,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 10,
                              color: context.isDark ? const Color(0xFF79C0FF) : const Color(0xFF0284C7),
                            ),
                            maxLines: 4,
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (onEdit != null || onDelete != null) ...[
              Divider(color: context.borderColor, height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (onEdit != null)
                      TextButton.icon(
                        icon: Icon(Icons.edit_outlined, size: 16, color: context.textSecondary),
                        label: Text(context.tr('edit'), style: TextStyle(color: context.textPrimary, fontSize: 12)),
                        onPressed: onEdit,
                      ),
                    if (onDelete != null) ...[
                      const SizedBox(width: 8),
                      TextButton.icon(
                        icon: Icon(Icons.delete_outline, size: 16, color: context.dangerColor),
                        label: Text(context.tr('delete'), style: TextStyle(color: context.dangerColor, fontSize: 12)),
                        onPressed: onDelete,
                      ),
                    ],
                  ],
                ),
              ),
            ] else if (lockedNote != null) ...[
              Divider(color: context.borderColor, height: 1),
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 8),
                child: Row(
                  children: [
                    Icon(Icons.lock_outline_rounded, size: 14, color: context.textSecondary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        lockedNote!,
                        style: TextStyle(color: context.textSecondary, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
  }

  static void _showZatcaDialog(BuildContext context, String rawQr) {
    final decoded = ZatcaDecoder.decodeTlv(rawQr);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: context.borderColor),
        ),
        title: Row(
          children: [
            Icon(
              Icons.qr_code_2_rounded,
              color: context.accentText,
              size: 24,
            ),
            const SizedBox(width: 8),
            Text(
              context.tr('tib_saudi_zatca_qr'),
              style: GoogleFonts.outfit(
                color: context.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (decoded != null) ...[
                if (decoded['seller'] != null) ...[
                  Text(context.tr('seller_merchant'), style: GoogleFonts.outfit(color: context.textSecondary, fontSize: 11)),
                  Text(decoded['seller']!, style: GoogleFonts.outfit(color: context.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                ],
                if (decoded['vat_number'] != null) ...[
                  Text(context.tr('vat_registration'), style: GoogleFonts.outfit(color: context.textSecondary, fontSize: 11)),
                  Text(decoded['vat_number']!, style: GoogleFonts.outfit(color: context.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                ],
                if (decoded['timestamp'] != null) ...[
                  Text(context.tr('invoice_date'), style: GoogleFonts.outfit(color: context.textSecondary, fontSize: 11)),
                  Text(decoded['timestamp']!, style: GoogleFonts.outfit(color: context.textPrimary, fontSize: 13)),
                  const SizedBox(height: 8),
                ],
                if (decoded['total'] != null) ...[
                  Text(context.tr('verified_total_vat'), style: GoogleFonts.outfit(color: context.textSecondary, fontSize: 11)),
                  Text(
                    context.trArgs('tib_total_vat', {'total': context.sar(num.tryParse('${decoded['total']}') ?? 0), 'vat': context.sar(num.tryParse('${decoded['vat'] ?? 0}') ?? 0)}),
                    style: GoogleFonts.outfit(
                      color: context.accentText,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Divider(color: context.borderColor),
              ],
              Text(context.tr('tib_raw_tlv_string'), style: GoogleFonts.outfit(color: context.textSecondary, fontSize: 11)),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: context.subtleCardBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: context.borderColor),
                ),
                child: SelectableText(
                  rawQr,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    color: Color(0xFF79C0FF),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            icon: Icon(
              Icons.copy_rounded,
              size: 14,
              color: context.accentText,
            ),
            label: Text(
              context.tr('copy_base64'),
              style: TextStyle(
                color: context.accentText,
              ),
            ),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: rawQr));
              Navigator.pop(ctx);
              AppSnackBar.showSuccess(
                context,
                context.tr('tib_b64_copied'),
                title: context.tr('set_copied'),
                duration: const Duration(seconds: 2),
              );
            },
          ),
          TextButton(
            child: Text(context.tr('close'), style: TextStyle(color: context.textSecondary)),
            onPressed: () => Navigator.pop(ctx),
          ),
        ],
      ),
    );
  }
}
