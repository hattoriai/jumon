// The palette: a modal dialog with a search box and a list of results,
// pages for the children and the arguments of an action, a menu of the
// actions of a result, and the keyboard shortcuts of the page.
//
// The list is a WAI-ARIA combobox: the box keeps the focus, and the
// active result is its aria-activedescendant. Its rows have fixed heights
// (the --jumon-item-height and --jumon-heading-height properties), so a
// list of thousands renders only the rows in view.

import { append, el, format, uid } from "./dom";
import { type Entry, type History, LocalHistory, NoHistory, ServerHistory } from "./history";
import * as icons from "./icons";
import { type Binding, eventChord, hasCommandModifier, isApple, isEditable, parseShortcut, Sequences, shortcutLabels, shortcutText } from "./keys";
import { score } from "./match";
import { type ActionData, type ArgSpec, type Config, readConfig } from "./types";

/** What the hook gives the palette: the LiveView, or nothing on a page without it. */
export interface Live {
  push(event: string, payload: Record<string, unknown>, onReply?: (reply: Record<string, unknown>) => void): void;
  pushEvent(event: string, value: Record<string, unknown>, target?: string): void;
  navigate(to: string, replace: boolean): void;
  patch(to: string, replace: boolean): void;
  exec(js: string): void;
}

/** An action of the palette's own: the actions of a result, and the help. */
interface Item extends ActionData {
  internal?: "newTab" | "copyLink" | "forget" | "help" | "info";
  internalIcon?: icons.Icon;
  target?: ActionData;
}

type Page =
  | { kind: "root"; query: string }
  | { kind: "children"; action: Item; query: string }
  | { kind: "arg"; action: Item; index: number; values: Record<string, string | null>; labels: string[]; query: string }
  | { kind: "help"; query: string };

type Row =
  | { kind: "heading"; label: string }
  | { kind: "item"; action: Item; positions: number[]; recent?: boolean; trail?: string }
  | { kind: "status"; text: string; tone: "loading" | "error" | "empty" | "hint"; retry?: boolean };

interface Remote {
  ref: number;
  query: string;
  key: string;
  results: Map<string, ActionData[]>;
  pending: Set<string>;
  errors: Set<string>;
}

type Bound = { kind: "open" } | { kind: "help" } | { kind: "action"; action: Item };

const OVERSCAN = 6;
const DEBOUNCE = 140;

export class Palette {
  readonly id: string;
  private config: Config;
  private apple = isApple();
  private actions = new Map<string, Item>();
  private children = new Map<string, Item[]>();
  private history: History;

  private dialog: HTMLDialogElement;
  private panel: HTMLElement;
  private crumbs: HTMLElement;
  private input: HTMLInputElement;
  private searchIcon: HTMLElement;
  private list: HTMLElement;
  private inner: HTMLElement;
  private message: HTMLElement;
  private footer: HTMLElement;
  private announcer: HTMLElement;
  private menu: HTMLElement;
  private listId: string;

  private isOpen = false;
  private stack: Page[] = [{ kind: "root", query: "" }];
  private rows: Row[] = [];
  private offsets: number[] = [];
  private active = -1;
  // The query of the last refresh: a refresh for the same query (results
  // that came in) keeps the active result.
  private lastQuery = "";
  private itemHeight = 44;
  private headingHeight = 32;
  private measured = false;
  private recent: Entry[] = [];
  private remote: Remote | null = null;
  private refCounter = 0;
  private debounce: ReturnType<typeof setTimeout> | null = null;
  private announceTimer: ReturnType<typeof setTimeout> | null = null;
  private menuState: { items: Item[]; active: number; of: Item } | null = null;
  private confirming: { action: Item; values?: Record<string, string | null> } | null = null;
  private busy = false;
  private returnFocus: HTMLElement | null = null;
  private sequences = new Sequences<Bound>([]);
  private onKeydown = (event: KeyboardEvent) => this.globalKeydown(event);
  private onOpenEvent = (event: Event) => this.open((event as CustomEvent<{ query?: string; page?: string }>).detail ?? {});
  private onCloseEvent = () => this.close();
  private onToggleEvent = () => (this.isOpen ? this.close() : this.open());

  constructor(
    private root: HTMLElement,
    private live: Live | null,
  ) {
    this.id = root.id;
    this.config = readConfig(root);
    this.history = this.makeHistory();
    this.listId = uid("jumon-list");
    const inputId = uid("jumon-input");

    this.searchIcon = el("span", { class: "jumon-search-icon" }, [icons.renderIcon(icons.search)]);
    this.input = el("input", {
      id: inputId,
      class: "jumon-input",
      type: "text",
      role: "combobox",
      autocomplete: "off",
      autocapitalize: "off",
      spellcheck: "false",
      "aria-autocomplete": "list",
      "aria-expanded": "true",
      "aria-controls": this.listId,
    });
    this.crumbs = el("div", { class: "jumon-crumbs" });
    this.inner = el("div", { class: "jumon-list-inner" });
    this.list = el("div", { id: this.listId, class: "jumon-list", role: "listbox" }, [this.inner]);
    this.message = el("div", { class: "jumon-message", hidden: true });
    this.footer = el("div", { class: "jumon-footer", "aria-hidden": "true" });
    this.announcer = el("div", { class: "jumon-sr-only", "aria-live": "polite", "aria-atomic": "true" });
    this.menu = el("div", { class: "jumon-menu", role: "listbox", hidden: true, id: uid("jumon-menu") });

    this.panel = el("div", { class: "jumon-panel" }, [
      el("div", { class: "jumon-search" }, [this.crumbs, this.searchIcon, this.input]),
      this.list,
      this.message,
      this.menu,
      this.footer,
      this.announcer,
    ]);
    this.dialog = el("dialog", { class: "jumon-dialog" }, [this.panel]);

    const container = root.querySelector<HTMLElement>(".jumon-ui") ?? root;
    container.appendChild(this.dialog);
    root.classList.add("jumon-ready");

    this.applyMessages();
    this.index();
    this.bindEvents();
    formatKeys(document, this.apple);
  }

  /** Reads the config again, after a render of the server. */
  update(): void {
    this.config = readConfig(this.root);
    this.applyMessages();
    this.index();
    if (this.isOpen) this.refresh();
  }

  destroy(): void {
    document.removeEventListener("keydown", this.onKeydown);
    this.root.removeEventListener("jumon:open", this.onOpenEvent);
    this.root.removeEventListener("jumon:close", this.onCloseEvent);
    this.root.removeEventListener("jumon:toggle", this.onToggleEvent);
    if (this.dialog.open) this.dialog.close();
    this.dialog.remove();
  }

  get opened(): boolean {
    return this.isOpen;
  }

