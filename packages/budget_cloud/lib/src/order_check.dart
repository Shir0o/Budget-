import 'package:budget_core/budget_core.dart';
import 'package:budget_migration/orders.dart';
import 'package:budget_sync/core.dart';

import 'cloud_mcp.dart';

/// The cloud server's daily order-email check (issue 4): the Worker hands
/// over the raw Amazon, Walmart and AliExpress emails it found in Gmail,
/// this reads their orders with plain code (no AI), and keeps them as order
/// offers in a sealed file in the server's own Drive folder. The app
/// matches them to bank lines under Store item names, where a person
/// applies each one; nothing here changes the budget (ADR 0003).
final class OrderCheck {
  OrderCheck({
    required this.drive,
    required this.config,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final DriveGateway drive;
  final CloudConfig config;
  final DateTime Function() _now;

  /// How long an order stays offered, so the app can still match it after
  /// a card posts late or the phone wasn't opened for a while.
  static const keepDays = 120;

  /// Reads [messages], each one raw email, merges their orders into the
  /// offers already kept, and saves them. Returns what it found, or why it
  /// failed, as one line.
  Future<({String text, bool isError})> run(List<String> messages) async {
    final found = [
      for (final message in messages) ...orderChargesFromMessage(message),
    ];
    final pairing = config.pairing;
    final client = SyncClient(drive: drive, snapshotEvery: 0);
    final List<Map<String, Object?>> bodies;
    try {
      bodies = await client.readOrderOffers(
        budgetId: pairing.budgetId,
        key: pairing.key,
      );
    } on DriveException catch (error) {
      return (text: error.message, isError: true);
    } on SyncException catch (error) {
      return (text: error.message, isError: true);
    }
    final kept = [
      for (final body in bodies)
        if (body['deviceId'] == config.deviceId)
          for (final json in body['charges'] as List? ?? const [])
            ?StoreCharge.fromJson(json),
    ];
    final today = CivilDate.fromDateTime(_now());
    final oldest = today.addDays(-keepDays);
    final seen = <String>{};
    final charges = [
      for (final charge in [...found, ...kept])
        if (charge.date.compareTo(oldest) >= 0 &&
            seen.add(
              '${charge.store.name}|${charge.orderId}|'
              '${charge.items.length}|${charge.total.cents}',
            ))
          charge,
    ];
    final error = await client.writeOrderOffers(
      budgetId: pairing.budgetId,
      deviceId: config.deviceId,
      key: pairing.key,
      body: {
        'version': 1,
        'deviceId': config.deviceId,
        'checkedAt': _now().toUtc().toIso8601String(),
        'charges': [for (final charge in charges) charge.toJson()],
      },
    );
    if (error != null) return (text: error, isError: true);
    return (
      text:
          'Read ${messages.length} emails, found ${found.length} orders, '
          'offering ${charges.length}.',
      isError: false,
    );
  }
}
