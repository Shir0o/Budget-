import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:budget_core/budget_core.dart';

import 'store_orders.dart';

// Store item names from order emails (issue 4): read the order confirmation
// emails Amazon, Walmart and AliExpress send, from a Google Takeout export
// of Gmail (an .mbox file, alone or in Takeout's zip) or from single raw
// messages, into the charges each store should have made. Plain code reads
// them: no AI, nothing signs in, and every match is still only an offer a
// person applies (ADR 0003).

/// One email as its headers and its text: the plain text part when there is
/// one, otherwise the HTML part turned into lines, with each picture's alt
/// text on a line of its own.
final class OrderEmail {
  const OrderEmail({
    required this.from,
    required this.subject,
    required this.date,
    required this.lines,
  });

  final String from;
  final String subject;
  final CivilDate? date;
  final List<String> lines;
}

/// Reads [bytes], a Gmail Takeout .mbox (alone, or inside Takeout's zip),
/// into the charges its order emails describe. Emails from other senders,
/// and order emails it can't read, are skipped.
List<StoreCharge> readOrderEmails(List<int> bytes) {
  final charges = <StoreCharge>[];
  for (final mbox in _mboxTexts(bytes)) {
    for (final raw in splitMbox(mbox)) {
      charges.addAll(orderChargesFromMessage(raw));
    }
  }
  return _dedupe(charges);
}

/// The charges one raw RFC 822 message describes, or none when it isn't an
/// order confirmation from a store this reads.
List<StoreCharge> orderChargesFromMessage(String raw) {
  final OrderEmail email;
  try {
    email = parseEmail(raw);
  } on FormatException {
    return const [];
  }
  final from = email.from.toLowerCase();
  final subject = email.subject.toLowerCase();
  if (from.contains('amazon.')) {
    if (subject.startsWith('ordered') ||
        subject.contains('your amazon.com order')) {
      return [?_amazon(email)];
    }
  } else if (from.contains('walmart.com')) {
    if (subject.startsWith('thanks for your')) return [?_walmart(email)];
  } else if (from.contains('aliexpress.')) {
    if (subject.contains('confirmed') || subject.contains('payment')) {
      return _aliExpress(email);
    }
  }
  return const [];
}

/// The messages in an mbox, each as its raw text.
List<String> splitMbox(String mbox) {
  final text = mbox.replaceAll('\r\n', '\n');
  final starts = RegExp(r'^From \S.*$', multiLine: true);
  final messages = <String>[];
  int? start;
  for (final match in starts.allMatches(text)) {
    if (match.start != 0 && text[match.start - 1] != '\n') continue;
    if (start != null) {
      messages.add(text.substring(start, match.start));
    }
    start = match.end + 1;
  }
  if (start != null && start < text.length) messages.add(text.substring(start));
  if (messages.isEmpty && text.trim().isNotEmpty) messages.add(text);
  return [
    for (final message in messages)
      message.replaceAllMapped(
        RegExp(r'^>(>*From )', multiLine: true),
        (m) => m[1]!,
      ),
  ];
}

/// Parses one raw message into its sender, subject, date and text.
OrderEmail parseEmail(String raw) {
  final part = _Part.parse(raw.replaceAll('\r\n', '\n'));
  String? plain;
  String? html;
  void walk(_Part part) {
    if (part.isMultipart) {
      part.children.forEach(walk);
    } else if (part.mimeType == 'text/plain' && !part.isAttachment) {
      plain ??= part.text;
    } else if (part.mimeType == 'text/html' && !part.isAttachment) {
      html ??= part.text;
    }
  }

  walk(part);
  final htmlLines = html == null ? const <String>[] : htmlToLines(html!);
  final plainLines = plain == null ? const <String>[] : _lines(plain!);
  return OrderEmail(
    from: decodeHeader(part.header('from')),
    subject: decodeHeader(part.header('subject')),
    date: _headerDate(part.header('date')),
    // Keep both: plain text carries Amazon's full item names, and HTML
    // carries Walmart's (in picture alt text) and AliExpress's.
    lines: [...plainLines, ...htmlLines],
  );
}

/// HTML as trimmed, non-empty lines of text, each picture's alt text on a
/// line of its own.
List<String> htmlToLines(String html) {
  var text = html.replaceAll(
    RegExp(
      r'<(style|script|head|title)\b.*?</\1\s*>',
      caseSensitive: false,
      dotAll: true,
    ),
    '\n',
  );
  text = text.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '\n');
  text = text.replaceAllMapped(
    RegExp(
      r'''<img\b[^>]*?\balt\s*=\s*("([^"]*)"|'([^']*)')[^>]*>''',
      caseSensitive: false,
    ),
    (m) => '\n${m[2] ?? m[3] ?? ''}\n',
  );
  text = text.replaceAll(RegExp(r'<[^>]*>'), '\n');
  return _lines(_unescape(text));
}

