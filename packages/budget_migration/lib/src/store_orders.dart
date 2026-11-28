import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:budget_core/budget_core.dart';

import 'ynab_export.dart' show readCsv;

// Store item names on bank lines (issue 4): read an order history file a
// person exported from Amazon (or a simple CSV for Walmart or any store),
// match each charge to a bank line by amount and date, and offer the item
// names as a memo or as split lines. The file stays on the device, nothing
// signs in to a store, and a person still reviews every line (ADR 0003).

/// The stores whose bank lines can carry item names.
enum Store {
  amazon('Amazon', ['amazon', 'amzn']),
  walmart('Walmart', ['walmart', 'walmrt', 'walmart.com', 'wmsupercenter']),
  aliExpress('AliExpress', ['aliexpress', 'alipay']);

  const Store(this.label, this._payeeWords);

  final String label;
  final List<String> _payeeWords;

  /// Whether a bank payee looks like this store, such as `AMZN Mktp US*2K4`
  /// or `WAL-MART #1234`.
  bool matchesPayee(String payee) {
    final normalized = payee.toLowerCase().replaceAll(RegExp(r'[^a-z.]'), '');
    return _payeeWords.any(normalized.contains);
  }
}

/// One item in an order.
final class StoreItem {
  const StoreItem({required this.name, required this.amount});

  final String name;

  /// What the item cost, tax included, positive.
  final Money amount;
}

/// One charge a store expects to make: a whole order, or one shipment of
/// it, since Amazon charges each shipment on its own.
final class StoreCharge {
  const StoreCharge({
    required this.store,
    required this.orderId,
    required this.date,
    required this.items,
    Money? total,
  }) : _total = total; // ignore: prefer_initializing_formals

  final Store store;
  final String orderId;

  /// When the store charged or should have: the ship date if the file has
  /// one, otherwise the order date.
  final CivilDate date;
  final List<StoreItem> items;

  final Money? _total;

  /// What the charge comes to, positive: the total the store gave (an order
  /// email's grand total, with tax and shipping), else its items' sum.
  Money get total => _total ?? itemSum;

  /// What the items add up to.
  Money get itemSum =>
      items.fold(Money.zero, (total, item) => total + item.amount);

  /// Whether the items can become split lines: each has a price and they add
  /// up to the charge.
  bool get itemsSumToTotal =>
      items.every((item) => item.amount.isPositive) && itemSum == total;
}

/// An order history file that couldn't be read.
final class StoreOrdersException implements Exception {
  const StoreOrdersException(this.message);

  final String message;

  @override
  String toString() => message;
}

const _dateColumns = ['ship date', 'order date', 'date'];
const _orderColumns = ['order id', 'order number', 'order #', 'order'];
const _itemColumns = ['product name', 'item', 'item name', 'product', 'name'];
const _amountColumns = ['total owed', 'item total', 'amount', 'total', 'price'];

/// Reads [bytes], an Amazon "Your Orders" export (the
/// `Retail.OrderHistory` CSV, alone or in the zip Amazon sends) or any CSV
/// with date, item and amount columns (and optionally an order column), into
/// the charges [store] should have made.
///
/// Rows of one order that share a ship date are one charge. An order with
/// several shipments also offers its whole total, since some cards see one
/// charge. Cancelled rows and rows with no amount are skipped.
List<StoreCharge> readStoreOrders(List<int> bytes, Store store) {
  final text = _csvText(bytes);
  final rows = readCsv(text);
  if (rows.isEmpty) {
    throw const StoreOrdersException('That file is empty.');
  }
  final header = {
    for (final (index, name) in rows.first.indexed)
      name.trim().toLowerCase(): index,
  };
  int? column(List<String> names) {
    for (final name in names) {
      if (header[name] case final index?) return index;
    }
    return null;
  }

  final orderDate = column(['order date', 'date']);
  final shipDate = column(['ship date']);
  final order = column(_orderColumns);
  final item = column(_itemColumns);
  final amount = column(_amountColumns);
  final quantity = column(['quantity']);
  final status = column(['order status', 'status']);
  if (column(_dateColumns) == null || item == null || amount == null) {
    throw const StoreOrdersException(
      'That file needs date, item and amount columns, like Amazon’s order '
      'history export.',
    );
  }

  String cell(List<String> row, int? index) =>
      index == null || index >= row.length ? '' : row[index].trim();

  // Order id → ship date → items, in file order.
  final orders = <String, Map<CivilDate, List<StoreItem>>>{};
  final orderDates = <String, CivilDate>{};
  for (final (number, row) in rows.skip(1).indexed) {
    if (cell(row, status).toLowerCase().startsWith('cancel')) continue;
    final cost = _money(cell(row, amount));
    final placed = _date(cell(row, orderDate));
    final shipped = _date(cell(row, shipDate));
    final name = cell(row, item);
    if (cost == null || !cost.isPositive || (placed ?? shipped) == null) {
      continue;
    }
    final id = switch (cell(row, order)) {
      '' => 'row-$number',
      final id => id,
    };
    final count = int.tryParse(cell(row, quantity)) ?? 1;
    orderDates.putIfAbsent(id, () => (placed ?? shipped)!);
    orders
        .putIfAbsent(id, () => {})
        .putIfAbsent(shipped ?? (placed ?? shipped)!, () => [])
        .add(
          StoreItem(
            name: count > 1 ? '$name ×$count' : (name.isEmpty ? 'Item' : name),
            amount: cost,
          ),
        );
  }

  return [
    for (final MapEntry(key: id, value: shipments) in orders.entries) ...[
      for (final MapEntry(key: date, value: items) in shipments.entries)
        StoreCharge(store: store, orderId: id, date: date, items: items),
      if (shipments.length > 1)
        StoreCharge(
          store: store,
          orderId: id,
          date: orderDates[id]!,
          items: [for (final items in shipments.values) ...items],
        ),
    ],
  ];
}

