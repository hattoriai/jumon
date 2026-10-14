// The Jumon hook for a LiveSocket, and `mountJumon` for a page without
// LiveView. The hook makes a Palette of its element, gives it the server's
// later renders (`updated`) and the state of the connection
// (`disconnected`, `reconnected`), and passes the events of Jumon.Live
// (jumon:results, jumon:open, jumon:close) to it.

import { Palette, type Live } from "./palette";

interface HookContext {
  el: HTMLElement;
  pushEvent(event: string, payload: object, onReply?: (reply: Record<string, unknown>, ref: number) => void): void;
  pushEventTo(target: string | HTMLElement, event: string, payload: object, onReply?: (reply: Record<string, unknown>, ref: number) => void): void;
  handleEvent(event: string, callback: (payload: Record<string, unknown>) => void): void;
  js(): {
    navigate(href: string, opts?: { replace?: boolean }): void;
    patch(href: string, opts?: { replace?: boolean }): void;
    exec(encodedJS: string): void;
  };
}

interface JumonHook extends HookContext {
  palette?: Palette;
}

// The palettes mounted, by the hook or by mountJumon, so that neither
// mounts a second palette on an element.
const mounted = new WeakMap<HTMLElement, Palette>();

export const Jumon = {
  mounted(this: JumonHook) {
    const hook = this;
    const target = hook.el.getAttribute("phx-target");
    const live: Live = {
      push(event, payload, onReply) {
        const reply = onReply ? (response: Record<string, unknown>) => onReply(response) : undefined;
        if (target) hook.pushEventTo(target, event, payload, reply);
        else hook.pushEvent(event, payload, reply);
      },
      pushEvent(event, value, eventTarget) {
        if (eventTarget) hook.pushEventTo(eventTarget, event, value);
        else hook.pushEvent(event, value);
      },
      navigate(to, replace) {
        hook.js().navigate(to, { replace });
      },
      patch(to, replace) {
        hook.js().patch(to, { replace });
      },
      exec(js) {
        hook.js().exec(js);
      },
    };
    hook.palette = new Palette(hook.el, live);
    mounted.set(hook.el, hook.palette);

    hook.handleEvent("jumon:results", (payload) => hook.palette?.receiveResults(payload));
    hook.handleEvent("jumon:open", (payload) => {
      if (!payload.id || payload.id === hook.palette?.id) hook.palette?.open({ query: payload.query as string | null, page: payload.page as string | null });
    });
    hook.handleEvent("jumon:close", (payload) => {
      if (!payload.id || payload.id === hook.palette?.id) hook.palette?.close();
    });
  },

  updated(this: JumonHook) {
    this.palette?.update();
  },

  disconnected(this: JumonHook) {
    this.palette?.setConnected(false);
  },

  reconnected(this: JumonHook) {
    this.palette?.setConnected(true);
  },

  destroyed(this: JumonHook) {
    this.palette?.destroy();
    mounted.delete(this.el);
    this.palette = undefined;
  },
};

/**
 * Mounts the palettes under `root` on a page without a LiveSocket (a
 * controller's template): the actions that navigate, open links, run JS
 * commands or copy, with no server. Returns them; a palette already
 * mounted (by an earlier call, or by the hook) is skipped.
 */
export function mountJumon(root: ParentNode = document): Palette[] {
  const palettes: Palette[] = [];
  for (const element of root.querySelectorAll<HTMLElement>('[phx-hook="Jumon"]')) {
    if (mounted.has(element)) continue;
    const palette = new Palette(element, null);
    mounted.set(element, palette);
    palettes.push(palette);
  }
  return palettes;
}