  /** Opens the palette, at a query or on the page of an action. */
  open(options: { query?: string | null; page?: string | null } = {}): void {
    if (!this.isOpen) {
      this.returnFocus = document.activeElement instanceof HTMLElement ? document.activeElement : null;
      this.stack = [{ kind: "root", query: "" }];
      this.isOpen = true;
      try {
        this.dialog.showModal();
      } catch {
        this.dialog.setAttribute("open", "");
      }
      this.measure();
      this.root.dispatchEvent(new CustomEvent("jumon:opened", { bubbles: true }));
      void this.loadRecent();
    }
    if (options.page) {
      const action = this.actions.get(options.page);
      if (action) this.enter(action, false);
    }
    if (typeof options.query === "string") this.setQuery(options.query);
    else this.syncInput();
    this.refresh();
    this.input.focus();
  }

  close(): void {
    if (!this.isOpen) return;
    this.isOpen = false;
    this.menuState = null;
    this.confirming = null;
    this.remote = null;
    this.busy = false;
    if (this.debounce) clearTimeout(this.debounce);
    if (this.dialog.open) this.dialog.close();
    else this.dialog.removeAttribute("open");
    this.root.dispatchEvent(new CustomEvent("jumon:closed", { bubbles: true }));
    const focus = this.returnFocus;
    this.returnFocus = null;
    if (focus && focus.isConnected) focus.focus({ preventScroll: true });
  }

  /** Results of a search of the server, pushed after its reply (async sources). */
  receiveResults(payload: Record<string, unknown>): void {
    const remote = this.remote;
    if (!remote || payload.ref !== remote.ref) return;
    const source = String(payload.source);
    remote.pending.delete(source);
    if (payload.error) remote.errors.add(source);
    else remote.results.set(source, Array.isArray(payload.results) ? (payload.results as ActionData[]) : []);
    this.refresh();
  }

  // ## Setup

  private makeHistory(): History {
    switch (this.config.history) {
      case "server":
        return this.live ? new ServerHistory((event, payload, onReply) => this.live!.push(event, payload, onReply)) : new NoHistory();
      case "off":
        return new NoHistory();
      default:
        return new LocalHistory(`jumon:${location.host}:${this.id}`);
    }
  }

  private applyMessages(): void {
    this.dialog.setAttribute("aria-label", this.t("label"));
    this.input.setAttribute("aria-label", this.t("label"));
    this.list.setAttribute("aria-label", this.t("label"));
    this.root.setAttribute("lang", this.config.locale);
  }

  private t(key: string): string {
    return this.config.messages[key] ?? key;
  }

  /** Whether the browser can do what an action does here. */
  private available(action: ActionData): boolean {
    if (this.live) return true;
    const type = action.perform?.type;
    if (type === "server" || type === "event") return false;
    if (action.args?.length) return false;
    return true;
  }

  private index(): void {
    this.actions.clear();
    this.children.clear();
    for (const action of this.config.actions) {
      if (!this.available(action)) continue;
      this.actions.set(action.id, action);
      if (action.parent) {
        const siblings = this.children.get(action.parent) ?? [];
        siblings.push(action);
        this.children.set(action.parent, siblings);
      }
    }
    const bindings: Binding<Bound>[] = [];
    for (const shortcut of this.config.options.shortcut) bindings.push({ chords: parseShortcut(shortcut, this.apple), value: { kind: "open" } });
    if (this.config.options.help) bindings.push({ chords: parseShortcut("?", this.apple), value: { kind: "help" } });
    for (const action of this.actions.values()) {
      if (action.disabled) continue;
      for (const shortcut of action.shortcut ?? []) bindings.push({ chords: parseShortcut(shortcut, this.apple), value: { kind: "action", action } });
    }
    this.sequences.setBindings(bindings);
  }

  private bindEvents(): void {
    document.addEventListener("keydown", this.onKeydown);
    this.root.addEventListener("jumon:open", this.onOpenEvent);
    this.root.addEventListener("jumon:close", this.onCloseEvent);
    this.root.addEventListener("jumon:toggle", this.onToggleEvent);

    this.dialog.addEventListener("cancel", (event) => {
      // Escape: the input handles it, a page at a time.
      event.preventDefault();
    });
    this.dialog.addEventListener("close", () => {
      if (this.isOpen) this.close();
    });
    this.dialog.addEventListener("pointerdown", (event) => {
      if (event.target === this.dialog) this.close();
    });
    this.input.addEventListener("keydown", (event) => this.inputKeydown(event));
    this.input.addEventListener("input", () => {
      if (this.confirming) return;
      this.page().query = this.input.value;
      this.clearMessage();
      this.refresh();
    });
    this.list.addEventListener("scroll", () => this.renderRows(), { passive: true });
    this.list.addEventListener("pointermove", (event) => {
      const index = rowIndex(event.target);
      if (index !== null && index !== this.active && this.selectable(index)) {
        this.active = index;
        this.paintActive();
      }
    });
    this.list.addEventListener("mousedown", (event) => event.preventDefault());
    this.list.addEventListener("click", (event) => {
      const target = event.target as Element;
      const index = rowIndex(target);
      if (index === null || !this.selectable(index)) return;
      this.active = index;
      if (target.closest(".jumon-more")) this.openMenu();
      else this.activate(event.metaKey || event.ctrlKey);
    });
    this.menu.addEventListener("mousedown", (event) => event.preventDefault());
    this.menu.addEventListener("click", (event) => {
      const option = (event.target as Element).closest<HTMLElement>("[data-menu]");
      if (option && this.menuState) {
        this.menuState.active = Number(option.dataset.menu);
        this.runMenu();
      }
    });
    this.message.addEventListener("click", (event) => {
      const button = (event.target as Element).closest<HTMLElement>("[data-message]");
      if (!button) return;
      if (button.dataset.message === "confirm") this.confirm();
      else this.cancelConfirm();
      this.input.focus();
    });
    this.crumbs.addEventListener("mousedown", (event) => event.preventDefault());
    this.crumbs.addEventListener("click", (event) => {
      if ((event.target as Element).closest(".jumon-back")) this.back();
    });
  }

  // ## Keys

  private globalKeydown(event: KeyboardEvent): void {
    if (event.defaultPrevented || event.isComposing || event.keyCode === 229) return;
    if (this.isOpen) return;
    const chord = eventChord(event, this.apple);
    if (chord === null) return;
    // In a text field, only chords with ⌘, Ctrl or Alt.
    if (isEditable(event.target) && !hasCommandModifier(chord)) {
      this.sequences.reset();
      return;
    }
    const result = this.sequences.feed(chord);
    if (result === null || result === "pending") return;
    event.preventDefault();
    const bound = result.match;
    if (bound.kind === "open") this.open();
    else if (bound.kind === "help") this.openHelp();
    else this.runShortcut(bound.action);
  }

  private runShortcut(action: Item): void {
    if (action.children || action.args?.length || action.confirm) {
      this.open();
      this.activateAction(action, false);
    } else {
      this.activateAction(action, false);
    }
  }

