import 'package:budget_core/budget_core.dart';
import 'package:budget_mcp/tools.dart';
import 'package:budget_sync/core.dart';

/// The platform the cloud server's manifest records, beside `android` and
/// `mac`.
const cloudPlatform = 'cloud';

/// What the cloud MCP server may do, from the Worker's settings (ADR 0004).
final class CloudConfig {
  CloudConfig({
    required this.pairing,
    this.mode = McpMode.readOnly,
    Set<String>? writeTools,
    this.deviceId = 'cloud-mcp',
  }) : writeTools = writeTools ?? defaultWriteTools;

  /// Reads the Worker's settings. [pairingCode] is the code the app shows
  /// under Encrypted sync › Pair a device; [mode] is `read-only` (the
  /// default) or `read-write`; [writeTools] is a comma-separated list.
  factory CloudConfig.parse({
    required String pairingCode,
    String? mode,
    String? writeTools,
    String? deviceId,
  }) {
    final tools = writeTools?.trim();
    return CloudConfig(
      pairing: PairingPayload.parse(pairingCode),
      mode: switch (mode?.trim().toLowerCase()) {
        null || '' || 'read-only' || 'readonly' => McpMode.readOnly,
        'read-write' || 'readwrite' => McpMode.readWrite,
        'off' => McpMode.off,
        final other => throw ArgumentError.value(
          other,
          'mode',
          'Use read-only or read-write',
        ),
      },
      writeTools: tools == null || tools.isEmpty
          ? null
          : {
              for (final name in tools.split(','))
                if (name.trim().isNotEmpty) name.trim(),
            },
      deviceId: switch (deviceId?.trim()) {
        null || '' => 'cloud-mcp',
        final id => id,
      },
    );
  }

  /// The write tools a read-write cloud server offers unless told otherwise:
  /// fill a line's Category and Personal/Business (it stays Unreviewed),
  /// fix a payee, date or memo, and revert one of its own changes.
  static const defaultWriteTools = {
    'suggest_review',
    'update_transaction',
    'revert_change',
  };

  /// The budget's Drive folder and the Budget Key that opens it.
  final PairingPayload pairing;
  final McpMode mode;

  /// Write tools offered in Read-write mode. A name that isn't one of
  /// ticket 13's write tools does nothing; nothing can add a tool that
  /// deletes, because none exists. `mark_imported_reviewed`, the one tool
  /// that marks lines Reviewed (only lines an import brought in), is
  /// offered only when named here.
  final Set<String> writeTools;

  /// The Drive folder this server writes its own segments to.
  final String deviceId;
}

/// The MCP tools over the budget in Google Drive (ADR 0004). Every call
/// reads every device's folder with the Budget Key and replays the Events,
/// so it answers from what the phone and the Mac last synced. A write
/// appends one Event group as `mcp:<client>` and uploads it to this
/// server's own folder, the way another device would; nothing is kept
/// between calls.
final class CloudMcp {
  CloudMcp({
    required this.drive,
    required this.config,
    DateTime Function()? now,
    this.nowMs,
  }) : _now = now ?? DateTime.now;

  final DriveGateway drive;
  final CloudConfig config;
  final DateTime Function() _now;

  /// The clock Events are stamped with, for tests.
  final int Function()? nowMs;

  /// The tools this server lists: every read tool, and in Read-write mode
  /// the allowed write tools.
  List<ToolSpec> get tools => [
    if (config.mode.allowsRead) ...BudgetTools.specs,
    if (config.mode.allowsWrite)
      for (final spec in BudgetTools.writeSpecs)
        if (config.writeTools.contains(spec.name)) spec,
  ];

  /// [tools] as MCP's `tools/list` lists them.
  List<Map<String, Object?>> get toolList => [
    for (final spec in tools)
      {
        'name': spec.name,
        'description': spec.description,
        'inputSchema': spec.inputSchema,
        'annotations': {
          'readOnlyHint': !spec.writes,
          // A write tool only adds or edits; nothing is deleted.
          'destructiveHint': false,
          'idempotentHint': !spec.writes,
          'openWorldHint': false,
        },
      },
  ];

