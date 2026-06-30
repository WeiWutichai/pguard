import 'dart:convert';

/// A dependency-free byte-mode QR encoder (ECC level M), ported verbatim from the web-admin's
/// `apps/web-admin/src/components/ui/qr-code.tsx`. It produces a square boolean matrix (`true` =
/// dark module) that a widget renders — exactly the same algorithm the web uses, so the PromptPay
/// `qr_payload` scans identically on both clients.
///
/// Why hand-rolled (no package): the PromptPay payload is generated server-side as the single
/// authoritative source (amount + receiver can't drift), and the client must NEVER send it to a
/// third-party QR image service. A small self-contained encoder is exactly enough for the ~100-char
/// EMVCo string (auto-picks the smallest fitting version 1–10). Pure Dart, no Flutter imports → unit
/// testable. Verified against the standard QR algorithm: data codewords → Reed–Solomon ECC →
/// interleave → matrix placement (finder/timing/alignment) → lowest-penalty mask.

/// EC codewords per block, level M, by version (1–10).
const Map<int, int> _ecCodewordsPerBlockM = {
  1: 10, 2: 16, 3: 26, 4: 18, 5: 24, 6: 16, 7: 18, 8: 22, 9: 22, 10: 26,
};

/// `[numBlocksGroup1, dataCwPerBlockGroup1, numBlocksGroup2, dataCwPerBlockGroup2]`, level M.
const Map<int, List<int>> _ecBlocksM = {
  1: [1, 16, 0, 0],
  2: [1, 28, 0, 0],
  3: [1, 44, 0, 0],
  4: [2, 32, 0, 0],
  5: [2, 43, 0, 0],
  6: [4, 27, 0, 0],
  7: [4, 31, 0, 0],
  8: [2, 38, 2, 39],
  9: [3, 36, 2, 37],
  10: [4, 43, 1, 44],
};

/// Alignment-pattern centre coordinates, by version.
const Map<int, List<int>> _alignPos = {
  1: [], 2: [6, 18], 3: [6, 22], 4: [6, 26], 5: [6, 30],
  6: [6, 34], 7: [6, 22, 38], 8: [6, 24, 42], 9: [6, 26, 46], 10: [6, 28, 50],
};

/// 18-bit Golay-encoded version-information strings, versions 7–10.
const Map<int, int> _versionInfo = {
  7: 0x07c94,
  8: 0x085bc,
  9: 0x09a99,
  10: 0x0a4d3,
};

/// Format info (level M = `0b00`) BCH-encoded + masked, by mask-pattern index.
const List<int> _formatBitsM = [
  0x5412, 0x5125, 0x5e7c, 0x5b4b, 0x45f9, 0x40ce, 0x4f97, 0x4aa0,
];

// ---- GF(256) arithmetic for Reed–Solomon ----
final List<int> _exp = List<int>.filled(512, 0);
final List<int> _log = List<int>.filled(256, 0);
bool _gfReady = false;

void _initGf() {
  if (_gfReady) return;
  var x = 1;
  for (var i = 0; i < 255; i++) {
    _exp[i] = x;
    _log[x] = i;
    x <<= 1;
    if (x & 0x100 != 0) x ^= 0x11d;
  }
  for (var i = 255; i < 512; i++) {
    _exp[i] = _exp[i - 255];
  }
  _gfReady = true;
}

int _gfMul(int a, int b) => (a == 0 || b == 0) ? 0 : _exp[_log[a] + _log[b]];

/// Generator polynomial for [degree] ECC codewords (descending degree order).
List<int> _rsGenerator(int degree) {
  var poly = <int>[1];
  for (var i = 0; i < degree; i++) {
    final next = List<int>.filled(poly.length + 1, 0);
    for (var j = 0; j < poly.length; j++) {
      next[j] ^= poly[j];
      next[j + 1] ^= _gfMul(poly[j], _exp[i]);
    }
    poly = next;
  }
  return poly;
}

List<int> _rsEncode(List<int> data, int ecLen) {
  final gen = _rsGenerator(ecLen);
  final res = List<int>.filled(ecLen, 0, growable: true);
  for (final d in data) {
    final factor = d ^ res[0];
    res.removeAt(0);
    res.add(0);
    if (factor != 0) {
      for (var i = 0; i < gen.length - 1; i++) {
        res[i] ^= _gfMul(gen[i + 1], factor);
      }
    }
  }
  return res;
}

