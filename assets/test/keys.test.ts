import { test } from "node:test";
import assert from "node:assert/strict";
import { eventChord, parseShortcut, Sequences, shortcutLabels } from "../src/keys";

const key = (init: Partial<KeyboardEvent> & { key: string }): KeyboardEvent =>
  ({ metaKey: false, ctrlKey: false, altKey: false, shiftKey: false, code: "", ...init }) as KeyboardEvent;

test("mod is ⌘ on Apple devices and Ctrl elsewhere", () => {
  assert.deepEqual(parseShortcut("mod+k", true), ["mod+k"]);
  assert.equal(eventChord(key({ key: "k", metaKey: true }), true), "mod+k");
  assert.equal(eventChord(key({ key: "k", ctrlKey: true }), true), "ctrl+k");
  assert.equal(eventChord(key({ key: "k", ctrlKey: true }), false), "mod+k");
  assert.deepEqual(parseShortcut("ctrl+k", false), ["mod+k"]);
});

test("shift is part of the key for punctuation", () => {
  assert.equal(eventChord(key({ key: "?", shiftKey: true }), false), "?");
  assert.deepEqual(parseShortcut("shift+?", false), ["?"]);
  assert.equal(eventChord(key({ key: "P", shiftKey: true, metaKey: true }), true), "mod+shift+p");
});

test("alt reads the code of the key", () => {
  assert.equal(eventChord(key({ key: "π", altKey: true, code: "KeyP" }), true), "alt+p");
});

test("sequences match after their last chord, within the timeout", () => {
  const sequences = new Sequences([{ chords: ["g", "h"], value: "home" }, { chords: ["c"], value: "create" }], 1000);
  assert.equal(sequences.feed("g", 0), "pending");
  assert.deepEqual(sequences.feed("h", 500), { match: "home" });
  assert.equal(sequences.feed("g", 1000), "pending");
  assert.equal(sequences.feed("h", 3000), null);
  assert.deepEqual(sequences.feed("c", 3100), { match: "create" });
  assert.equal(sequences.feed("x", 3200), null);
});

test("labels for the platform", () => {
  assert.deepEqual(shortcutLabels("mod+shift+p", true), [["⌘", "⇧", "P"]]);
  assert.deepEqual(shortcutLabels("mod+k", false), [["Ctrl", "K"]]);
  assert.deepEqual(shortcutLabels("g h", false), [["G"], ["H"]]);
  assert.deepEqual(shortcutLabels("mod+enter", true), [["⌘", "↵"]]);
});
