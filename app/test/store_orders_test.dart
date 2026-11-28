import 'dart:convert';
import 'dart:typed_data';

import 'package:budget/screens/store_orders_screen.dart';
import 'package:budget/services.dart';
import 'package:budget_core/budget_core.dart';
import 'package:budget_migration/budget_migration.dart';
import 'package:budget_sync/budget_sync.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Issue 4. Every order, item and amount here is made up.
const _csv = '''
Date,Order,Item,Amount
11/05/2026,W-1,Paper towels,12.48
11/05/2026,W-1,Bananas,1.52
''';

BudgetEngine _engine() {
  final engine = BudgetEngine(
    log: InMemoryEventLog(),
    deviceId: 'test-device',
    actor: Actor.userAndroid,
  );
  engine.execute(const CreateBudget(name: 'Home'));
  engine.execute(
    AddAccount(
      name: 'Checking',
      type: AccountType.checking,
      startingBalance: const Money(100000),
      asOf: CivilDate(2026, 11, 1),
    ),
  );
  engine.execute(
    ImportBankTransactions(
      entries: [
        BankEntry(
          accountId: engine.state.accounts.single.id,
          bankId: 'b-1',
          date: CivilDate(2026, 11, 6),
          amount: const Money(-1400),
          description: 'WALMART SUPERCENTER',
        ),
      ],
    ),
  );
  return engine;
}

Future<(BudgetEngine, AppServices)> _open(WidgetTester tester) async {
  final engine = _engine();
  final services = AppServices.inMemory();
  (services.loader as InMemoryFileLoader).next = Uint8List.fromList(
    utf8.encode(_csv),
  );
  await tester.pumpWidget(
    MaterialApp(
      home: StoreOrdersScreen(engine: engine, services: services),
    ),
  );
  await tester.tap(find.text('Walmart'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('store-choose-file')));
  await tester.pumpAndSettle();
  return (engine, services);
}

Transaction _line(BudgetEngine engine) => engine.state.transactions.singleWhere(
  (t) => t.payee == 'WALMART SUPERCENTER',
);

/// A Walmart order email in a Takeout mbox, made up.
const _mbox = '''
From 1800000000000000000@xxx Fri Nov 06 17:00:00 +0000 2026
From: Walmart <help@walmart.com>
Subject: Thanks for your order, Sam
Date: Thu, 5 Nov 2026 17:00:00 +0000
Content-Type: text/html; charset=UTF-8

<p>Order number:</p><p>#2000000-22222222</p>
<img alt="quantity 1 item Sample Paper Towels">
<p>Order total</p><p>\$14.00</p>
''';

void main() {
  testWidgets('offers orders the daily Gmail check left in Drive', (
    tester,
  ) async {
    final engine = _engine();
    final services = AppServices.inMemory();
    final budgetId = engine.state.budget!.id;
    await tester.runAsync(() async {
      await services.prefs.writeSyncBook(
        budgetId,
        const SyncBook(enabled: true),
      );
      final error = await SyncClient(drive: services.drive).writeOrderOffers(
        budgetId: budgetId,
        deviceId: 'cloud-mcp',
        key: await services.keys.keyFor(budgetId),
        body: {
          'deviceId': 'cloud-mcp',
          'checkedAt': '2026-11-07T15:00:00Z',
          'charges': [
            StoreCharge(
              store: Store.walmart,
              orderId: '2000000-33333333',
              date: CivilDate(2026, 11, 5),
              items: const [
                StoreItem(name: 'Sample Paper Towels', amount: Money.zero),
              ],
              total: const Money(1400),
            ).toJson(),
          ],
        },
      );
      expect(error, isNull);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: StoreOrdersScreen(engine: engine, services: services),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('From your daily Gmail check'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('store-add-names')));
    await tester.pumpAndSettle();
    expect(_line(engine).memo, 'Sample Paper Towels');
  });

  testWidgets('order emails add names to a Reviewed line', (tester) async {
    final engine = _engine();
    final line = _line(engine);
    final group =
        (engine.execute(
              const CreateCategoryGroup(name: 'Everyday'),
            ) as Accepted).events.single.payload['categoryGroupId']
            as String;
    final category =
        (engine.execute(
              CreateCategory(groupId: group, name: 'Home'),
            ) as Accepted).events.single.payload['categoryId']
            as String;
    engine.execute(
      ReviewLine(
        transactionId: line.id,
        lineId: line.lines.single.id,
        category: category,
        business: const Personal(),
      ),
    );
    final services = AppServices.inMemory();
    (services.loader as InMemoryFileLoader).next = Uint8List.fromList(
      latin1.encode(_mbox),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: StoreOrdersScreen(engine: engine, services: services),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('store-choose-emails')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('store-split')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('store-add-names')));
    await tester.pumpAndSettle();
    final edited = _line(engine);
    expect(edited.memo, 'Sample Paper Towels');
    expect(edited.lines.single.reviewed, isTrue);
  });

  testWidgets('splitting a matched order keeps every line unreviewed', (
    tester,
  ) async {
    final (engine, _) = await _open(tester);
    expect(find.text('1 orders read · 1 match a bank line'), findsOneWidget);
    expect(find.text('Paper towels'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('store-split')));
    await tester.pumpAndSettle();

    final transaction = _line(engine);
    expect(
      [for (final l in transaction.lines) l.memo],
      ['Paper towels', 'Bananas'],
    );
    expect(transaction.lines.every((l) => !l.reviewed), isTrue);
    expect(transaction.lines.every((l) => l.category == null), isTrue);
    expect(find.text('1 orders read · 0 match a bank line'), findsOneWidget);
  });

  testWidgets('adding item names only sets the memo', (tester) async {
    final (engine, _) = await _open(tester);

    await tester.tap(find.byKey(const ValueKey('store-add-names')));
    await tester.pumpAndSettle();

    final transaction = _line(engine);
    expect(transaction.memo, 'Paper towels; Bananas');
    expect(transaction.lines, hasLength(1));
    expect(transaction.lines.single.reviewed, isFalse);
  });
}
