// What a person runs from the palette, for "Recent" and for the order of
// the results: in the browser (localStorage), on the server (through the
// LiveView, see Jumon.History), or nowhere. The score is the frecency of
// Jumon.History: one for each use, halved every 14 days.

import type { ActionData } from "./types";

const HALF_LIFE_DAYS = 14;
const MAX_ENTRIES = 200;
const DAY = 86_400_000;

export interface Entry {
  id: string;
  score: number;
  usedAt: number;
  action: ActionData | null;
}

/** The score of an entry now. */
export function frecency(score: number, usedAt: number, now = Date.now()): number {
  const days = Math.max(now - usedAt, 0) / DAY;
  return score * Math.pow(0.5, days / HALF_LIFE_DAYS);
}

export interface History {
  /** The entries, best first. */
  recent(limit: number): Promise<Entry[]>;
  /** Records a use; the promise settles when the record is kept (at once in the browser). */
  record(action: ActionData): Promise<void>;
  forget(id: string): void;
  /** The score of each action, now, for the order of the results. */
  scores(): Map<string, number>;
}

/** A history that keeps nothing. */
export class NoHistory implements History {
  async recent(): Promise<Entry[]> {
    return [];
  }
  async record(): Promise<void> {}
  forget(): void {}
  scores(): Map<string, number> {
    return new Map();
  }
}

/** What an action keeps of itself in the history: no secondary actions. */
function snapshot(action: ActionData): ActionData {
  const { actions: _actions, ...rest } = action;
  return rest;
}

/** The history of this browser, in localStorage, by the palette's key. */
export class LocalHistory implements History {
  private entries: Map<string, Entry>;

  constructor(private key: string) {
    this.entries = this.load();
  }

  async recent(limit: number): Promise<Entry[]> {
    return this.ranked().slice(0, limit);
  }

  async record(action: ActionData): Promise<void> {
    const now = Date.now();
    const old = this.entries.get(action.id);
    const score = old ? frecency(old.score, old.usedAt, now) + 1 : 1;
    this.entries.set(action.id, { id: action.id, score, usedAt: now, action: snapshot(action) });
    if (this.entries.size > MAX_ENTRIES) {
      const oldest = [...this.entries.values()].sort((a, b) => a.usedAt - b.usedAt);
      for (const entry of oldest.slice(0, this.entries.size - MAX_ENTRIES)) this.entries.delete(entry.id);
    }
    this.save();
  }

  forget(id: string): void {
    this.entries.delete(id);
    this.save();
  }

  scores(): Map<string, number> {
    const now = Date.now();
    return new Map([...this.entries.values()].map((entry) => [entry.id, frecency(entry.score, entry.usedAt, now)]));
  }

  private ranked(): Entry[] {
    const now = Date.now();
    return [...this.entries.values()]
      .map((entry) => ({ ...entry, score: frecency(entry.score, entry.usedAt, now) }))
      .sort((a, b) => b.score - a.score || (a.id < b.id ? -1 : 1));
  }

  private load(): Map<string, Entry> {
    try {
      const raw = JSON.parse(window.localStorage.getItem(this.key) ?? "[]") as Entry[];
      return new Map(raw.filter((entry) => typeof entry?.id === "string").map((entry) => [entry.id, entry]));
    } catch {
      return new Map();
    }
  }

  private save(): void {
    try {
      window.localStorage.setItem(this.key, JSON.stringify([...this.entries.values()]));
    } catch {
      // Private browsing, or storage full: the history lives for the page.
    }
  }
}

export type Push = (event: string, payload: Record<string, unknown>, onReply?: (reply: Record<string, unknown>) => void) => void;

/** The history on the server, through the LiveView. */
export class ServerHistory implements History {
  private cache: Entry[] | null = null;

  constructor(private push: Push) {}

  recent(limit: number): Promise<Entry[]> {
    return new Promise((resolve) => {
      if (this.cache) return resolve(this.cache.slice(0, limit));
      this.push("jumon:recent", { v: 1, limit: Math.max(limit, 20) }, (reply) => {
        const items = Array.isArray(reply.items) ? (reply.items as Array<Record<string, unknown>>) : [];
        this.cache = items.map((item) => ({
          id: String(item.id),
          score: Number(item.score) || 0,
          usedAt: Date.parse(String(item.usedAt)) || Date.now(),
          action: (item.action as ActionData | null) ?? null,
        }));
        resolve(this.cache.slice(0, limit));
      });
    });
  }

  record(action: ActionData): Promise<void> {
    this.bump(action);
    // An action that runs on the server is recorded there when it runs.
    if (action.perform?.type === "server") return Promise.resolve();
    // The promise settles on the reply, or after a moment: a navigation
    // waits for it, so that the LiveView it leaves gets the event.
    return new Promise((resolve) => {
      const timer = setTimeout(resolve, 300);
      this.push("jumon:used", { v: 1, id: action.id }, () => {
        clearTimeout(timer);
        resolve();
      });
    });
  }

  forget(id: string): void {
    if (this.cache) this.cache = this.cache.filter((entry) => entry.id !== id);
    this.push("jumon:forget", { v: 1, id });
  }

  scores(): Map<string, number> {
    const now = Date.now();
    return new Map((this.cache ?? []).map((entry) => [entry.id, frecency(entry.score, entry.usedAt, now)]));
  }

  private bump(action: ActionData): void {
    if (!this.cache) return;
    const now = Date.now();
    const old = this.cache.find((entry) => entry.id === action.id);
    const score = old ? frecency(old.score, old.usedAt, now) + 1 : 1;
    this.cache = [{ id: action.id, score, usedAt: now, action: snapshot(action) }, ...this.cache.filter((entry) => entry.id !== action.id)].sort((a, b) => frecency(b.score, b.usedAt, now) - frecency(a.score, a.usedAt, now));
  }
}
