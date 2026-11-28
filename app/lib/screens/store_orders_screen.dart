import 'package:budget_core/budget_core.dart';
import 'package:budget_migration/budget_migration.dart';
import 'package:flutter/material.dart';

import '../services.dart';
import '../theme.dart';
import '../widgets.dart';

/// Store item names (issue 4): read an Amazon, Walmart or AliExpress order
/// history export, or a Gmail Takeout export of their order emails, on the
/// phone, match its orders to bank lines by store, amount and date, and
/// offer the item names as a memo or as split lines. The file is read in
/// memory and never kept; nothing is signed in to. Every offer waits for a
/// tap. A Reviewed line only takes the names in its memo, and split lines
/// stay Unreviewed (ADR 0003).
class StoreOrdersScreen extends StatefulWidget {
  const StoreOrdersScreen({
    super.key,
    required this.engine,
    required this.services,
  });

  final BudgetEngine engine;
  final AppServices services;

  @override
  State<StoreOrdersScreen> createState() => _StoreOrdersScreenState();
}

class _StoreOrdersScreenState extends State<StoreOrdersScreen> {
  var _store = Store.amazon;
  List<StoreCharge>? _charges;
  final _applied = <String>{};
  var _busy = false;
  var _error = '';

  BudgetState get _state => widget.engine.state;

  List<StoreMatch> get _matches => [
    for (final match in matchStoreOrders(_state, _charges ?? const []))
      if (!_applied.contains(match.transaction.id)) match,
  ];

  Future<void> _choose() =>
      _read(['csv', 'zip'], (bytes) => readStoreOrders(bytes, _store));

  Future<void> _chooseEmails() => _read(['mbox', 'zip'], readOrderEmails);

  Future<void> _read(
    List<String> extensions,
    List<StoreCharge> Function(List<int> bytes) read,
  ) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final bytes = await widget.services.keepUnlocked(
        () => widget.services.loader.pick(extensions: extensions),
      );
      if (bytes == null) return;
      final charges = read(bytes);
      if (mounted) {
        setState(() {
          _charges = charges;
          _applied.clear();
        });
      }
    } on StoreOrdersException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Exception {
      if (mounted) {
        setState(() => _error = 'Could not read that file.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Puts the item names in the memo, after any memo already there.
  void _addNames(StoreMatch match) {
    final memo = match.transaction.memo.trim();
    final names = match.memo();
    _apply(
      match,
      EditTransaction(
        transactionId: match.transaction.id,
        memo: memo.isEmpty || memo.contains(names) ? names : '$memo; $names',
        // The button says it only adds names to the memo, and the amount
        // and lines stay as they were reconciled.
        confirmReconciled: true,
      ),
    );
  }

  /// One line per item, each with its name and no Category yet.
  void _split(StoreMatch match) => _apply(
    match,
    EditTransaction(
      transactionId: match.transaction.id,
      lines: match.splitLines(),
    ),
  );

  void _apply(StoreMatch match, Command command) {
    final result = widget.engine.execute(command);
    setState(() {
      if (result is Accepted) {
        _applied.add(match.transaction.id);
      } else {
        _error = 'Could not change that transaction.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final charges = _charges;
    final matches = _matches;
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 16, 16, 4),
              child: Row(
                spacing: 4,
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Back',
                    constraints: const BoxConstraints.tightFor(
                      width: 44,
                      height: 44,
                    ),
                    icon: const Icon(Icons.chevron_left, color: Palette.ink),
                  ),
                  const Expanded(
                    child: Text(
                      'Store item names',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  SegmentedButton<Store>(
                    segments: [
                      for (final store in Store.values)
                        ButtonSegment(value: store, label: Text(store.label)),
                    ],
                    selected: {_store},
                    onSelectionChanged: (selected) => setState(() {
                      _store = selected.first;
                      _charges = null;
                      _applied.clear();
                      _error = '';
                    }),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    key: const ValueKey('store-choose-file'),
                    onPressed: _busy ? null : _choose,
                    child: Text('Choose ${_store.label} order history'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    key: const ValueKey('store-choose-emails'),
                    onPressed: _busy ? null : _chooseEmails,
                    child: const Text('Choose order emails from Gmail'),
                  ),
                  if (_error.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Palette.problemText,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  if (charges == null)
                    Hint(
                      'Download your order history from ${_store.label}'
                      '’s privacy or account page, then choose the CSV or '
                      'zip here. Or label your Amazon, Walmart and '
                      'AliExpress order emails in Gmail, export that label '
                      'with Google Takeout and choose its .mbox or zip. The '
                      'file stays on this phone and is not kept.',
                    )
                  else ...[
                    Text(
                      '${charges.length} orders read · '
                      '${matches.length} match a bank line',
                      key: const ValueKey('store-summary'),
                      style: const TextStyle(
                        fontSize: 13,
                        color: Palette.muted,
                      ),
                    ),
                    for (final match in matches) ...[
                      const SizedBox(height: 12),
                      _MatchCard(
                        state: _state,
                        match: match,
                        onAddNames: () => _addNames(match),
                        onSplit: match.canSplit && match.charge.items.length > 1
                            ? () => _split(match)
                            : null,
                      ),
                    ],
                    if (matches.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Hint(
                        'Nothing changes until you tap. A Reviewed line only '
                        'takes the names in its memo. Split lines have no '
                        'Category yet and wait in Review like any other.',
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MatchCard extends StatelessWidget {
  const _MatchCard({
    required this.state,
    required this.match,
    required this.onAddNames,
    required this.onSplit,
  });

  static const _shown = 5;

  final BudgetState state;
  final StoreMatch match;
  final VoidCallback onAddNames;
  final VoidCallback? onSplit;

  @override
  Widget build(BuildContext context) {
    final transaction = match.transaction;
    final items = match.charge.items;
    final account = state.account(transaction.accountId)?.name ?? '';
    return CardBox(
      key: ValueKey('store-match-${transaction.id}'),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 12,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Text(
                      transaction.payee.isEmpty
                          ? 'No payee'
                          : transaction.payee,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      '${formatDay(transaction.date)} · $account',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Palette.muted,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                formatSigned(transaction.amount),
                style: amountStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const Divider(height: 1, color: Palette.divider),
          for (final item in items.take(_shown))
            Row(
              spacing: 12,
              children: [
                Expanded(
                  child: Text(
                    item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
                if (item.amount.isPositive)
                  Text(
                    formatSigned(-item.amount),
                    style: amountStyle(fontSize: 14),
                  ),
              ],
            ),
          if (items.length > _shown)
            Text(
              'and ${items.length - _shown} more',
              style: const TextStyle(fontSize: 13, color: Palette.muted),
            ),
          Row(
            spacing: 8,
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('store-add-names'),
                  onPressed: onAddNames,
                  child: const Text('Add item names'),
                ),
              ),
              if (onSplit != null)
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('store-split'),
                    onPressed: onSplit,
                    child: const Text('Split by item'),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
