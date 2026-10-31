import 'package:flutter_test/flutter_test.dart';

import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/models/nafaqah.dart';
import 'package:budget_tracker/widgets/card_error_state.dart';
import 'package:budget_tracker/widgets/dashboard/family_reimbursement_card.dart';
import 'package:budget_tracker/widgets/dashboard/household_balances_section.dart';
import '../support/localized_app.dart';

void main() {
  testWidgets('HouseholdBalancesSection: isFamily: true renders FamilyReimbursementCard without calling settlement loader', (tester) async {
    var settlementCalls = 0;
    Future<SettlementV2Summary> loadSettlement(String hid) async {
      settlementCalls++;
      throw Exception('Settlement v2 should not be called in family mode');
    }

    const summary = NafaqahSummary(
      mode: 'family_nafaqah',
      husbandId: 'u-1',
      husbandName: 'Ahmed',
      wives: [
        NafaqahWife(
          id: 'w-1',
          displayName: 'Fatima',
          reimbursement: ReimbursementBalance(
            grossAdvanced: 0.0,
            reimbursed: 0.0,
            outstanding: 0.0,
            overpaid: 0.0,
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      localizedApp(
        HouseholdBalancesSection(
          householdId: 'hh-1',
          isFamily: true,
          loadSettlement: loadSettlement,
          loadNafaqah: (hid) async => summary,
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(settlementCalls, equals(0));
    expect(find.byType(CardErrorState), findsNothing);
    expect(find.byType(FamilyReimbursementCard), findsOneWidget);
  });
}
