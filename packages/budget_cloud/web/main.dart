// The JavaScript entry the Cloudflare Worker in mcp/ loads (ADR 0004). Built
// with `dart compile js -O2 web/main.dart -o ../../mcp/src/budget.dart.js`.
// The Worker does OAuth and MCP's JSON-RPC; this file runs the tools.
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:budget_cloud/budget_cloud.dart';
import 'package:budget_sync/core.dart';
import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

@JS('budgetMcp')
external set _budgetMcp(JSFunction handler);

@JS('console.error')
external void _log(JSString message);

@JS('fetch')
external JSPromise<_Response> _fetch(JSString url, _RequestInit init);

extension type _RequestInit._(JSObject _) implements JSObject {
  external factory _RequestInit({
    required JSString method,
    required JSAny headers,
    JSAny? body,
  });
}

extension type _Response._(JSObject _) implements JSObject {
  external int get status;
  external JSPromise<JSArrayBuffer> arrayBuffer();
}

/// Google Drive over the Worker's own fetch.
final class _FetchTransport implements DriveTransport {
  @override
  Future<DriveResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    Uint8List? body,
  }) async {
    try {
      final response = await _fetch(
        uri.toString().toJS,
        _RequestInit(
          method: method.toJS,
          headers: headers.jsify()!,
          body: body?.toJS,
        ),
      ).toDart;
      final bytes = (await response.arrayBuffer().toDart).toDart;
      return DriveResponse(status: response.status, body: bytes.asUint8List());
    } on Object {
      throw const DriveException('Couldn’t reach Google Drive');
    }
  }
}

final class _Token implements DriveAccess {
  const _Token(this.token);

  final String token;

  @override
  Future<String?> accessToken() async => token;
}

/// One request from the Worker, as JSON:
/// `{config: {pairingCode, mode, writeTools, deviceId}, accessToken,
/// method: "list" | "call" | "orders", name, arguments, client, messages}`.
/// Answers `{tools: [...]}` for list and `{text, isError}` for call and for
/// orders, the daily check of order emails (each message one raw email).
Future<String> _handle(String json) async {
  try {
    final request = (jsonDecode(json) as Map).cast<String, Object?>();
    final config = (request['config'] as Map).cast<String, Object?>();
    final drive = GoogleDriveAppData(
      transport: _FetchTransport(),
      access: _Token(request['accessToken'] as String? ?? ''),
    );
    final cloudConfig = CloudConfig.parse(
      pairingCode: config['pairingCode'] as String? ?? '',
      mode: config['mode'] as String?,
      writeTools: config['writeTools'] as String?,
      deviceId: config['deviceId'] as String?,
    );
    if (request['method'] == 'orders') {
      final result = await OrderCheck(drive: drive, config: cloudConfig).run([
        for (final message in request['messages'] as List? ?? const [])
          if (message is String) message,
      ]);
      return jsonEncode({'text': result.text, 'isError': result.isError});
    }
    final cloud = CloudMcp(drive: drive, config: cloudConfig);
    if (request['method'] == 'list') {
      return jsonEncode({'tools': cloud.toolList});
    }
    final result = await cloud.call(
      request['name'] as String? ?? '',
      (request['arguments'] as Map?)?.cast<String, Object?>() ?? const {},
      client: request['client'] as String? ?? '',
    );
    return jsonEncode({'text': result.text, 'isError': result.isError});
  } on SyncException catch (error) {
    return _error(error.message);
  } on ArgumentError catch (error) {
    // Settings the Worker was deployed with; never echoes the pairing code.
    return _error('The server’s settings are wrong: ${error.message}');
  } on Object catch (error, stack) {
    _log('budget-cloud: $error\n$stack'.toJS);
    return _error('Something went wrong reading the budget.');
  }
}

String _error(String message) => jsonEncode({
  'text': jsonEncode({'error': message}),
  'isError': true,
});

void main() {
  // A Worker has no `window`, so the package's browser check fails. The
  // pure Dart ciphers need nothing from the host but random bytes.
  Cryptography.instance = DartCryptography.defaultInstance;
  _budgetMcp = ((JSString json) => _handle(
    json.toDart,
  ).then((text) => text.toJS).toJS).toJS;
}