  private inputKeydown(event: KeyboardEvent): void {
    if (event.isComposing || event.keyCode === 229) return;
    const chord = eventChord(event, this.apple);
    const mod = this.apple ? event.metaKey : event.ctrlKey;
    // Ctrl+N and Ctrl+P move, as in Emacs and cmdk; on Apple devices also
    // Ctrl+J and Ctrl+K. (Elsewhere Ctrl is mod.)
    const ctrl = (key: string) => chord === (this.apple ? `ctrl+${key}` : `mod+${key}`);

    if (this.menuState) {
      this.menuKeydown(event, chord);
      return;
    }

    if (this.confirming) {
      if (event.key === "Enter") {
        event.preventDefault();
        this.confirm();
      } else if (event.key === "Escape") {
        event.preventDefault();
        this.cancelConfirm();
      } else if (event.key !== "Tab") {
        event.preventDefault();
      }
      return;
    }

    switch (true) {
      case event.key === "ArrowDown" || ctrl("n") || (this.apple && ctrl("j")):
        event.preventDefault();
        this.move(1);
        return;
      case event.key === "ArrowUp" || ctrl("p") || (this.apple && ctrl("k")):
        event.preventDefault();
        this.move(-1);
        return;
      case event.key === "PageDown":
        event.preventDefault();
        this.move(this.pageSize());
        return;
      case event.key === "PageUp":
        event.preventDefault();
        this.move(-this.pageSize());
        return;
      case (event.key === "Home" || event.key === "End") && this.input.value === "":
        event.preventDefault();
        this.moveTo(event.key === "Home" ? 0 : this.rows.length - 1, event.key === "Home" ? 1 : -1);
        return;
      case event.key === "Enter":
        event.preventDefault();
        if (!event.repeat) this.activate(mod);
        return;
      case event.key === "Escape":
        event.preventDefault();
        if (this.message.hidden === false && this.message.dataset.kind === "error") this.clearMessage();
        else if (this.stack.length > 1) this.back();
        else this.close();
        return;
      case event.key === "Backspace" && mod && this.activeRow()?.recent === true:
        event.preventDefault();
        this.forget(this.activeRow()!.action);
        return;
      case event.key === "Backspace" && this.input.selectionStart === 0 && this.input.selectionEnd === 0 && this.stack.length > 1:
        event.preventDefault();
        this.back();
        return;
      // → at the end of the box opens the actions of the result, as in
      // Alfred; ⌘K (the shortcut that opened the palette) closes it.
      case event.key === "ArrowRight" && this.input.selectionStart === this.input.value.length && this.menuItems(this.activeRow()?.action).length > 0:
        event.preventDefault();
        this.openMenu();
        return;
      case chord !== null && this.config.options.shortcut.some((shortcut) => parseShortcut(shortcut, this.apple).join(" ") === chord):
        event.preventDefault();
        this.close();
        return;
      case event.key === "Tab":
        event.preventDefault();
        return;
    }
  }

  private menuKeydown(event: KeyboardEvent, chord: string | null): void {
    const state = this.menuState!;
    const ctrl = (key: string) => chord === (this.apple ? `ctrl+${key}` : `mod+${key}`);
    if (event.key === "ArrowDown" || ctrl("n")) {
      event.preventDefault();
      state.active = (state.active + 1) % state.items.length;
      this.renderMenu();
    } else if (event.key === "ArrowUp" || ctrl("p")) {
      event.preventDefault();
      state.active = (state.active - 1 + state.items.length) % state.items.length;
      this.renderMenu();
    } else if (event.key === "Enter") {
      event.preventDefault();
      this.runMenu();
    } else if (event.key === "Escape" || event.key === "ArrowLeft") {
      event.preventDefault();
      this.closeMenu();
    } else if (event.key !== "Tab" && !event.metaKey && !event.ctrlKey) {
      event.preventDefault();
    }
  }

  // ## Pages

  private page(): Page {
    return this.stack[this.stack.length - 1]!;
  }

  private setQuery(query: string): void {
    this.page().query = query;
    this.syncInput();
  }

  private syncInput(): void {
    const page = this.page();
    this.input.value = page.query;
    let placeholder = this.t("placeholder");
    if (page.kind === "children") placeholder = page.action.name;
    if (page.kind === "arg") {
      const arg = page.action.args![page.index]!;
      placeholder = arg.placeholder ?? arg.label;
      if (arg.optional) placeholder += ` (${this.t("optional")})`;
    }
    if (page.kind === "help") placeholder = this.t("shortcuts");
    this.input.placeholder = placeholder;
    this.input.readOnly = false;
    this.renderCrumbs();
  }

  private push(page: Page): void {
    this.stack.push(page);
    this.active = -1;
    this.remote = null;
    this.clearMessage();
    this.syncInput();
    this.refresh();
    this.list.scrollTop = 0;
  }

  private back(): void {
    if (this.stack.length <= 1) return;
    this.stack.pop();
    this.active = -1;
    this.remote = null;
    this.closeMenu();
    this.clearMessage();
    this.syncInput();
    this.refresh();
  }

  private openHelp(): void {
    this.open();
    if (this.page().kind !== "help") this.push({ kind: "help", query: "" });
  }

  private renderCrumbs(): void {
    this.crumbs.replaceChildren();
    if (this.stack.length <= 1) {
      this.crumbs.hidden = true;
      this.searchIcon.hidden = false;
      return;
    }
    this.crumbs.hidden = false;
    this.searchIcon.hidden = true;
    const back = el("button", { type: "button", class: "jumon-back", tabindex: "-1", "aria-label": this.t("back"), title: this.t("back") }, [icons.renderIcon(icons.back)]);
    this.crumbs.appendChild(back);
    for (const page of this.stack.slice(1)) {
      if (page.kind === "children") this.crumbs.appendChild(el("span", { class: "jumon-crumb" }, [page.action.name]));
      if (page.kind === "help") this.crumbs.appendChild(el("span", { class: "jumon-crumb" }, [this.t("shortcuts")]));
      if (page.kind === "arg") {
        if (page.index === 0) this.crumbs.appendChild(el("span", { class: "jumon-crumb" }, [page.action.name]));
        const label = page.labels[page.index - 1];
        if (page.index > 0 && label) this.crumbs.appendChild(el("span", { class: "jumon-crumb jumon-crumb-value" }, [label]));
      }
    }
  }

  // ## Rows

  private refresh(): void {
    if (!this.isOpen) return;
    const page = this.page();
    const previous = this.activeRow()?.action.id;
    const query = page.query;
    let rows: Row[];

    switch (page.kind) {
      case "root":
        rows = this.rootRows(query);
        break;
      case "children":
        rows = this.grouped(this.children.get(page.action.id) ?? [], query, true);
        if (rows.length === 0) rows = [{ kind: "status", text: this.t("noResults"), tone: "empty" }];
        break;
      case "arg":
        rows = this.argRows(page, query);
        break;
      case "help":
        rows = this.helpRows(query);
        break;
    }

    this.rows = rows;
    this.layout();
    const keep = previous === undefined ? -1 : rows.findIndex((row) => row.kind === "item" && row.action.id === previous);
    this.active = keep >= 0 && query === this.lastQuery ? keep : this.firstSelectable(0, 1);
    this.lastQuery = query;
    this.renderRows();
    this.ensureVisible();
    this.renderFooter();
    this.searchIcon.classList.toggle("jumon-busy", this.busy || (this.remote?.pending.size ?? 0) > 0);
    this.scheduleAnnounce();
  }