/// Decodes RFC 2047 encoded words, like `=?UTF-8?Q?Ordered=3A?=`, and raw
/// UTF-8 read as Latin-1 (an mbox is read byte for byte).
String decodeHeader(String value) => _asUtf8(value)
    .replaceAllMapped(
      RegExp(r'=\?([^?]+)\?([bBqQ])\?([^?]*)\?=\s*(?==\?)'),
      (m) => m[0]!.trimRight(),
    )
    .replaceAllMapped(RegExp(r'=\?([^?]+)\?([bBqQ])\?([^?]*)\?='), (m) {
      try {
        final bytes = m[2]!.toLowerCase() == 'b'
            ? base64.decode(base64.normalize(m[3]!))
            : _quotedPrintable(m[3]!.replaceAll('_', ' '));
        return _decodeBytes(bytes, m[1]!);
      } on FormatException {
        return m[0]!;
      }
    })
    .trim();

// --- Stores -----------------------------------------------------------------

final _amazonOrder = RegExp(r'\b\d{3}-\d{7}-\d{7}\b');
final _money = RegExp(
  r'(?:US\s*)?\$?\s*(\d{1,3}(?:,\d{3})*\.\d{2})(?:\s*USD)?',
);

/// Amazon's "Ordered: …" email: order number, items with their quantity and
/// price from the plain text, and the grand total. Newer emails name only
/// the items' departments; those become the item names.
StoreCharge? _amazon(OrderEmail email) {
  final lines = email.lines;
  final total = _amountAfter(lines, (line) => line.startsWith('Grand Total'));
  final date = email.date;
  if (total == null || date == null) return null;
  final orderId =
      _amazonOrder.firstMatch(lines.join('\n'))?[0] ??
      'amazon-${date.toIso()}-${total.cents}';
  final items = <StoreItem>[];
  for (var i = 0; i < lines.length; i++) {
    if (!lines[i].startsWith('* ')) continue;
    final name = lines[i].substring(2).trim();
    var count = 1;
    Money? price;
    for (var j = i + 1; j < lines.length && j <= i + 3; j++) {
      final quantity = RegExp(r'^Quantity:\s*(\d+)').firstMatch(lines[j]);
      if (quantity != null) {
        count = int.parse(quantity[1]!);
        continue;
      }
      price = _parseMoney(lines[j]);
      if (price != null) break;
    }
    items.add(
      StoreItem(
        name: count > 1 ? '$name ×$count' : name,
        amount: Money((price ?? Money.zero).cents * count),
      ),
    );
  }
  if (items.isEmpty) {
    final subject = email.subject;
    final departments = RegExp(r'^Ordered \d+ items?:\s*(.+)$')
        .firstMatch(subject);
    final named = RegExp(r'^Ordered:\s*(?:(\d+)\s+)?"(.+?)"?$')
        .firstMatch(subject);
    final name = departments?[1] ?? named?[2]?.replaceAll('...', '…');
    if (name == null || name.isEmpty) return null;
    items.add(StoreItem(name: name, amount: total));
  }
  return StoreCharge(
    store: Store.amazon,
    orderId: orderId,
    date: date,
    items: items,
    total: total,
  );
}

/// Walmart's "Thanks for your order" email: items from the pictures' alt
/// text (`quantity 2 item Bananas`) and the order total.
StoreCharge? _walmart(OrderEmail email) {
  final lines = email.lines;
  final total = _amountAfter(lines, (line) => line.startsWith('Order total'));
  final placed =
      _civil(
        RegExp(r'^Order date:\s*(.+)$').firstMatch(
          lines.firstWhere(
            (l) => l.startsWith('Order date:'),
            orElse: () => '',
          ),
        )?[1],
      ) ??
      email.date;
  if (total == null || placed == null) return null;
  final numberAt = lines.indexWhere((line) => line.startsWith('Order number'));
  final orderId = numberAt < 0
      ? 'walmart-${placed.toIso()}-${total.cents}'
      : (RegExp(r'#?\s*([\d-]{6,})').firstMatch(
              [
                lines[numberAt],
                if (numberAt + 1 < lines.length) lines[numberAt + 1],
              ].join(' '),
            )?[1] ??
            'walmart-${placed.toIso()}-${total.cents}');
  final items = <StoreItem>[];
  final seen = <String>{};
  for (final line in lines) {
    final item = RegExp(
      r'^quantity (\d+) items? (.+)$',
      caseSensitive: false,
    ).firstMatch(line);
    if (item == null || !seen.add(line)) continue;
    final count = int.parse(item[1]!);
    final name = item[2]!.trim();
    items.add(
      StoreItem(name: count > 1 ? '$name ×$count' : name, amount: Money.zero),
    );
  }
  if (items.isEmpty) {
    items.add(const StoreItem(name: 'Walmart order', amount: Money.zero));
  }
  return StoreCharge(
    store: Store.walmart,
    orderId: orderId,
    date: placed,
    items: items,
    total: total,
  );
}

