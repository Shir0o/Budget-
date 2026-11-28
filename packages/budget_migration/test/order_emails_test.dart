import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:budget_core/budget_core.dart';
import 'package:budget_migration/budget_migration.dart';
import 'package:test/test.dart';

// Issue 4, order emails. Every sender name, order, item and amount here is
// made up; the layouts follow the stores' emails.

const _amazonOld = '''
From: "Amazon.com" <auto-confirm@amazon.com>
To: someone@example.com
Subject: =?UTF-8?Q?Ordered:_2_=22Sample_Notebook=2C_3-pack...=22?=
Date: Mon, 2 Nov 2026 18:32:10 +0000
MIME-Version: 1.0
Content-Type: multipart/alternative; boundary="b1"

--b1
Content-Type: text/plain; charset=UTF-8
Content-Transfer-Encoding: quoted-printable

    Thanks for your order, Sam!
Order #
111-0000001-0000001
View or edit order
* Sample Notebook, 3-pack, College Ruled, Blue =E2=80=93 Pack of 3
  Quantity: 2
  10.00 USD
* Blue Pens
  1.50 USD
Grand Total:
23.29 USD

--b1
Content-Type: text/html; charset=UTF-8

<html><body><p>Grand Total:</p><p>\$23.29</p></body></html>
--b1--
''';

const _amazonNew = '''
From: auto-confirm@amazon.com
Subject: Ordered 2 items: Toys & Games, Books
Date: Wed, 4 Nov 2026 05:51:00 +0000
Content-Type: text/plain; charset=UTF-8

Sam, thanks for your order!
Order #
111-0000002-0000002
Grand Total:
16.34 USD
''';

final _walmartHtml = '''
<html><head><style>p{margin:0}</style></head><body>
<p>Order date: Sat, Nov 7, 2026</p>
<p>Order number:</p><p>#2000000-11111111</p>
<img src="x.png" alt="quantity 1 item Sample Paper Towels 6 Rolls">
<img src="y.png" alt="quantity 2 item Sample Bananas">
<p>Order total</p><p>Includes all fees, taxes and discounts</p><p>&#36;12.42</p>
<p>You might also like</p><img alt="Something else">
</body></html>''';

final _aliHtml = '''
<html><body>
<p>Order confirmation</p>
<p>Order 1</p><p>8000000000000001</p><p>Sample Fidget Toy ...</p><p>Blue</p><p>x1</p><p>Total</p><p>\$5.42</p>
<p>Order 2</p><p>8000000000000002</p><p>Sample Sticker Pack</p><p>x1</p><p>Total</p><p>\$3.23</p>
</body></html>''';

String _walmart() =>
    '''
From: Walmart <help@walmart.com>
Subject: Thanks for your delivery order, Sam
Date: Sat, 7 Nov 2026 17:25:46 +0000
Content-Type: text/html; charset=UTF-8

$_walmartHtml
''';

String _ali() =>
    '''
From: AliExpress <transaction@notice.aliexpress.com>
Subject: 2 orders confirmed: 8000000000000001 & more
Date: Tue, 6 Oct 2026 19:06:59 +0000
Content-Type: text/html; charset=UTF-8
Content-Transfer-Encoding: base64

${base64.encode(utf8.encode(_aliHtml))}
''';

const _other = '''
From: friend@example.com
Subject: Lunch?
Date: Tue, 6 Oct 2026 19:06:59 +0000

Grand Total: 99.99 USD
''';

String _mbox(List<String> messages) => [
  for (final message in messages)
    'From 1800000000000000000@xxx Mon Nov 02 18:32:10 +0000 2026\n${message.trim()}\n',
].join('\n');

