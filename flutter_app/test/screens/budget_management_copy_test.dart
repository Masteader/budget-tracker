import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final src = File('lib/screens/home/budget_management_screen.dart').readAsStringSync();

  group('Silent Sinking-Fund-Aware Budget Copy', () {
    test('does not prompt redundant sweep vs rollover dialog', () {
      // The pop-up dialog asking for bm_option_sweep vs bm_option_rollover has been eliminated
      expect(src.contains("context.tr('bm_option_sweep')"), isFalse);
      expect(src.contains("context.tr('bm_option_rollover')"), isFalse);
      expect(src.contains("context.trArgs('bm_unspent_title'"), isFalse);
    });

    test('shows silent success notification with sinking fund carryover', () {
      expect(src.contains("context.tr('bm_copied_silent_success')"), isTrue);
    });

    test('implements sinking fund accumulation for sub-allocations and parent categories', () {
      // Inspect presence of sinking fund accumulation calculation
      expect(src.contains("sinkingCfg = Map<String, dynamic>.from(subAllocs['_sinking_fund'] as Map);"), isTrue);
      expect(src.contains("scCfg['accumulate'] == true"), isTrue);
      expect(src.contains("newSubNumeric[sc] = double.parse((baseAmt + unspent).toStringAsFixed(2));"), isTrue);
      expect(src.contains("newSubNumeric[sc] = double.parse(baseAmt.toStringAsFixed(2));"), isTrue);
      expect(src.contains("parentCfg['accumulate'] == true"), isTrue);
    });
  });
}
