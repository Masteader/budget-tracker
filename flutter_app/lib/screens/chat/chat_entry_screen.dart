import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../main.dart';
import '../../services/api_service.dart';
import '../../widgets/transaction_item_breakdown_card.dart';

class ChatMessage {
  final bool isUser;
  final String text;
  final Map<String, dynamic>? transactionData;
  final bool isDuplicatePrompt;
  final Map<String, dynamic>? candidateData;

  ChatMessage({
    required this.isUser,
    required this.text,
    this.transactionData,
    this.isDuplicatePrompt = false,
    this.candidateData,
  });
}

class ChatEntryScreen extends StatefulWidget {
  const ChatEntryScreen({super.key});

  @override
  State<ChatEntryScreen> createState() => _ChatEntryScreenState();
}

class _ChatEntryScreenState extends State<ChatEntryScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _isLoading = false;
  String? _householdId;

  final List<String> _quickChips = [
    "Dunkin 19 SAR: 16 latte, 3 donut",
    "Danube 145 SAR: 2 milk 20, chicken 125",
    "Albaik 28 SAR combo meal",
    "Aramco 50 SAR 91 fuel",
  ];

  @override
  void initState() {
    super.initState();
    _fetchHousehold();
    _messages.add(
      ChatMessage(
        isUser: false,
        text: "👋 Hi! You can tell me what you spent in plain English or Arabic.\n"
            "Try: 'merchant dunkin and i spent 19 sar total, 16 ice latte and 3 donut'",
      ),
    );
  }

  Future<void> _fetchHousehold() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    try {
      final res = await supabase
          .from('users')
          .select('household_id')
          .eq('id', user.id)
          .single();
      setState(() {
        _householdId = res['household_id'] as String?;
      });
    } catch (_) {}
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage(String text, {bool allowDuplicate = false, String? enrichTxId}) async {
    final message = text.trim();
    if (message.isEmpty || _householdId == null) return;

    if (enrichTxId == null && !allowDuplicate) {
      setState(() {
        _messages.add(ChatMessage(isUser: true, text: message));
        _isLoading = true;
      });
      _controller.clear();
      _scrollToBottom();
    } else {
      setState(() {
        _isLoading = true;
      });
    }

    final user = supabase.auth.currentUser;
    final res = await ApiService.instance.postChatTransaction(
      message: message,
      householdId: _householdId!,
      userId: user?.id,
      allowDuplicate: allowDuplicate,
      enrichTxId: enrichTxId,
    );

    setState(() {
      _isLoading = false;
      final status = res['status'] as String? ?? 'error';

      if (status == 'duplicate_candidate') {
        _messages.add(
          ChatMessage(
            isUser: false,
            text: res['message'] ?? 'Recent matching transaction found.',
            isDuplicatePrompt: true,
            candidateData: res,
          ),
        );
      } else if (status == 'success' || status == 'enriched') {
        final parsedItems = (res['items'] as List?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ??
            [];

        _messages.add(
          ChatMessage(
            isUser: false,
            text: res['message'] ?? 'Transaction recorded successfully!',
            transactionData: {
              'merchant': res['merchant'] ?? 'Merchant',
              'amount': (res['amount'] as num?)?.toDouble() ?? 0.0,
              'category_code': res['category_code'],
              'items': parsedItems,
              'is_reallocated': res['is_reallocated'] ?? false,
              'source': 'chat',
            },
          ),
        );
      } else {
        _messages.add(
          ChatMessage(
            isUser: false,
            text: res['message'] ?? 'Could not parse transaction details.',
          ),
        );
      }
    });

    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.auto_awesome, color: Color(0xFF00C896), size: 20),
            const SizedBox(width: 8),
            Text('AI Transaction Chat', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
          ],
        ),
        backgroundColor: const Color(0xFF161B22),
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                itemCount: _messages.length,
                itemBuilder: (ctx, idx) {
                  final msg = _messages[idx];
                  if (msg.isUser) {
                    return _buildUserBubble(msg.text);
                  } else {
                    return _buildAssistantBubble(msg);
                  }
                },
              ),
            ),
            if (_isLoading)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00C896)),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      "Magic is happening...",
                      style: GoogleFonts.outfit(color: const Color(0xFF8B949E), fontSize: 13),
                    ),
                  ],
                ),
              ),
            // Quick suggestions chips
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _quickChips.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (ctx, i) {
                  return ActionChip(
                    backgroundColor: const Color(0xFF161B22),
                    side: const BorderSide(color: Color(0xFF30363D)),
                    label: Text(_quickChips[i], style: const TextStyle(fontSize: 12, color: Color(0xFFC9D1D9))),
                    onPressed: () => _sendMessage(_quickChips[i]),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            // Input bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: const BoxDecoration(
                color: Color(0xFF161B22),
                border: Border(top: BorderSide(color: Color(0xFF30363D))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (v) => _sendMessage(v),
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: "e.g. Dunkin 19 SAR, 16 latte 3 donut...",
                        hintStyle: const TextStyle(color: Color(0xFF8B949E), fontSize: 13),
                        filled: true,
                        fillColor: const Color(0xFF0D1117),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: const BorderSide(color: Color(0xFF30363D)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: const BorderSide(color: Color(0xFF30363D)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: const BorderSide(color: Color(0xFF00C896)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFF00C896),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.send_rounded, color: Colors.black, size: 20),
                      onPressed: () => _sendMessage(_controller.text),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserBubble(String text) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12, left: 40),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF1F6FEB),
          borderRadius: BorderRadius.circular(16).copyWith(bottomRight: Radius.zero),
        ),
        child: Text(
          text,
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
      ),
    );
  }

  Widget _buildAssistantBubble(ChatMessage msg) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12, right: 30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF161B22),
                borderRadius: BorderRadius.circular(16).copyWith(bottomLeft: Radius.zero),
                border: Border.all(color: const Color(0xFF30363D)),
              ),
              child: Text(
                msg.text,
                style: const TextStyle(color: Color(0xFFC9D1D9), fontSize: 14, height: 1.4),
              ),
            ),
            if (msg.transactionData != null) ...[
              const SizedBox(height: 6),
              TransactionItemBreakdownCard(
                merchant: msg.transactionData!['merchant'] as String,
                amount: msg.transactionData!['amount'] as double,
                categoryCode: msg.transactionData!['category_code'] as String?,
                source: 'chat',
                items: (msg.transactionData!['items'] as List)
                    .map((e) => Map<String, dynamic>.from(e as Map))
                    .toList(),
                isReallocated: msg.transactionData!['is_reallocated'] as bool? ?? false,
              ),
            ],
            if (msg.isDuplicatePrompt && msg.candidateData != null) ...[
              const SizedBox(height: 8),
              _buildDuplicateResolutionBar(msg.candidateData!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDuplicateResolutionBar(Map<String, dynamic> candidateData) {
    final candidateId = candidateData['candidate_transaction_id'] as String?;
    final parsed = candidateData['parsed_data'] as Map<String, dynamic>?;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF21262D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18),
              const SizedBox(width: 8),
              Text(
                'Duplicate Prevention Check',
                style: GoogleFonts.outfit(fontWeight: FontWeight.w600, color: Colors.orange, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00C896),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  icon: const Icon(Icons.attach_file, size: 16),
                  label: const Text('Enrich Existing SMS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  onPressed: () {
                    if (candidateId != null) {
                      _sendMessage("", enrichTxId: candidateId);
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFF8B949E)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  child: const Text('Log as New', style: TextStyle(fontSize: 12)),
                  onPressed: () {
                    final originalMsg = parsed != null
                        ? "${parsed['merchant']} ${parsed['amount']} SAR"
                        : "Expense";
                    _sendMessage(originalMsg, allowDuplicate: true);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