  private rootRows(query: string): Row[] {
    const rows: Row[] = [];
    const trimmed = query.trim();

    if (trimmed === "") {
      const recent = this.recentRows();
      if (recent.length > 0) rows.push({ kind: "heading", label: this.t("recent") }, ...recent);
      const top = [...this.actions.values()].filter((action) => !action.parent && !action.hidden);
      rows.push(...this.grouped(top.concat(this.helpEntry()), "", false));
    } else {
      const candidates = [...this.actions.values()].filter((action) => !action.hidden || action.parent);
      rows.push(...this.grouped(candidates.concat(this.helpEntry()), query, false));
    }

    this.searchSources(query);
    rows.push(...this.remoteRows());

    if (rows.length === 0 && !(this.remote && this.remote.pending.size > 0)) rows.push({ kind: "status", text: this.t("noResults"), tone: "empty" });
    return rows;
  }

  private helpEntry(): Item[] {
    if (!this.config.options.help) return [];
    return [{ id: "_help", name: this.t("shortcuts"), internal: "help", internalIcon: icons.keyboard, shortcut: ["?"], priority: -100, children: true }];
  }

  private recentRows(): Row[] {
    const limit = this.config.options.recent;
    if (limit <= 0 || this.page().kind !== "root") return [];
    const rows: Row[] = [];
    for (const entry of this.recent) {
      const action = this.actions.get(entry.id) ?? this.fromSnapshot(entry);
      if (!action || action.hidden || action.disabled) continue;
      rows.push({ kind: "item", action, positions: [], recent: true, trail: this.trail(action) });
      if (rows.length >= limit) break;
    }
    return rows;
  }

  // A result of a search that the history kept: shown again when the
  // browser can do what it does by itself.
  private fromSnapshot(entry: Entry): Item | null {
    const action = entry.action;
    if (!action || typeof action.name !== "string") return null;
    const type = action.perform?.type;
    if (!type || type === "server" || action.args?.length || action.children) return null;
    return this.available(action) ? { ...action, id: entry.id } : null;
  }

  private trail(action: ActionData): string | undefined {
    const names: string[] = [];
    let parent = action.parent ? this.actions.get(action.parent) : undefined;
    while (parent) {
      names.unshift(parent.name);
      parent = parent.parent ? this.actions.get(parent.parent) : undefined;
    }
    return names.length > 0 ? names.join(" › ") : undefined;
  }

  /** Actions grouped by section; with a query, matched and ranked. */
  private grouped(actions: Item[], query: string, page: boolean): Row[] {
    const scores = query.trim() === "" ? null : this.history.scores();
    const matched: Array<{ action: Item; score: number; positions: number[]; order: number }> = [];
    actions.forEach((action, order) => {
      const result = score(action, query);
      if (!result) return;
      const boost = scores ? Math.round(Math.min(scores.get(action.id) ?? 0, 10) * 8) : 0;
      matched.push({ action, score: result.score + boost, positions: result.positions, order });
    });
    matched.sort((a, b) => b.score - a.score || a.order - b.order);

    const groups = new Map<string, typeof matched>();
    for (const match of matched) {
      const section = this.sectionOf(match.action) ?? (page ? "" : this.t("general"));
      const group = groups.get(section) ?? [];
      group.push(match);
      groups.set(section, group);
    }

    const rows: Row[] = [];
    for (const [section, group] of groups) {
      if (section !== "" && (groups.size > 1 || !page)) rows.push({ kind: "heading", label: section });
      for (const match of group) {
        rows.push({ kind: "item", action: match.action, positions: match.positions, trail: page ? undefined : this.trail(match.action) });
      }
    }
    return rows;
  }

  // A nested action is in the section of its top-level ancestor.
  private sectionOf(action: ActionData): string | undefined {
    let current: ActionData | undefined = action;
    while (current?.parent) {
      const parent = this.actions.get(current.parent);
      if (!parent) break;
      if (current.section) return current.section;
      current = parent;
    }
    return current?.section;
  }

  private helpRows(query: string): Row[] {
    const keys: Item[] = [
      ...this.config.options.shortcut.map((shortcut) => ({ id: "_key:open", name: this.t("label"), shortcut: [shortcut], internal: "info" as const })),
      { id: "_key:run", name: this.t("run"), shortcut: ["enter"], internal: "info" },
      { id: "_key:actions", name: this.t("actions"), shortcut: ["right"], internal: "info" },
      { id: "_key:back", name: this.t("back"), shortcut: ["backspace"], internal: "info" },
      { id: "_key:close", name: this.t("close"), shortcut: ["escape"], internal: "info" },
    ];
    const withShortcuts = [...this.actions.values()].filter((action) => (action.shortcut?.length ?? 0) > 0);
    const rows: Row[] = [];
    const listed = this.grouped(withShortcuts, query, false);
    rows.push(...listed);
    const own = keys.filter((key) => score(key, query));
    if (own.length > 0) {
      rows.push({ kind: "heading", label: this.t("label") });
      for (const key of own) rows.push({ kind: "item", action: key, positions: [] });
    }
    if (rows.length === 0) rows.push({ kind: "status", text: this.t("noResults"), tone: "empty" });
    return rows;
  }

  private argRows(page: Extract<Page, { kind: "arg" }>, query: string): Row[] {
    const arg = page.action.args![page.index]!;
    if (arg.type === "text") return [{ kind: "status", text: this.t("typeText"), tone: "hint" }];
    if (arg.type === "choice") {
      const rows = this.grouped((arg.options ?? []) as Item[], query, true);
      return rows.length > 0 ? rows : [{ kind: "status", text: this.t("noResults"), tone: "empty" }];
    }
    if (query.trim().length < (arg.minLength ?? 0)) {
      this.remote = null;
      return [{ kind: "status", text: this.t("keepTyping"), tone: "hint" }];
    }
    this.searchArg(page, arg, query);
    const remote = this.remote;
    const results = remote?.results.get("_arg");
    if (remote?.errors.has("_arg")) return [{ kind: "status", text: this.t("error"), tone: "error", retry: true }];
    if (!results) return [{ kind: "status", text: this.t("loading"), tone: "loading" }];
    if (results.length === 0) return remote && remote.pending.size > 0 ? [{ kind: "status", text: this.t("loading"), tone: "loading" }] : [{ kind: "status", text: this.t("noResults"), tone: "empty" }];
    return results.map((action) => ({ kind: "item", action, positions: score(action, query)?.positions ?? [] }));
  }

