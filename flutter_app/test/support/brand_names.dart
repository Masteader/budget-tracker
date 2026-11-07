/// The old and the withdrawn app names, shared by the brand guards:
/// ui_l10n_guard_test.dart, screens/brand_identity_test.dart and
/// ios/ios_project_config_test.dart.
library;

/// An Arabic-script letter or mark. Punctuation and digits (، ؟ ۔ ٣) are not,
/// so a name next to them is still a whole word.
const _arabicLetter = '[ؐ-ؚؠ-ٟٮ-ۓە-ۯۺ-ۿ]';

/// The withdrawn name, in its Latin and Arabic-script spellings. Same pattern
/// as `_WITHDRAWN_NAME` in ai_service/tests/test_qawam_money_branding.py: keep
/// the two in step.
///
/// Doubled ي/ی, a shadda or an alef are not ordinary words, so those forms
/// match anywhere. وفير/وفیر is also the ordinary word for "abundant" and sits
/// inside توفير/توفیر (saving), so it matches as a whole word with at most one
/// attached proclitic (ب ل و ف ك, or وب ول فب فل): the ت of توفير is not one.
final withdrawnAppName = RegExp(
  'wa+f+(?:ee|ei|ie|i|y)r'
  '|وفّ?[يی]{2}ر|وفّ[يی]ر|وافّ?[يی]{1,2}ر'
  '|(?<!$_arabicLetter)(?:[وف][بل]|[بلوفك])?وف[يی]ر(?!$_arabicLetter)',
  caseSensitive: false,
);

/// The former names Budget Tracker and its Urdu-script form.
final formerAppName = RegExp('budget tracker|بجٹ ٹریکر', caseSensitive: false);

/// The former Arabic name. It is also the ordinary phrase for "household
/// budget", so each guard decides where it may stay.
const formerArabicAppName = 'ميزانية الأسرة';
