// Keyboard shortcuts: the same form as Jumon.Shortcut ("mod+k", "g h",
// "shift+?"), matched against key events, and shown for the platform
// (⌘K on Apple devices, Ctrl+K elsewhere).

const MODIFIERS = ["mod", "ctrl", "alt", "shift", "meta"] as const;
type Modifier = (typeof MODIFIERS)[number];

const NAMED: Record<string, string> = {
  arrowup: "up",
  arrowdown: "down",
  arrowleft: "left",
  arrowright: "right",
  " ": "space",
  spacebar: "space",
  esc: "escape",
  del: "delete",
};

/** Whether the device is an Apple one, where `mod` is ⌘. */
export function isApple(): boolean {
  if (typeof navigator === "undefined") return false;
  const platform = (navigator as Navigator & { userAgentData?: { platform?: string } }).userAgentData?.platform ?? navigator.platform ?? "";
  return /mac|iphone|ipad|ipod/i.test(platform) || (/mac/i.test(navigator.userAgent) && !/android/i.test(navigator.userAgent));
}

const isLetter = (key: string): boolean => /^[a-z]$/.test(key);

/**
 * A chord in its canonical form for this platform: `mod` for ⌘ on Apple
 * devices and Ctrl elsewhere, and no `shift` with a key that shift makes
 * (`?`, `!`), which the key already says.
 */
function canonical(modifiers: Set<Modifier>, key: string, apple: boolean): string {
  const set = new Set(modifiers);
  if (apple && set.has("meta")) {
    set.delete("meta");
    set.add("mod");
  }
  if (!apple && set.has("ctrl")) {
    set.delete("ctrl");
    set.add("mod");
  }
  if (set.has("shift") && key.length === 1 && !isLetter(key) && !/^[0-9]$/.test(key)) set.delete("shift");
  return [...MODIFIERS.filter((modifier) => set.has(modifier)), key].join("+");
}

/** Parses a normalized shortcut into its chords, canonical for this platform. */
export function parseShortcut(shortcut: string, apple = isApple()): string[] {
  return shortcut
    .split(/\s+/)
    .filter((chord) => chord !== "")
    .map((chord) => {
      const parts = chord === "+" ? ["+"] : chord.endsWith("++") ? [...chord.slice(0, -2).split("+"), "+"] : chord.split("+");
      const key = parts.pop() ?? "";
      return canonical(new Set(parts as Modifier[]), key, apple);
    });
}

/** The key of an event, in the names of shortcuts; null for a modifier alone. */
export function eventKey(event: KeyboardEvent): string | null {
  const raw = event.key;
  if (raw === undefined || ["Shift", "Control", "Alt", "Meta", "OS", "Dead", "Unidentified", "Process"].includes(raw)) return null;
  // With Alt (Option), the key is often another character: read the code.
  if (event.altKey && event.code) {
    const code = /^Key([A-Z])$/.exec(event.code) ?? /^Digit([0-9])$/.exec(event.code);
    if (code) return code[1]!.toLowerCase();
  }
  const lower = raw.toLowerCase();
  return NAMED[lower] ?? lower;
}

/** The chord of a key event, canonical for this platform, or null. */
export function eventChord(event: KeyboardEvent, apple = isApple()): string | null {
  const key = eventKey(event);
  if (key === null) return null;
  const modifiers = new Set<Modifier>();
  if (event.metaKey) modifiers.add("meta");
  if (event.ctrlKey) modifiers.add("ctrl");
  if (event.altKey) modifiers.add("alt");
  if (event.shiftKey) modifiers.add("shift");
  return canonical(modifiers, key, apple);
}

/** Whether a chord has a modifier other than shift (it works in a text field). */
export function hasCommandModifier(chord: string): boolean {
  return /(^|\+)(mod|ctrl|alt|meta)\+/.test(chord);
}

