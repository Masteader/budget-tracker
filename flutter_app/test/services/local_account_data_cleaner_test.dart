// What deleting an account removes from the device, and when: one user's queue
// rows and blobs and household prefs, never another account's items, never theme
// or language.
import 'dart:io';

import 'package:budget_tracker/services/household_resolver.dart';
import 'package:budget_tracker/services/local_account_data_cleaner.dart';
import 'package:budget_tracker/services/offline_queue_manager.dart';
import 'package:budget_tracker/services/salary_cycle_service.dart';
import 'package:budget_tracker/services/statement_pdf_service.dart';
import 'package:budget_tracker/widgets/dashboard/household_setup_card.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _me = 'user-me';
const _other = 'user-other';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late Directory blobs;
  late OfflineQueueManager queue;
  late int reminderCancels;
  late int statementDeletes;
  late int urlClears;
  late LocalAccountDataCleaner cleaner;

  Future<String> enqueue(String? owner, {String householdId = 'h-1', List<String>? images}) async {
    final id = await queue.enqueue(
      operationType: 'receipt',
      payload: {
        if (owner != null) 'user_id': owner,
        'merchant': 'Shop',
        if (images != null) OfflineQueueManager.inlineImagesKey: images,
      },
      householdId: householdId,
    );
    return id!;
  }

  Future<List<String>> remainingIds() async =>
      (await db.query(OfflineQueueManager.tableName, columns: ['id'])).map((r) => r['id'] as String).toList();

  List<String> blobNames() => blobs.listSync().map((f) => p.basename(f.path)).toList();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await OfflineQueueManager.createSchema(db);
    blobs = await Directory.systemTemp.createTemp('appagent_blobs');
    queue = OfflineQueueManager(customDb: db, blobDirectoryProvider: () async => blobs);
    reminderCancels = 0;
    statementDeletes = 0;
    urlClears = 0;
    cleaner = LocalAccountDataCleaner(
      queue: queue,
      cancelReminders: () async => reminderCancels++,
      deleteStatements: () async => statementDeletes++,
      clearSignedUrls: () => urlClears++,
    );
  });

  tearDown(() async {
    await db.close();
    await blobs.delete(recursive: true);
    SalaryCycleService.paydayDay = SalaryCycleService.defaultPaydayDay;
  });

  group('clearForUser', () {
    test('removes this user\'s rows and blobs in every status, and nothing else', () async {
      final mine = await enqueue(_me, images: ['aGVsbG8=']);
      final mineFailed = await enqueue(_me);
      await db.update(OfflineQueueManager.tableName, {'status': 'failed'}, where: 'id = ?', whereArgs: [mineFailed]);
      final mineSyncing = await enqueue(_me);
      await queue.markSyncing(mineSyncing);
      final theirs = await enqueue(_other, images: ['d29ybGQ=']);

      final removed = await queue.clearForUser(_me);

      expect(removed, 3);
      expect(await remainingIds(), [theirs]);
      expect(blobNames().where((n) => n.startsWith(mine)), isEmpty, reason: 'my blob is gone');
      expect(blobNames().where((n) => n.startsWith(theirs)), hasLength(1), reason: 'their blob stays');
      final loaded = await queue.getPendingItems();
      expect(await queue.loadImages(loaded.single), ['d29ybGQ=']);
    });

    test('leaves ownerless items: nothing says they are this user\'s', () async {
      final ownerless = await enqueue(null);
      await enqueue(_me);
      await queue.clearForUser(_me);
      expect(await remainingIds(), [ownerless]);
    });

    test('leaves a row it cannot read rather than guessing whose it is', () async {
      final mine = await enqueue(_me);
      await db.update(OfflineQueueManager.tableName, {'payload': 'not json {'}, where: 'id = ?', whereArgs: [mine]);
      await queue.clearForUser(_me);
      expect(await remainingIds(), [mine]);
    });

    test('with nothing of this user removes nothing', () async {
      final theirs = await enqueue(_other);
      expect(await queue.clearForUser(_me), 0);
      expect(await remainingIds(), [theirs]);
    });
  });

  group('wipeForUser', () {
    Future<void> seedPrefs() async {
      SharedPreferences.setMockInitialValues({
        HouseholdResolver.cacheKeyFor(_me): 'h-active',
        HouseholdResolver.cacheKeyFor(_other): 'h-theirs',
        HouseholdSetupPrefs.paydayConfirmedKey('h-active'): true,
        HouseholdSetupPrefs.hiddenKey('h-active'): true,
        HouseholdSetupPrefs.paydayConfirmedKey('h-second'): true,
        HouseholdSetupPrefs.hiddenKey('h-second'): true,
        HouseholdSetupPrefs.paydayConfirmedKey('h-theirs'): true,
        HouseholdSetupPrefs.hiddenKey('h-theirs'): true,
        SalaryCycleService.paydayPrefKey: 15,
        'app_theme_mode': 'dark',
        'app_language_code': 'ur',
      });
    }

    test('removes this user\'s prefs and keeps theme, language and the other account\'s', () async {
      await seedPrefs();
      await cleaner.wipeForUser(_me, householdIds: const ['h-second']);
      final prefs = await SharedPreferences.getInstance();

      expect(prefs.containsKey(HouseholdResolver.cacheKeyFor(_me)), isFalse);
      for (final hid in ['h-active', 'h-second']) {
        expect(prefs.containsKey(HouseholdSetupPrefs.paydayConfirmedKey(hid)), isFalse, reason: hid);
        expect(prefs.containsKey(HouseholdSetupPrefs.hiddenKey(hid)), isFalse, reason: hid);
      }
      expect(prefs.containsKey(SalaryCycleService.paydayPrefKey), isFalse);

      expect(prefs.getString('app_theme_mode'), 'dark');
      expect(prefs.getString('app_language_code'), 'ur');
      expect(prefs.getString(HouseholdResolver.cacheKeyFor(_other)), 'h-theirs');
      expect(prefs.getBool(HouseholdSetupPrefs.paydayConfirmedKey('h-theirs')), isTrue);
      expect(prefs.getBool(HouseholdSetupPrefs.hiddenKey('h-theirs')), isTrue);
    });

    test('the households remembered in the flag are cleaned too', () async {
      await seedPrefs();
      await cleaner.setFlag(_me, DateTime.utc(2026, 12, 5), householdIds: const ['h-second']);
      await cleaner.wipeForUser(_me);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(HouseholdSetupPrefs.hiddenKey('h-second')), isFalse);
    });

    test('resets the payday in memory, so the next account does not inherit it', () async {
      await seedPrefs();
      SalaryCycleService.paydayDay = 15;
      await cleaner.wipeForUser(_me);
      expect(SalaryCycleService.paydayDay, SalaryCycleService.defaultPaydayDay);
    });

    test('clears the queue, reminders, statements, signed URLs and the flag', () async {
      final mine = await enqueue(_me);
      final theirs = await enqueue(_other);
      await cleaner.setFlag(_me, DateTime.utc(2026, 12, 5));

      final done = await cleaner.wipeForUser(_me);

      expect(done, isTrue);
      expect(await remainingIds(), [theirs]);
      expect(await remainingIds(), isNot(contains(mine)));
      expect(reminderCancels, 1);
      expect(statementDeletes, 1);
      expect(urlClears, 1);
      expect(await cleaner.readFlag(_me), isNull);
    });

    test('one failing step does not stop the others, and keeps the flag to retry', () async {
      final failing = LocalAccountDataCleaner(
        queue: queue,
        cancelReminders: () async => throw Exception('notification plugin failed'),
        deleteStatements: () async => statementDeletes++,
        clearSignedUrls: () => urlClears++,
      );
      await enqueue(_me);
      await failing.setFlag(_me, DateTime.utc(2026, 12, 5));

      final done = await failing.wipeForUser(_me);

      expect(done, isFalse);
      expect(await remainingIds(), isEmpty);
      expect(statementDeletes, 1);
      expect(urlClears, 1);
      expect(await failing.readFlag(_me), isNotNull);
    });
  });

  group('the local flag', () {
    test('keeps the date and households for this user only', () async {
      await cleaner.setFlag(_me, DateTime.utc(2026, 12, 5, 10), householdIds: const ['h-1', 'h-2']);
      final flag = await cleaner.readFlag(_me);
      expect(flag!.scheduledFor, DateTime.utc(2026, 12, 5, 10));
      expect(flag.householdIds, ['h-1', 'h-2']);
      expect(await cleaner.readFlag(_other), isNull);
    });

    test('is removed by clearFlag', () async {
      await cleaner.setFlag(_me, DateTime.utc(2026, 12, 5));
      await cleaner.clearFlag(_me);
      expect(await cleaner.readFlag(_me), isNull);
    });

    test('a corrupt flag reads as no flag and does not throw', () async {
      SharedPreferences.setMockInitialValues({LocalAccountDataCleaner.flagKey(_me): 'not json {'});
      expect(await cleaner.readFlag(_me), isNull);
    });
  });

  group('wipeDueUsers', () {
    final now = DateTime.utc(2026, 12, 5, 12);

    test('wipes a flagged user whose date has passed', () async {
      await enqueue(_me);
      await cleaner.setFlag(_me, now.subtract(const Duration(minutes: 1)));

      expect(await cleaner.wipeDueUsers(now: now), [_me]);
      expect(await remainingIds(), isEmpty);
      expect(await cleaner.readFlag(_me), isNull);
    });

    test('leaves a flagged user whose date is still ahead', () async {
      final mine = await enqueue(_me);
      await cleaner.setFlag(_me, now.add(const Duration(minutes: 1)));

      expect(await cleaner.wipeDueUsers(now: now), isEmpty);
      expect(await remainingIds(), [mine]);
      expect(await cleaner.readFlag(_me), isNotNull);
    });

    test('leaves users with no flag', () async {
      final mine = await enqueue(_me);
      expect(await cleaner.wipeDueUsers(now: now), isEmpty);
      expect(await remainingIds(), [mine]);
    });

    test('skips the signed-in user: the server still decides for them', () async {
      final mine = await enqueue(_me);
      await enqueue(_other);
      await cleaner.setFlag(_me, now.subtract(const Duration(days: 1)));
      await cleaner.setFlag(_other, now.subtract(const Duration(days: 1)));

      expect(await cleaner.wipeDueUsers(now: now, exceptUserId: _me), [_other]);
      expect(await remainingIds(), [mine]);
      expect(await cleaner.readFlag(_me), isNotNull);
    });

    test('with B signed in, removes only A\'s items, cached household and flag', () async {
      // B is signed in with payday 10 and reminders scheduled. A, who shared B's
      // household, was flagged and their date has passed.
      const userA = 'user-a';
      const userB = 'user-b';
      SharedPreferences.setMockInitialValues({
        HouseholdResolver.cacheKeyFor(userA): 'h-shared',
        HouseholdResolver.cacheKeyFor(userB): 'h-shared',
        HouseholdSetupPrefs.paydayConfirmedKey('h-shared'): true,
        HouseholdSetupPrefs.hiddenKey('h-shared'): true,
        SalaryCycleService.paydayPrefKey: 10,
      });
      SalaryCycleService.paydayDay = 10;
      final remindersOfB = <String>['bill-rent', 'installment-car'];
      var statementsOfB = 1;
      var signedUrlsOfB = 3;
      final shared = LocalAccountDataCleaner(
        queue: queue,
        cancelReminders: () async => remindersOfB.clear(),
        deleteStatements: () async => statementsOfB = 0,
        clearSignedUrls: () => signedUrlsOfB = 0,
      );
      await enqueue(userA, householdId: 'h-shared', images: ['aGVsbG8=']);
      final itemOfB = await enqueue(userB, householdId: 'h-shared');
      await shared.setFlag(userA, now.subtract(const Duration(days: 1)), householdIds: const ['h-shared']);

      expect(await shared.wipeDueUsers(now: now, exceptUserId: userB), [userA]);

      final prefs = await SharedPreferences.getInstance();
      expect(await remainingIds(), [itemOfB]);
      expect(prefs.containsKey(HouseholdResolver.cacheKeyFor(userA)), isFalse);
      expect(await shared.readFlag(userA), isNull);
      // Everything of B's, and of the household B is in, stays.
      expect(prefs.getString(HouseholdResolver.cacheKeyFor(userB)), 'h-shared');
      expect(prefs.getInt(SalaryCycleService.paydayPrefKey), 10);
      expect(SalaryCycleService.paydayDay, 10);
      expect(remindersOfB, ['bill-rent', 'installment-car']);
      expect(statementsOfB, 1);
      expect(signedUrlsOfB, 3);
      expect(prefs.getBool(HouseholdSetupPrefs.paydayConfirmedKey('h-shared')), isTrue);
      expect(prefs.getBool(HouseholdSetupPrefs.hiddenKey('h-shared')), isTrue);
    });

    test('with nobody signed in still touches nothing device-wide', () async {
      SharedPreferences.setMockInitialValues({SalaryCycleService.paydayPrefKey: 10});
      SalaryCycleService.paydayDay = 10;
      await enqueue(_me);
      await cleaner.setFlag(_me, now.subtract(const Duration(days: 1)));

      expect(await cleaner.wipeDueUsers(now: now), [_me]);

      expect(await remainingIds(), isEmpty);
      expect(reminderCancels, 0);
      expect(statementDeletes, 0);
      expect(urlClears, 0);
      expect(SalaryCycleService.paydayDay, 10);
      expect((await SharedPreferences.getInstance()).getInt(SalaryCycleService.paydayPrefKey), 10);
    });
  });

  group('wipeUserData', () {
    test('removes the queue items, the cached household and the flag, and nothing device-wide', () async {
      SharedPreferences.setMockInitialValues({
        HouseholdResolver.cacheKeyFor(_me): 'h-active',
        HouseholdSetupPrefs.hiddenKey('h-active'): true,
        SalaryCycleService.paydayPrefKey: 15,
      });
      SalaryCycleService.paydayDay = 15;
      await enqueue(_me);
      final theirs = await enqueue(_other);
      await cleaner.setFlag(_me, DateTime.utc(2026, 12, 5));

      expect(await cleaner.wipeUserData(_me), isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(await remainingIds(), [theirs]);
      expect(prefs.containsKey(HouseholdResolver.cacheKeyFor(_me)), isFalse);
      expect(await cleaner.readFlag(_me), isNull);
      expect(prefs.getBool(HouseholdSetupPrefs.hiddenKey('h-active')), isTrue);
      expect(prefs.getInt(SalaryCycleService.paydayPrefKey), 15);
      expect(SalaryCycleService.paydayDay, 15);
      expect(reminderCancels, 0);
      expect(statementDeletes, 0);
      expect(urlClears, 0);
    });

    test('keepFlag leaves the flag for the signed-out wipe, which still finds the households', () async {
      SharedPreferences.setMockInitialValues({
        HouseholdResolver.cacheKeyFor(_me): 'h-active',
        HouseholdSetupPrefs.hiddenKey('h-active'): true,
        HouseholdSetupPrefs.hiddenKey('h-second'): true,
      });
      await cleaner.setFlag(_me, DateTime.utc(2026, 12, 5), householdIds: const ['h-active', 'h-second']);

      await cleaner.wipeUserData(_me, keepFlag: true);
      expect(await cleaner.readFlag(_me), isNotNull);

      await cleaner.wipeForUser(_me);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(HouseholdSetupPrefs.hiddenKey('h-active')), isFalse);
      expect(prefs.containsKey(HouseholdSetupPrefs.hiddenKey('h-second')), isFalse);
      expect(await cleaner.readFlag(_me), isNull);
      expect(reminderCancels, 1);
    });
  });

  group('temporary statements', () {
    test('deleteTemporaryStatements removes the folder and tolerates its absence', () async {
      final dir = Directory(p.join(blobs.path, StatementPdfService.folderName));
      await dir.create();
      await File(p.join(dir.path, 'statement.pdf')).writeAsString('pdf');

      await StatementPdfService.deleteTemporaryStatements(directory: () async => dir);
      expect(await dir.exists(), isFalse);
      await StatementPdfService.deleteTemporaryStatements(directory: () async => dir);
    });
  });
}