  private remoteRows(): Row[] {
    const remote = this.remote;
    if (!remote) return [];
    const rows: Row[] = [];
    for (const source of this.config.sources) {
      const results = remote.results.get(source.name);
      const pending = remote.pending.has(source.name);
      const failed = remote.errors.has(source.name);
      if (!results && !pending && !failed) continue;
      const items = (results ?? []).filter((action) => this.available(action));
      if (items.length === 0 && !pending && !failed) continue;
      rows.push({ kind: "heading", label: source.label });
      for (const action of items) rows.push({ kind: "item", action, positions: score(action, remote.query)?.positions ?? [] });
      if (pending && items.length === 0) rows.push({ kind: "status", text: this.t("loading"), tone: "loading" });
      if (failed) rows.push({ kind: "status", text: this.t("error"), tone: "error", retry: true });
    }
    return rows;
  }

  // ## The server's searches

  private searchSources(query: string): void {
    if (!this.live) return;
    const length = query.trim().length;
    const sources = this.config.sources.filter((source) => length >= source.minLength);
    const key = `sources:${query}`;
    if (sources.length === 0) {
      this.remote = null;
      return;
    }
    if (this.remote?.key === key) return;
    this.startSearch(key, query, {}, sources.map((source) => source.name));
  }

  private searchArg(page: Extract<Page, { kind: "arg" }>, arg: ArgSpec, query: string): void {
    if (!this.live) return;
    const key = `arg:${page.action.id}:${arg.name}:${query}`;
    if (this.remote?.key === key) return;
    this.startSearch(key, query, { action: page.action.id, arg: arg.name }, ["_arg"]);
  }

  // The results of the last search stay until the new ones come, so the
  // list does not flash while the person types.
  private startSearch(key: string, query: string, extra: Record<string, string>, names: string[], immediate = false): void {
    const previous = this.remote;
    const remote: Remote = { ref: ++this.refCounter, query, key, results: previous?.results ?? new Map(), pending: new Set(names), errors: new Set() };
    this.remote = remote;
    if (this.debounce) clearTimeout(this.debounce);
    const send = () => {
      if (this.remote !== remote) return;
      this.live!.push("jumon:search", { v: 1, ref: remote.ref, query, ...extra }, (reply) => {
        if (this.remote !== remote || reply.ref !== remote.ref) return;
        const results = (reply.results ?? {}) as Record<string, ActionData[]>;
        remote.results = new Map();
        for (const name of names) {
          if (name in results) remote.results.set(name, results[name]!);
        }
        remote.pending = new Set(Array.isArray(reply.pending) ? (reply.pending as string[]) : []);
        remote.errors = new Set(Array.isArray(reply.errors) ? (reply.errors as string[]) : []);
        this.refresh();
      });
    };
    if (immediate) send();
    else this.debounce = setTimeout(send, DEBOUNCE);
  }

  // A source that failed: Enter on its row searches again.
  private retry(): void {
    this.remote = null;
    this.refresh();
  }

  // ## Layout and rendering

  private measure(): void {
    if (this.measured) return;
    const probe = el("div", { class: "jumon-item", style: "position:absolute;visibility:hidden" }, ["x"]);
    const heading = el("div", { class: "jumon-heading", style: "position:absolute;visibility:hidden" }, ["x"]);
    this.inner.append(probe, heading);
    const item = probe.getBoundingClientRect().height;
    const head = heading.getBoundingClientRect().height;
    probe.remove();
    heading.remove();
    if (item > 0) {
      this.itemHeight = item;
      this.headingHeight = head > 0 ? head : item * 0.7;
      this.measured = true;
    }
  }

  private height(row: Row): number {
    return row.kind === "heading" ? this.headingHeight : this.itemHeight;
  }

  private layout(): void {
    const offsets: number[] = [];
    let top = 0;
    for (const row of this.rows) {
      offsets.push(top);
      top += this.height(row);
    }
    this.offsets = offsets;
    this.inner.style.height = `${top}px`;
  }

  private renderRows(): void {
    const scroll = this.list.scrollTop;
    const view = this.list.clientHeight || 400;
    const start = Math.max(this.indexAt(scroll) - OVERSCAN, 0);
    const end = Math.min(this.indexAt(scroll + view) + OVERSCAN, this.rows.length - 1);
    const wanted = new Set<number>();
    for (let i = start; i <= end; i++) wanted.add(i);
    if (this.active >= 0) wanted.add(this.active);

    const fragment = document.createDocumentFragment();
    for (const index of [...wanted].sort((a, b) => a - b)) fragment.appendChild(this.renderRow(index));
    this.inner.replaceChildren(fragment);
    this.paintActive();
  }

  private indexAt(offset: number): number {
    let low = 0;
    let high = this.offsets.length - 1;
    while (low < high) {
      const middle = Math.ceil((low + high) / 2);
      if (this.offsets[middle]! <= offset) low = middle;
      else high = middle - 1;
    }
    return low;
  }

  private rowId(index: number): string {
    return `${this.listId}-${index}`;
  }

  private renderRow(index: number): HTMLElement {
    const row = this.rows[index]!;
    const style = `top:${this.offsets[index]}px`;
    if (row.kind === "heading") {
      return el("div", { class: "jumon-heading", role: "presentation", style, "data-row": index }, [row.label]);
    }
    if (row.kind === "status") {
      const icon = row.tone === "loading" ? icons.loading : row.tone === "error" ? icons.alert : null;
      return el("div", { class: `jumon-status jumon-status-${row.tone}`, role: "presentation", style, "data-row": index }, [icon && icons.renderIcon(icon), el("span", {}, [row.text]), row.retry ? el("span", { class: "jumon-status-retry" }, [this.t("retry")]) : null]);
    }

    const action = row.action;
    const setSize = this.rows.filter((r) => r.kind === "item").length;
    const position = this.rows.slice(0, index + 1).filter((r) => r.kind === "item").length;
    const info = action.internal === "info";
    const disabled = Boolean(action.disabled);
    const opens = action.children || (action.args?.length ?? 0) > 0;
    const more = this.menuItems(action).length > 0;

    const name = el("span", { class: "jumon-item-name" });
    highlight(name, action.name, row.positions);
    const text = el("span", { class: "jumon-item-text" }, [
      row.trail ? el("span", { class: "jumon-item-trail" }, [`${row.trail} › `]) : null,
      name,
      action.subtitle ? el("span", { class: "jumon-item-subtitle" }, [action.subtitle]) : null,
      typeof action.disabled === "string" ? el("span", { class: "jumon-item-subtitle" }, [action.disabled]) : null,
    ]);

    return el(
      "div",
      {
        id: this.rowId(index),
        class: ["jumon-item", action.tone ? `jumon-tone-${action.tone}` : "", row.recent ? "jumon-recent" : "", info ? "jumon-info" : ""].join(" ").trim(),
        role: "option",
        "aria-selected": "false",
        "aria-disabled": disabled ? "true" : null,
        "aria-setsize": setSize,
        "aria-posinset": position,
        style,
        "data-row": index,
        "data-id": action.id,
      },
      [
        this.renderIcon(action, row.recent === true),
        text,
        action.badge ? el("span", { class: "jumon-badge" }, [action.badge]) : null,
        (action.shortcut?.length ?? 0) > 0 ? this.renderKeys(action.shortcut![0]!) : null,
        // A column of the same width on every row, so that the keys line up.
        el("span", { class: "jumon-trail" }, [
          more ? el("span", { class: "jumon-more", "aria-hidden": "true", title: this.t("actions") }, [icons.renderIcon(icons.more)]) : null,
          opens ? el("span", { class: "jumon-chevron", "aria-hidden": "true" }, [icons.renderIcon(icons.chevron)]) : el("span", { class: "jumon-enter", "aria-hidden": "true" }, [icons.renderIcon(icons.enter)]),
        ]),
      ],
    );
  }

