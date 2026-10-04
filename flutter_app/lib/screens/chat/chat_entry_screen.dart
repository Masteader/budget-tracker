import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../main.dart';
import '../../services/api_service.dart';
import '../../widgets/transaction_item_breakdown_card.dart';

import '../../services/offline_sync_service.dart';

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

  // Speech-to-text state
  late final stt.SpeechToText _speech;
  bool _speechAvailable = false;
  bool _isListening = false;
  String _selectedLocale = 'ar_SA'; // 'ar_SA' (Saudi Arabic) or 'en_US' (English)
  double _soundLevel = 0.0;

  final List<String> _quickChips = [
    "Can I buy a 1200 SAR iPad?",
    "أقدر اشتري ايباد بـ 1200 ريال؟",
    "Dunkin 19 SAR: 16 latte, 3 donut",
    "Danube 145 SAR: 2 milk 20, chicken 125",
    "فاتورة بنده 85 ريال: حليب 15 ودجاج 45 وجبنة 25",
    "Albaik 28 SAR combo meal",
    "Aramco 50 SAR 91 fuel",
  ];

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _initSpeech();
    _fetchHousehold();
    _messages.add(
      ChatMessage(
        isUser: false,
        text: "👋 Hi! You can speak or type your expenses in English or Arabic.\n"
            "Tap the 🎙️ mic button or try: 'فاتورة بنده 85 ريال: حليب 15 ودجاج 45 وجبنة 25' or 'Dunkin 19 SAR: 16 latte and 3 donut'",
      ),
    );
  }

  @override
  void dispose() {
    if (_isListening) {
      _speech.stop();
    }
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initSpeech() async {
    try {
      final available = await _speech.initialize(
        onStatus: (status) {
          if (mounted) {
            setState(() {
              if (status == 'notListening' || status == 'done') {
                _isListening = false;
              }
            });
          }
        },
        onError: (val) {
          if (mounted) {
            setState(() {
              _isListening = false;
            });
            debugPrint("SpeechToText onError: ${val.errorMsg}");
          }
        },
      );
      if (mounted) {
        setState(() {
          _speechAvailable = available;
        });
      }
    } catch (e) {
      debugPrint("Speech init exception: $e");
    }
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _speech.stop();
      if (mounted) {
        setState(() => _isListening = false);
      }
      return;
    }

    // Check microphone permission
    final micStatus = await Permission.microphone.status;
    if (!micStatus.isGranted) {
      final requested = await Permission.microphone.request();
      if (!requested.isGranted) {
        if (requested.isPermanentlyDenied && mounted) {
          _showMicrophonePermissionDialog();
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Microphone permission required for voice entry.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }
    }

    if (!_speechAvailable) {
      await _initSpeech();
      if (!_speechAvailable && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Speech recognition is initializing or not available on device.'),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }
    }

    final initialText = _controller.text.trim();
    setState(() {
      _isListening = true;
    });

    try {
      final options = stt.SpeechListenOptions(
        localeId: _selectedLocale,
        listenMode: stt.ListenMode.dictation,
        pauseFor: const Duration(seconds: 4),
        partialResults: true,
        cancelOnError: false,
      );

      await _speech.listen(
        listenOptions: options,
        onResult: (result) {
          if (mounted) {
            setState(() {
              final words = result.recognizedWords;
              if (initialText.isEmpty) {
                _controller.text = words;
              } else {
                _controller.text = '$initialText $words';
              }
              _controller.selection = TextSelection.fromPosition(
                TextPosition(offset: _controller.text.length),
              );
            });
          }
        },
        onSoundLevelChange: (level) {
          if (mounted) {
            setState(() {
              _soundLevel = level;
            });
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isListening = false);
      }
    }
  }

  void _showMicrophonePermissionDialog() {
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
            const Icon(Icons.mic_off, color: Colors.orange, size: 22),
            const SizedBox(width: 8),
            Text(
              'Microphone Permission',
              style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        content: const Text(
          'Microphone access is required to speak your invoice items into the chat. Please tap "Open Settings" to enable Microphone access.',
          style: TextStyle(color: Color(0xFF8B949E), fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF8B949E))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00C896),
              foregroundColor: Colors.black,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
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

  Future<void> _sendMessage(
    String text, {
    bool allowDuplicate = false,
    String? enrichTxId,
    bool previewOnly = true,
  }) async {
    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
    }

    final message = text.trim();
    if (message.isEmpty && enrichTxId == null) return;
    if (_householdId == null) return;

    if (enrichTxId == null) {
      if (message.isNotEmpty && !allowDuplicate) {
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
    } else {
      setState(() {
        _isLoading = true;
      });
    }

    final isPreview = (enrichTxId == null && previewOnly);
    final user = supabase.auth.currentUser;
    final res = await ApiService.instance.postChatTransaction(
      message: message,
      householdId: _householdId!,
      userId: user?.id,
      allowDuplicate: allowDuplicate,
      enrichTxId: enrichTxId,
      previewOnly: isPreview,
    );

    setState(() {
      _isLoading = false;
      final status = res['status'] as String? ?? 'error';

      if (status == 'simulation') {
        _messages.add(
          ChatMessage(
            isUser: false,
            text: res['message'] ?? 'Affordability simulation complete.',
            simulationData: res,
          ),
        );
      } else if (status == 'pending_confirmation') {
        _messages.add(
          ChatMessage(
            isUser: false,
            text: res['message'] ?? 'Please confirm the store name and who spent it before adding:',
            isPendingConfirmation: true,
            pendingData: res,
          ),
        );
      } else if (status == 'duplicate_candidate') {
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
        // Check for offline network error and save to SQLite queue
        final errText = res['message']?.toString() ?? '';
        if (errText.contains('connect') || errText.contains('offline') || errText.contains('SocketException') || errText.contains('timeout')) {
          OfflineSyncService.instance.enqueue(
            endpoint: 'chat',
            payload: {'message': message, 'user_id': user?.id},
            householdId: _householdId!,
          );
          _messages.add(
            ChatMessage(
              isUser: false,
              text: '📶 Offline: Stored in local SQLite queue. Will sync automatically when network returns.',
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
      }
    });

    _scrollToBottom();
  }

  Future<void> _confirmPendingExpense(ChatMessage originalMsg, String merchant, String spentBy) async {
    final pending = originalMsg.pendingData;
    if (pending == null || _householdId == null) return;

    setState(() => _isLoading = true);

    final user = supabase.auth.currentUser;
    final originalText = pending['original_message'] as String? ??
        "$merchant ${(pending['amount'] as num?)?.toStringAsFixed(2) ?? '0.00'} SAR";

    final res = await ApiService.instance.postChatTransaction(
      message: originalText,
      householdId: _householdId!,
      userId: user?.id,
      allowDuplicate: true,
      previewOnly: false,
      merchant: merchant.trim().isNotEmpty ? merchant.trim() : null,
      spentBy: spentBy,
    );

    setState(() {
      _isLoading = false;
      final status = res['status'] as String? ?? 'error';
      if (status == 'success' || status == 'enriched') {
        final parsedItems = (res['items'] as List?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ??
            [];

        final idx = _messages.indexOf(originalMsg);
        final confirmedMsg = ChatMessage(
          isUser: false,
          text: res['message'] ?? 'Transaction recorded successfully!',
          transactionData: {
            'merchant': res['merchant'] ?? merchant,
            'amount': (res['amount'] as num?)?.toDouble() ?? (pending['amount'] as num?)?.toDouble() ?? 0.0,
            'category_code': res['category_code'] ?? pending['category_code'],
            'items': parsedItems.isNotEmpty ? parsedItems : (pending['items'] as List? ?? []),
            'is_reallocated': res['is_reallocated'] ?? false,
            'spent_by': res['spent_by'] ?? spentBy,
            'source': 'chat',
          },
        );

        if (idx != -1) {
          _messages[idx] = confirmedMsg;
        } else {
          _messages.add(confirmedMsg);
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['message'] ?? 'Failed to save transaction.'),
            backgroundColor: Colors.redAccent,
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
            Text('AI Transaction Chat', style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 17)),
          ],
        ),
        actions: [
          // Language selector toggle pill
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: const Color(0xFF21262D),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF30363D)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () {
                    setState(() => _selectedLocale = 'ar_SA');
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _selectedLocale == 'ar_SA' ? const Color(0xFF00C896) : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      '🇸🇦 ع',
                      style: TextStyle(
                        color: _selectedLocale == 'ar_SA' ? Colors.black : const Color(0xFF8B949E),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    setState(() => _selectedLocale = 'en_US');
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _selectedLocale == 'en_US' ? const Color(0xFF00C896) : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      '🇺🇸 EN',
                      style: TextStyle(
                        color: _selectedLocale == 'en_US' ? Colors.black : const Color(0xFF8B949E),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
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
            // Live Listening Banner
            if (_isListening)
              Container(
                margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 10 + (_soundLevel.clamp(0.0, 10.0) * 0.8),
                      height: 10 + (_soundLevel.clamp(0.0, 10.0) * 0.8),
                      decoration: const BoxDecoration(
                        color: Colors.redAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _selectedLocale == 'ar_SA'
                            ? "🎙️ جاري الاستماع باللغة العربية... تحدث الآن"
                            : "🎙️ Listening in English... Speak your items",
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ),
                    InkWell(
                      onTap: _toggleListening,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00C896),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'Done',
                          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                    ),
                  ],
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
                        hintText: _selectedLocale == 'ar_SA'
                            ? "تحدث أو اكتب: بنده 85 ريال حليب 15..."
                            : "Speak or type: Dunkin 19 SAR...",
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
                  // Animated Microphone Button
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      color: _isListening ? Colors.redAccent : const Color(0xFF21262D),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _isListening ? Colors.red : const Color(0xFF30363D),
                        width: 1.5,
                      ),
                      boxShadow: _isListening
                          ? [
                              BoxShadow(
                                color: Colors.redAccent.withValues(alpha: 0.5),
                                blurRadius: 10,
                                spreadRadius: 2,
                              ),
                            ]
                          : null,
                    ),
                    child: IconButton(
                      icon: Icon(
                        _isListening ? Icons.mic : Icons.mic_none_rounded,
                        color: _isListening ? Colors.white : const Color(0xFF00C896),
                        size: 20,
                      ),
                      tooltip: _isListening ? 'Stop Listening' : 'Voice Input',
                      onPressed: _toggleListening,
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Send Button
                  Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFF00C896),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.send_rounded, color: Colors.black, size: 20),
                      tooltip: 'Send',
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
            if (msg.simulationData != null) ...[
              const SizedBox(height: 6),
              _buildSimulationCard(msg.simulationData!),
            ],
            if (msg.isPendingConfirmation && msg.pendingData != null) ...[
              const SizedBox(height: 8),
              PendingExpenseConfirmationCard(
                pendingData: msg.pendingData!,
                onConfirm: (confirmedMerchant, confirmedSpentBy) {
                  _confirmPendingExpense(msg, confirmedMerchant, confirmedSpentBy);
                },
                onCancel: () {
                  setState(() {
                    _messages.remove(msg);
                  });
                },
              ),
            ],
            if (msg.transactionData != null) ...[
              const SizedBox(height: 6),
              TransactionItemBreakdownCard(
                merchant: msg.transactionData!['merchant'] as String,
                amount: msg.transactionData!['amount'] as double,
                categoryCode: msg.transactionData!['category_code'] as String?,
                source: 'chat',
                spentBy: (msg.transactionData!['spent_by'] as String?) ?? 'me',
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

  Widget _buildSimulationCard(Map<String, dynamic> sim) {
    final verdict = sim['verdict'] as String? ?? 'comfortable';
    final targetAmt = (sim['amount'] as num?)?.toDouble() ?? 0.0;
    final item = sim['merchant'] as String? ?? 'Item';
    final daysToPayday = sim['days_to_payday'] as int? ?? 0;
    final dailyCurrent = (sim['current_daily_allowance'] as num?)?.toDouble() ?? 0.0;
    final dailyPost = (sim['post_purchase_daily_allowance'] as num?)?.toDouble() ?? 0.0;

    Color badgeColor = const Color(0xFF00C896);
    IconData badgeIcon = Icons.check_circle_outline_rounded;
    String verdictLabel = "Comfortably Affordable";

    if (verdict == 'caution') {
      badgeColor = Colors.orange;
      badgeIcon = Icons.warning_amber_rounded;
      verdictLabel = "Caution (Reallocation Needed)";
    } else if (verdict == 'unaffordable' || verdict == 'not_recommended') {
      badgeColor = Colors.redAccent;
      badgeIcon = Icons.cancel_outlined;
      verdictLabel = "Unaffordable / Exceeds Budget";
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: badgeColor.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(badgeIcon, color: badgeColor, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Purchase Simulator',
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  verdictLabel,
                  style: TextStyle(
                    color: badgeColor,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '$item • SAR ${targetAmt.toStringAsFixed(2)}',
            style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Days to 27th Payday: $daysToPayday days away',
            style: const TextStyle(color: Color(0xFF8B949E), fontSize: 12),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF0D1117),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      const Text(
                        'Daily Allowance Now',
                        style: TextStyle(color: Color(0xFF8B949E), fontSize: 10),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'SAR ${dailyCurrent.toStringAsFixed(1)}/d',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(Icons.arrow_forward_rounded, color: Color(0xFF8B949E), size: 14),
                ),
                Expanded(
                  child: Column(
                    children: [
                      const Text(
                        'After Purchase',
                        style: TextStyle(color: Color(0xFF8B949E), fontSize: 10),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'SAR ${dailyPost.toStringAsFixed(1)}/d',
                        style: TextStyle(color: badgeColor, fontWeight: FontWeight.bold, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
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
        border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
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
                    _sendMessage(originalMsg, allowDuplicate: true, previewOnly: true);
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

class PendingExpenseConfirmationCard extends StatefulWidget {
  final Map<String, dynamic> pendingData;
  final void Function(String confirmedMerchant, String confirmedSpentBy) onConfirm;
  final VoidCallback onCancel;

  const PendingExpenseConfirmationCard({
    super.key,
    required this.pendingData,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  State<PendingExpenseConfirmationCard> createState() => _PendingExpenseConfirmationCardState();
}

class _PendingExpenseConfirmationCardState extends State<PendingExpenseConfirmationCard> {
  late final TextEditingController _merchantController;
  late String _selectedSpentBy;

  @override
  void initState() {
    super.initState();
    final defaultMerchant = widget.pendingData['merchant'] as String? ?? 'Store Name';
    _merchantController = TextEditingController(text: defaultMerchant);
    _selectedSpentBy = (widget.pendingData['spent_by'] as String? ?? 'both').toLowerCase();
    if (!['me', 'partner', 'both'].contains(_selectedSpentBy)) {
      _selectedSpentBy = 'both';
    }
  }

  @override
  void dispose() {
    _merchantController.dispose();
    super.dispose();
  }

  Widget _buildSpentByOption(String key, String title, IconData icon, Color activeColor) {
    final isSelected = _selectedSpentBy == key;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedSpentBy = key),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? activeColor.withValues(alpha: 0.18) : const Color(0xFF0D1117),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? activeColor : const Color(0xFF30363D),
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: isSelected ? activeColor : const Color(0xFF8B949E)),
              const SizedBox(height: 3),
              Text(
                title,
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? Colors.white : const Color(0xFF8B949E),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final amount = (widget.pendingData['amount'] as num?)?.toDouble() ?? 0.0;
    final rawItems = widget.pendingData['items'] as List?;
    final items = rawItems != null
        ? rawItems.map((e) => Map<String, dynamic>.from(e as Map)).toList()
        : <Map<String, dynamic>>[];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF00C896).withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.edit_note_rounded, color: Color(0xFF00C896), size: 18),
                  const SizedBox(width: 6),
                  Text(
                    'Confirm Expense Details',
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF00C896).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'SAR ${amount.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Color(0xFF00C896),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Store Name field
          TextField(
            controller: _merchantController,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              labelText: 'Store Name / Merchant',
              labelStyle: const TextStyle(color: Color(0xFF8B949E), fontSize: 11),
              prefixIcon: const Icon(Icons.storefront_outlined, color: Color(0xFF00C896), size: 18),
              filled: true,
              fillColor: const Color(0xFF0D1117),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF30363D))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF30363D))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF00C896))),
            ),
          ),
          const SizedBox(height: 12),

          // Items Preview (if any)
          if (items.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF0D1117),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF21262D)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${items.length} item(s) found:',
                    style: const TextStyle(color: Color(0xFF8B949E), fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  ...items.map((it) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${it['quantity']}x ${it['name']}',
                              style: const TextStyle(color: Colors.white, fontSize: 12),
                            ),
                            Text(
                              'SAR ${(it['price'] as num?)?.toStringAsFixed(2) ?? '0.00'}',
                              style: const TextStyle(color: Color(0xFF00C896), fontSize: 11),
                            ),
                          ],
                        ),
                      )),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Spent By selector
          Text(
            'SPENT BY WHO?',
            style: GoogleFonts.outfit(fontSize: 10, letterSpacing: 0.8, fontWeight: FontWeight.w600, color: const Color(0xFF8B949E)),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _buildSpentByOption('me', 'Me', Icons.person_outline, const Color(0xFF58A6FF)),
              const SizedBox(width: 6),
              _buildSpentByOption('partner', 'Partner', Icons.favorite_outline, const Color(0xFFBC8CFF)),
              const SizedBox(width: 6),
              _buildSpentByOption('both', 'Both (Shared)', Icons.group_outlined, const Color(0xFF00C896)),
            ],
          ),
          const SizedBox(height: 14),

          // Confirm button
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00C896),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.check_circle_rounded, size: 16),
                  label: const Text('Confirm & Add Expense', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  onPressed: () {
                    final store = _merchantController.text.trim();
                    widget.onConfirm(store.isNotEmpty ? store : 'Store Name', _selectedSpentBy);
                  },
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: widget.onCancel,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF8B949E),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
                child: const Text('Cancel', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

