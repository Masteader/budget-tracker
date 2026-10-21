import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:budget_tracker/services/household_resolver.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('caches the server answer per user', () async {
    final resolver = HouseholdResolver(fetchRemote: (_) async => 'h-1');
    expect(await resolver.resolve('u-1'), 'h-1');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(HouseholdResolver.cacheKeyFor('u-1')), 'h-1');
  });

  test('falls back to the cached household when offline', () async {
    SharedPreferences.setMockInitialValues({HouseholdResolver.cacheKeyFor('u-1'): 'h-1'});
    final resolver = HouseholdResolver(fetchRemote: (_) async => throw const SocketException('offline'));
    expect(await resolver.resolve('u-1'), 'h-1');
  });

  test('never uses another user\'s cached household', () async {
    SharedPreferences.setMockInitialValues({HouseholdResolver.cacheKeyFor('u-1'): 'h-1'});
    final resolver = HouseholdResolver(fetchRemote: (_) async => throw const SocketException('offline'));
    expect(() => resolver.resolve('u-2'), throwsA(isA<SocketException>()));
  });

  test('a confirmed "no household" clears the cache (left household)', () async {
    SharedPreferences.setMockInitialValues({HouseholdResolver.cacheKeyFor('u-1'): 'h-1'});
    final resolver = HouseholdResolver(fetchRemote: (_) async => null);
    expect(await resolver.resolve('u-1'), isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(HouseholdResolver.cacheKeyFor('u-1')), isNull);
  });
}
