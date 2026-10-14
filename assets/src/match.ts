// How the palette matches and ranks actions: the same rules, and the same
// numbers, as Jumon.Match in Elixir (test/fixtures/match.json holds the
// two to the same results).

import type { ActionData } from "./types";

const BASE = 16;
const START_BONUS = 24;
const WORD_BONUS = 16;
const CONSECUTIVE = 20;
const LEAD_CAP = 12;
const EXACT = 1000;
const PREFIX = 200;
const KEYWORD_COST = 40;
const SUBTITLE_COST = 60;
const SECTION_COST = 80;
const TYPO = 8;

export interface MatchResult {
  score: number;
  /** The characters of the name to highlight, by index (code points). */
  positions: number[];
}

const MARK = /\p{Mn}/gu;
const ALNUM = /^[\p{L}\p{N}]$/u;

function foldChar(char: string): string {
  return char.normalize("NFKD").replace(MARK, "").toLowerCase();
}

/** Folds a text: decomposed (NFKD), without marks, in lower case, character by character. */
export function fold(text: string): string {
  let out = "";
  for (const char of text) out += foldChar(char);
  return out;
}

interface Field {
  text: string;
  chars: string[];
  /** For each folded character, the index of the character it came from. */
  origin: number[];
}

const fieldCache = new Map<string, Field>();

function folded(text: string): Field {
  const cached = fieldCache.get(text);
  if (cached) return cached;
  const chars: string[] = [];
  const origin: number[] = [];
  let index = 0;
  for (const char of text) {
    for (const part of foldChar(char)) {
      chars.push(part);
      origin.push(index);
    }
    index++;
  }
  const field = { text: chars.join(""), chars, origin };
  if (fieldCache.size > 5000) fieldCache.clear();
  fieldCache.set(text, field);
  return field;
}

const isAlnum = (char: string | undefined): boolean => char !== undefined && ALNUM.test(char);

function bonus(text: string[], j: number): number {
  if (j === 0) return BASE + START_BONUS;
  if (!isAlnum(text[j - 1])) return BASE + WORD_BONUS;
  return BASE;
}

type Cell = { score: number; from: number | null } | null;

// The best alignment of the query's characters in order in the text.
function subsequence(query: string[], text: string[]): [number, number[]] | null {
  const n = query.length;
  const m = text.length;
  if (n === 0 || n > m) return null;

  const rows: Cell[][] = [];
  const first: Cell[] = [];
  for (let j = 0; j < m; j++) {
    first.push(text[j] === query[0] ? { score: bonus(text, j) - Math.min(j, LEAD_CAP), from: null } : null);
  }
  rows.push(first);

  for (let i = 1; i < n; i++) {
    const previous = rows[i - 1]!;
    const row: Cell[] = [];
    let best: [number, number] | null = null;
    for (let j = 0; j < m; j++) {
      if (j >= 2) {
        const cell = previous[j - 2];
        if (cell) {
          const candidate = cell.score + (j - 2);
          if (best === null || candidate > best[0]) best = [candidate, j - 2];
        }
      }
      let cell: Cell = null;
      if (j >= i && text[j] === query[i]) {
        const before = j >= 1 ? previous[j - 1] : null;
        const consecutive: [number, number] | null = before ? [before.score + CONSECUTIVE, j - 1] : null;
        const gap: [number, number] | null = best ? [best[0] - (j - 1), best[1]] : null;
        let pick: [number, number] | null;
        if (consecutive === null) pick = gap;
        else if (gap === null) pick = consecutive;
        else pick = consecutive[0] >= gap[0] ? consecutive : gap;
        if (pick) cell = { score: bonus(text, j) + pick[0], from: pick[1] };
      }
      row.push(cell);
    }
    rows.push(row);
  }

  const last = rows[n - 1]!;
  let end: number | null = null;
  for (let j = 0; j < m; j++) {
    const cell = last[j];
    if (!cell) continue;
    if (end === null || cell.score > last[end]!.score) end = j;
  }
  if (end === null) return null;

  const positions: number[] = [];
  let j: number | null = end;
  for (let i = n - 1; i >= 0 && j !== null; i--) {
    positions.unshift(j);
    j = rows[i]![j]!.from;
  }
  return [last[end]!.score, positions];
}

function words(chars: string[]): Array<[number, string[]]> {
  const out: Array<[number, string[]]> = [];
  let start = -1;
  for (let i = 0; i <= chars.length; i++) {
    const alnum = i < chars.length && isAlnum(chars[i]);
    if (alnum && start < 0) start = i;
    if (!alnum && start >= 0) {
      out.push([start, chars.slice(start, i)]);
      start = -1;
    }
  }
  return out;
}

