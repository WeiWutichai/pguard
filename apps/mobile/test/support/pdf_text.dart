// Reads the TEXT back out of a generated PDF, so a test can assert on what the document actually
// says instead of on how it was built.
//
// Why this is not a one-liner: the receipt embeds TrueType fonts (it has to — Thai), and the pdf
// package writes text for an embedded TTF as hex GLYPH INDICES inside a Flate-compressed content
// stream (`<00A3011F…> Tj`). The literal string "฿1,968.80" is nowhere in the file. To read it back
// we do what a PDF viewer does: inflate the streams, pick up each font's `/ToUnicode` CMap
// (glyph id → code point) and map the glyph runs back through it.
//
// A document embeds one CMap per face, and a glyph run does not carry which face drew it, so every
// run is decoded under every CMap and all readings are returned together. That is sound for the
// `contains` assertions these tests make: a specific string like "฿1,968.80" appearing under some
// face means the document really printed it.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// Asserts that [expected] is printed in the extracted text, IGNORING whitespace.
///
/// A PDF has no spaces: the layout engine positions each word on the page and the gaps between
/// them are coordinates, not characters. So `"10 ส.ค. 2569"` comes back as `"10ส.ค.2569"`. Both
/// sides are squashed before comparing, which keeps assertions readable as the document reads.
Matcher containsPdfText(String expected) => predicate<String>(
      (text) => _squash(text).contains(_squash(expected)),
      'contains "$expected" (whitespace-insensitive — a PDF positions words, '
      'it does not store the spaces between them)',
    );

String _squash(String s) => s.replaceAll(RegExp(r'\s+'), '');

/// Every text run in [pdfBytes], decoded through the document's `/ToUnicode` CMaps.
String extractPdfText(Uint8List pdfBytes) {
  final streams = inflatedPdfStreams(pdfBytes);
  final cmaps = <Map<int, int>>[];
  final contents = <String>[];
  for (final s in streams) {
    if (s.contains('beginbfchar')) {
      cmaps.add(_parseCmap(s));
    } else {
      contents.add(s);
    }
  }
  if (cmaps.isEmpty) return '';

  final out = StringBuffer();
  for (final content in contents) {
    for (final cmap in cmaps) {
      for (final match in _hexString.allMatches(content)) {
        final hex = match.group(1)!;
        if (hex.length % 4 != 0) continue;
        for (var i = 0; i < hex.length; i += 4) {
          final glyph = int.parse(hex.substring(i, i + 4), radix: 16);
          final rune = cmap[glyph];
          if (rune != null && rune != 0) out.writeCharCode(rune);
        }
      }
      out.write('\n');
    }
  }
  return out.toString();
}

/// The inflated payload of every Flate-compressed stream object in the file (content streams,
/// `/ToUnicode` CMaps, embedded font programs — the latter simply fail to decode as text and are
/// harmless).
List<String> inflatedPdfStreams(Uint8List bytes) {
  final out = <String>[];
  final open = ascii.encode('stream');
  final close = ascii.encode('endstream');
  var i = 0;
  while (i < bytes.length) {
    final start = _indexOf(bytes, open, i);
    if (start < 0) break;
    var from = start + open.length;
    if (from < bytes.length && bytes[from] == 0x0d) from++;
    if (from < bytes.length && bytes[from] == 0x0a) from++;
    final end = _indexOf(bytes, close, from);
    if (end < 0) break;
    var to = end;
    while (to > from && (bytes[to - 1] == 0x0a || bytes[to - 1] == 0x0d)) {
      to--;
    }
    try {
      out.add(latin1.decode(ZLibDecoder().convert(bytes.sublist(from, to))));
    } catch (_) {
      // Not a Flate stream (or an image/font blob) — nothing to read as text.
    }
    i = end + close.length;
  }
  return out;
}

/// `<0041> <0E3F>` pairs out of a `/ToUnicode` CMap: glyph index → code point.
Map<int, int> _parseCmap(String cmap) {
  final map = <int, int>{};
  for (final m in _bfChar.allMatches(cmap)) {
    map[int.parse(m.group(1)!, radix: 16)] = int.parse(m.group(2)!, radix: 16);
  }
  return map;
}

final RegExp _bfChar =
    RegExp(r'<([0-9A-Fa-f]{4})>\s*<([0-9A-Fa-f]{4})>', multiLine: true);

/// A hex string operand — `<...>`, never the `<<` that opens a dictionary.
final RegExp _hexString = RegExp(r'(?<!<)<([0-9A-Fa-f]{4,})>(?!>)');

int _indexOf(Uint8List haystack, List<int> needle, int from) {
  outer:
  for (var i = from; i <= haystack.length - needle.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) continue outer;
    }
    return i;
  }
  return -1;
}
