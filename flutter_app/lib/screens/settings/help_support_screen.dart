import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/api_service.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/onboarding/user_guide_walkthrough_dialog.dart';

class HelpSupportScreen extends StatefulWidget {
  final String? householdId;
  final String? userEmail;

  const HelpSupportScreen({
    super.key,
    this.householdId,
    this.userEmail,
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

  final List<_SupportMessage> _messages = [
    const _SupportMessage(
      isUser: false,
      text:
          'مرحباً بك في مركز المساعدة والدعم الذكي! 👋\nأنا مساعدك التقني، كيف أقدر أساعدك اليوم في إدارة الميزانية، دورة الرواتب، أو مسح الفواتير؟',
    ),
  ];

  static const String developerEmail = 'fmscoinfo@fmsco.com.sa';

  final List<_FaqCategory> _faqCategories = const [
    _FaqCategory(
      title: 'Salary Cycle & Payday (27th)',
      icon: Icons.calendar_month_rounded,
      color: Color(0xFFF59E0B),
      faqs: [
        _FaqItem(
          question: 'How does the salary cycle work in this app?',
          answer:
              'The budget cycle is automatically synced with the standard Saudi 27th payday. A monthly cycle starts on the 27th and concludes on the 26th of the following month, preventing mid-month budget misalignment.',
        ),
        _FaqItem(
          question: 'What happens to unspent funds at the end of the cycle?',
          answer:
              'Any unspent discretionary funds automatically roll over into the next cycle as surplus carryover or can be credited towards household savings reserves.',
        ),
        _FaqItem(
          question: 'How is the daily allowance pacing calculated?',
          answer:
              'Your remaining discretionary budget is divided by the exact number of days remaining until the 27th, providing a safe daily spending limit.',
        ),
      ],
    ),
    _FaqCategory(
      title: 'Receipt & ZATCA Scanning',
      icon: Icons.qr_code_scanner_rounded,
      color: Color(0xFF00C896),
      faqs: [
        _FaqItem(
          question: 'How do I scan printed paper receipts?',
          answer:
              'Tap the green camera scanner button. You can capture multiple receipt pages or pick an invoice image from your photo gallery. Our Gemini Vision model automatically extracts line items, VAT, and merchant details.',
        ),
        _FaqItem(
          question: 'How does Saudi ZATCA QR code verification work?',
          answer:
              'Our scanner decodes official Saudi ZATCA Base64 TLV barcodes in real time to verify seller tax identification, invoice timestamps, VAT amounts, and total values.',
        ),
        _FaqItem(
          question: 'What happens when a duplicate invoice is scanned?',
          answer:
              'If an invoice matches an existing transaction, you will see a Duplicate Defense card allowing you to Enrich the existing transaction, Log as a separate expense, or Discard.',
        ),
      ],
    ),
    _FaqCategory(
      title: 'Recurring Bills & Iqama Reserves',
      icon: Icons.receipt_long_rounded,
      color: Color(0xFF3B82F6),
      faqs: [
        _FaqItem(
          question: 'How do I add recurring bills (Rent, Utilities, Fiber)?',
          answer:
              'In the Dashboard Recurring Bills card, tap "Manage Bills" to toggle any sub-budget as recurring and configure its monthly due day.',
        ),
        _FaqItem(
          question: 'Where is the 400 SAR monthly Iqama fee tracked?',
          answer:
              'The 400 SAR Iqama fee is tracked under the Government (OPEX-GOV) category as a dedicated sub-budget reserve, protecting your essential funds from being spent on general shopping.',
        ),
        _FaqItem(
          question: 'How do I mark a recurring bill as paid?',
          answer:
              'Tap the green "Pay" button directly on any pending bill in the Dashboard card to record payment and adjust your reserved funds.',
        ),
      ],
    ),
    _FaqCategory(
      title: 'BNPL Installment Plans',
      icon: Icons.credit_card_rounded,
      color: Color(0xFF8B5CF6),
      faqs: [
        _FaqItem(
          question: 'How do Tabby and Tamara installment plans work?',
          answer:
              'When you log a BNPL purchase, you can view remaining installment payments, due dates, and total payoff progress directly on your dashboard card.',
        ),
      ],
    ),
    _FaqCategory(
      title: 'Household & 2D Partner Split',
      icon: Icons.people_alt_rounded,
      color: Color(0xFF10B981),
      faqs: [
        _FaqItem(
          question: 'How does 2-Dimensional expense attribution work?',
          answer:
              'For every expense, you can track who paid (paid_by: me or partner) and who it was for (beneficiary: me, partner, or both). The app calculates the exact net settlement owed at the end of each cycle.',
        ),
        _FaqItem(
          question: 'How do I invite my partner to my household?',
          answer:
              'Go to Settings -> Household & Membership and copy your unique 6-character Household Invite Code. Your partner can enter it upon signing up.',
        ),
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
      );

      final reply = res['reply'] as String? ??
          'تم استلام استفسارك! للمساعدة الإضافية يرجى التواصل مع المطور.';
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
          _messages.add(const _SupportMessage(
            isUser: false,
            text:
                'تعذر الاتصال بخادم الدعم حالياً. يمكنك نسخ بريد المطور أدناه للتواصل المباشر.',
            isEscalation: true,
            escalationSummary: 'Network error contacting support agent',
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

  void _contactDeveloper(String issueSummary) {
    final emailText = '''To: $developerEmail
Subject: [Budget Tracker Support] $issueSummary

Issue details:
$issueSummary

App: Budget Tracker (v1.0.0+1)
Household: ${widget.householdId ?? "N/A"}
User: ${widget.userEmail ?? "N/A"}
''';

    Clipboard.setData(ClipboardData(text: developerEmail));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF30363D)),
        ),
        title: Row(
          children: [
            const Icon(Icons.mail_rounded, color: Color(0xFF00C896), size: 24),
            const SizedBox(width: 10),
            Text('Contact Developer',
                style: GoogleFonts.outfit(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Developer email address copied to clipboard:',
              style: GoogleFonts.outfit(
                  color: const Color(0xFF8B949E), fontSize: 13),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF0D1117),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF30363D)),
              ),
              child: SelectableText(
                developerEmail,
                style: GoogleFonts.outfit(
                    color: const Color(0xFF00C896),
                    fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Please send an email from your preferred mail client. Your diagnostics information has been prepared.',
              style: GoogleFonts.outfit(
                  color: const Color(0xFF8B949E), fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: emailText));
              Navigator.pop(ctx);
              AppSnackBar.showSuccess(
                context,
                'Support email & diagnostic info copied to clipboard',
                title: 'Copied',
                icon: Icons.copy_rounded,
              );
            },
            child: const Text('Copy Full Diagnostic Info',
                style: TextStyle(color: Color(0xFF00C896))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00C896),
              foregroundColor: Colors.black,
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        elevation: 0,
        title: Text(
          'Help & Support',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.play_circle_outline_rounded,
                color: Color(0xFF00C896)),
            tooltip: 'Replay App Guide',
            onPressed: () => UserGuideWalkthroughDialog.show(context),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF00C896),
          indicatorWeight: 3,
          labelColor: const Color(0xFF00C896),
          unselectedLabelColor: const Color(0xFF8B949E),
          labelStyle:
              GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: const [
            Tab(icon: Icon(Icons.menu_book_rounded), text: 'FAQs & Guide'),
            Tab(icon: Icon(Icons.smart_toy_rounded), text: 'AI Assistant'),
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

  Widget _buildFaqTab() {
    final query = _faqQuery.toLowerCase();
    final filteredCategories = _faqCategories.map((cat) {
      final matchingFaqs = cat.faqs.where((f) {
        return f.question.toLowerCase().contains(query) ||
            f.answer.toLowerCase().contains(query) ||
            cat.title.toLowerCase().contains(query);
      }).toList();
      return _FaqCategory(
        title: cat.title,
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
            gradient: const LinearGradient(
              colors: [Color(0xFF161B22), Color(0xFF1F242C)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF30363D)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF00C896).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.explore_rounded,
                    color: Color(0xFF00C896), size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Interactive Feature Walkthrough',
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Replay the 5-step visual guide to learn about scanners, bills, and salary cycles.',
                      style: GoogleFonts.outfit(
                        color: const Color(0xFF8B949E),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00C896),
                  foregroundColor: Colors.black,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () => UserGuideWalkthroughDialog.show(context),
                child: const Text('Replay',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Search Bar
        TextField(
          controller: _faqSearchController,
          onChanged: (v) => setState(() => _faqQuery = v),
          style: GoogleFonts.outfit(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Search help topics and guides...',
            hintStyle:
                GoogleFonts.outfit(color: const Color(0xFF8B949E), fontSize: 13),
            prefixIcon:
                const Icon(Icons.search_rounded, color: Color(0xFF8B949E)),
            suffixIcon: _faqQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear_rounded,
                        color: Color(0xFF8B949E)),
                    onPressed: () {
                      _faqSearchController.clear();
                      setState(() => _faqQuery = '');
                    },
                  )
                : null,
            filled: true,
            fillColor: const Color(0xFF161B22),
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF30363D)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF00C896)),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Categories List
        ...filteredCategories.map((cat) {
          return Card(
            color: const Color(0xFF161B22),
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: Color(0xFF30363D)),
            ),
            child: Theme(
              data:
                  Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                leading: Icon(cat.icon, color: cat.color, size: 22),
                title: Text(
                  cat.title,
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                children: cat.faqs.map((faq) {
                  return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: const BoxDecoration(
                      border: Border(
                        top: BorderSide(color: Color(0xFF21262D)),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          faq.question,
                          style: GoogleFonts.outfit(
                            color: const Color(0xFF00C896),
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          faq.answer,
                          style: GoogleFonts.outfit(
                            color: const Color(0xFF8B949E),
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
            color: const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF30363D)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.mail_outline_rounded,
                      color: Color(0xFF00C896), size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Direct Developer Support',
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Have a custom question, feature request, or encountered a defect? Reach out to the developer directly.',
                style: GoogleFonts.outfit(
                  color: const Color(0xFF8B949E),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF00C896),
                    side: const BorderSide(color: Color(0xFF00C896)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.send_rounded, size: 16),
                  label: Text('Email $developerEmail',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                  onPressed: () => _contactDeveloper('General Developer Inquiry'),
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
      'How does the 27th salary cycle work?',
      'How to add 400 SAR Iqama fee?',
      'How to scan a ZATCA QR code?',
      'How do I split expenses with my partner?',
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
                backgroundColor: const Color(0xFF161B22),
                side: const BorderSide(color: Color(0xFF30363D)),
                label: Text(
                  quickChips[idx],
                  style: GoogleFonts.outfit(
                    color: const Color(0xFF00C896),
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
                          ? const Color(0xFF00C896)
                          : const Color(0xFF161B22),
                      borderRadius: BorderRadius.circular(14),
                      border: msg.isUser
                          ? null
                          : Border.all(color: const Color(0xFF30363D)),
                    ),
                    child: Text(
                      msg.text,
                      style: GoogleFonts.outfit(
                        color: msg.isUser ? Colors.black : Colors.white,
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
                        color: const Color(0xFF1F242C),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF00C896)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.engineering_rounded,
                                  color: Color(0xFF00C896), size: 18),
                              const SizedBox(width: 6),
                              Text(
                                'Escalate to Developer',
                                style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Detected technical query or bug. Tap below to send this directly to the developer email.',
                            style: GoogleFonts.outfit(
                              color: const Color(0xFF8B949E),
                              fontSize: 11.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF00C896),
                                foregroundColor: Colors.black,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              icon: const Icon(Icons.email_rounded, size: 14),
                              label: Text(
                                'Send Email to $developerEmail',
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
                    color: Color(0xFF00C896),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Thinking...',
                  style: GoogleFonts.outfit(
                      color: const Color(0xFF8B949E), fontSize: 12),
                ),
              ],
            ),
          ),

        // Chat Input Bar
        Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          decoration: const BoxDecoration(
            color: Color(0xFF161B22),
            border: Border(top: BorderSide(color: Color(0xFF30363D))),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _chatController,
                  style: GoogleFonts.outfit(color: Colors.white, fontSize: 13.5),
                  decoration: InputDecoration(
                    hintText: 'Ask anything about Budget Tracker...',
                    hintStyle: GoogleFonts.outfit(
                        color: const Color(0xFF8B949E), fontSize: 12.5),
                    filled: true,
                    fillColor: const Color(0xFF0D1117),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF30363D)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF30363D)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF00C896)),
                    ),
                  ),
                  onSubmitted: (_) => _sendSupportQuery(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFF00C896),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
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
  final String title;
  final IconData icon;
  final Color color;
  final List<_FaqItem> faqs;

  const _FaqCategory({
    required this.title,
    required this.icon,
    required this.color,
    required this.faqs,
  });
}

class _FaqItem {
  final String question;
  final String answer;

  const _FaqItem({
    required this.question,
    required this.answer,
  });
}
