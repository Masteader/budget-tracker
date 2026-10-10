import 'package:flutter/material.dart';
import '../../models/models.dart';

/// Modal bottom sheet allowing users to view active vs inactive categories,
/// activate new developer categories from the library, deactivate unused categories,
/// and add custom root categories for their household.
class CategoryLibrarySheet extends StatefulWidget {
  final List<CategoryItem> activeCategories;
  final List<CategoryItem> inactiveCategories;
  final void Function(CategoryItem category, bool isActive) onToggle;
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
  void _confirmDeactivate(CategoryItem item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Deactivate "${item.name}"?'),
        content: const Text(
          'Inactivating this category removes it from your active monthly budget and returns unspent funds to your Savings Reserve.\n\nAll past transaction history remains safe and intact.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              widget.onToggle(item, false);
            },
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );
  }

  void _confirmActivate(CategoryItem item) {
    widget.onToggle(item, true);
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
                  const Icon(Icons.category_outlined, color: Color(0xFF00C896)),
                  const SizedBox(width: 8),
                  Text(
                    'Category Library',
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  FilledButton.tonalIcon(
                    onPressed: widget.onAddCustom,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Custom'),
                  ),
                ],
              ),
            ),
            // TabBar
            TabBar(
              indicatorColor: const Color(0xFF00C896),
              labelColor: const Color(0xFF00C896),
              unselectedLabelColor: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              tabs: [
                Tab(text: 'Active (${widget.activeCategories.length})'),
                Tab(text: 'Library / Inactive (${widget.inactiveCategories.length})'),
              ],
            ),
            // TabBarView
            Expanded(
              child: TabBarView(
                children: [
                  // Active Categories List
                  widget.activeCategories.isEmpty
                      ? const Center(child: Text('No active categories'))
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: widget.activeCategories.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (ctx, index) {
                            final item = widget.activeCategories[index];
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: const Color(0xFF00C896).withValues(alpha: 0.15),
                                child: const Icon(Icons.check_circle, color: Color(0xFF00C896), size: 20),
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
                              trailing: OutlinedButton(
                                onPressed: () => _confirmDeactivate(item),
                                style: OutlinedButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  foregroundColor: theme.colorScheme.error,
                                ),
                                child: const Text('Deactivate'),
                              ),
                            );
                          },
                        ),
                  // Inactive / Library Categories List
                  widget.inactiveCategories.isEmpty
                      ? const Center(child: Text('All categories are currently active'))
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: widget.inactiveCategories.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (ctx, index) {
                            final item = widget.inactiveCategories[index];
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
                                        color: const Color(0xFF00C896).withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text(
                                        'Available',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF00C896),
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
                              trailing: FilledButton(
                                onPressed: () => _confirmActivate(item),
                                style: FilledButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  backgroundColor: const Color(0xFF00C896),
                                ),
                                child: const Text('Activate'),
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