/// AliExpress's "orders confirmed" email: one or more orders, each with its
/// number, item and total. One payment covers them all, so the whole email
/// is one charge; with several orders each is offered on its own too.
List<StoreCharge> _aliExpress(OrderEmail email) {
  final date = email.date;
  if (date == null) return const [];
  final lines = email.lines;
  final orders = <StoreCharge>[];
  for (var i = 0; i < lines.length; i++) {
    if (!RegExp(r'^Order \d+$').hasMatch(lines[i]) || i + 2 >= lines.length) {
      continue;
    }
    final number = lines[i + 1];
    if (!RegExp(r'^\d{8,}$').hasMatch(number)) continue;
    final name = lines[i + 2];
    Money? total;
    for (var j = i + 3; j < lines.length && j <= i + 10; j++) {
      if (lines[j] == 'Total' && j + 1 < lines.length) {
        total = _parseMoney(lines[j + 1]);
        break;
      }
    }
    if (total == null) continue;
    orders.add(
      StoreCharge(
        store: Store.aliExpress,
        orderId: number,
        date: date,
        items: [StoreItem(name: name.replaceAll('...', '…'), amount: total)],
      ),
    );
  }
  if (orders.length < 2) return orders;
  return [
    StoreCharge(
      store: Store.aliExpress,
      orderId: orders.first.orderId,
      date: date,
      items: [for (final order in orders) ...order.items],
    ),
    ...orders,
  ];
}

// --- Helpers -----------------------------------------------------------------

/// The first amount on the line [isLabel] picks, or on one of the next
/// three lines.
Money? _amountAfter(List<String> lines, bool Function(String) isLabel) {
  for (var i = 0; i < lines.length; i++) {
    if (!isLabel(lines[i])) continue;
    for (var j = i; j < lines.length && j <= i + 3; j++) {
      final text = j == i
          ? lines[j].replaceFirst(RegExp(r'^[^:]*:?'), '')
          : lines[j];
      if (_parseMoney(text) case final amount?) return amount;
    }
  }
  return null;
}

Money? _parseMoney(String text) {
  final match = _money.firstMatch(text);
  if (match == null) return null;
  final cents = int.tryParse(match[1]!.replaceAll(RegExp(r'[,.]'), ''));
  return cents == null ? null : Money(cents);
}

const _months = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6, //
  'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
};

/// `Sat, 21 Nov 2026 17:25:46 +0000`: the day as written, in the sender's
/// own zone.
CivilDate? _headerDate(String value) {
  final match = RegExp(r'(\d{1,2})\s+([A-Za-z]{3})[a-z]*\s+(\d{4})')
      .firstMatch(value);
  if (match == null) return null;
  final month = _months[match[2]!.toLowerCase()];
  if (month == null) return null;
  try {
    return CivilDate(int.parse(match[3]!), month, int.parse(match[1]!));
  } on ArgumentError {
    return null;
  }
}

/// `Sat, Nov 21, 2026` as a date.
CivilDate? _civil(String? value) {
  if (value == null) return null;
  final match = RegExp(r'([A-Za-z]{3})[a-z]*\.?\s+(\d{1,2}),?\s+(\d{4})')
      .firstMatch(value);
  if (match == null) return null;
  final month = _months[match[1]!.toLowerCase()];
  if (month == null) return null;
  try {
    return CivilDate(int.parse(match[3]!), month, int.parse(match[2]!));
  } on ArgumentError {
    return null;
  }
}

/// Trimmed, non-empty lines, with the invisible spacing characters emails
/// pad their previews with taken out.
List<String> _lines(String text) => [
  for (final line in text.split('\n'))
    if (line
            .replaceAll(
              RegExp(
                '[\\u00ad\\u034f\\u200b-\\u200f\\u202a-\\u202e\\u2060\\ufeff\\u00a0]',
              ),
              ' ',
            )
            .trim()
        case final clean when clean.isNotEmpty)
      clean.replaceAll(RegExp(r'\s+'), ' '),
];

String _unescape(String text) => text
    .replaceAllMapped(RegExp(r'&#(\d+);'), (m) => _char(int.parse(m[1]!)))
    .replaceAllMapped(
      RegExp(r'&#[xX]([0-9a-fA-F]+);'),
      (m) => _char(int.parse(m[1]!, radix: 16)),
    )
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&apos;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&amp;', '&');

String _asUtf8(String text) => text.codeUnits.every((c) => c < 256)
    ? utf8.decode(latin1.encode(text), allowMalformed: true)
    : text;

String _char(int code) =>
    code > 0 && code <= 0x10ffff ? String.fromCharCode(code) : '';

