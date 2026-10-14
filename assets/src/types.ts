// What the server sends: the config of the palette in data-config, and
// the actions in it and in the results of a search (see Jumon.Action).

export interface Perform {
  type: "navigate" | "patch" | "href" | "event" | "js" | "copy" | "server";
  to?: string;
  replace?: boolean;
  method?: string;
  target?: string;
  event?: string;
  value?: Record<string, unknown>;
  js?: string;
  text?: string;
}

export interface ArgSpec {
  name: string;
  type: "text" | "choice" | "search";
  label: string;
  placeholder?: string;
  options?: ActionData[];
  minLength?: number;
  maxLength?: number;
  optional?: boolean;
}

export interface ActionData {
  id: string;
  name: string;
  subtitle?: string;
  section?: string;
  keywords?: string[];
  icon?: string;
  glyph?: string;
  avatar?: string;
  badge?: string;
  shortcut?: string[];
  priority?: number;
  perform?: Perform | null;
  parent?: string;
  children?: boolean;
  args?: ArgSpec[];
  actions?: ActionData[];
  confirm?: string;
  tone?: string;
  disabled?: boolean | string;
  keepOpen?: boolean;
  hidden?: boolean;
  source?: string;
}

export interface SourceSpec {
  name: string;
  label: string;
  minLength: number;
}

export interface Options {
  shortcut: string[];
  recent: number;
  help: boolean;
  linkActions: boolean;
  icons: boolean;
}

export interface Config {
  v: number;
  live: boolean;
  actions: ActionData[];
  sources: SourceSpec[];
  history: "local" | "server" | "off";
  locale: string;
  messages: Record<string, string>;
  options: Options;
}

/** Reads the config of a palette element, with defaults for what is missing. */
export function readConfig(element: HTMLElement): Config {
  let raw: Partial<Config> = {};
  try {
    raw = JSON.parse(element.dataset.config ?? "{}") as Partial<Config>;
  } catch {
    raw = {};
  }
  return {
    v: raw.v ?? 1,
    live: raw.live ?? false,
    actions: Array.isArray(raw.actions) ? raw.actions : [],
    sources: Array.isArray(raw.sources) ? raw.sources : [],
    history: raw.history ?? "local",
    locale: raw.locale ?? "en",
    messages: raw.messages ?? {},
    options: {
      shortcut: raw.options?.shortcut ?? ["mod+k"],
      recent: raw.options?.recent ?? 5,
      help: raw.options?.help ?? true,
      linkActions: raw.options?.linkActions ?? true,
      icons: raw.options?.icons ?? false,
    },
  };
}
