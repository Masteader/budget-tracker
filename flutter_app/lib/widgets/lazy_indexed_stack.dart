import 'package:flutter/widgets.dart';

/// An [IndexedStack] whose children are built the first time they are shown
/// and kept alive afterwards (UX-26): the home screen no longer builds — and
/// fetches for — every tab at launch.
class LazyIndexedStack extends StatefulWidget {
  final int index;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  const LazyIndexedStack({
    super.key,
    required this.index,
    required this.itemCount,
    required this.itemBuilder,
  });

  @override
  State<LazyIndexedStack> createState() => _LazyIndexedStackState();
}

class _LazyIndexedStackState extends State<LazyIndexedStack> {
  final Set<int> _visited = {};

  @override
  Widget build(BuildContext context) {
    _visited.add(widget.index);
    return IndexedStack(
      index: widget.index,
      children: [
        for (var i = 0; i < widget.itemCount; i++)
          _visited.contains(i)
              ? KeyedSubtree(key: ValueKey('lazy_tab_$i'), child: widget.itemBuilder(context, i))
              : const SizedBox.shrink(),
      ],
    );
  }
}
