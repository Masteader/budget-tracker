import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../main.dart';
import '../../providers/budget_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../services/api_service.dart';
import '../../services/offline_sync_service.dart';
import '../../widgets/chat/chat_message_bubble.dart';
import '../../widgets/chat/voice_listening_banner.dart';
import '../../widgets/app_snackbar.dart';

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

    final micStatus = await Permission.microphone.status;
    if (!micStatus.isGranted) {
      final requested = await Permission.microphone.request();
      if (!requested.isGranted) {
        if (requested.isPermanentlyDenied && mounted) {
          _showMicrophonePermissionDialog();
        } else if (mounted) {
          AppSnackBar.showWarning(
            context,
            'Microphone permission required for voice entry.',
            title: 'Permission Required',
          );
        }
        return;
      }
    }

    if (!_speechAvailable) {
      await _initSpeech();
      if (!_speechAvailable && mounted) {
        AppSnackBar.showInfo(
          context,
          'Speech recognition is initializing or not available on device.',
          title: 'Speech Recognition',
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

  void _refreshGlobalProviders() {
    if (!mounted) return;
    try {
      context.read<TransactionProvider>().refresh();
      context.read<BudgetProvider>().refresh();
    } catch (_) {}
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
              'spent_by': res['spent_by'] ?? 'both',
              'source': 'chat',
            },
          ),
        );
        _refreshGlobalProviders();
      } else {
        // Check for offline network error and save to SQLite queue
        final errText = res['message']?.toString() ?? '';
        if (errText.contains('connect') ||
            errText.contains('offline') ||
            errText.contains('SocketException') ||
            errText.contains('timeout')) {
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
        _refreshGlobalProviders();
      } else {
        AppSnackBar.showError(
          context,
          res['message'] ?? 'Failed to save transaction.',
          title: 'Save Error',
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
        titleSpacing: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome, color: Color(0xFF00C896), size: 18),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'AI Transaction Chat',
                style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 15),
                overflow: TextOverflow.ellipsis,
              ),
            ),
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
                  onTap: () => setState(() => _selectedLocale = 'ar_SA'),
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
                  onTap: () => setState(() => _selectedLocale = 'en_US'),
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
                GestureDetector(
                  onTap: () => setState(() => _selectedLocale = 'ur_PK'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _selectedLocale == 'ur_PK' ? const Color(0xFF00C896) : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      '🇵🇰 اردو',
                      style: TextStyle(
                        color: _selectedLocale == 'ur_PK' ? Colors.black : const Color(0xFF8B949E),
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
                  return ChatMessageBubble(
                    message: msg,
                    onConfirmPending: (store, spentBy) {
                      _confirmPendingExpense(msg, store, spentBy);
                    },
                    onCancelPending: () {
                      setState(() {
                        _messages.remove(msg);
                      });
                    },
                    onEnrichCandidate: (candidateId) {
                      _sendMessage("", enrichTxId: candidateId);
                    },
                    onLogAsNewCandidate: (originalMsg) {
                      _sendMessage(originalMsg, allowDuplicate: true, previewOnly: true);
                    },
                    onDiscardCandidate: () {
                      setState(() {
                        _messages.remove(msg);
                        _messages.add(
                          ChatMessage(
                            isUser: false,
                            text: 'Duplicate expense discarded.',
                          ),
                        );
                      });
                    },
                  );
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
            VoiceListeningBanner(
              isListening: _isListening,
              soundLevel: _soundLevel,
              selectedLocale: _selectedLocale,
              onToggleListening: _toggleListening,
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
}
