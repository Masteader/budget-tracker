// AccountDeletionProvider: the state the Settings section and the banner read,
// and when it touches the device.
import 'package:budget_tracker/models/account_deletion.dart';
import 'package:budget_tracker/providers/account_deletion_provider.dart';
import 'package:budget_tracker/services/account_deletion_service.dart';
import 'package:budget_tracker/services/local_account_data_cleaner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _me = 'user-me';
final _date = DateTime.utc(2026, 12, 5, 10);
final _now = DateTime.utc(2026, 11, 5, 10);

AccountDeletionStatus _scheduled({List<MarkedHousehold> marked = const []}) => AccountDeletionStatus(
      state: AccountDeletionState.scheduled,
      scheduledFor: _date,
      canCancel: true,
      markedHouseholds: marked,
    );

class _FakeService extends AccountDeletionService {
  AccountDeletionStatus status = AccountDeletionStatus.none;
  AccountDeletionPreflight preflight = const AccountDeletionPreflight(
    deletion: AccountDeletionStatus.none,
    households: [
      AccountDeletionHousehold(id: 'h-1', name: 'One', position: HouseholdDeletionPosition.member),
      AccountDeletionHousehold(id: 'h-2', name: 'Two', position: HouseholdDeletionPosition.member),
    ],
  );
  Object? statusError;
  Object? requestError;
  Object? cancelError;
  Object? markError;
  bool accountExists = true;
  Object? accountExistsError;
  final Map<String, HouseholdDeletionMark> marks = {};
  int statusReads = 0;
  int preflightReads = 0;
  int markReads = 0;
  int cancels = 0;
  final requests = <({String confirmation, List<HouseholdDeletionChoice> choices, String locale})>[];

  @override
  Future<AccountDeletionStatus> getStatus() async {
    statusReads++;
    if (statusError != null) throw statusError!;
    return status;
  }

  @override
  Future<AccountDeletionPreflight> getPreflight() async {
    preflightReads++;
    return preflight;
  }

  @override
  Future<AccountDeletionStatus> request({
    required String confirmation,
    required List<HouseholdDeletionChoice> choices,
    required String locale,
  }) async {
    requests.add((confirmation: confirmation, choices: choices, locale: locale));
    if (requestError != null) throw requestError!;
    status = _scheduled();
    return status;
  }

  @override
  Future<void> cancel() async {
    cancels++;
    if (cancelError != null) throw cancelError!;
    status = AccountDeletionStatus.none;
  }

  @override
  Future<HouseholdDeletionMark> readHouseholdMark(String householdId) async {
    markReads++;
    if (markError != null) throw markError!;
    return marks[householdId] ?? const HouseholdDeletionMark(readable: true);
  }

  @override
  Future<bool> accountRowExists() async {
    if (accountExistsError != null) throw accountExistsError!;
    return accountExists;
  }
}

class _SpyCleaner extends LocalAccountDataCleaner {
  _SpyCleaner() : super(cancelReminders: () async {}, deleteStatements: () async {}, clearSignedUrls: () {});

  final wiped = <String>[];
  final wipedHouseholds = <Iterable<String>>[];
  final userDataWiped = <({String userId, bool keepFlag})>[];
  ({DateTime now, String? except})? dueCall;

  @override
  Future<bool> wipeUserData(String userId, {bool keepFlag = false}) async {
    userDataWiped.add((userId: userId, keepFlag: keepFlag));
    if (!keepFlag) await clearFlag(userId);
    return true;
  }

  @override
  Future<bool> wipeForUser(String userId, {Iterable<String> householdIds = const []}) async {
    wiped.add(userId);
    wipedHouseholds.add(householdIds);
    await clearFlag(userId);
    return true;
  }

  @override
  Future<List<String>> wipeDueUsers({required DateTime now, String? exceptUserId}) async {
    dueCall = (now: now, except: exceptUserId);
    return const [];
  }
}