// The optimal string alignment distance.
function distance(a: string[], b: string[]): number {
  const n = a.length;
  const m = b.length;
  const d: number[][] = Array.from({ length: n + 1 }, () => new Array<number>(m + 1).fill(0));
  for (let i = 0; i <= n; i++) d[i]![0] = i;
  for (let j = 0; j <= m; j++) d[0]![j] = j;
  for (let i = 1; i <= n; i++) {
    for (let j = 1; j <= m; j++) {
      const cost = a[i - 1] === b[j - 1] ? 0 : 1;
      let best = Math.min(d[i - 1]![j]! + 1, d[i]![j - 1]! + 1, d[i - 1]![j - 1]! + cost);
      if (i > 1 && j > 1 && a[i - 1] === b[j - 2] && a[i - 2] === b[j - 1]) best = Math.min(best, d[i - 2]![j - 2]! + 1);
      d[i]![j] = best;
    }
  }
  return d[n]![m]!;
}

function typoIn(word: string[], chars: string[]): [number, number] | null {
  const n = word.length;
  for (const [start, token] of words(chars)) {
    for (const length of [n, n - 1, n + 1]) {
      const prefix = token.slice(0, length);
      if (length > 0 && prefix.length === length && distance(word, prefix) <= 1) return [start, length];
    }
  }
  return null;
}

// A match of letters next to each other, else null: the other fields of an
// action only match so.
function contiguous(result: [number, number[]] | null): [number, number[]] | null {
  if (result === null) return null;
  const positions = result[1];
  return positions[positions.length - 1]! - positions[0]! === positions.length - 1 ? result : null;
}

function better(a: [number, number[]] | null, b: [number, number[]] | null): [number, number[]] | null {
  if (a === null) return b;
  if (b === null) return a;
  return b[0] > a[0] ? b : a;
}

function best(word: string[], name: Field, keywords: Field[], subtitle: Field | null, section: Field | null): [number, number[]] | null {
  let found: [number, number[]] | null = subsequence(word, name.chars);

  let keyword: [number, number[]] | null = null;
  for (const field of keywords) {
    const result = contiguous(subsequence(word, field.chars));
    if (result && (keyword === null || result[0] > keyword[0])) keyword = result;
  }
  if (keyword) found = better(found, [keyword[0] - KEYWORD_COST, []]);

  if (subtitle) {
    const result = contiguous(subsequence(word, subtitle.chars));
    if (result) found = better(found, [result[0] - SUBTITLE_COST, []]);
  }
  if (section) {
    const result = contiguous(subsequence(word, section.chars));
    if (result) found = better(found, [result[0] - SECTION_COST, []]);
  }
  if (found) return found;

  if (word.length < 4) return null;
  const typo = typoIn(word, name.chars);
  if (typo) {
    const positions: number[] = [];
    for (let i = typo[0]; i < typo[0] + typo[1]; i++) positions.push(i);
    return [TYPO * word.length, positions];
  }
  if (keywords.some((field) => typoIn(word, field.chars))) return [TYPO * word.length - KEYWORD_COST, []];
  return null;
}

/** Splits a folded query into its words. */
export function queryWords(query: string): string[] {
  return fold(query)
    .split(/\s+/u)
    .filter((word) => word !== "");
}

/** The score of an action for a query, or null when it does not match. */
export function score(action: Pick<ActionData, "name" | "keywords" | "subtitle" | "section" | "priority">, query: string): MatchResult | null {
  const priority = action.priority ?? 0;
  const list = queryWords(query);
  if (list.length === 0) return { score: priority, positions: [] };

  const name = folded(action.name);
  const keywords = (action.keywords ?? []).map(folded);
  const subtitle = action.subtitle ? folded(action.subtitle) : null;
  const section = action.section ? folded(action.section) : null;

  let total = 0;
  let positions: number[] = [];
  for (const word of list) {
    const result = best(Array.from(word), name, keywords, subtitle, section);
    if (result === null) return null;
    total += result[0];
    positions = positions.concat(result[1]);
  }

  const whole = list.join(" ");
  const extra = name.text === whole ? EXACT : name.text.startsWith(whole) ? PREFIX : 0;
  const mapped = Array.from(new Set(positions.map((index) => name.origin[index]!))).sort((a, b) => a - b);
  return { score: total + extra - Math.floor(Math.min(name.chars.length, 40) / 4) + priority, positions: mapped };
}