  private renderIcon(action: Item, recent: boolean): HTMLElement | null {
    if (action.avatar) return el("span", { class: "jumon-item-icon jumon-avatar" }, [el("img", { src: action.avatar, alt: "", loading: "lazy" })]);
    if (action.glyph) return el("span", { class: "jumon-item-icon jumon-glyph", "aria-hidden": "true" }, [action.glyph]);
    if (action.icon) {
      const holder = el("span", { class: "jumon-item-icon", "aria-hidden": "true" });
      const template = this.config.options.icons ? this.root.querySelector<HTMLTemplateElement>(`template[data-jumon-icon="${cssEscape(action.icon)}"]`) : null;
      if (template) holder.appendChild(template.content.cloneNode(true));
      else holder.appendChild(el("span", { class: action.icon }));
      return holder;
    }
    if (action.internalIcon) return el("span", { class: "jumon-item-icon" }, [icons.renderIcon(action.internalIcon)]);
    if (recent) return el("span", { class: "jumon-item-icon jumon-item-icon-muted" }, [icons.renderIcon(icons.recent)]);
    return null;
  }

  private renderKeys(shortcut: string): HTMLElement {
    const keys = el("span", { class: "jumon-keys", title: shortcutText(shortcut, this.apple) });
    for (const chord of shortcutLabels(shortcut, this.apple)) {
      const group = el("span", { class: "jumon-chord" });
      for (const label of chord) group.appendChild(el("kbd", {}, [label]));
      keys.appendChild(group);
    }
    return keys;
  }

  private paintActive(): void {
    for (const option of this.inner.querySelectorAll<HTMLElement>("[role=option]")) {
      const selected = Number(option.dataset.row) === this.active;
      option.setAttribute("aria-selected", selected ? "true" : "false");
      option.classList.toggle("jumon-active", selected);
    }
    if (this.active >= 0) this.input.setAttribute("aria-activedescendant", this.rowId(this.active));
    else this.input.removeAttribute("aria-activedescendant");
    this.renderFooter();
  }

  private renderFooter(): void {
    if (this.confirming) {
      this.footer.replaceChildren(
        el("span", { class: "jumon-hint" }, [this.renderKeys("enter"), this.t("confirm")]),
        el("span", { class: "jumon-hint" }, [this.renderKeys("escape"), this.t("cancel")]),
      );
      return;
    }
    const row = this.activeRow();
    const hints: Array<[string, string]> = [];
    if (row && row.action.internal !== "info") {
      const opens = row.action.children || (row.action.args?.length ?? 0) > 0;
      hints.push(["enter", opens ? this.t("open") : this.t("run")]);
      if (this.menuItems(row.action).length > 0) hints.push(["right", this.t("actions")]);
    }
    const page = this.page();
    if (page.kind === "arg" && page.action.args![page.index]!.type === "text") hints.splice(0, hints.length, ["enter", this.t("run")]);
    hints.push(["escape", this.stack.length > 1 ? this.t("back") : this.t("close")]);
    this.footer.replaceChildren(...hints.map(([keys, label]) => el("span", { class: "jumon-hint" }, [this.renderKeys(keys), label])));
  }

  private ensureVisible(): void {
    if (this.active < 0) return;
    const top = this.offsets[this.active]!;
    const bottom = top + this.height(this.rows[this.active]!);
    const view = this.list.clientHeight;
    // Show the heading above the first row of a group with it.
    const previous = this.rows[this.active - 1];
    const headingTop = previous?.kind === "heading" ? this.offsets[this.active - 1]! : top;
    if (headingTop < this.list.scrollTop) this.list.scrollTop = headingTop;
    else if (bottom > this.list.scrollTop + view) this.list.scrollTop = bottom - view;
    this.renderRows();
  }

  private selectable(index: number): boolean {
    const row = this.rows[index];
    return row !== undefined && (row.kind === "item" || (row.kind === "status" && row.retry === true));
  }

  private firstSelectable(from: number, step: 1 | -1): number {
    for (let i = from; i >= 0 && i < this.rows.length; i += step) if (this.selectable(i)) return i;
    return -1;
  }

  private move(delta: number): void {
    if (this.rows.length === 0) return;
    const step = delta > 0 ? 1 : -1;
    if (this.active < 0) {
      this.active = this.firstSelectable(step > 0 ? 0 : this.rows.length - 1, step);
    } else if (Math.abs(delta) === 1) {
      let next = this.firstSelectable(this.active + step, step);
      if (next < 0) next = this.firstSelectable(step > 0 ? 0 : this.rows.length - 1, step);
      this.active = next;
    } else {
      const target = Math.min(Math.max(this.active + delta, 0), this.rows.length - 1);
      let next = this.firstSelectable(target, step);
      if (next < 0) next = this.firstSelectable(target, step > 0 ? -1 : 1);
      this.active = next;
    }
    this.ensureVisible();
  }

  private moveTo(index: number, step: 1 | -1): void {
    this.active = this.firstSelectable(index, step);
    this.ensureVisible();
  }

  private pageSize(): number {
    return Math.max(Math.floor((this.list.clientHeight || 400) / this.itemHeight) - 1, 1);
  }

  private activeRow(): Extract<Row, { kind: "item" }> | null {
    const row = this.rows[this.active];
    return row?.kind === "item" ? row : null;
  }

  private scheduleAnnounce(): void {
    if (this.announceTimer) clearTimeout(this.announceTimer);
    this.announceTimer = setTimeout(() => {
      const count = this.rows.filter((row) => row.kind === "item").length;
      const loading = this.rows.some((row) => row.kind === "status" && row.tone === "loading");
      if (loading) return;
      const plural = new Intl.PluralRules(this.config.locale).select(count) === "one" ? "resultsOne" : "resultsOther";
      this.announcer.textContent = count === 0 ? this.t("noResults") : format(this.t(plural), { n: count });
    }, 400);
  }

  // ## Running