List<int> _quotedPrintable(String text) {
  final bytes = <int>[];
  final source = text.replaceAll(RegExp(r'=\r?\n'), '');
  for (var i = 0; i < source.length; i++) {
    final c = source[i];
    if (c == '=' && i + 2 < source.length) {
      final value = int.tryParse(source.substring(i + 1, i + 3), radix: 16);
      if (value != null) {
        bytes.add(value);
        i += 2;
        continue;
      }
    }
    final code = c.codeUnitAt(0);
    if (code < 256) {
      bytes.add(code);
    } else {
      bytes.addAll(utf8.encode(c));
    }
  }
  return bytes;
}

String _decodeBytes(List<int> bytes, String charset) {
  final name = charset.toLowerCase();
  if (name.contains('8859') ||
      name.contains('latin') ||
      name.contains('1252') ||
      name == 'us-ascii') {
    return latin1.decode(bytes, allowInvalid: true);
  }
  return utf8.decode(bytes, allowMalformed: true);
}

/// One MIME part: its headers and either its children or its decoded body.
final class _Part {
  _Part(this._headers, this._body);

  factory _Part.parse(String raw) {
    final split = raw.indexOf('\n\n');
    final head = split < 0 ? raw : raw.substring(0, split);
    final body = split < 0 ? '' : raw.substring(split + 2);
    final headers = <String, String>{};
    String? last;
    for (final line in head.split('\n')) {
      if (line.startsWith(' ') || line.startsWith('\t')) {
        if (last != null) headers[last] = '${headers[last]} ${line.trim()}';
        continue;
      }
      final colon = line.indexOf(':');
      if (colon <= 0) continue;
      last = line.substring(0, colon).trim().toLowerCase();
      headers.putIfAbsent(last, () => line.substring(colon + 1).trim());
    }
    return _Part(headers, body);
  }

  final Map<String, String> _headers;
  final String _body;

  String header(String name) => _headers[name] ?? '';

  String get mimeType =>
      header('content-type')
          .split(';')
          .first
          .trim()
          .toLowerCase()
          .ifEmpty('text/plain');

  bool get isMultipart => mimeType.startsWith('multipart/');

  bool get isAttachment =>
      header('content-disposition').toLowerCase().startsWith('attachment');

  String? _param(String headerValue, String name) => RegExp(
    '\\b$name\\s*=\\s*(?:"([^"]*)"|([^;\\s]+))',
    caseSensitive: false,
  ).firstMatch(headerValue)?.let((m) => m[1] ?? m[2]);

  List<_Part> get children {
    final boundary = _param(header('content-type'), 'boundary');
    if (boundary == null) return const [];
    final marker = '--$boundary';
    final pieces = _body.split(marker);
    return [
      for (final piece in pieces.skip(1))
        if (!piece.startsWith('--'))
          _Part.parse(piece.replaceFirst(RegExp(r'^[ \t]*\n'), '')),
    ];
  }

  String get text {
    final encoding = header('content-transfer-encoding').toLowerCase();
    final charset = _param(header('content-type'), 'charset') ?? 'utf-8';
    final List<int> bytes;
    if (encoding.contains('base64')) {
      final clean = _body.replaceAll(RegExp(r'[^A-Za-z0-9+/=]'), '');
      try {
        bytes = base64.decode(base64.normalize(clean));
      } on FormatException {
        return '';
      }
    } else if (encoding.contains('quoted-printable')) {
      bytes = _quotedPrintable(_body);
    } else {
      bytes = latin1.encode(_body.replaceAll(RegExp('[^\u0000-ÿ]'), '?'));
      return _decodeBytes(
        bytes,
        charset.toLowerCase() == 'us-ascii' ? 'utf-8' : charset,
      );
    }
    return _decodeBytes(bytes, charset);
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}

/// The .mbox texts in [bytes]: the file itself, or every .mbox in a zip.
List<String> _mboxTexts(List<int> bytes) {
  final zip = bytes.length > 4 && bytes[0] == 0x50 && bytes[1] == 0x4b;
  if (!zip) return [latin1.decode(bytes)];
  final archive = ZipDecoder().decodeBytes(bytes);
  final texts = [
    for (final file in archive.files)
      if (file.isFile && file.name.toLowerCase().endsWith('.mbox'))
        latin1.decode(file.content),
  ];
  if (texts.isEmpty) {
    throw const StoreOrdersException('That zip has no Gmail .mbox file in it.');
  }
  return texts;
}

/// One charge per store and order: Gmail can hold the same email twice.
List<StoreCharge> _dedupe(List<StoreCharge> charges) {
  final seen = <String>{};
  return [
    for (final charge in charges)
      if (seen.add(
        '${charge.store.name}|${charge.orderId}|${charge.items.length}|${charge.total.cents}',
      ))
        charge,
  ];
}