  /// Runs one tool call for [client], the MCP client's announced name.
  Future<ToolResult> call(
    String name,
    Map<String, Object?> arguments, {
    String client = '',
  }) async {
    final offered = tools.any((spec) => spec.name == name);
    if (!offered) {
      if (BudgetTools.writeToolNames.contains(name)) {
        return ToolResult.error(
          config.mode.allowsWrite
              ? 'This server doesn’t offer “$name”.'
              : 'This server is read-only.',
        );
      }
      if (!BudgetTools.neverToolNames.contains(name)) {
        return ToolResult.error('No tool named “$name”.');
      }
      // A tool that never exists gets BudgetTools' own refusal below.
    }

    final pairing = config.pairing;
    final joined = await SyncClient(
      drive: drive,
      snapshotEvery: 0,
    ).join(budgetId: pairing.budgetId, key: pairing.key);
    if (joined.error case final error?) return ToolResult.error(error);

    final log = InMemoryEventLog()..append(joined.events);
    final state = BudgetState.replay(log.readAll());
    final budget = McpBudget(
      id: pairing.budgetId,
      name: state.budget?.name ?? 'Budget',
      store: cloudPlatform,
      book: McpBook(mode: config.mode),
      deviceId: config.deviceId,
    );
    final writes = _Writes(log, config.deviceId, nowMs);
    final budgetTools = BudgetTools(
      store: InMemoryMcpStore([budget]),
      events: _Events(log),
      writes: writes,
      now: _now,
    );
    final result = await budgetTools.call(
      ToolRequest(name, arguments),
      client: McpClient(client),
    );
    if (!writes.wrote || result.isError) return result;

    final saved = await _push(log, pairing, joined.events);
    if (saved != null) {
      return ToolResult.error(
        'The change wasn’t saved to Google Drive, so nothing changed: '
        '$saved',
      );
    }
    return result;
  }

  /// Uploads this server's new Events to its own folder. Returns why it
  /// failed, or null. It doesn't pull again: the call just read every
  /// folder, and a Worker has no memory to spare for a second copy.
  Future<String?> _push(
    EventLog log,
    PairingPayload pairing,
    List<Event> before,
  ) async {
    final had = before.where((e) => e.deviceId == config.deviceId).length;
    final own = [
      for (final event in log.readAll())
        if (event.deviceId == config.deviceId) event,
    ];
    return SyncClient(drive: drive, snapshotEvery: 0).push(
      budgetId: pairing.budgetId,
      deviceId: config.deviceId,
      events: own.sublist(had),
      afterSeq: await _latestSeq(pairing.budgetId),
      eventCount: own.length,
      key: pairing.key,
      platform: cloudPlatform,
    );
  }

  /// The highest segment number in this server's own folder, 0 when it has
  /// none, so a new segment never takes an existing file's name.
  Future<int> _latestSeq(String budgetId) async {
    final budgetFolder = await _find(budgetId, null);
    if (budgetFolder == null) return 0;
    final mine = await _find(config.deviceId, budgetFolder);
    if (mine == null) return 0;
    var latest = 0;
    for (final file in await drive.list(mine)) {
      final match = _segment.firstMatch(file.name);
      if (match == null) continue;
      final seq = int.parse(match.group(1)!);
      if (seq > latest) latest = seq;
    }
    return latest;
  }

  Future<String?> _find(String name, String? parent) async {
    for (final entry in await drive.list(parent)) {
      if (entry.isFolder && entry.name == name) return entry.id;
    }
    return null;
  }

  static final _segment = RegExp(r'^seg-(\d+)\.bin$');
}

final class _Events implements EventSource {
  _Events(this._log);

  final EventLog _log;

  @override
  Future<List<Event>> events(McpBudget budget) async => _log.readAll();
}

/// Runs a write tool's Command on the replayed log as this server's device,
/// and remembers that something needs uploading.
final class _Writes implements BudgetWrites {
  _Writes(this._log, this._deviceId, this._nowMs);

  final EventLog _log;
  final String _deviceId;
  final int Function()? _nowMs;
  var wrote = false;

  @override
  Future<CommandResult> write(
    McpBudget budget,
    Command command,
    Actor actor,
  ) async {
    final result = BudgetEngine(
      log: _log,
      deviceId: _deviceId,
      actor: actor,
      nowMs: _nowMs,
    ).execute(command);
    if (result case Accepted(:final events) when events.isNotEmpty) {
      wrote = true;
    }
    return result;
  }
}