/// Smallest level-M version (1–10) that fits [dataLen] bytes in byte mode.
int _pickVersion(int dataLen) {
  for (var v = 1; v <= 10; v++) {
    final b = _ecBlocksM[v]!;
    final totalDataCw = b[0] * b[1] + b[2] * b[3];
    final lenBits = v <= 9 ? 8 : 16;
    final neededBits = 4 + lenBits + dataLen * 8;
    if (neededBits <= totalDataCw * 8) return v;
  }
  return 10;
}

List<int> _buildBitstream(List<int> bytes, int version, int totalDataCw) {
  final bits = <int>[];
  void push(int val, int len) {
    for (var i = len - 1; i >= 0; i--) {
      bits.add((val >> i) & 1);
    }
  }

  push(0x4, 4); // byte mode
  push(bytes.length, version <= 9 ? 8 : 16);
  for (final b in bytes) {
    push(b, 8);
  }
  final cap = totalDataCw * 8;
  push(0, (4 < cap - bits.length) ? 4 : cap - bits.length); // terminator
  while (bits.length % 8 != 0) {
    bits.add(0);
  }
  const padBytes = [0xec, 0x11];
  var p = 0;
  while (bits.length < cap) {
    push(padBytes[p++ % 2], 8);
  }
  final codewords = <int>[];
  for (var i = 0; i < bits.length; i += 8) {
    var cw = 0;
    for (var j = 0; j < 8; j++) {
      cw = (cw << 1) | bits[i + j];
    }
    codewords.add(cw);
  }
  return codewords;
}

/// Interleave data + ECC blocks per the QR spec.
List<int> _assembleCodewords(List<int> dataCw, int version) {
  final b = _ecBlocksM[version]!;
  final d1 = b[1];
  final d2 = b[3];
  final ecPerBlock = _ecCodewordsPerBlockM[version]!;
  final blocks = <({List<int> data, List<int> ec})>[];
  var offset = 0;
  for (var i = 0; i < b[0]; i++) {
    final data = dataCw.sublist(offset, offset + d1);
    offset += d1;
    blocks.add((data: data, ec: _rsEncode(data, ecPerBlock)));
  }
  for (var i = 0; i < b[2]; i++) {
    final data = dataCw.sublist(offset, offset + d2);
    offset += d2;
    blocks.add((data: data, ec: _rsEncode(data, ecPerBlock)));
  }
  final out = <int>[];
  final maxData = d1 > d2 ? d1 : d2;
  for (var i = 0; i < maxData; i++) {
    for (final blk in blocks) {
      if (i < blk.data.length) out.add(blk.data[i]);
    }
  }
  for (var i = 0; i < ecPerBlock; i++) {
    for (final blk in blocks) {
      out.add(blk.ec[i]);
    }
  }
  return out;
}

List<List<bool>> _reservedMatrix(int size, int version) {
  final res = List.generate(size, (_) => List<bool>.filled(size, false));
  void mark(int r, int c) {
    if (r >= 0 && r < size && c >= 0 && c < size) res[r][c] = true;
  }

  for (final corner in [
    [0, 0],
    [0, size - 7],
    [size - 7, 0]
  ]) {
    for (var r = -1; r <= 7; r++) {
      for (var c = -1; c <= 7; c++) {
        mark(corner[0] + r, corner[1] + c);
      }
    }
  }
  for (var i = 0; i < size; i++) {
    mark(6, i);
    mark(i, 6);
  }
  final ap = _alignPos[version]!;
  for (final r in ap) {
    for (final c in ap) {
      final isFinder = (r <= 8 && c <= 8) ||
          (r <= 8 && c >= size - 9) ||
          (r >= size - 9 && c <= 8);
      if (isFinder) continue;
      for (var dr = -2; dr <= 2; dr++) {
        for (var dc = -2; dc <= 2; dc++) {
          mark(r + dr, c + dc);
        }
      }
    }
  }
  for (var i = 0; i < 9; i++) {
    mark(8, i);
    mark(i, 8);
  }
  for (var i = 0; i < 8; i++) {
    mark(8, size - 1 - i);
    mark(size - 1 - i, 8);
  }
  mark(size - 8, 8); // dark module
  if (version >= 7) {
    for (var i = 0; i < 6; i++) {
      for (var j = 0; j < 3; j++) {
        mark(i, size - 11 + j);
        mark(size - 11 + j, i);
      }
    }
  }
  return res;
}