const APPLE_LABELS: Record<string, string> = { mod: "⌘", ctrl: "⌃", alt: "⌥", shift: "⇧", meta: "⌘" };
const OTHER_LABELS: Record<string, string> = { mod: "Ctrl", ctrl: "Ctrl", alt: "Alt", shift: "Shift", meta: "Win" };
const KEY_LABELS: Record<string, string> = {
  enter: "↵",
  escape: "Esc",
  backspace: "⌫",
  delete: "Del",
  tab: "Tab",
  space: "Space",
  up: "↑",
  down: "↓",
  left: "←",
  right: "→",
  home: "Home",
  end: "End",
  pageup: "PgUp",
  pagedown: "PgDn",
};

/** The keys of a shortcut to show, chord by chord: [["⌘", "K"], ["G"], ["H"]]. */
export function shortcutLabels(shortcut: string, apple = isApple()): string[][] {
  return parseShortcut(shortcut, apple).map((chord) => {
    const parts = chord === "+" ? ["+"] : chord.endsWith("++") ? [...chord.slice(0, -2).split("+"), "+"] : chord.split("+");
    const key = parts.pop() ?? "";
    const labels = parts.map((modifier) => (apple ? APPLE_LABELS : OTHER_LABELS)[modifier] ?? modifier);
    labels.push(KEY_LABELS[key] ?? (key.length === 1 ? key.toUpperCase() : key.charAt(0).toUpperCase() + key.slice(1)));
    return labels;
  });
}

/** The words of a shortcut for a screen reader or a title: "⌘ K, then G". */
export function shortcutText(shortcut: string, apple = isApple()): string {
  return shortcutLabels(shortcut, apple)
    .map((chord) => chord.join(apple ? "" : "+"))
    .join(" ");
}

/** Whether the target of a key event takes text, where single keys type. */
export function isEditable(target: EventTarget | null): boolean {
  if (!(target instanceof Element)) return false;
  if (target.closest('[contenteditable]:not([contenteditable="false"])')) return true;
  if (target instanceof HTMLTextAreaElement || target instanceof HTMLSelectElement) return true;
  if (target instanceof HTMLInputElement) {
    return !["button", "checkbox", "radio", "submit", "reset", "range", "color", "file", "image"].includes(target.type);
  }
  return false;
}

export interface Binding<T> {
  chords: string[];
  value: T;
}

/**
 * Matches key sequences ("g h") against bindings. Each chord is fed in
 * turn; a sequence that waits more than `timeout` ms between chords starts
 * again.
 */
export class Sequences<T> {
  private buffer: string[] = [];
  private last = 0;

  constructor(
    private bindings: Binding<T>[],
    private timeout = 1000,
  ) {}

  setBindings(bindings: Binding<T>[]): void {
    this.bindings = bindings;
    this.buffer = [];
  }

  /**
   * Feeds a chord. Returns `{match}` when a binding is complete, `"pending"`
   * when the chords so far start a binding, or null.
   */
  feed(chord: string, now = Date.now()): { match: T } | "pending" | null {
    if (now - this.last > this.timeout) this.buffer = [];
    this.last = now;
    this.buffer.push(chord);
    if (this.buffer.length > 4) this.buffer = this.buffer.slice(-4);

    for (let start = 0; start < this.buffer.length; start++) {
      const tail = this.buffer.slice(start);
      const exact = this.bindings.find((binding) => sameChords(binding.chords, tail));
      if (exact) {
        this.buffer = [];
        return { match: exact.value };
      }
      if (this.bindings.some((binding) => binding.chords.length > tail.length && sameChords(binding.chords.slice(0, tail.length), tail))) {
        this.buffer = tail;
        return "pending";
      }
    }
    this.buffer = [];
    return null;
  }

  reset(): void {
    this.buffer = [];
  }
}

function sameChords(a: string[], b: string[]): boolean {
  return a.length === b.length && a.every((chord, index) => chord === b[index]);
}
