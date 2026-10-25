import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_themes.dart';

/// Modal bottom sheet allowing users to view active vs inactive categories,
/// activate new developer categories from the library, deactivate unused categories,
/// and add custom root categories for their household.
class CategoryLibrarySheet extends StatefulWidget {
  final List<CategoryItem> activeCategories;
  final List<CategoryItem> inactiveCategories;
  final FutureOr<void> Function(CategoryItem category, bool isActive) onToggle;
  final VoidCallback onAddCustom;

  const CategoryLibrarySheet({
    super.key,
    required this.activeCategories,
    required this.inactiveCategories,
    required this.onToggle,
    required this.onAddCustom,
  });

  @override
  State<CategoryLibrarySheet> createState() => _CategoryLibrarySheetState();
}

class _CategoryLibrarySheetState extends State<CategoryLibrarySheet> {
  late List<CategoryItem> _activeCategories;
  late List<CategoryItem> _inactiveCategories;
  final Set<String> _processingCodes = {};

  @override
  void initState() {
    super.initState();
    _activeCategories = List<CategoryItem>.from(widget.activeCategories)
      ..removeWhere((c) => c.name.toLowerCase().contains('test') || c.code.toLowerCase().contains('test'));
    _inactiveCategories = List<CategoryItem>.from(widget.inactiveCategories)
      ..removeWhere((c) => c.name.toLowerCase().contains('test') || c.code.toLowerCase().contains('test'));
  }

  void _confirmDeactivate(CategoryItem item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.trArgs('cls_deactivate_title', {'name': item.name})),
        content: Text(
          context.tr('cls_deactivate_desc'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.tr('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _handleDeactivate(item);
            },
            child: Text(context.tr('deactivate')),
          ),
        ],
      ),
    );
  }

  Future<void> _handleDeactivate(CategoryItem item) async {
    setState(() {
      _processingCodes.add(item.code);
      _activeCategories.removeWhere((c) => c.code == item.code);
      if (!_inactiveCategories.any((c) => c.code == item.code)) {
        _inactiveCategories.add(item);
      }
    });
    try {
      await widget.onToggle(item, false);
    } catch (_) {
      if (mounted) {
        setState(() {
          _inactiveCategories.removeWhere((c) => c.code == item.code);
          if (!_activeCategories.any((c) => c.code == item.code)) {
            _activeCategories.add(item);
          }
        });
      }
    } finally {
      if (mounted) {
        setState(() => _processingCodes.remove(item.code));
      }
    }
  }

  Future<void> _confirmActivate(CategoryItem item) async {
    setState(() {
      _processingCodes.add(item.code);
      _inactiveCategories.removeWhere((c) => c.code == item.code);
      if (!_activeCategories.any((c) => c.code == item.code)) {
        _activeCategories.add(item);
      }
    });
    try {
      await widget.onToggle(item, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _activeCategories.removeWhere((c) => c.code == item.code);
          if (!_inactiveCategories.any((c) => c.code == item.code)) {
            _inactiveCategories.add(item);
          }
        });
      }
    } finally {
      if (mounted) {
        setState(() => _processingCodes.remove(item.code));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DefaultTabController(
      length: 2,
      child: Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle bar
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.category_outlined,
                    color: context.isDark ? const Color(0xFFF0A3BC) : const Color(0xFF4A0E1E),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    context.tr('category_library'),
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      backgroundColor: context.isDark ? const Color(0xFF5E1327) : const Color(0xFF4A0E1E),
                      foregroundColor: context.isDark ? const Color(0xFFF0A3BC) : Colors.white,
                    ),
                    onPressed: widget.onAddCustom,
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(context.tr('cls_custom')),
                  ),
                ],
              ),
            ),
            // TabBar
            TabBar(
              indicatorColor: context.isDark ? const Color(0xFFF0A3BC) : const Color(0xFF4A0E1E),
              labelColor: context.isDark ? const Color(0xFFF0A3BC) : const Color(0xFF4A0E1E),
              unselectedLabelColor: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              tabs: [
                Tab(text: context.trArgs('cls_active_tab', {'count': _activeCategories.length})),
                Tab(text: context.trArgs('cls_inactive_tab', {'count': _inactiveCategories.length})),
              ],
            ),
            // TabBarView
            Expanded(
              child: TabBarView(
                children: [
                  // Active Categories List
                  _activeCategories.isEmpty
                      ? Center(child: Text(context.tr('cls_no_active')))
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _activeCategories.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (ctx, index) {
                            final item = _activeCategories[index];
                            final isBusy = _processingCodes.contains(item.code);
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: (context.isDark ? const Color(0xFF10B981) : const Color(0xFF059669)).withValues(alpha: 0.15),
                                child: Icon(
                                  Icons.check_circle,
                                  color: context.isDark ? const Color(0xFF10B981) : const Color(0xFF059669),
                                  size: 20,
                                ),
                              ),
                              title: Text(
                                item.name,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              subtitle: Text(
                                item.code,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                ),
                              ),
                              trailing: isBusy
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : OutlinedButton(
                                      onPressed: () => _confirmDeactivate(item),
                                      style: OutlinedButton.styleFrom(
                                        visualDensity: VisualDensity.compact,
                                        foregroundColor: theme.colorScheme.error,
                                      ),
                                      child: Text(context.tr('deactivate')),
                                    ),
                            );
                          },
                        ),
                  // Inactive / Library Categories List
                  _inactiveCategories.isEmpty
                      ? Center(child: Text(context.tr('cls_all_active')))
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _inactiveCategories.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (ctx, index) {
                            final item = _inactiveCategories[index];
                            final isBusy = _processingCodes.contains(item.code);
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.08),
                                child: Icon(
                                  item.isSystem ? Icons.auto_awesome : Icons.label_outline,
                                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                                  size: 20,
                                ),
                              ),
                              title: Row(
                                children: [
                                  Text(
                                    item.name,
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  if (item.isSystem) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: (context.isDark ? const Color(0xFFF0A3BC) : const Color(0xFF4A0E1E)).withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        context.tr('cls_available'),
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: context.isDark ? const Color(0xFFF0A3BC) : const Color(0xFF4A0E1E),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              subtitle: Text(
                                item.code,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                ),
                              ),
                              trailing: isBusy
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : FilledButton(
                                      onPressed: () => _confirmActivate(item),
                                      style: FilledButton.styleFrom(
                                        visualDensity: VisualDensity.compact,
                                        backgroundColor: context.isDark ? const Color(0xFF5E1327) : const Color(0xFF4A0E1E),
                                        foregroundColor: context.isDark ? const Color(0xFFF0A3BC) : Colors.white,
                                      ),
                                      child: Text(context.tr('activate')),
                                    ),
                            );
                          },
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
