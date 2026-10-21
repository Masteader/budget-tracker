// UX-26: home tabs are built on first visit and kept alive afterwards, so
// chat, budgets and settings no longer build and fetch at launch.
import 'package:budget_tracker/widgets/lazy_indexed_stack.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Probe extends StatefulWidget {
  final String name;
  final Map<String, int> inits;
  const _Probe(this.name, this.inits);

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  int taps = 0;

  @override
  void initState() {
    super.initState();
    widget.inits[widget.name] = (widget.inits[widget.name] ?? 0) + 1;
  }

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: () => setState(() => taps++),
        child: Text('${widget.name} $taps'),
      );
}

void main() {
  testWidgets('only the visible tab is built at start; visited tabs keep their state', (tester) async {
    final inits = <String, int>{};
    var index = 0;
    late StateSetter setOuter;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(builder: (context, setState) {
          setOuter = setState;
          return LazyIndexedStack(
            index: index,
            itemCount: 3,
            itemBuilder: (context, i) => _Probe('tab$i', inits),
          );
        }),
      ),
    ));

    expect(inits, {'tab0': 1}, reason: 'tabs 1 and 2 are not built at launch');

    await tester.tap(find.text('tab0 0'));
    await tester.pump();

    setOuter(() => index = 2);
    await tester.pump();
    expect(inits, {'tab0': 1, 'tab2': 1});
    expect(find.text('tab2 0'), findsOneWidget);

    setOuter(() => index = 0);
    await tester.pump();
    expect(inits, {'tab0': 1, 'tab2': 1}, reason: 'kept alive, not rebuilt from scratch');
    expect(find.text('tab0 1'), findsOneWidget, reason: 'state survived the switch');
    expect(inits.containsKey('tab1'), isFalse);
  });
}
