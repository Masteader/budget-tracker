// UI-20: TextEditingControllers created for dialogs must be disposed, but only
// after the dialog's exit animation (disposing right after `await showDialog`
// makes the still-animating TextField use a disposed controller).
import 'dart:io';

import 'package:budget_tracker/widgets/dispose_on_unmount.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

bool _isDisposed(ChangeNotifier n) {
  try {
    n.addListener(() {});
    return false;
  } on FlutterError {
    return true;
  }
}

void main() {
  testWidgets('controllers outlive the exit animation and are disposed afterwards', (tester) async {
    final ctrl = TextEditingController();
    String? submitted;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => DisposeOnUnmount(
                    disposables: [ctrl],
                    child: AlertDialog(
                      content: TextField(controller: ctrl),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('OK')),
                      ],
                    ),
                  ),
                );
                // Reading right after the pop, as several call sites do.
                if (ok == true) submitted = ctrl.text;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Groceries');
    await tester.tap(find.text('OK'));

    // Mid exit animation: the TextField still renders and the controller is alive.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(submitted, 'Groceries');
    expect(_isDisposed(ctrl), isFalse);
    expect(tester.takeException(), isNull);

    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(_isDisposed(ctrl), isTrue);
    expect(tester.takeException(), isNull);
  });

  test('dialog controllers in screens and widgets are handed to DisposeOnUnmount', () {
    // Controllers stored in State lists and disposed in State.dispose.
    const ownedByState = {'lib/widgets/sub_budget_allocation_dialog.dart:ctrl'};
    final local = RegExp(r'^    final (\w+) = TextEditingController\(', multiLine: true);
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final src = entity.readAsStringSync();
      for (final m in local.allMatches(src)) {
        final name = m.group(1)!;
        final path = entity.path.replaceAll(r'\', '/');
        if (ownedByState.contains('$path:$name')) continue;
        final handedOver = RegExp(r'disposables: \[[^\]]*\b' + name + r'\b').hasMatch(src);
        if (!handedOver) offenders.add('$path: $name');
      }
    }
    expect(offenders, isEmpty);
  });
}
