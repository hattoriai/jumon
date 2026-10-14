import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fold, score } from "../src/match";

interface Case {
  action: { name: string; keywords: string[]; subtitle: string | null; section: string | null; priority: number };
  query: string;
  expected: { score: number; positions: number[] } | null;
}

// The same results as Jumon.Match in Elixir, which wrote the fixture.
const cases = JSON.parse(readFileSync("../test/fixtures/match.json", "utf8")) as Case[];

test("the matcher gives the results of Jumon.Match", () => {
  assert.ok(cases.length > 40);
  for (const { action, query, expected } of cases) {
    const result = score({ ...action, subtitle: action.subtitle ?? undefined, section: action.section ?? undefined }, query);
    assert.deepEqual(result, expected, `${JSON.stringify(query)} in ${JSON.stringify(action.name)}`);
  }
});

test("folding ignores case, accents and width", () => {
  assert.equal(fold("Café ＡＢ"), "cafe ab");
  assert.equal(fold("Ärger"), "arger");
});

test("an exact name ranks before a prefix, and a prefix before the rest", () => {
  const exact = score({ name: "Home" }, "home")!.score;
  const prefix = score({ name: "Homepage" }, "home")!.score;
  const inside = score({ name: "My home" }, "home")!.score;
  assert.ok(exact > prefix && prefix > inside);
});

test("each word of the query must match", () => {
  assert.equal(score({ name: "New issue" }, "new zebra"), null);
  assert.notEqual(score({ name: "New issue", keywords: ["create"] }, "create issue"), null);
});
