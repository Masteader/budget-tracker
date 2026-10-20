import 'package:flutter/widgets.dart';

/// Owns [ChangeNotifier]s (typically `TextEditingController`s) created for a
/// dialog or bottom sheet and disposes them when that route's widgets are
/// unmounted (UI-20).
///
/// Disposing right after `await showDialog(...)` is too early: the future
/// completes when the route is popped, but its exit animation still rebuilds
/// the `TextField`s, which then use a disposed controller. Wrapping the route
/// content in this widget disposes the controllers in `State.dispose`, which
/// Flutter calls after the route is removed and after the `TextField`s (its
/// descendants) have detached their listeners.
///
/// ```dart
/// final nameCtrl = TextEditingController();
/// await showDialog(
///   context: context,
///   builder: (ctx) => DisposeOnUnmount(
///     disposables: [nameCtrl],
///     child: AlertDialog(content: TextField(controller: nameCtrl)),
///   ),
/// );
/// ```
class DisposeOnUnmount extends StatefulWidget {
  const DisposeOnUnmount({super.key, required this.disposables, required this.child});

  final List<ChangeNotifier> disposables;
  final Widget child;

  @override
  State<DisposeOnUnmount> createState() => _DisposeOnUnmountState();
}

class _DisposeOnUnmountState extends State<DisposeOnUnmount> {
  @override
  void dispose() {
    for (final notifier in widget.disposables) {
      notifier.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
