import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../supabase_config.dart';

/// Standalone diagnostic application displayed when the app encounters
/// invalid configuration flags, missing environment defines, or a fatal
/// startup initialization error before [runApp] in production/release mode.
///
/// Running this widget ensures the native Flutter splash logo is dismissed
/// cleanly, preventing silent Android startup freezes while providing
/// developers and users with actionable diagnostic information.
class ConfigErrorApp extends StatefulWidget {
  final Object? error;
  final StackTrace? stackTrace;
  final List<String> problems;
  final VoidCallback? onRetry;

  const ConfigErrorApp({
    super.key,
    this.error,
    this.stackTrace,
    this.problems = const [],
    this.onRetry,
  });

  @override
  State<ConfigErrorApp> createState() => _ConfigErrorAppState();
}

class _ConfigErrorAppState extends State<ConfigErrorApp> {
  bool _showStackTrace = false;
  bool _copied = false;

  String _formatDiagnosticReport() {
    final buf = StringBuffer();
    buf.writeln('=== Budget Tracker Diagnostic Report ===');
    buf.writeln('Timestamp: ${DateTime.now().toUtc().toIso8601String()}');
    buf.writeln('Supabase URL: ${supabaseUrl.isEmpty ? '(Empty)' : supabaseUrl}');
    buf.writeln(
      'Supabase Key: ${supabasePublishableKey.isEmpty ? '(Empty)' : '${supabasePublishableKey.substring(0, supabasePublishableKey.length > 12 ? 12 : supabasePublishableKey.length)}... (isPrivileged: ${isPrivilegedSupabaseKey(supabasePublishableKey)})'}',
    );
    buf.writeln('FastAPI URL: ${fastapiBaseUrl.isEmpty ? '(Empty)' : fastapiBaseUrl}');
    buf.writeln();

    if (widget.problems.isNotEmpty) {
      buf.writeln('Configuration Problems:');
      for (final p in widget.problems) {
        buf.writeln('  - $p');
      }
      buf.writeln();
    }

    if (widget.error != null) {
      buf.writeln('Startup Error: ${widget.error}');
      if (widget.stackTrace != null) {
        buf.writeln('Stack Trace:');
        buf.writeln(widget.stackTrace);
      }
    }
    return buf.toString();
  }