void _placePatterns(List<List<bool?>> grid, int size, int version) {
  void drawFinder(int br, int bc) {
    for (var r = -1; r <= 7; r++) {
      for (var c = -1; c <= 7; c++) {
        final rr = br + r;
        final cc = bc + c;
        if (rr < 0 || rr >= size || cc < 0 || cc >= size) continue;
        final inBorder = r == 0 || r == 6 || c == 0 || c == 6;
        final inCore = r >= 2 && r <= 4 && c >= 2 && c <= 4;
        final onPattern = r >= 0 && r <= 6 && c >= 0 && c <= 6;
        grid[rr][cc] = onPattern ? (inBorder || inCore) : false;
      }
    }
  }

  drawFinder(0, 0);
  drawFinder(0, size - 7);
  drawFinder(size - 7, 0);
  for (var i = 8; i < size - 8; i++) {
    final v = i % 2 == 0;
    grid[6][i] = v;
    grid[i][6] = v;
  }
  final ap = _alignPos[version]!;
  for (final r in ap) {
    for (final c in ap) {
      final isFinder = (r <= 8 && c <= 8) ||
          (r <= 8 && c >= size - 9) ||
          (r >= size - 9 && c <= 8);
      if (isFinder) continue;
      for (var dr = -2; dr <= 2; dr++) {
        for (var dc = -2; dc <= 2; dc++) {
          final ring = dr.abs() > dc.abs() ? dr.abs() : dc.abs();
          grid[r + dr][c + dc] = ring != 1;
        }
      }
    }
  }
  grid[size - 8][8] = true; // dark module
  if (version >= 7) {
    final info = _versionInfo[version]!;
    for (var i = 0; i < 18; i++) {
      final bit = ((info >> i) & 1) == 1;
      final row = i ~/ 3;
      final col = i % 3;
      grid[size - 11 + col][row] = bit;
      grid[row][size - 11 + col] = bit;
    }
  }
}

void _placeData(
    List<List<bool?>> grid, List<List<bool>> reserved, int size, List<int> cw) {
  var bitIdx = 0;
  int bitAt(int i) => (cw[i >> 3] >> (7 - (i & 7))) & 1;
  var upward = true;
  for (var col = size - 1; col > 0; col -= 2) {
    if (col == 6) col--; // skip timing column
    for (var i = 0; i < size; i++) {
      final row = upward ? size - 1 - i : i;
      for (var c = 0; c < 2; c++) {
        final cc = col - c;
        if (reserved[row][cc]) continue;
        final bit = bitIdx < cw.length * 8 ? bitAt(bitIdx) : 0;
        grid[row][cc] = bit == 1;
        bitIdx++;
      }
    }
    upward = !upward;
  }
}

final List<bool Function(int r, int c)> _masks = [
  (r, c) => (r + c) % 2 == 0,
  (r, c) => r % 2 == 0,
  (r, c) => c % 3 == 0,
  (r, c) => (r + c) % 3 == 0,
  (r, c) => ((r ~/ 2) + (c ~/ 3)) % 2 == 0,
  (r, c) => ((r * c) % 2) + ((r * c) % 3) == 0,
  (r, c) => (((r * c) % 2) + ((r * c) % 3)) % 2 == 0,
  (r, c) => (((r + c) % 2) + ((r * c) % 3)) % 2 == 0,
];

List<List<bool?>> _applyMask(List<List<bool?>> grid, List<List<bool>> reserved,
    int size, bool Function(int, int) maskFn) {
  final out = grid.map((row) => List<bool?>.from(row)).toList();
  for (var r = 0; r < size; r++) {
    for (var c = 0; c < size; c++) {
      if (reserved[r][c]) continue;
      if (maskFn(r, c)) out[r][c] = !(out[r][c] ?? false);
    }
  }
  return out;
}

