import { test } from "node:test";
import assert from "node:assert/strict";
import { frecency, LocalHistory } from "../src/history";

const store = new Map<string, string>();
(globalThis as unknown as { window: unknown }).window = {
  localStorage: {
    getItem: (key: string) => store.get(key) ?? null,
    setItem: (key: string, value: string) => void store.set(key, value),
  },
};

test("the score halves every 14 days", () => {
  assert.equal(frecency(4, 0, 14 * 86_400_000), 2);
  assert.equal(frecency(4, 0, 0), 4);
});

test("the local history ranks by frecency and forgets", async () => {
  const history = new LocalHistory("test");
  history.record({ id: "a", name: "A" });
  history.record({ id: "b", name: "B" });
  history.record({ id: "b", name: "B" });
  assert.deepEqual((await history.recent(5)).map((entry) => entry.id), ["b", "a"]);
  assert.ok((history.scores().get("b") ?? 0) > 1.9);
  history.forget("b");
  assert.deepEqual((await new LocalHistory("test").recent(5)).map((entry) => entry.id), ["a"]);
});