  private activate(alternate: boolean): void {
    const row = this.rows[this.active];
    if (!row) {
      const page = this.page();
      if (page.kind === "arg" && page.action.args![page.index]!.type === "text") this.submitText(page);
      return;
    }
    if (row.kind === "status") {
      if (row.retry) this.retry();
      return;
    }
    if (row.kind !== "item") return;
    const page = this.page();
    if (page.kind === "arg") {
      this.chooseValue(page, row.action);
      return;
    }
    if (alternate) {
      const items = this.menuItems(row.action);
      if (items.length > 0) {
        this.runItem(items[0]!, row.action);
        return;
      }
    }
    this.activateAction(row.action, alternate);
  }

  private activateAction(action: Item, alternate: boolean): void {
    if (action.internal === "info") return;
    if (action.internal === "help") {
      this.push({ kind: "help", query: "" });
      return;
    }
    if (action.disabled) {
      this.showMessage(typeof action.disabled === "string" ? action.disabled : this.t("disabled"), "error");
      return;
    }
    if (action.children || (action.args?.length ?? 0) > 0) {
      this.enter(action, true);
      return;
    }
    if (action.confirm) {
      this.askConfirm(action);
      return;
    }
    this.perform(action, alternate);
  }

  private enter(action: Item, focus: boolean): void {
    if (action.children) this.push({ kind: "children", action, query: "" });
    else if (action.args?.length) this.push({ kind: "arg", action, index: 0, values: {}, labels: [], query: "" });
    if (focus) this.input.focus();
  }

  private chooseValue(page: Extract<Page, { kind: "arg" }>, option: ActionData): void {
    const arg = page.action.args![page.index]!;
    this.nextArg(page, arg, option.id, `${arg.label}: ${option.name}`);
  }

  private submitText(page: Extract<Page, { kind: "arg" }>): void {
    const arg = page.action.args![page.index]!;
    const text = this.input.value.trim();
    if (text === "" && !arg.optional) return;
    if (arg.maxLength && text.length > arg.maxLength) {
      this.showMessage(this.t("invalid"), "error");
      return;
    }
    this.nextArg(page, arg, text === "" ? null : text, text === "" ? `${arg.label}: –` : `${arg.label}: ${text}`);
  }

  private nextArg(page: Extract<Page, { kind: "arg" }>, arg: ArgSpec, value: string | null, label: string): void {
    const values = { ...page.values, [arg.name]: value };
    const labels = [...page.labels.slice(0, page.index), label];
    const args = page.action.args!;
    if (page.index + 1 < args.length) {
      this.push({ kind: "arg", action: page.action, index: page.index + 1, values, labels, query: "" });
      return;
    }
    if (page.action.confirm) this.askConfirm(page.action, values);
    else this.runServer(page.action, values);
  }

  private askConfirm(action: Item, values?: Record<string, string | null>): void {
    this.confirming = { action, values };
    this.input.readOnly = true;
    this.message.dataset.kind = "confirm";
    this.message.hidden = false;
    this.message.replaceChildren(
      el("p", { class: "jumon-message-text" }, [action.confirm ?? ""]),
      el("div", { class: "jumon-message-buttons" }, [
        el("button", { type: "button", class: "jumon-button-secondary", "data-message": "cancel", tabindex: "-1" }, [this.t("cancel")]),
        el("button", { type: "button", class: action.tone === "danger" ? "jumon-button-primary jumon-tone-danger" : "jumon-button-primary", "data-message": "confirm", tabindex: "-1" }, [this.t("confirm")]),
      ]),
    );
    this.panel.classList.add("jumon-confirming");
    this.renderFooter();
    this.announcer.textContent = `${action.confirm ?? ""} ${this.t("confirmHint")}`;
  }

  private confirm(): void {
    const confirming = this.confirming;
    if (!confirming) return;
    this.cancelConfirm();
    if (confirming.values) this.runServer(confirming.action, confirming.values);
    else this.perform(confirming.action, false);
  }

  private cancelConfirm(): void {
    this.confirming = null;
    this.input.readOnly = false;
    this.panel.classList.remove("jumon-confirming");
    this.clearMessage();
    this.renderFooter();
  }

  private showMessage(text: string, kind: "error" | "info"): void {
    this.message.dataset.kind = kind;
    this.message.hidden = false;
    this.message.replaceChildren(el("p", { class: "jumon-message-text" }, [kind === "error" ? icons.renderIcon(icons.alert) : null, text]));
    this.announcer.textContent = text;
  }

  private clearMessage(): void {
    if (this.confirming) return;
    this.message.hidden = true;
    this.message.replaceChildren();
    delete this.message.dataset.kind;
  }

  private perform(action: Item, alternate: boolean): void {
    const perform = action.perform;
    if (!perform) return;
    let recorded: Promise<void> = Promise.resolve();
    const done = () => {
      recorded = this.history.record(action);
      this.root.dispatchEvent(new CustomEvent("jumon:run", { bubbles: true, detail: { id: action.id } }));
      if (!action.keepOpen) this.close();
      else void this.loadRecent();
    };
    // A navigation leaves this LiveView: it goes once the history has the use.
    const leave = (go: () => void) => {
      done();
      void recorded.then(go);
    };

    switch (perform.type) {
      case "navigate":
      case "patch": {
        const to = perform.to ?? "/";
        if (alternate) {
          window.open(to, "_blank", "noopener");
          done();
        } else if (this.live) {
          const live = this.live;
          if (perform.type === "navigate") leave(() => live.navigate(to, perform.replace === true));
          else leave(() => live.patch(to, perform.replace === true));
        } else {
          leave(() => window.location.assign(to));
        }
        return;
      }
      case "href": {
        const to = perform.to ?? "/";
        if (alternate || perform.target === "_blank") {
          window.open(to, "_blank", "noopener");
          done();
        } else if (perform.method && perform.method !== "get") {
          leave(() => submitMethod(to, perform.method!));
        } else {
          leave(() => window.location.assign(to));
        }
        return;
      }
      case "event":
        this.live?.pushEvent(perform.event ?? "", perform.value ?? {}, perform.target);
        done();
        return;
      case "js":
        if (perform.js) this.live?.exec(perform.js);
        done();
        return;
      case "copy":
        void copyText(perform.text ?? "").then(() => {
          this.announcer.textContent = this.t("copied");
          done();
        });
        return;
      case "server":
        this.runServer(action, {});
        return;
    }
  }

  private runServer(action: Item, values: Record<string, string | null>): void {
    if (!this.live) return;
    if (this.busy) return;
    this.busy = true;
    this.searchIcon.classList.add("jumon-busy");
    this.live.push("jumon:run", { v: 1, id: action.id, args: values }, (reply) => {
      this.busy = false;
      this.searchIcon.classList.remove("jumon-busy");
      if (reply.ok) {
        void this.history.record(action);
        this.root.dispatchEvent(new CustomEvent("jumon:run", { bubbles: true, detail: { id: action.id } }));
        if (action.keepOpen) {
          while (this.stack.length > 1) this.stack.pop();
          this.syncInput();
          this.refresh();
          void this.loadRecent();
        } else {
          this.close();
        }
        return;
      }
      const error = String(reply.error ?? "failed");
      const text = error === "message" ? String(reply.message ?? this.t("failed")) : error === "invalid" ? this.t("invalid") : error === "disabled" || error === "forbidden" ? this.t("disabled") : this.t("failed");
      // A value that the server refused: back to its page, to choose again.
      if (typeof reply.arg === "string") {
        const index = this.stack.findIndex((page) => page.kind === "arg" && page.action.args![page.index]!.name === reply.arg);
        if (index >= 0) {
          this.stack = this.stack.slice(0, index + 1);
          this.syncInput();
          this.refresh();
        }
      }
      this.showMessage(text, "error");
    });
  }

