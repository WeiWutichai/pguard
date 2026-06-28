"use client";

import { useMemo } from "react";

// Dependency-free QR encoder (byte mode, ECC level M) rendered as an inline SVG.
//
// Why hand-rolled and not a library: the 2FA `otpauth://` URI embeds the TOTP secret, so it must
// NEVER be sent to a third-party QR image service. Adding an npm QR dependency was also out of
// scope (no package.json change), so this is a small, self-contained byte-mode encoder — exactly
// enough to render the ~100-char provisioning URI (auto-picks the smallest fitting version 1–10).
//
// Standard QR algorithm: data codewords → Reed–Solomon ECC → interleave → place on the matrix with
// finder/timing/alignment patterns → apply the lowest-penalty mask. Verified against known vectors.

/** Total data codeword capacity by [version][ecLevel] — level M only (index 1) is used here. */
const EC_CODEWORDS_PER_BLOCK_M: Record<number, number> = {
  1: 10, 2: 16, 3: 26, 4: 18, 5: 24, 6: 16, 7: 18, 8: 22, 9: 22, 10: 26,
};
/** [version] → [numBlocksGroup1, dataCodewordsPerBlockGroup1, numBlocksGroup2, dataCodewordsPerBlockGroup2] for level M. */
const EC_BLOCKS_M: Record<number, [number, number, number, number]> = {
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
/** Alignment-pattern center coordinates by version. */
const ALIGN_POS: Record<number, number[]> = {
  1: [], 2: [6, 18], 3: [6, 22], 4: [6, 26], 5: [6, 30],
  6: [6, 34], 7: [6, 22, 38], 8: [6, 24, 42], 9: [6, 26, 46], 10: [6, 28, 50],
};

// ---- GF(256) arithmetic for Reed–Solomon ----
const EXP = new Uint8Array(512);
const LOG = new Uint8Array(256);
(() => {
  let x = 1;
  for (let i = 0; i < 255; i++) {
    EXP[i] = x;
    LOG[x] = i;
    x <<= 1;
    if (x & 0x100) x ^= 0x11d;
  }
  for (let i = 255; i < 512; i++) EXP[i] = EXP[i - 255];
})();
const gfMul = (a: number, b: number) => (a === 0 || b === 0 ? 0 : EXP[LOG[a] + LOG[b]]);

/** Generator polynomial for `degree` ECC codewords, coefficients in DESCENDING degree order
 *  (so `gen[0]` is the leading 1). Product of (x − α^i) for i in 0..degree-1. */
function rsGenerator(degree: number): number[] {
  let poly = [1]; // descending: [coeff of x^k, …, constant]
  for (let i = 0; i < degree; i++) {
    // multiply by (x − α^i): shift up by one degree, then add (−α^i)·poly (= α^i·poly in GF(2)).
    const next = new Array(poly.length + 1).fill(0);
    for (let j = 0; j < poly.length; j++) {
      next[j] ^= poly[j]; // x · poly term
      next[j + 1] ^= gfMul(poly[j], EXP[i]); // α^i · poly term
    }
    poly = next;
  }
  return poly;
}

function rsEncode(data: number[], ecLen: number): number[] {
  const gen = rsGenerator(ecLen);
  const res = new Array(ecLen).fill(0);
  for (const d of data) {
    const factor = d ^ res[0];
    res.shift();
    res.push(0);
    if (factor !== 0) for (let i = 0; i < gen.length - 1; i++) res[i] ^= gfMul(gen[i + 1], factor);
  }
  return res;
}

/** Smallest level-M version (1–10) that fits `dataLen` bytes in byte mode (4-bit mode + length header). */
function pickVersion(dataLen: number): number {
  for (let v = 1; v <= 10; v++) {
    const [b1, d1, b2, d2] = EC_BLOCKS_M[v];
    const totalDataCw = b1 * d1 + b2 * d2;
    const lenBits = v <= 9 ? 8 : 16;
    const neededBits = 4 + lenBits + dataLen * 8;
    if (neededBits <= totalDataCw * 8) return v;
  }
  return 10;
}

function buildBitstream(bytes: number[], version: number, totalDataCw: number): number[] {
  const bits: number[] = [];
  const push = (val: number, len: number) => {
    for (let i = len - 1; i >= 0; i--) bits.push((val >> i) & 1);
  };
  push(0b0100, 4); // byte mode
  push(bytes.length, version <= 9 ? 8 : 16);
  for (const b of bytes) push(b, 8);
  const cap = totalDataCw * 8;
  push(0, Math.min(4, cap - bits.length)); // terminator
  while (bits.length % 8 !== 0) bits.push(0);
  const padBytes = [0xec, 0x11];
  let p = 0;
  while (bits.length < cap) push(padBytes[p++ % 2], 8);
  const codewords: number[] = [];
  for (let i = 0; i < bits.length; i += 8) {
    let cw = 0;
    for (let j = 0; j < 8; j++) cw = (cw << 1) | bits[i + j];
    codewords.push(cw);
  }
  return codewords;
}

/** Interleave data+ECC blocks per the QR spec. */
function assembleCodewords(dataCw: number[], version: number): number[] {
  const [b1, d1, b2, d2] = EC_BLOCKS_M[version];
  const ecPerBlock = EC_CODEWORDS_PER_BLOCK_M[version];
  const blocks: { data: number[]; ec: number[] }[] = [];
  let offset = 0;
  for (let i = 0; i < b1; i++) {
    const data = dataCw.slice(offset, offset + d1);
    offset += d1;
    blocks.push({ data, ec: rsEncode(data, ecPerBlock) });
  }
  for (let i = 0; i < b2; i++) {
    const data = dataCw.slice(offset, offset + d2);
    offset += d2;
    blocks.push({ data, ec: rsEncode(data, ecPerBlock) });
  }
  const out: number[] = [];
  const maxData = Math.max(d1, d2);
  for (let i = 0; i < maxData; i++) for (const blk of blocks) if (i < blk.data.length) out.push(blk.data[i]);
  for (let i = 0; i < ecPerBlock; i++) for (const blk of blocks) out.push(blk.ec[i]);
  return out;
}

type Grid = (boolean | null)[][];

function reservedMatrix(size: number, version: number): boolean[][] {
  const res: boolean[][] = Array.from({ length: size }, () => new Array(size).fill(false));
  const mark = (r: number, c: number) => {
    if (r >= 0 && r < size && c >= 0 && c < size) res[r][c] = true;
  };
  // finders + separators (3 corners), 8×8 each
  for (const [br, bc] of [[0, 0], [0, size - 7], [size - 7, 0]]) {
    for (let r = -1; r <= 7; r++) for (let c = -1; c <= 7; c++) mark(br + r, bc + c);
  }
  // timing
  for (let i = 0; i < size; i++) {
    mark(6, i);
    mark(i, 6);
  }
  // alignment
  const ap = ALIGN_POS[version];
  for (const r of ap) for (const c of ap) {
    const isFinder =
      (r <= 8 && c <= 8) || (r <= 8 && c >= size - 9) || (r >= size - 9 && c <= 8);
    if (isFinder) continue;
    for (let dr = -2; dr <= 2; dr++) for (let dc = -2; dc <= 2; dc++) mark(r + dr, c + dc);
  }
  // format info areas
  for (let i = 0; i < 9; i++) {
    mark(8, i);
    mark(i, 8);
  }
  for (let i = 0; i < 8; i++) {
    mark(8, size - 1 - i);
    mark(size - 1 - i, 8);
  }
  mark(size - 8, 8); // dark module
  // version information (versions ≥ 7): two 6×3 blocks by the top-right + bottom-left finders.
  if (version >= 7) {
    for (let i = 0; i < 6; i++) for (let j = 0; j < 3; j++) {
      mark(i, size - 11 + j);
      mark(size - 11 + j, i);
    }
  }
  return res;
}

/** 18-bit version-information strings (Golay-encoded), versions 7–10. */
const VERSION_INFO: Record<number, number> = {
  7: 0x07c94,
  8: 0x085bc,
  9: 0x09a99,
  10: 0x0a4d3,
};

function placePatterns(grid: Grid, size: number, version: number) {
  const drawFinder = (br: number, bc: number) => {
    for (let r = -1; r <= 7; r++) for (let c = -1; c <= 7; c++) {
      const rr = br + r;
      const cc = bc + c;
      if (rr < 0 || rr >= size || cc < 0 || cc >= size) continue;
      const inBorder = r === 0 || r === 6 || c === 0 || c === 6;
      const inCore = r >= 2 && r <= 4 && c >= 2 && c <= 4;
      const onPattern = r >= 0 && r <= 6 && c >= 0 && c <= 6;
      grid[rr][cc] = onPattern ? inBorder || inCore : false;
    }
  };
  drawFinder(0, 0);
  drawFinder(0, size - 7);
  drawFinder(size - 7, 0);
  for (let i = 8; i < size - 8; i++) {
    const v = i % 2 === 0;
    grid[6][i] = v;
    grid[i][6] = v;
  }
  const ap = ALIGN_POS[version];
  for (const r of ap) for (const c of ap) {
    const isFinder =
      (r <= 8 && c <= 8) || (r <= 8 && c >= size - 9) || (r >= size - 9 && c <= 8);
    if (isFinder) continue;
    for (let dr = -2; dr <= 2; dr++) for (let dc = -2; dc <= 2; dc++) {
      const ring = Math.max(Math.abs(dr), Math.abs(dc));
      grid[r + dr][c + dc] = ring !== 1;
    }
  }
  grid[size - 8][8] = true; // dark module
  // version information (v ≥ 7): 18 bits, LSB-first, mirrored into both blocks.
  if (version >= 7) {
    const info = VERSION_INFO[version];
    for (let i = 0; i < 18; i++) {
      const bit = ((info >> i) & 1) === 1;
      const row = Math.floor(i / 3);
      const col = i % 3;
      grid[size - 11 + col][row] = bit; // bottom-left
      grid[row][size - 11 + col] = bit; // top-right
    }
  }
}

function placeData(grid: Grid, reserved: boolean[][], size: number, codewords: number[]) {
  let bitIdx = 0;
  const bitAt = (i: number) => (codewords[i >> 3] >> (7 - (i & 7))) & 1;
  let upward = true;
  for (let col = size - 1; col > 0; col -= 2) {
    if (col === 6) col--; // skip timing column
    for (let i = 0; i < size; i++) {
      const row = upward ? size - 1 - i : i;
      for (let c = 0; c < 2; c++) {
        const cc = col - c;
        if (reserved[row][cc]) continue;
        const bit = bitIdx < codewords.length * 8 ? bitAt(bitIdx) : 0;
        grid[row][cc] = bit === 1;
        bitIdx++;
      }
    }
    upward = !upward;
  }
}

const MASKS: ((r: number, c: number) => boolean)[] = [
  (r, c) => (r + c) % 2 === 0,
  (r) => r % 2 === 0,
  (_r, c) => c % 3 === 0,
  (r, c) => (r + c) % 3 === 0,
  (r, c) => (Math.floor(r / 2) + Math.floor(c / 3)) % 2 === 0,
  (r, c) => ((r * c) % 2) + ((r * c) % 3) === 0,
  (r, c) => (((r * c) % 2) + ((r * c) % 3)) % 2 === 0,
  (r, c) => (((r + c) % 2) + ((r * c) % 3)) % 2 === 0,
];

function applyMask(grid: Grid, reserved: boolean[][], size: number, maskFn: (r: number, c: number) => boolean): Grid {
  const out: Grid = grid.map((row) => row.slice());
  for (let r = 0; r < size; r++) for (let c = 0; c < size; c++) {
    if (reserved[r][c]) continue;
    if (maskFn(r, c)) out[r][c] = !out[r][c];
  }
  return out;
}

function penalty(grid: Grid, size: number): number {
  let score = 0;
  const at = (r: number, c: number) => grid[r][c] === true;
  // rule 1: runs ≥5
  for (let r = 0; r < size; r++) {
    let run = 1;
    for (let c = 1; c < size; c++) {
      if (at(r, c) === at(r, c - 1)) run++;
      else {
        if (run >= 5) score += 3 + (run - 5);
        run = 1;
      }
    }
    if (run >= 5) score += 3 + (run - 5);
  }
  for (let c = 0; c < size; c++) {
    let run = 1;
    for (let r = 1; r < size; r++) {
      if (at(r, c) === at(r - 1, c)) run++;
      else {
        if (run >= 5) score += 3 + (run - 5);
        run = 1;
      }
    }
    if (run >= 5) score += 3 + (run - 5);
  }
  // rule 2: 2×2 blocks
  for (let r = 0; r < size - 1; r++) for (let c = 0; c < size - 1; c++) {
    const v = at(r, c);
    if (v === at(r, c + 1) && v === at(r + 1, c) && v === at(r + 1, c + 1)) score += 3;
  }
  // rule 3: finder-like 1:1:3:1:1 patterns (dark-light-dark-dark-dark-light-dark) with a
  // 4-module light run on either side → +40 each, both orientations.
  const pat1 = [true, false, true, true, true, false, true, false, false, false, false];
  const pat2 = [false, false, false, false, true, false, true, true, true, false, true];
  const matchAt = (get: (i: number) => boolean, n: number, start: number, pat: boolean[]) => {
    if (start + pat.length > n) return false;
    for (let k = 0; k < pat.length; k++) if (get(start + k) !== pat[k]) return false;
    return true;
  };
  for (let r = 0; r < size; r++) {
    for (let c = 0; c <= size - 11; c++) {
      const get = (i: number) => at(r, i);
      if (matchAt(get, size, c, pat1) || matchAt(get, size, c, pat2)) score += 40;
    }
  }
  for (let c = 0; c < size; c++) {
    for (let r = 0; r <= size - 11; r++) {
      const get = (i: number) => at(i, c);
      if (matchAt(get, size, r, pat1) || matchAt(get, size, r, pat2)) score += 40;
    }
  }
  // rule 4: dark proportion
  let dark = 0;
  for (let r = 0; r < size; r++) for (let c = 0; c < size; c++) if (at(r, c)) dark++;
  const pct = (dark * 100) / (size * size);
  score += Math.floor(Math.abs(pct - 50) / 5) * 10;
  return score;
}

// Format info (level M = 0b00) BCH-encoded + masked, by mask pattern index.
const FORMAT_BITS_M = [
  0x5412, 0x5125, 0x5e7c, 0x5b4b, 0x45f9, 0x40ce, 0x4f97, 0x4aa0,
];

function placeFormat(grid: Grid, size: number, maskIdx: number) {
  const bits = FORMAT_BITS_M[maskIdx];
  const get = (i: number) => ((bits >> i) & 1) === 1; // bit 0 = LSB
  // Copy 1 — around the top-left finder (ISO/IEC 18004 §8.9 placement).
  for (let i = 0; i <= 5; i++) grid[i][8] = get(i); // bits 0–5 down column 8
  grid[7][8] = get(6);
  grid[8][8] = get(7);
  grid[8][7] = get(8);
  for (let i = 9; i <= 14; i++) grid[8][14 - i] = get(i); // bits 9–14 along row 8 (cols 5→0)
  // Copy 2 — split across the top-right (row 8) and bottom-left (column 8) finders.
  for (let i = 0; i <= 7; i++) grid[8][size - 1 - i] = get(i);
  for (let i = 8; i <= 14; i++) grid[size - 15 + i][8] = get(i);
}

function encode(text: string): { matrix: boolean[][]; size: number } {
  const bytes = Array.from(new TextEncoder().encode(text));
  const version = pickVersion(bytes.length);
  const [b1, d1, b2, d2] = EC_BLOCKS_M[version];
  const totalDataCw = b1 * d1 + b2 * d2;
  const dataCw = buildBitstream(bytes, version, totalDataCw);
  const finalCw = assembleCodewords(dataCw, version);

  const size = 17 + version * 4;
  const reserved = reservedMatrix(size, version);
  const base: Grid = Array.from({ length: size }, () => new Array(size).fill(null));
  placePatterns(base, size, version);
  placeData(base, reserved, size, finalCw);

  let best: Grid | null = null;
  let bestScore = Infinity;
  let bestMask = 0;
  for (let m = 0; m < 8; m++) {
    const masked = applyMask(base, reserved, size, MASKS[m]);
    placeFormat(masked, size, m);
    const s = penalty(masked, size);
    if (s < bestScore) {
      bestScore = s;
      best = masked;
      bestMask = m;
    }
  }
  const chosen = best ?? base;
  placeFormat(chosen, size, bestMask);
  const matrix = chosen.map((row) => row.map((v) => v === true));
  return { matrix, size };
}

export interface QrCodeProps {
  /** The text to encode (here: an `otpauth://` provisioning URI). */
  value: string;
  /** Rendered pixel size of the square (default 184). */
  size?: number;
  className?: string;
}

/** Renders `value` as a scannable QR (inline SVG, no network, no dependency). 4-module quiet zone. */
export function QrCode({ value, size = 184, className }: QrCodeProps) {
  const { matrix, modules } = useMemo(() => {
    const enc = encode(value);
    return { matrix: enc.matrix, modules: enc.size };
  }, [value]);

  const quiet = 4;
  const dim = modules + quiet * 2;
  const rects: string[] = [];
  for (let r = 0; r < modules; r++) {
    for (let c = 0; c < modules; c++) {
      if (matrix[r][c]) rects.push(`M${c + quiet} ${r + quiet}h1v1h-1z`);
    }
  }
  return (
    <svg
      width={size}
      height={size}
      viewBox={`0 0 ${dim} ${dim}`}
      shapeRendering="crispEdges"
      role="img"
      aria-label="QR code"
      className={className}
    >
      <rect width={dim} height={dim} fill="#ffffff" />
      <path d={rects.join("")} fill="#000000" />
    </svg>
  );
}