void main() {
  group('readOrderEmails', () {
    final charges = readOrderEmails(
      latin1.encode(
        _mbox([_amazonOld, _amazonNew, _walmart(), _ali(), _other]),
      ),
    );

    test('reads Amazon items, quantities and the grand total', () {
      final order = charges.firstWhere(
        (c) => c.orderId == '111-0000001-0000001',
      );
      expect(order.store, Store.amazon);
      expect(order.date, CivilDate(2026, 11, 2));
      expect(order.total, const Money(2329));
      expect(order.items.map((i) => i.name), [
        'Sample Notebook, 3-pack, College Ruled, Blue – Pack of 3 ×2',
        'Blue Pens',
      ]);
      expect(order.items.first.amount, const Money(2000));
      expect(order.itemsSumToTotal, isFalse);
    });

    test('names newer Amazon orders by their departments', () {
      final order = charges.firstWhere(
        (c) => c.orderId == '111-0000002-0000002',
      );
      expect(order.items.single.name, 'Toys & Games, Books');
      expect(order.total, const Money(1634));
    });

    test('reads Walmart items from picture alt text', () {
      final order = charges.firstWhere((c) => c.store == Store.walmart);
      expect(order.orderId, '2000000-11111111');
      expect(order.date, CivilDate(2026, 11, 7));
      expect(order.total, const Money(1242));
      expect(order.items.map((i) => i.name), [
        'Sample Paper Towels 6 Rolls',
        'Sample Bananas ×2',
      ]);
    });

    test('offers an AliExpress payment whole and order by order', () {
      final ali = charges.where((c) => c.store == Store.aliExpress).toList();
      expect(ali.map((c) => c.total), const [
        Money(865),
        Money(542),
        Money(323),
      ]);
      expect(ali.first.items.map((i) => i.name), [
        'Sample Fidget Toy …',
        'Sample Sticker Pack',
      ]);
      expect(ali.first.itemsSumToTotal, isTrue);
    });

    test('skips other senders', () {
      expect(charges, hasLength(6));
    });

    test('reads the .mbox inside Takeout’s zip', () {
      final archive = Archive()
        ..addFile(
          ArchiveFile.bytes(
            'Takeout/Mail/Orders.mbox',
            latin1.encode(_mbox([_amazonNew])),
          ),
        );
      final zipped = ZipEncoder().encodeBytes(archive);
      expect(readOrderEmails(zipped).single.orderId, '111-0000002-0000002');
    });
  });

  group('matching order emails', () {
    late BudgetEngine engine;
    late String account;

    setUp(() {
      engine = BudgetEngine(
        log: InMemoryEventLog(),
        deviceId: 'test',
        actor: Actor.userAndroid,
      );
      engine.execute(const CreateBudget(name: 'Home'));
      engine.execute(
        AddAccount(
          name: 'Card',
          type: AccountType.checking,
          startingBalance: const Money(100000),
          asOf: CivilDate(2026, 10, 1),
        ),
      );
      account = engine.state.accounts.single.id;
      engine.execute(
        ImportBankTransactions(
          entries: [
            BankEntry(
              accountId: account,
              bankId: 'a',
              date: CivilDate(2026, 11, 4),
              amount: const Money(-2329),
              description: 'AMZN Mktp US*SAMPLE',
            ),
            BankEntry(
              accountId: account,
              bankId: 'b',
              date: CivilDate(2026, 10, 7),
              amount: const Money(-865),
              description: 'ALIPAY ALIEXPRESS',
            ),
          ],
        ),
      );
    });

    test('offers names for a Reviewed line, but no split', () {
      final amazon = engine.state.transactions.firstWhere(
        (t) => t.amount == const Money(-2329),
      );
      final group =
          (engine.execute(
                const CreateCategoryGroup(name: 'Everyday'),
              ) as Accepted).events.single.payload['categoryGroupId']
              as String;
      final category =
          (engine.execute(
                CreateCategory(groupId: group, name: 'Stuff'),
              ) as Accepted).events.single.payload['categoryId']
              as String;
      expect(
        engine.execute(
          ReviewLine(
            transactionId: amazon.id,
            lineId: amazon.lines.single.id,
            category: category,
            business: const Personal(),
          ),
        ),
        isA<Accepted>(),
      );
      final matches = matchStoreOrders(
        engine.state,
        readOrderEmails(latin1.encode(_mbox([_amazonOld]))),
      );
      expect(matches.single.canSplit, isFalse);
      expect(matches.single.memo(), contains('Blue Pens'));
    });

    test('an applied memo is not offered again', () {
      final charges = readOrderEmails(latin1.encode(_mbox([_ali()])));
      final match = matchStoreOrders(engine.state, charges).single;
      expect(match.canSplit, isTrue);
      engine.execute(
        EditTransaction(
          transactionId: match.transaction.id,
          memo: match.memo(),
        ),
      );
      expect(matchStoreOrders(engine.state, charges), isEmpty);
    });
  });
}