  // ## The actions of a result

  private menuItems(action: Item | undefined): Item[] {
    if (!action || action.internal) return [];
    const items: Item[] = ((action.actions ?? []) as Item[]).filter((item) => this.available(item));
    const perform = action.perform;
    if (this.config.options.linkActions && perform && (perform.type === "navigate" || perform.type === "patch" || (perform.type === "href" && (!perform.method || perform.method === "get")))) {
      items.push({ id: "_newtab", name: this.t("openNewTab"), internal: "newTab", internalIcon: icons.external, target: action });
      items.push({ id: "_copylink", name: this.t("copyLink"), internal: "copyLink", internalIcon: icons.copy, target: action });
    }
    const recent = this.activeRow()?.recent && this.activeRow()?.action.id === action.id;
    if (recent && this.config.history !== "off") items.push({ id: "_forget", name: this.t("forget"), internal: "forget", internalIcon: icons.trash, target: action, shortcut: ["mod+backspace"] });
    return items;
  }

  private openMenu(): void {
    const row = this.activeRow();
    if (!row) return;
    const items = this.menuItems(row.action);
    if (items.length === 0) return;
    this.menuState = { items, active: 0, of: row.action };
    this.renderMenu();
  }

  private renderMenu(): void {
    const state = this.menuState;
    if (!state) return;
    this.menu.hidden = false;
    this.menu.setAttribute("aria-label", format(this.t("actionsOf"), { name: state.of.name }));
    this.menu.replaceChildren(
      el("div", { class: "jumon-menu-title", role: "presentation" }, [state.of.name]),
      ...state.items.map((item, index) =>
        el("div", { id: `${this.menu.id}-${index}`, class: index === state.active ? "jumon-menu-item jumon-active" : "jumon-menu-item", role: "option", "aria-selected": index === state.active ? "true" : "false", "data-menu": index }, [
          this.renderIcon(item, false),
          el("span", { class: "jumon-item-text" }, [el("span", { class: "jumon-item-name" }, [item.name])]),
          index === 0 ? this.renderKeys("mod+enter") : item.shortcut?.[0] ? this.renderKeys(item.shortcut[0]) : null,
        ]),
      ),
    );
    this.input.setAttribute("aria-controls", this.menu.id);
    this.input.setAttribute("aria-activedescendant", `${this.menu.id}-${state.active}`);
  }

  private closeMenu(): void {
    if (!this.menuState) return;
    this.menuState = null;
    this.menu.hidden = true;
    this.menu.replaceChildren();
    this.input.setAttribute("aria-controls", this.listId);
    this.paintActive();
  }

  private runMenu(): void {
    const state = this.menuState;
    if (!state) return;
    const item = state.items[state.active];
    this.closeMenu();
    if (item) this.runItem(item, state.of);
  }

  private runItem(item: Item, of: Item): void {
    const target = item.target ?? of;
    const to = target.perform?.to ?? "/";
    switch (item.internal) {
      case "newTab":
        window.open(to, "_blank", "noopener");
        void this.history.record(target);
        this.close();
        return;
      case "copyLink":
        void copyText(new URL(to, window.location.href).href).then(() => {
          this.announcer.textContent = this.t("copied");
          this.close();
        });
        return;
      case "forget":
        this.forget(target);
        return;
      default:
        this.activateAction(item, false);
    }
  }

  private forget(action: Item): void {
    this.history.forget(action.id);
    this.recent = this.recent.filter((entry) => entry.id !== action.id);
    this.refresh();
  }

  private async loadRecent(): Promise<void> {
    if (this.config.options.recent <= 0) return;
    this.recent = await this.history.recent(Math.max(this.config.options.recent * 3, 20));
    if (this.isOpen && this.page().kind === "root" && this.page().query.trim() === "") this.refresh();
  }
}

function rowIndex(target: EventTarget | null): number | null {
  const row = target instanceof Element ? target.closest<HTMLElement>("[data-row]") : null;
  return row ? Number(row.dataset.row) : null;
}

/** Writes a name with the matched characters marked. */
function highlight(container: HTMLElement, name: string, positions: number[]): void {
  if (positions.length === 0) {
    container.textContent = name;
    return;
  }
  const marked = new Set(positions);
  let run = "";
  let inMark = false;
  const flush = () => {
    if (run === "") return;
    append(container, [inMark ? el("mark", { class: "jumon-match" }, [run]) : run]);
    run = "";
  };
  Array.from(name).forEach((char, index) => {
    const mark = marked.has(index);
    if (mark !== inMark) {
      flush();
      inMark = mark;
    }
    run += char;
  });
  flush();
}

function cssEscape(value: string): string {
  return typeof CSS !== "undefined" && CSS.escape ? CSS.escape(value) : value.replace(/["\\]/g, "\\$&");
}

async function copyText(text: string): Promise<void> {
  try {
    await navigator.clipboard.writeText(text);
  } catch {
    const area = el("textarea", { style: "position:fixed;opacity:0" }, [text]);
    document.body.appendChild(area);
    area.select();
    document.execCommand("copy");
    area.remove();
  }
}

// A link with a method, as phoenix_html's data-method: a form with the
// page's CSRF token.
function submitMethod(to: string, method: string): void {
  const csrf = document.querySelector<HTMLMetaElement>("meta[name='csrf-token']")?.content ?? "";
  const form = el("form", { method: "post", action: to, style: "display:none" }, [el("input", { type: "hidden", name: "_method", value: method }), el("input", { type: "hidden", name: "_csrf_token", value: csrf })]);
  document.body.appendChild(form);
  form.submit();
}

/** Shows the shortcuts of `[data-jumon-keys]` elements for the platform. */
export function formatKeys(root: ParentNode, apple = isApple()): void {
  for (const element of root.querySelectorAll<HTMLElement>("[data-jumon-keys]")) {
    const shortcut = element.dataset.jumonKeys ?? "";
    if (element.dataset.jumonFormatted === shortcut) continue;
    element.replaceChildren(...shortcutLabels(shortcut, apple).map((chord) => el("span", { class: "jumon-chord" }, chord.map((label) => el("kbd", {}, [label])))));
    element.setAttribute("aria-label", shortcutText(shortcut, apple));
    element.dataset.jumonFormatted = shortcut;
  }
}