/// How many days before a charge's date a bank line may be dated.
const storeMatchDaysBefore = 2;

/// How many days after a charge's date a bank line may be dated: cards can
/// take a few days to post.
const storeMatchDaysAfter = 7;

/// A bank line and the store charge it looks like.
final class StoreMatch {
  const StoreMatch({required this.transaction, required this.charge});

  final Transaction transaction;
  final StoreCharge charge;

  /// The item names as one memo, at most [maxLength] characters, with card
  /// and account numbers masked so the memo can be stored.
  String memo({int maxLength = 200}) {
    final text = maskSensitiveNumbers(
      charge.items.map((item) => item.name).join('; '),
    );
    return text.length <= maxLength
        ? text
        : '${text.substring(0, maxLength - 1)}…';
  }

  /// Whether the names are already in the transaction's memo.
  bool get applied {
    final memo = transaction.memo;
    return memo.isNotEmpty && memo.contains(this.memo());
  }

  /// Whether the bank line can become one line per item: it's a single
  /// Unreviewed line and the items have prices that add up to it. A Reviewed
  /// line only takes the names in its memo, so nothing a person reviewed
  /// changes (ADR 0003).
  bool get canSplit =>
      transaction.lines.length == 1 &&
      !transaction.lines.single.reviewed &&
      charge.itemsSumToTotal;

  /// One Unreviewed line per item, its name as the line memo, for an
  /// [EditTransaction] that splits the bank line. The lines sum to the
  /// line's amount because the charge matched it exactly.
  List<LineInput> splitLines() => [
    for (final (i, item) in charge.items.indexed)
      LineInput(
        id: i == 0 ? transaction.lines.first.id : null,
        amount: -item.amount,
        memo: maskSensitiveNumbers(item.name),
      ),
  ];
}

/// Pairs bank lines in [state] with [charges]: an outflow that isn't a
/// transfer, doesn't already carry the names, has the store's payee and exactly the
/// charge's total, dated from [storeMatchDaysBefore] before to
/// [storeMatchDaysAfter] after it. Each line and each order matches at most
/// once, the closest date first. A match is only an offer: a person applies
/// it.
List<StoreMatch> matchStoreOrders(
  BudgetState state,
  List<StoreCharge> charges,
) {
  final lines = [
    for (final transaction in state.transactions)
      if (transaction.amount.isNegative &&
          !transaction.isTransfer &&
          charges.any((c) => c.store.matchesPayee(transaction.payee)))
        transaction,
  ];
  final options = <(int, Transaction, StoreCharge)>[];
  for (final transaction in lines) {
    for (final charge in charges) {
      if (-transaction.amount != charge.total ||
          !charge.store.matchesPayee(transaction.payee)) {
        continue;
      }
      final days = _days(charge.date, transaction.date);
      if (days < -storeMatchDaysBefore || days > storeMatchDaysAfter) continue;
      options.add((days.abs(), transaction, charge));
    }
  }
  options.sort((a, b) => a.$1.compareTo(b.$1));
  final usedLines = <String>{};
  final usedCharges = <StoreCharge>{};
  final matches = <StoreMatch>[];
  for (final (_, transaction, charge) in options) {
    if (usedLines.contains(transaction.id) || usedCharges.contains(charge)) {
      continue;
    }
    usedLines.add(transaction.id);
    usedCharges.add(charge);
    final match = StoreMatch(transaction: transaction, charge: charge);
    if (!match.applied) matches.add(match);
  }
  return matches;
}

/// Days from [from] to [to], negative when [to] is earlier.
int _days(CivilDate from, CivilDate to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

/// The CSV text of [bytes], or of the order history CSV inside a zip.
String _csvText(List<int> bytes) {
  final zip = bytes.length > 4 && bytes[0] == 0x50 && bytes[1] == 0x4b;
  if (!zip) return _decode(bytes);
  final archive = ZipDecoder().decodeBytes(bytes);
  for (final file in archive.files) {
    final name = file.name.toLowerCase();
    if (file.isFile && name.endsWith('.csv') && name.contains('orderhistory')) {
      return _decode(file.content);
    }
  }
  throw const StoreOrdersException(
    'That zip has no order history CSV (Retail.OrderHistory).',
  );
}

String _decode(List<int> bytes) {
  var text = String.fromCharCodes(bytes);
  try {
    text = const Utf8Decoder().convert(bytes);
  } on FormatException {
    // Keep the Latin-1 reading.
  }
  return text.startsWith('﻿') ? text.substring(1) : text;
}

/// `12.34`, `$1,234.50` or `USD 9.99` as Money; null for anything else.
Money? _money(String text) => Money.tryParse(
  text.replaceAll(RegExp(r'^(USD|US\$)\s*', caseSensitive: false), ''),
);

/// `2026-11-03`, `2026-11-03T18:32:10Z` or `11/03/2026` as a date; null
/// for anything else, such as `Not Available`.
CivilDate? _date(String text) {
  final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(text);
  final us = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})').firstMatch(text);
  try {
    if (iso != null) {
      return CivilDate(
        int.parse(iso[1]!),
        int.parse(iso[2]!),
        int.parse(iso[3]!),
      );
    }
    if (us != null) {
      return CivilDate(int.parse(us[3]!), int.parse(us[1]!), int.parse(us[2]!));
    }
  } on ArgumentError {
    return null;
  }
  return null;
}
