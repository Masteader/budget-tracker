// The stored note must say who paid whom whichever way the paragraph around it
// runs. U+2192 does not mirror: left to itself, an RTL paragraph puts the payer on
// the right, so the arrow points from recipient to payer. Asserted on painted
// positions, since the string looks right either way.
import 'package:budget_tracker/models/transaction_attribution.dart';
import 'package:budget_tracker/widgets/dashboard/multi_roommate_settlement_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _arrow = '→';

const _pairs = <String, (String, String)>{
  'Arabic names': ('أحمد', 'عمر'),
  'Urdu names': ('عمران', 'فیصل'),
  'Latin names': ('Ahmed', 'Omar'),
  'Arabic to Latin': ('أحمد', 'Omar'),
  'Latin to Arabic': ('Ahmed', 'عمر'),
  'mixed names': ('Ali علي', 'عمر Omar'),
  'names with digits': ('أحمد 2', '3 Omar'),
};

({double left, double right}) _span(TextPainter painter, String text, String part) {
  final start = text.lastIndexOf(part);
  expect(start, isNonNegative, reason: part);
  final boxes = painter.getBoxesForSelection(TextSelection(baseOffset: start, extentOffset: start + part.length));
  expect(boxes, isNotEmpty, reason: part);
  return (
    left: boxes.map((b) => b.left).reduce((a, b) => a < b ? a : b),
    right: boxes.map((b) => b.right).reduce((a, b) => a > b ? a : b),
  );
}

/// Paints [text] in a paragraph running [direction] and checks payer, arrow,
/// recipient and method appear left to right, so the arrow runs payer to recipient.
void _expectPaintedPayerToRecipient(String text, TextDirection direction, String payer, String recipient, String method) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: const TextStyle(fontSize: 10)),
    textDirection: direction,
  )..layout();
  addTearDown(painter.dispose);
  final from = _span(painter, text, payer);
  final arrow = _span(painter, text, _arrow);
  final to = _span(painter, text, recipient);
  final via = _span(painter, text, method);
  expect(from.right, lessThanOrEqualTo(arrow.left), reason: '$direction: the payer is behind the arrow in "$text"');
  expect(arrow.right, lessThanOrEqualTo(to.left), reason: '$direction: the recipient is ahead of the arrow in "$text"');
  expect(to.right, lessThanOrEqualTo(via.left), reason: '$direction: the method follows in "$text"');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  _pairs.forEach((label, names) {
    final (payer, recipient) = names;
    final note = roommateSettlementNote(from: payer, to: recipient, method: 'cash');

    for (final direction in TextDirection.values) {
      test('$label read in ${direction.name}', () {
        _expectPaintedPayerToRecipient(note, direction, payer, recipient, 'cash');
      });

      test('$label read in ${direction.name} inside the stored audit note', () {
        // What the server stores, and what auditNoteHead hands back.
        final stored = 'Settlement | PaidBy: 11 | Recipient: 22 | Method: CASH | Note: $note';
        _expectPaintedPayerToRecipient(stored, direction, payer, recipient, 'cash');
        final head = auditNoteHead(stored, fallback: '');
        expect(head, endsWith(note), reason: 'auditNoteHead keeps the marks');
        _expectPaintedPayerToRecipient(head, direction, payer, recipient, 'cash');
      });
    }

    test('$label survive the server normalising the note', () {
      // supabase_client.record_household_reimbursement: "|" to "/", whitespace runs
      // collapsed. Mirrors its `" ".join(text.replace("|", "/").split())`; the real
      // function is covered by ai_service/tests/test_fable_settlement_note_isolates.py.
      final normalised = note.replaceAll('|', '/').trim().split(RegExp(r'\s+')).join(' ');
      expect(normalised, note);
    });
  });

  test('an arrow left to itself is reversed in RTL: the failure this guards against', () {
    const bare = 'أحمد $_arrow عمر · cash';
    final painter = TextPainter(text: const TextSpan(text: bare), textDirection: TextDirection.rtl)..layout();
    addTearDown(painter.dispose);
    expect(_span(painter, bare, 'أحمد').left, greaterThan(_span(painter, bare, 'عمر').left));
  });

  test('names are searchable: the note holds them unbroken', () {
    final note = roommateSettlementNote(from: 'Omar', to: 'سامي', method: 'cash');
    expect(note.toLowerCase(), contains('omar'));
    expect(note, contains('سامي'));
  });

  test('a bidi control inside a name cannot break out of its isolate', () {
    const controls = '\u202A\u202B\u202C\u202D\u202E\u2066\u2067\u2068\u2069';
    final note = roommateSettlementNote(from: 'A${controls}li', to: 'Omar\u202E', method: 'cash');
    expect(note, roommateSettlementNote(from: 'Ali', to: 'Omar', method: 'cash'));
  });

  test('a name that looks like a placeholder stays as written', () {
    expect(roommateSettlementNote(from: '{to}', to: 'Omar', method: 'cash'), contains('{to}'));
  });
}
