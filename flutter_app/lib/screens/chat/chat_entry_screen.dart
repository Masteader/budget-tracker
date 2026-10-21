import 'package:flutter/material.dart';
import '../../theme/app_themes.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../main.dart';
import '../../providers/budget_provider.dart';
import '../../providers/recurring_bills_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../services/api/preview_token.dart';
import '../../services/api_service.dart';
import '../../services/nafaqah_write_errors.dart';
import '../../services/offline_sync_service.dart';
import '../../widgets/chat/chat_message_bubble.dart';
import '../../widgets/chat/pending_expense_confirmation_card.dart' show PendingExpenseEdits;
import '../../widgets/chat/voice_listening_banner.dart';
import '../../widgets/chat/voice_language_button.dart';
import '../../widgets/transactions/inactive_category_resolution_dialog.dart';
import '../../widgets/app_snackbar.dart';
import '../../l10n/app_localizations.dart';

/// Key under which a preview keeps the exact text it was parsed from.
const String _previewMessageKey = 'preview_message';

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

  /// Example messages in the app language only (UX-18).
  List<String> _quickChips(BuildContext context) => [for (final k in chatExampleKeys) context.tr(k)];

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _initSpeech();
    _fetchHousehold();
  }

  bool _welcomeAdded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_welcomeAdded) {
      _welcomeAdded = true;
      // Voice recognition and the welcome text follow the app language.
      final lang = Localizations.maybeLocaleOf(context)?.languageCode;
      _selectedLocale = lang == 'en' ? 'en_US' : (lang == 'ur' ? 'ur_PK' : 'ar_SA');
      _messages.add(ChatMessage(isUser: false, text: context.tr('chat_welcome')));
    }
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
            context.tr('chat_mic_required'),
            title: context.tr('chat_permission_required'),
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
          context.tr('chat_speech_unavailable'),
          title: context.tr('chat_speech_recognition'),
        );
        return;
      }
    }

    final initialText = _controller.text.trim();
    if (!mounted) return;
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
        backgroundColor: context.cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: context.borderColor),
        ),
        title: Row(
          children: [
            const Icon(Icons.mic_off, color: Colors.orange, size: 22),
            const SizedBox(width: 8),
            Text(
              context.tr('chat_mic_permission_title'),
              style: GoogleFonts.outfit(color: context.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        content: Text(
          context.tr('chat_mic_permission_desc'),
          style: TextStyle(color: context.textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.tr('cancel'), style: TextStyle(color: context.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppThemes.success,
              foregroundColor: Colors.black,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings();
            },
            child: Text(context.tr('open_settings')),
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
      if (!mounted) return;
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
      context.read<RecurringBillsProvider>().fetchBills();
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
      if (!mounted) return;
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

    if (!mounted) return;
    var queueOffline = false;
    setState(() {
      _isLoading = false;
      final status = res['status'] as String? ?? 'error';

      if (status == 'simulation') {
        _messages.add(
          ChatMessage(
            isUser: false,
            text: res['message'] ?? context.tr('chat_simulation_complete'),
            simulationData: res,
          ),
        );
      } else if (status == 'pending_confirmation') {
        // The commit must resend the previewed text with its preview_token.
        res[_previewMessageKey] = message;
        if (res['is_category_inactive'] == true) {
          final catCode = res['category_code']?.toString() ?? context.tr('category');
          final amt = (res['amount'] as num?)?.toDouble() ?? 0.0;
          final store = res['merchant']?.toString() ?? context.tr('merchant_generic');
          WidgetsBinding.instance.addPostFrameCallback((_) {
            InactiveCategoryResolutionDialog.show(
              context: context,
              categoryName: catCode,
              amount: amt,
              merchant: store,
              onReactivate: () async {
                if (_householdId != null) {
                  await ApiService.instance.toggleCategoryStatus(
                    householdId: _householdId!,
                    categoryCode: catCode,
                    isActive: true,
                  );
                }
              },
              onChangeCategory: () {
                res['category_code'] = 'OPEX-MISC';
              },
            );
          });
        }
        _messages.add(
          ChatMessage(
            isUser: false,
            text: res['message'] ?? context.tr('chat_confirm_before_adding'),
            isPendingConfirmation: true,
            pendingData: res,
          ),
        );
      } else if (status == 'duplicate_candidate') {
        _messages.add(
          ChatMessage(
            isUser: false,
            text: res['message'] ?? context.tr('chat_recent_match'),
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
            text: res['message'] ?? context.tr('chat_tx_recorded'),
            transactionData: {
              'merchant': res['merchant'] ?? context.tr('merchant_generic'),
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
          // Queued below; the reply depends on whether the write succeeded.
          queueOffline = true;
        } else {
          _messages.add(
            ChatMessage(
              isUser: false,
              text: res['message'] ?? context.tr('chat_parse_failed'),
            ),
          );
        }
      }
    });

    if (queueOffline) {
      // MOB-28: only claim "stored offline" when the queue write succeeded.
      String reply;
      try {
        await OfflineSyncService.instance.enqueue(
          endpoint: 'chat',
          payload: {'message': message, 'user_id': user?.id},
          householdId: _householdId!,
        );
        reply = mounted ? context.tr('chat_offline_queued') : '';
      } catch (e) {
        debugPrint('[ChatEntry] Offline queue write failed: $e');
        reply = mounted ? context.tr('offline_queue_failed') : '';
      }
      if (!mounted) return;
      setState(() => _messages.add(ChatMessage(isUser: false, text: reply)));
    }

    _scrollToBottom();
  }

  Future<void> _confirmPendingExpense(
    ChatMessage originalMsg,
    String merchant,
    String categoryCode,
    String? subCategory,
    String paidBy,
    String beneficiary,
    String? nafaqahClass,
    String? nafaqahSpouseId,
    PendingExpenseEdits edits,
  ) async {
    final pending = originalMsg.pendingData;
    if (pending == null || _householdId == null) return;

    setState(() => _isLoading = true);

    final user = supabase.auth.currentUser;
    final originalText = pending[_previewMessageKey] as String? ??
        pending['original_message'] as String? ??
        "$merchant ${(pending['amount'] as num?)?.toStringAsFixed(2) ?? '0.00'} SAR";

    final householdId = _householdId!;
    // The preview's token (when the server sends one) is returned unchanged;
    // an expired token re-runs the preview once (preview_token.dart).
    final res = await commitWithPreviewToken(
      token: previewTokenOf(pending),
      commit: (token) => ApiService.instance.postChatTransaction(
        message: originalText,
        householdId: householdId,
        userId: user?.id,
        allowDuplicate: true,
        previewOnly: false,
        merchant: merchant.trim().isNotEmpty ? merchant.trim() : null,
        spentBy: beneficiary == 'partner' ? 'partner' : (beneficiary == 'me' ? 'me' : 'both'),
        categoryCode: categoryCode,
        subCategory: subCategory,
        paidBy: paidBy,
        beneficiary: beneficiary,
        nafaqahClass: nafaqahClass,
        nafaqahSpouseId: nafaqahSpouseId,
        // The user's corrections travel with the token (UX-12).
        amount: edits.amount,
        occurredAt: edits.occurredAt,
        previewToken: token,
      ),
      rePreview: () => ApiService.instance.postChatTransaction(
        message: originalText,
        householdId: householdId,
        userId: user?.id,
        allowDuplicate: true,
        previewOnly: true,
      ),
    );

    if (!mounted) return;
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
          text: res['message'] ?? context.tr('chat_tx_recorded'),
          transactionData: {
            'merchant': res['merchant'] ?? merchant,
            'amount': (res['amount'] as num?)?.toDouble() ?? edits.amount ?? (pending['amount'] as num?)?.toDouble() ?? 0.0,
            'category_code': res['category_code'] ?? pending['category_code'],
            'items': parsedItems.isNotEmpty ? parsedItems : (pending['items'] as List? ?? []),
            'spent_by': res['spent_by'] ?? (beneficiary == 'partner' ? 'partner' : (beneficiary == 'me' ? 'me' : 'both')),
            'paid_by': res['paid_by'] ?? paidBy,
            'beneficiary': res['beneficiary'] ?? beneficiary,
            'sub_category': res['sub_category'] ?? subCategory,
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
          expenseApiErrorText(context, res) ?? res['message'] ?? context.tr('chat_save_failed'),
          title: context.tr('chat_save_error'),
        );
      }
    });

    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.scaffoldBg,
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome, color: AppThemes.success, size: 18),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                context.tr('chat_title'),
                style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 15),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          // The microphone's language (UX-19: one 48 dp control, not three 25 dp pills).
          VoiceLanguageButton(
            localeId: _selectedLocale,
            onChanged: (v) => setState(() => _selectedLocale = v),
          ),
        ],
        backgroundColor: context.cardBg,
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
                    onConfirmPending: (store, cat, subCat, paidBy, beneficiary, nafaqahClass, nafaqahSpouseId, edits) {
                      _confirmPendingExpense(msg, store, cat, subCat, paidBy, beneficiary, nafaqahClass, nafaqahSpouseId, edits);
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
                            text: context.tr('chat_duplicate_discarded'),
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
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppThemes.success),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      context.tr('chat_thinking'),
                      style: GoogleFonts.outfit(color: context.textSecondary, fontSize: 13),
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
                itemCount: chatExampleKeys.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (ctx, i) {
                  return ActionChip(
                    backgroundColor: context.cardBg,
                    side: BorderSide(color: context.borderColor),
                    label: Text(_quickChips(context)[i], style: TextStyle(fontSize: 13, color: context.textPrimary)),
                    onPressed: () => _sendMessage(_quickChips(context)[i]),
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
              decoration: BoxDecoration(
                color: context.cardBg,
                border: Border(top: BorderSide(color: context.borderColor)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (v) => _sendMessage(v),
                      style: TextStyle(color: context.textPrimary, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: AppLocalizations(Locale(_selectedLocale.substring(0, 2))).get('chat_input_hint'),
                        hintStyle: TextStyle(color: context.textSecondary, fontSize: 13),
                        filled: true,
                        fillColor: context.inputBg,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide(color: context.borderColor),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide(color: context.borderColor),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: const BorderSide(color: AppThemes.success),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Animated Microphone Button
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      color: _isListening ? Colors.redAccent : context.chipBg,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _isListening ? Colors.red : context.borderColor,
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
                        color: _isListening ? Colors.white : AppThemes.success,
                        size: 20,
                      ),
                      tooltip: _isListening ? context.tr('chat_stop_listening') : context.tr('chat_voice_input'),
                      onPressed: _toggleListening,
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Send Button
                  Container(
                    decoration: const BoxDecoration(
                      color: AppThemes.success,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.send_rounded, color: Colors.black, size: 20),
                      tooltip: context.tr('support_send'),
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
