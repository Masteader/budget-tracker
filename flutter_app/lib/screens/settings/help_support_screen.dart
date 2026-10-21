import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/api/support_api_client.dart';
import '../../services/api_service.dart';
import '../../widgets/app_snackbar.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_themes.dart';
import '../../widgets/onboarding/user_guide_walkthrough_dialog.dart';

class HelpSupportScreen extends StatefulWidget {
  final String? householdId;
  final String? userEmail;

  /// Sends developer inquiries; defaults to [ApiService.instance.support].
  final SupportApiClient? supportClient;

  const HelpSupportScreen({
    super.key,
    this.householdId,
    this.userEmail,
    this.supportClient,
  });

  @override
  State<HelpSupportScreen> createState() => _HelpSupportScreenState();
}

class _HelpSupportScreenState extends State<HelpSupportScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _faqSearchController = TextEditingController();
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();

  String _faqQuery = '';
  bool _isSending = false;
  String _selectedLanguage = 'ar';
  bool _languageInitialized = false;

  final List<_SupportMessage> _messages = [];

  /// Resolves [key] in the support language chosen on this screen.
  String _t(String key) => AppLocalizations(Locale(_selectedLanguage)).get(key);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_languageInitialized) {
      _languageInitialized = true;
      final appLang = Localizations.maybeLocaleOf(context)?.languageCode;
      if (appLang == 'en' || appLang == 'ar' || appLang == 'ur') {
        _selectedLanguage = appLang!;
      }
      _messages.add(_SupportMessage(isUser: false, text: _t('support_welcome')));
    }
  }

  void _onLanguageChanged(String newLang) {
    if (_selectedLanguage == newLang) return;
    setState(() {
      _selectedLanguage = newLang;
      if (_messages.length == 1 && !_messages.first.isUser) {
        _messages[0] = _SupportMessage(isUser: false, text: _t('support_welcome'));
      }
    });
  }

  /// Manual fallback address, shown only when in-app delivery fails. In-app
  /// messages go through POST /support/inquiries, which emails the same inbox.
  static const String developerEmail = 'fmscoinfo@fmsco.com.sa';

  SupportApiClient get _supportClient => widget.supportClient ?? ApiService.instance.support;

  // FAQ content is stored as translation keys and resolved in the language
  // selected on this screen (defaults to the app locale).
  static const List<_FaqCategory> _faqCategories = [
    _FaqCategory(
      titleKey: 'faq_cat_salary',
      icon: Icons.calendar_month_rounded,
      color: Color(0xFFF59E0B),
      faqs: [
        _FaqItem(questionKey: 'faq_salary_q1', answerKey: 'faq_salary_a1'),
        _FaqItem(questionKey: 'faq_salary_q2', answerKey: 'faq_salary_a2'),
        _FaqItem(questionKey: 'faq_salary_q3', answerKey: 'faq_salary_a3'),
      ],
    ),
    // UX-05: the family rules, from the owner's decision (no spousal split).
    _FaqCategory(
      titleKey: 'faq_cat_nafaqah',
      icon: Icons.family_restroom_rounded,
      color: AppThemes.champagneGold,
      faqs: [
        _FaqItem(questionKey: 'faq_nafaqah_q1', answerKey: 'faq_nafaqah_a1'),
        _FaqItem(questionKey: 'faq_nafaqah_q2', answerKey: 'faq_nafaqah_a2'),
        _FaqItem(questionKey: 'faq_nafaqah_q3', answerKey: 'faq_nafaqah_a3'),
      ],
    ),
    _FaqCategory(
      titleKey: 'faq_cat_receipts',
      icon: Icons.qr_code_scanner_rounded,
      color: AppThemes.success,
      faqs: [
        _FaqItem(questionKey: 'faq_receipts_q1', answerKey: 'faq_receipts_a1'),
        _FaqItem(questionKey: 'faq_receipts_q2', answerKey: 'faq_receipts_a2'),
        _FaqItem(questionKey: 'faq_receipts_q3', answerKey: 'faq_receipts_a3'),
      ],
    ),
    _FaqCategory(
      titleKey: 'faq_cat_bills',
      icon: Icons.receipt_long_rounded,
      color: Color(0xFF3B82F6),
      faqs: [
        _FaqItem(questionKey: 'faq_bills_q1', answerKey: 'faq_bills_a1'),
        _FaqItem(questionKey: 'faq_bills_q2', answerKey: 'faq_bills_a2'),
        _FaqItem(questionKey: 'faq_bills_q3', answerKey: 'faq_bills_a3'),
      ],
    ),
    _FaqCategory(
      titleKey: 'faq_cat_bnpl',
      icon: Icons.credit_card_rounded,
      color: Color(0xFF8B5CF6),
      faqs: [
        _FaqItem(questionKey: 'faq_bnpl_q1', answerKey: 'faq_bnpl_a1'),
      ],
    ),
    _FaqCategory(
      titleKey: 'faq_cat_household',
      icon: Icons.people_alt_rounded,
      color: Color(0xFF10B981),
      faqs: [
        _FaqItem(questionKey: 'faq_household_q1', answerKey: 'faq_household_a1'),
        _FaqItem(questionKey: 'faq_household_q2', answerKey: 'faq_household_a2'),
      ],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _faqSearchController.dispose();
    _chatController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  void _sendSupportQuery([String? predefinedText]) async {
    final query = (predefinedText ?? _chatController.text).trim();
    if (query.isEmpty || _isSending) return;

    _chatController.clear();
    setState(() {
      _messages.add(_SupportMessage(isUser: true, text: query));
      _isSending = true;
    });
    _scrollToBottom();

    try {
      final res = await ApiService.instance.support.postSupportChat(
        message: query,
        householdId: widget.householdId,
        language: _selectedLanguage,
      );

      final reply = res['reply'] as String? ?? _t('support_reply_fallback');
      final escalate = res['escalate_to_developer'] == true;
      final summary = res['summary'] as String?;

      if (mounted) {
        setState(() {
          _messages.add(_SupportMessage(
            isUser: false,
            text: reply,
            isEscalation: escalate,
            escalationSummary: summary ?? query,
          ));
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.add(_SupportMessage(
            isUser: false,
            text: _t('support_network_error'),
            isEscalation: true,
            escalationSummary: query,
          ));
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
        _scrollToBottom();
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Plain-text diagnostics for the manual email fallback (copied to the clipboard).
  String _diagnostics(String issueSummary) => '''To: $developerEmail
Subject: [Budget Tracker Support] $issueSummary

Issue details:
$issueSummary

App: Budget Tracker (v1.0.0+1)
Household: ${widget.householdId ?? "N/A"}
User: ${widget.userEmail ?? "N/A"}
''';

  /// Opens the in-app composer that emails the developer through the backend.
  /// [issueSummary] (an escalation summary) pre-fills the message.
  Future<void> _contactDeveloper([String? issueSummary]) async {
    final result = await showDialog<SupportInquiryResult>(
      context: context,
      builder: (ctx) => _DeveloperInquiryDialog(
        initialMessage: issueSummary ?? '',
        locale: _selectedLanguage,
        householdId: widget.householdId,
        client: _supportClient,
        developerEmail: developerEmail,
        diagnostics: _diagnostics,
      ),
    );
    if (!mounted || result == null || !result.isSent) return;
    AppSnackBar.showSuccess(
      context,
      context.trArgs('support_inquiry_sent', {'ref': result.reference ?? '-'}),
      title: context.tr('support_inquiry_sent_title'),
      icon: Icons.mark_email_read_rounded,
      duration: const Duration(seconds: 5),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.scaffoldBg,
      appBar: AppBar(
        backgroundColor: context.cardBg,
        elevation: 0,
        title: Text(
          context.tr('help_support'),
          style: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: context.textPrimary),
        ),
        actions: [
          // Independent language selector toggle pill
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: context.chipBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: context.borderColor),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildLanguagePill('ar', '🇸🇦 ع', 'العربية'),
                _buildLanguagePill('en', '🇺🇸 EN', 'English'),
                _buildLanguagePill('ur', '🇵🇰 اردو', 'اردو'),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.play_circle_outline_rounded,
                color: AppThemes.success),
            tooltip: context.tr('support_replay_guide'),
            onPressed: () => UserGuideWalkthroughDialog.show(context),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppThemes.success,
          indicatorWeight: 3,
          labelColor: AppThemes.success,
          unselectedLabelColor: context.textSecondary,
          labelStyle:
              GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: [
            Tab(icon: const Icon(Icons.menu_book_rounded), text: context.tr('support_tab_faqs')),
            Tab(icon: const Icon(Icons.smart_toy_rounded), text: context.tr('nav_ai')),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildFaqTab(),
          _buildAiChatTab(),
        ],
      ),
    );
  }

  /// Language toggle used by the support assistant. Language names are shown
  /// as endonyms (each in its own script) so they are recognisable in any UI
  /// language; the pill exposes button/selected semantics for screen readers.
  Widget _buildLanguagePill(String code, String text, String semanticLabel) {
    final selected = _selectedLanguage == code;
    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      excludeSemantics: true,
      child: InkWell(
        onTap: () => _onLanguageChanged(code),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          constraints: const BoxConstraints(minHeight: 32),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: selected ? AppThemes.success : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            text,
            style: TextStyle(
              color: selected ? Colors.black : context.textSecondary,
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFaqTab() {
    final query = _faqQuery.toLowerCase();
    final filteredCategories = _faqCategories.map((cat) {
      final title = _t(cat.titleKey);
      final matchingFaqs = cat.faqs.where((f) {
        return _t(f.questionKey).toLowerCase().contains(query) ||
            _t(f.answerKey).toLowerCase().contains(query) ||
            title.toLowerCase().contains(query);
      }).toList();
      return _FaqCategory(
        titleKey: cat.titleKey,
        icon: cat.icon,
        color: cat.color,
        faqs: matchingFaqs,
      );
    }).where((cat) => cat.faqs.isNotEmpty).toList();

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      children: [
        // Replay Guide Banner
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: context.isDark ? const [Color(0xFF161B22), Color(0xFF1F242C)] : const [Color(0xFFF1F5F9), Color(0xFFE2E8F0)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.borderColor),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppThemes.success.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.explore_rounded,
                    color: AppThemes.success, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('support_walkthrough_title'),
                      style: GoogleFonts.outfit(
                        color: context.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.tr('support_walkthrough_desc'),
                      style: GoogleFonts.outfit(
                        color: context.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppThemes.success,
                  foregroundColor: Colors.black,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () => UserGuideWalkthroughDialog.show(context),
                child: Text(context.tr('support_replay'),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Search Bar
        TextField(
          controller: _faqSearchController,
          onChanged: (v) => setState(() => _faqQuery = v),
          style: GoogleFonts.outfit(color: context.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            hintText: context.tr('support_search_hint'),
            hintStyle:
                GoogleFonts.outfit(color: context.textSecondary, fontSize: 13),
            prefixIcon:
                Icon(Icons.search_rounded, color: context.textSecondary),
            suffixIcon: _faqQuery.isNotEmpty
                ? IconButton(
                    tooltip: context.tr('support_clear_search'),
                    icon: Icon(Icons.clear_rounded,
                        color: context.textSecondary),
                    onPressed: () {
                      _faqSearchController.clear();
                      setState(() => _faqQuery = '');
                    },
                  )
                : null,
            filled: true,
            fillColor: context.inputBg,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: context.borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppThemes.success),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Categories List
        ...filteredCategories.map((cat) {
          return Card(
            color: context.cardBg,
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: context.borderColor),
            ),
            child: Theme(
              data:
                  Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                leading: Icon(cat.icon, color: cat.color, size: 22),
                title: Text(
                  _t(cat.titleKey),
                  style: GoogleFonts.outfit(
                    color: context.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                children: cat.faqs.map((faq) {
                  return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: context.borderColor),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _t(faq.questionKey),
                          style: GoogleFonts.outfit(
                            color: context.successText,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _t(faq.answerKey),
                          style: GoogleFonts.outfit(
                            color: context.textSecondary,
                            fontSize: 12.5,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          );
        }),

        const SizedBox(height: 16),

        // Direct Email Developer Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.cardBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.mail_outline_rounded,
                      color: AppThemes.success, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    context.tr('support_direct_dev'),
                    style: GoogleFonts.outfit(
                      color: context.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 13.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                context.tr('support_direct_dev_desc'),
                style: GoogleFonts.outfit(
                  color: context.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppThemes.success,
                    side: const BorderSide(color: AppThemes.success),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.send_rounded, size: 16),
                  label: Text(context.tr('support_inquiry_send'),
                      style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                  onPressed: () => _contactDeveloper(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAiChatTab() {
    final quickChips = [
      _t('support_chip_salary'),
      _t('support_chip_iqama'),
      _t('support_chip_zatca'),
      _t('support_chip_split'),
    ];

    return Column(
      children: [
        // Quick Chips Horizontal Bar
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: quickChips.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (ctx, idx) {
              return ActionChip(
                backgroundColor: context.cardBg,
                side: BorderSide(color: context.borderColor),
                label: Text(
                  quickChips[idx],
                  style: GoogleFonts.outfit(
                    color: context.successText,
                    fontSize: 12,
                  ),
                ),
                onPressed: () => _sendSupportQuery(quickChips[idx]),
              );
            },
          ),
        ),

        // Chat Message List
        Expanded(
          child: ListView.builder(
            controller: _chatScrollController,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            itemCount: _messages.length,
            itemBuilder: (ctx, idx) {
              final msg = _messages[idx];
              return Column(
                crossAxisAlignment: msg.isUser
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    constraints: const BoxConstraints(maxWidth: 320),
                    decoration: BoxDecoration(
                      color: msg.isUser
                          ? AppThemes.success
                          : context.cardBg,
                      borderRadius: BorderRadius.circular(14),
                      border: msg.isUser
                          ? null
                          : Border.all(color: context.borderColor),
                    ),
                    child: Text(
                      msg.text,
                      style: GoogleFonts.outfit(
                        color: msg.isUser ? Colors.black : context.textPrimary,
                        fontSize: 13.5,
                        height: 1.4,
                        fontWeight:
                            msg.isUser ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),

                  // Escalation Action Card if flagged
                  if (msg.isEscalation) ...[
                    Container(
                      margin: const EdgeInsets.only(top: 4, bottom: 8),
                      padding: const EdgeInsets.all(12),
                      constraints: const BoxConstraints(maxWidth: 320),
                      decoration: BoxDecoration(
                        color: context.subtleCardBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppThemes.success),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.engineering_rounded,
                                  color: AppThemes.success, size: 18),
                              const SizedBox(width: 6),
                              Text(
                                context.tr('support_escalate'),
                                style: GoogleFonts.outfit(
                                  color: context.textPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            context.tr('support_escalate_desc'),
                            style: GoogleFonts.outfit(
                              color: context.textSecondary,
                              fontSize: 11.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppThemes.success,
                                foregroundColor: Colors.black,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              icon: const Icon(Icons.send_rounded, size: 14),
                              label: Text(
                                context.tr('support_inquiry_send'),
                                style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                              onPressed: () => _contactDeveloper(
                                  msg.escalationSummary ?? msg.text),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),

        // Sending indicator
        if (_isSending)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppThemes.success,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  context.tr('support_thinking'),
                  style: GoogleFonts.outfit(
                      color: context.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),

        // Chat Input Bar
        Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          decoration: BoxDecoration(
            color: context.cardBg,
            border: Border(top: BorderSide(color: context.borderColor)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _chatController,
                  style: GoogleFonts.outfit(color: context.textPrimary, fontSize: 13.5),
                  decoration: InputDecoration(
                    hintText: context.tr('support_chat_hint'),
                    hintStyle: GoogleFonts.outfit(
                        color: context.textSecondary, fontSize: 12.5),
                    filled: true,
                    fillColor: context.inputBg,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: context.borderColor),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: context.borderColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppThemes.success),
                    ),
                  ),
                  onSubmitted: (_) => _sendSupportQuery(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                style: IconButton.styleFrom(
                  backgroundColor: AppThemes.success,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                tooltip: context.tr('support_send'),
                icon: const Icon(Icons.send_rounded, size: 20),
                onPressed: _isSending ? null : () => _sendSupportQuery(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SupportMessage {
  final bool isUser;
  final String text;
  final bool isEscalation;
  final String? escalationSummary;

  const _SupportMessage({
    required this.isUser,
    required this.text,
    this.isEscalation = false,
    this.escalationSummary,
  });
}

class _FaqCategory {
  final String titleKey;
  final IconData icon;
  final Color color;
  final List<_FaqItem> faqs;

  const _FaqCategory({
    required this.titleKey,
    required this.icon,
    required this.color,
    required this.faqs,
  });
}

class _FaqItem {
  final String questionKey;
  final String answerKey;

  const _FaqItem({
    required this.questionKey,
    required this.answerKey,
  });
}

/// Composer that emails the developer via POST /support/inquiries. It reports
/// success only when the server confirms delivery; on failure it keeps the
/// text and offers the manual email fallback.
class _DeveloperInquiryDialog extends StatefulWidget {
  final String initialMessage;
  final String locale;
  final String? householdId;
  final SupportApiClient client;
  final String developerEmail;
  final String Function(String issueSummary) diagnostics;

  const _DeveloperInquiryDialog({
    required this.initialMessage,
    required this.locale,
    required this.householdId,
    required this.client,
    required this.developerEmail,
    required this.diagnostics,
  });

  @override
  State<_DeveloperInquiryDialog> createState() => _DeveloperInquiryDialogState();
}

class _DeveloperInquiryDialogState extends State<_DeveloperInquiryDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialMessage);
  bool _sending = false;
  String? _error;
  bool _offerFallback = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (_sending) return;
    if (text.isEmpty) {
      setState(() {
        _error = context.tr('support_inquiry_empty');
        _offerFallback = false;
      });
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    final result = await widget.client.sendSupportInquiry(
      message: text,
      locale: widget.locale,
      householdId: widget.householdId,
    );
    if (!mounted) return;
    if (result.isSent) {
      Navigator.of(context).pop(result);
      return;
    }
    setState(() {
      _sending = false;
      _offerFallback = result.outcome == SupportInquiryOutcome.unavailable ||
          result.outcome == SupportInquiryOutcome.network;
      _error = switch (result.outcome) {
        SupportInquiryOutcome.unauthorized => context.tr('support_inquiry_err_auth'),
        SupportInquiryOutcome.rateLimited => context.tr('support_inquiry_err_rate'),
        SupportInquiryOutcome.network => context.tr('support_inquiry_err_network'),
        _ => context.trArgs('support_inquiry_err_unavailable', {'email': widget.developerEmail}),
      };
    });
  }

  void _copyDiagnostics() {
    final text = _controller.text.trim();
    Clipboard.setData(ClipboardData(
      text: widget.diagnostics(text.isEmpty ? widget.initialMessage : text),
    ));
    AppSnackBar.showSuccess(
      context,
      context.tr('support_diag_copied'),
      title: context.tr('set_copied'),
      icon: Icons.copy_rounded,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: context.borderColor),
      ),
      title: Row(
        children: [
          const Icon(Icons.mail_rounded, color: AppThemes.success, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Text(context.tr('support_inquiry_title'),
                style: GoogleFonts.outfit(
                    color: context.textPrimary, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('support_inquiry_desc'),
              style: GoogleFonts.outfit(color: context.textSecondary, fontSize: 12.5),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('support-inquiry-message'),
              controller: _controller,
              enabled: !_sending,
              minLines: 4,
              maxLines: 8,
              maxLength: SupportApiClient.maxInquiryLength,
              textInputAction: TextInputAction.newline,
              style: GoogleFonts.outfit(color: context.textPrimary, fontSize: 13.5),
              decoration: InputDecoration(
                hintText: context.tr('support_inquiry_hint'),
                filled: true,
                fillColor: context.subtleCardBg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: context.borderColor),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 4),
              Semantics(
                liveRegion: true,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: context.dangerColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: context.dangerColor.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    _error!,
                    style: GoogleFonts.outfit(
                        color: context.textPrimary, fontSize: 12.5, height: 1.4),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (_offerFallback)
          TextButton(
            onPressed: _copyDiagnostics,
            child: Text(context.tr('support_copy_diag'),
                style: TextStyle(color: context.successText)),
          ),
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(),
          child: Text(context.tr('cancel'),
              style: TextStyle(color: context.textSecondary)),
        ),
        ElevatedButton.icon(
          key: const ValueKey('support-inquiry-send'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppThemes.success,
            foregroundColor: Colors.black,
          ),
          onPressed: _sending ? null : _send,
          icon: _sending
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                )
              : const Icon(Icons.send_rounded, size: 16),
          label: Text(
            _sending ? context.tr('support_inquiry_sending') : context.tr('support_inquiry_send'),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