  void _copyToClipboard(BuildContext context) {
    Clipboard.setData(ClipboardData(text: _formatDiagnosticReport()));
    setState(() => _copied = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Diagnostic report copied to clipboard'),
        duration: Duration(seconds: 2),
        backgroundColor: Color(0xFF5E1327),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const bgDark = Color(0xFF110509);
    const surfaceDark = Color(0xFF1E0B12);
    const borderDark = Color(0x33FFD2E1);
    const roseAccent = Color(0xFFF0A3BC);
    const burgundyPrimary = Color(0xFF5E1327);
    const errorRed = Color(0xFFFF5C5C);
    const textPrimary = Color(0xFFF1F5F9);
    const textSecondary = Color(0xFFC5A0AA);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Budget Tracker Diagnostics',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: bgDark,
        colorScheme: const ColorScheme.dark(
          primary: roseAccent,
          surface: surfaceDark,
          error: errorRed,
        ),
      ),
      home: Builder(
        builder: (context) {
          final hasProblems = widget.problems.isNotEmpty;

          return Scaffold(
            appBar: AppBar(
              backgroundColor: surfaceDark,
              elevation: 0,
              centerTitle: true,
              title: const Text(
                'Budget Tracker Diagnostic',
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(1),
                child: Container(color: borderDark, height: 1),
              ),
            ),
            body: SafeArea(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                children: [
                  // Status Header Badge
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: errorRed.withValues(alpha: 0.12),
                        border: Border.all(color: errorRed.withValues(alpha: 0.4)),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            hasProblems ? Icons.build_circle_outlined : Icons.error_outline_rounded,
                            color: errorRed,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            hasProblems ? 'Configuration Error' : 'Initialization Failure',
                            style: const TextStyle(
                              color: errorRed,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Descriptive Explanation
                  const Text(
                    'Application Startup Stopped',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    hasProblems
                        ? 'The application was compiled without valid environment configuration flags (--dart-define).'
                        : 'A fatal error occurred during core service startup before the main interface could be displayed.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: textSecondary,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Configuration Check Matrix
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: surfaceDark,
                      border: Border.all(color: borderDark),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Environment Parameters',
                          style: TextStyle(
                            color: textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildStatusRow(
                          label: 'Supabase URL',
                          value: supabaseUrl.isEmpty ? 'Missing' : supabaseUrl,
                          isValid: supabaseUrl.isNotEmpty && supabaseUrl.startsWith('https://'),
                          roseAccent: roseAccent,
                          errorRed: errorRed,
                        ),
                        const Divider(color: borderDark, height: 16),
                        _buildStatusRow(
                          label: 'Supabase Key',
                          value: supabasePublishableKey.isEmpty
                              ? 'Missing'
                              : (isPrivilegedSupabaseKey(supabasePublishableKey)
                                  ? 'Service Role (Rejected)'
                                  : 'Publishable Anon (Valid)'),
                          isValid: supabasePublishableKey.isNotEmpty &&
                              !isPrivilegedSupabaseKey(supabasePublishableKey),
                          roseAccent: roseAccent,
                          errorRed: errorRed,
                        ),
                        const Divider(color: borderDark, height: 16),
                        _buildStatusRow(
                          label: 'FastAPI Backend',
                          value: fastapiBaseUrl.isEmpty ? 'Missing' : fastapiBaseUrl,
                          isValid: fastapiBaseUrl.isNotEmpty && fastapiBaseUrl.startsWith('https://'),
                          roseAccent: roseAccent,
                          errorRed: errorRed,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Problem List Card
                  if (hasProblems) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: surfaceDark,
                        border: Border.all(color: errorRed.withValues(alpha: 0.5)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.warning_amber_rounded, color: errorRed, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Identified Issues',
                                style: TextStyle(
                                  color: errorRed,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          for (final problem in widget.problems)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('• ', style: TextStyle(color: errorRed, fontSize: 16)),
                                  Expanded(
                                    child: Text(
                                      problem,
                                      style: const TextStyle(
                                        color: textPrimary,
                                        fontSize: 13,
                                        fontFamily: 'monospace',
                                        height: 1.3,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Runtime Error & Stack Trace
                  if (widget.error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: surfaceDark,
                        border: Border.all(color: borderDark),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Runtime Exception',
                            style: TextStyle(
                              color: textPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 8),
                          SelectableText(
                            widget.error.toString(),
                            style: const TextStyle(
                              color: errorRed,
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                          if (widget.stackTrace != null) ...[
                            const SizedBox(height: 12),
                            TextButton.icon(
                              onPressed: () {
                                setState(() => _showStackTrace = !_showStackTrace);
                              },
                              icon: Icon(
                                _showStackTrace ? Icons.expand_less : Icons.expand_more,
                                size: 18,
                                color: roseAccent,
                              ),
                              label: Text(
                                _showStackTrace ? 'Hide Stack Trace' : 'View Stack Trace',
                                style: const TextStyle(color: roseAccent, fontSize: 13),
                              ),
                            ),
                            if (_showStackTrace)
                              Container(
                                margin: const EdgeInsets.only(top: 8),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: bgDark,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: borderDark),
                                ),
                                child: SelectableText(
                                  widget.stackTrace.toString(),
                                  style: const TextStyle(
                                    color: textSecondary,
                                    fontSize: 11,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Action Buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _copyToClipboard(context),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _copied ? roseAccent : textPrimary,
                            side: BorderSide(color: _copied ? roseAccent : borderDark),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          icon: Icon(
                            _copied ? Icons.check_circle_outline : Icons.copy_rounded,
                            size: 18,
                          ),
                          label: Text(_copied ? 'Copied' : 'Copy Report'),
                        ),
                      ),
                      if (widget.onRetry != null) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: widget.onRetry,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: burgundyPrimary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                            label: const Text(
                              'Retry Startup',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatusRow({
    required String label,
    required String value,
    required bool isValid,
    required Color roseAccent,
    required Color errorRed,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(
          isValid ? Icons.check_circle_rounded : Icons.cancel_rounded,
          color: isValid ? roseAccent : errorRed,
          size: 18,
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF94A3B8),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isValid ? const Color(0xFFF1F5F9) : errorRed,
              fontSize: 12,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