void main() {
  late _FakeService service;
  late _SpyCleaner cleaner;
  late AccountDeletionProvider provider;
  late int notified;
  late int signOuts;
  Object? signOutError;
  String? userId;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    service = _FakeService();
    cleaner = _SpyCleaner();
    userId = _me;
    signOuts = 0;
    signOutError = null;
    provider = AccountDeletionProvider(
      service: service,
      cleaner: cleaner,
      currentUserId: () => userId,
      clock: () => _now,
      signOut: () async {
        signOuts++;
        if (signOutError != null) throw signOutError!;
      },
    );
    notified = 0;
    provider.addListener(() => notified++);
  });

  group('load', () {
    test('nothing pending: not pending, loaded, listeners told', () async {
      await provider.load();
      expect(provider.isLoaded, isTrue);
      expect(provider.isPending, isFalse);
      expect(provider.isFromDevice, isFalse);
      expect(notified, greaterThan(0));
    });

    test('pending: shows the server\'s date and remembers it on this device', () async {
      service.status = _scheduled();
      await provider.load();
      expect(provider.isPending, isTrue);
      expect(provider.status.scheduledFor, _date);
      expect(provider.status.canCancel, isTrue);
      final flag = await cleaner.readFlag(_me);
      expect(flag!.scheduledFor, _date);
      expect(flag.householdIds, ['h-1', 'h-2']);
    });

    test('a known flag needs no second read of the households', () async {
      service.status = _scheduled();
      await provider.load();
      await provider.load();
      expect(service.preflightReads, 1);
    });

    test('signed out: reads nothing', () async {
      userId = null;
      await provider.load();
      expect(service.statusReads, 0);
      expect(provider.isLoaded, isFalse);
    });

    test('cancelled elsewhere before the date: the flag goes and nothing is wiped', () async {
      await cleaner.setFlag(_me, _date);
      await provider.load();
      expect(provider.isPending, isFalse);
      expect(await cleaner.readFlag(_me), isNull);
      expect(cleaner.wiped, isEmpty);
    });

    test('nothing pending after the date and the account is gone: their data goes and they are signed out', () async {
      await cleaner.setFlag(_me, _now.subtract(const Duration(hours: 1)), householdIds: const ['h-1']);
      service.accountExists = false;
      await provider.load();
      expect(cleaner.userDataWiped.single, (userId: _me, keepFlag: true));
      expect(signOuts, 1);
      // Device-wide steps wait for the sign-out, when nobody is signed in.
      expect(cleaner.wiped, isEmpty);
      expect(await cleaner.readFlag(_me), isNotNull);

      await provider.handleSignedOut(_me);
      expect(cleaner.wiped, [_me]);
      expect(cleaner.wipedHouseholds.single, ['h-1']);
    });

    test('a purged account whose sign-out fails is not left half-handled', () async {
      await cleaner.setFlag(_me, _now.subtract(const Duration(hours: 1)));
      service.accountExists = false;
      signOutError = Exception('offline');
      await provider.load();
      expect(signOuts, 1);
      expect(cleaner.userDataWiped, hasLength(1));
      // The flag stays: the next launch tries again.
      expect(await cleaner.readFlag(_me), isNotNull);
    });

    test('an account that lives is never signed out', () async {
      await cleaner.setFlag(_me, _now.subtract(const Duration(hours: 1)));
      await provider.load();
      expect(signOuts, 0);
      expect(cleaner.userDataWiped, isEmpty);
    });

    test('nothing pending after the date but the account lives: flag goes, nothing wiped', () async {
      await cleaner.setFlag(_me, _now.subtract(const Duration(hours: 1)));
      service.accountExists = true;
      await provider.load();
      expect(cleaner.wiped, isEmpty);
      expect(await cleaner.readFlag(_me), isNull);
    });

    test('cannot tell whether the account lives: keeps the flag and wipes nothing', () async {
      await cleaner.setFlag(_me, _now.subtract(const Duration(hours: 1)));
      service.accountExistsError = const AccountDeletionException(AccountDeletionException.network);
      await provider.load();
      expect(cleaner.wiped, isEmpty);
      expect(await cleaner.readFlag(_me), isNotNull);
    });

    test('offline with a flag: still shows the date and Cancel, from the device', () async {
      await cleaner.setFlag(_me, _date);
      service.statusError = const AccountDeletionException(AccountDeletionException.network);
      await provider.load();
      expect(provider.isPending, isTrue);
      expect(provider.isFromDevice, isTrue);
      expect(provider.status.scheduledFor, _date);
      expect(provider.status.canCancel, isTrue);
    });

    test('offline without a flag: not loaded, so the UI does not claim anything', () async {
      service.statusError = const AccountDeletionException(AccountDeletionException.network);
      await provider.load();
      expect(provider.isLoaded, isFalse);
      expect(provider.isPending, isFalse);
    });

    test('an answer that arrives after a sign-out is dropped', () async {
      service.status = _scheduled();
      final loading = provider.load();
      provider.reset();
      await loading;
      expect(provider.isPending, isFalse);
      expect(await cleaner.readFlag(_me), isNull);
    });

    test('another user\'s status is not shown while the new one loads', () async {
      service.status = _scheduled();
      await provider.load();
      expect(provider.isPending, isTrue);

      userId = 'user-next';
      service.statusError = const AccountDeletionException(AccountDeletionException.network);
      await provider.load();
      expect(provider.isPending, isFalse);
    });
  });

  group('requestDeletion', () {
    test('sends the choices, goes pending and sets the flag', () async {
      final status = await provider.requestDeletion(
        confirmation: 'DELETE',
        choices: const [HouseholdDeletionChoice.delete('h-1')],
        locale: 'en',
      );
      expect(service.requests.single.confirmation, 'DELETE');
      expect(service.requests.single.locale, 'en');
      expect(service.requests.single.choices.single.householdId, 'h-1');
      expect(status.scheduledFor, _date);
      expect(provider.isPending, isTrue);
      expect((await cleaner.readFlag(_me))!.scheduledFor, _date);
    });

    test('a refusal stays not pending, sets no flag, and passes the code on', () async {
      service.requestError = const AccountDeletionException('confirmation_mismatch');
      await expectLater(
        provider.requestDeletion(confirmation: 'x', choices: const [], locale: 'en'),
        throwsA(isA<AccountDeletionException>().having((e) => e.code, 'code', 'confirmation_mismatch')),
      );
      expect(provider.isPending, isFalse);
      expect(await cleaner.readFlag(_me), isNull);
    });

    test('refreshes the tracked household, so its banner appears at once', () async {
      await provider.loadHouseholdMark('h-1');
      expect(provider.householdDeletionDate('h-1'), isNull);
      service.marks['h-1'] = HouseholdDeletionMark(readable: true, scheduledFor: _date);
      await provider.requestDeletion(confirmation: 'DELETE', choices: const [], locale: 'en');
      expect(provider.householdDeletionDate('h-1'), _date);
    });
  });

  group('cancelDeletion', () {
    setUp(() async {
      service.status = _scheduled(marked: [MarkedHousehold(id: 'h-1', name: 'One', scheduledFor: _date)]);
      service.marks['h-1'] = HouseholdDeletionMark(readable: true, scheduledFor: _date);
      await provider.load();
      await provider.loadHouseholdMark('h-1');
    });

    test('clears the status, the flag and the household\'s banner, and wipes nothing', () async {
      expect(provider.householdDeletionDate('h-1'), _date);
      service.marks['h-1'] = const HouseholdDeletionMark(readable: true);

      await provider.cancelDeletion();

      expect(service.cancels, 1);
      expect(provider.isPending, isFalse);
      expect(await cleaner.readFlag(_me), isNull);
      expect(provider.householdDeletionDate('h-1'), isNull);
      expect(cleaner.wiped, isEmpty);
    });

    test('the requester\'s own mark goes even if the household read then fails', () async {
      service.markError = const AccountDeletionException(AccountDeletionException.network);
      await provider.cancelDeletion();
      expect(provider.householdDeletionDate('h-1'), isNull);
    });

    test('someone else\'s mark on the same household stays until the server says so', () async {
      final other = DateTime.utc(2026, 12, 20);
      service.marks['h-1'] = HouseholdDeletionMark(readable: true, scheduledFor: other);
      await provider.cancelDeletion();
      expect(provider.householdDeletionDate('h-1'), other);
    });

    test('refused because it is in progress: stays pending, cannot cancel, passes the code on', () async {
      service.cancelError = const AccountDeletionException('deletion_in_progress');
      service.status = const AccountDeletionStatus(state: AccountDeletionState.processing, canCancel: false);
      await expectLater(
        provider.cancelDeletion(),
        throwsA(isA<AccountDeletionException>().having((e) => e.code, 'code', 'deletion_in_progress')),
      );
      expect(provider.isPending, isTrue);
      expect(provider.status.canCancel, isFalse);
      expect(await cleaner.readFlag(_me), isNotNull);
    });

    test('offline: stays pending with Cancel still offered', () async {
      service.cancelError = const AccountDeletionException(AccountDeletionException.network);
      await expectLater(provider.cancelDeletion(), throwsA(isA<AccountDeletionException>()));
      expect(provider.isPending, isTrue);
      expect(provider.status.canCancel, isTrue);
      expect(await cleaner.readFlag(_me), isNotNull);
    });
  });

  group('household marks', () {
    test('a marked household reports its date, others none', () async {
      service.marks['h-1'] = HouseholdDeletionMark(readable: true, scheduledFor: _date);
      expect(await provider.loadHouseholdMark('h-1'), isFalse);
      expect(provider.householdDeletionDate('h-1'), _date);
      expect(provider.householdDeletionDate('h-2'), isNull);
    });

    test('a household that cannot be read has vanished and shows no banner', () async {
      service.marks['h-1'] = HouseholdDeletionMark(readable: true, scheduledFor: _date);
      await provider.loadHouseholdMark('h-1');
      service.marks['h-1'] = const HouseholdDeletionMark(readable: false);
      expect(await provider.loadHouseholdMark('h-1'), isTrue);
      expect(provider.householdDeletionDate('h-1'), isNull);
    });

    test('a failed read is not a vanished household and keeps the last answer', () async {
      service.marks['h-1'] = HouseholdDeletionMark(readable: true, scheduledFor: _date);
      await provider.loadHouseholdMark('h-1');
      service.markError = const AccountDeletionException(AccountDeletionException.network);
      expect(await provider.loadHouseholdMark('h-1'), isFalse);
      expect(provider.householdDeletionDate('h-1'), _date);
    });
  });

  group('refreshOnResume', () {
    test('rereads the status and the household the dashboard last showed', () async {
      await provider.loadHouseholdMark('h-2');
      final reads = service.markReads;
      service.status = _scheduled();
      service.marks['h-2'] = HouseholdDeletionMark(readable: true, scheduledFor: _date);

      expect(await provider.refreshOnResume(), isFalse);

      expect(provider.isPending, isTrue);
      expect(service.markReads, reads + 1);
      expect(provider.householdDeletionDate('h-2'), _date);
    });

    test('says so when that household has vanished', () async {
      await provider.loadHouseholdMark('h-2');
      service.marks['h-2'] = const HouseholdDeletionMark(readable: false);
      expect(await provider.refreshOnResume(), isTrue);
    });

    test('with no household on screen there is nothing to vanish', () async {
      expect(await provider.refreshOnResume(), isFalse);
      expect(service.markReads, 0);
    });
  });

  group('signing out', () {
    test('while pending wipes this user\'s data with the households it knows', () async {
      service.status = _scheduled();
      await provider.load();
      await provider.handleSignedOut(_me);
      expect(cleaner.wiped, [_me]);
      expect(cleaner.wipedHouseholds.single, ['h-1', 'h-2']);
      expect(provider.isPending, isFalse);
      expect(provider.isLoaded, isFalse);
    });

    test('with nothing pending keeps the data: unsynced items wait for this account', () async {
      await provider.load();
      await provider.handleSignedOut(_me);
      expect(cleaner.wiped, isEmpty);
      expect(provider.isLoaded, isFalse);
    });

    test('after a cancel keeps the data', () async {
      service.status = _scheduled();
      await provider.load();
      await provider.cancelDeletion();
      await provider.handleSignedOut(_me);
      expect(cleaner.wiped, isEmpty);
    });

    test('forgets the household marks', () async {
      service.marks['h-1'] = HouseholdDeletionMark(readable: true, scheduledFor: _date);
      await provider.loadHouseholdMark('h-1');
      await provider.handleSignedOut(_me);
      expect(provider.householdDeletionDate('h-1'), isNull);
    });
  });

  test('wipeDueUsers passes the clock and spares the signed-in user', () async {
    await provider.wipeDueUsers();
    expect(cleaner.dueCall!.now, _now);
    expect(cleaner.dueCall!.except, _me);
  });
}