int _penalty(List<List<bool?>> grid, int size) {
  var score = 0;
  bool at(int r, int c) => grid[r][c] == true;
  // rule 1: runs ≥5
  for (var r = 0; r < size; r++) {
    var run = 1;
    for (var c = 1; c < size; c++) {
      if (at(r, c) == at(r, c - 1)) {
        run++;
      } else {
        if (run >= 5) score += 3 + (run - 5);
        run = 1;
      }
    }
    if (run >= 5) score += 3 + (run - 5);
  }
  for (var c = 0; c < size; c++) {
    var run = 1;
    for (var r = 1; r < size; r++) {
      if (at(r, c) == at(r - 1, c)) {
        run++;
      } else {
        if (run >= 5) score += 3 + (run - 5);
        run = 1;
      }
    }
    if (run >= 5) score += 3 + (run - 5);
  }
  // rule 2: 2×2 blocks
  for (var r = 0; r < size - 1; r++) {
    for (var c = 0; c < size - 1; c++) {
      final v = at(r, c);
      if (v == at(r, c + 1) && v == at(r + 1, c) && v == at(r + 1, c + 1)) {
        score += 3;
      }
    }
  }
  // rule 3: finder-like 1:1:3:1:1 patterns, both orientations
  const pat1 = [
    true, false, true, true, true, false, true, false, false, false, false
  ];
  const pat2 = [
    false, false, false, false, true, false, true, true, true, false, true
  ];
  bool matchAt(bool Function(int) get, int n, int start, List<bool> pat) {
    if (start + pat.length > n) return false;
    for (var k = 0; k < pat.length; k++) {
      if (get(start + k) != pat[k]) return false;
    }
    return true;
  }

  for (var r = 0; r < size; r++) {
    for (var c = 0; c <= size - 11; c++) {
      get(int i) => at(r, i);
      if (matchAt(get, size, c, pat1) || matchAt(get, size, c, pat2)) {
        score += 40;
      }
    }
  }
  for (var c = 0; c < size; c++) {
    for (var r = 0; r <= size - 11; r++) {
      get(int i) => at(i, c);
      if (matchAt(get, size, r, pat1) || matchAt(get, size, r, pat2)) {
        score += 40;
      }
    }
  }
  // rule 4: dark proportion
  var dark = 0;
  for (var r = 0; r < size; r++) {
    for (var c = 0; c < size; c++) {
      if (at(r, c)) dark++;
    }
  }
  final pct = (dark * 100) / (size * size);
  score += ((pct - 50).abs() / 5).floor() * 10;
  return score;
}

void _placeFormat(List<List<bool?>> grid, int size, int maskIdx) {
  final bits = _formatBitsM[maskIdx];
  bool get(int i) => ((bits >> i) & 1) == 1;
  for (var i = 0; i <= 5; i++) {
    grid[i][8] = get(i);
  }
  grid[7][8] = get(6);
  grid[8][8] = get(7);
  grid[8][7] = get(8);
  for (var i = 9; i <= 14; i++) {
    grid[8][14 - i] = get(i);
  }
  for (var i = 0; i <= 7; i++) {
    grid[8][size - 1 - i] = get(i);
  }
  for (var i = 8; i <= 14; i++) {
    grid[size - 15 + i][8] = get(i);
  }
}

/// The encoded QR: a square [size]×[size] boolean [matrix] (`true` = a dark module). Render with
/// a 4-module quiet zone.
class QrMatrix {
  const QrMatrix({required this.matrix, required this.size});

  final List<List<bool>> matrix;
  final int size;
}

/// Encode [text] as a byte-mode level-M QR (versions 1–10). Throws [ArgumentError] if the text is
/// too long to fit version 10 (the PromptPay payload is ~100 chars, well within range).
QrMatrix encodeQr(String text) {
  _initGf();
  final bytes = utf8.encode(text);
  final version = _pickVersion(bytes.length);
  final b = _ecBlocksM[version]!;
  final totalDataCw = b[0] * b[1] + b[2] * b[3];
  final maxBytes = totalDataCw - 1 - (version <= 9 ? 1 : 2);
  if (bytes.length > maxBytes) {
    throw ArgumentError('QR payload too long: ${bytes.length} bytes');
  }
  final dataCw = _buildBitstream(bytes, version, totalDataCw);
  final finalCw = _assembleCodewords(dataCw, version);

  final size = 17 + version * 4;
  final reserved = _reservedMatrix(size, version);
  final base = List.generate(size, (_) => List<bool?>.filled(size, null));
  _placePatterns(base, size, version);
  _placeData(base, reserved, size, finalCw);

  List<List<bool?>>? best;
  var bestScore = 1 << 30;
  var bestMask = 0;
  for (var m = 0; m < 8; m++) {
    final masked = _applyMask(base, reserved, size, _masks[m]);
    _placeFormat(masked, size, m);
    final s = _penalty(masked, size);
    if (s < bestScore) {
      bestScore = s;
      best = masked;
      bestMask = m;
    }
  }
  final chosen = best ?? base;
  _placeFormat(chosen, size, bestMask);
  final matrix =
      chosen.map((row) => row.map((v) => v == true).toList()).toList();
  return QrMatrix(matrix: matrix, size: size);
}
