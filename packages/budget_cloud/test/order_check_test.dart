import 'package:budget_cloud/budget_cloud.dart';
import 'package:budget_core/budget_core.dart';
import 'package:budget_migration/orders.dart';
import 'package:budget_sync/core.dart';
import 'package:test/test.dart';

// Issue 4, the daily order-email check. Every email, order and amount here
// is made up.

String _amazon(String order, String total, {String date = '10 Nov 2026'}) =>
    '''
From: auto-confirm@amazon.com
Subject: Ordered: "Sample Notebook"
Date: Tue, $date 08:00:00 +0000
Content-Type: text/plain; charset=UTF-8

Order #
$order
* Sample Notebook
  10.00 USD
Grand Total:
$total USD
''';

void main() {
  late InMemoryDrive drive;
  late BudgetKey key;
  late String budgetId;
  var now = DateTime.utc(2026, 11, 12);

  setUp(() async {
    drive = InMemoryDrive();
    key = BudgetKey.generate();
    final engine = BudgetEngine(
      log: InMemoryEventLog(),
      deviceId: 'phone',
      actor: Actor.userAndroid,
    );
    engine.execute(const CreateBudget(name: 'Home'));
    budgetId = engine.state.budget!.id;
    final synced = await SyncClient(drive: drive)
        .sync(engine: engine, key: key, book: SyncBook.off);
    expect(synced.error, isNull);
    now = DateTime.utc(2026, 11, 12);
  });

  OrderCheck check() => OrderCheck(
    drive: drive,
    config: CloudConfig(
      pairing: PairingPayload(budgetId: budgetId, key: key),
    ),
    now: () => now,
  );

  Future<List<StoreCharge>> offers() async => [
    for (final body in await SyncClient(
      drive: drive,
    ).readOrderOffers(budgetId: budgetId, key: key))
      for (final json in body['charges'] as List) StoreCharge.fromJson(json)!,
  ];

  test('keeps the orders it reads, sealed, for the app to match', () async {
    final result = await check().run([
      _amazon('111-0000001-0000001', '10.83'),
      'From: friend@example.com\nSubject: Hi\n\nHello',
    ]);

    expect(result.isError, isFalse);
    final charges = await offers();
    expect(charges.single.orderId, '111-0000001-0000001');
    expect(charges.single.total, const Money(1083));
    expect(charges.single.items.single.name, 'Sample Notebook');
  });

  test('a later run adds new orders and keeps one copy of each', () async {
    await check().run([_amazon('111-0000001-0000001', '10.83')]);
    await check().run([
      _amazon('111-0000001-0000001', '10.83'),
      _amazon('111-0000002-0000002', '5.41'),
    ]);

    expect(
      (await offers()).map((c) => c.orderId),
      unorderedEquals(['111-0000001-0000001', '111-0000002-0000002']),
    );
  });

  test('drops orders older than it keeps', () async {
    await check().run([
      _amazon('111-0000001-0000001', '10.83', date: '1 Jun 2026'),
      _amazon('111-0000002-0000002', '5.41'),
    ]);
    now = DateTime.utc(2026, 11, 13);
    await check().run(const []);

    expect((await offers()).map((c) => c.orderId), ['111-0000002-0000002']);
  });

  test('the sync passes over the offers file', () async {
    await check().run([_amazon('111-0000001-0000001', '10.83')]);
    final joined = await SyncClient(drive: drive)
        .join(budgetId: budgetId, key: key);
    expect(joined.error, isNull);
  });
}
