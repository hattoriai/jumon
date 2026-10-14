// Icons from Lucide (https://lucide.dev), ISC licence, for the palette's
// own controls. The icons of actions are the app's (see Jumon.Components).
//
// Each icon is the list of the SVG shapes of one Lucide icon (24 × 24,
// stroke only), copied from the lucide-static package (1.56.0), as in
// Kotoba. `renderIcon` makes the SVG element. The bundle does not import
// Lucide.

type Shape = readonly [tag: "path" | "line" | "rect" | "circle", attributes: Readonly<Record<string, string>>];
export type Icon = readonly Shape[];

/** Lucide `search`: the box. */
export const search: Icon = [
  ["path", { d: "m21 21-4.34-4.34" }],
  ["circle", { cx: "11", cy: "11", r: "8" }],
];

/** Lucide `corner-down-left`: Enter, on the active row. */
export const enter: Icon = [
  ["path", { d: "M20 4v7a4 4 0 0 1-4 4H4" }],
  ["path", { d: "m9 10-5 5 5 5" }],
];

/** Lucide `chevron-right`: an action with a page of its own. */
export const chevron: Icon = [["path", { d: "m9 18 6-6-6-6" }]];

/** Lucide `arrow-left`: back to the page before. */
export const back: Icon = [
  ["path", { d: "m12 19-7-7 7-7" }],
  ["path", { d: "M19 12H5" }],
];

/** Lucide `loader-circle`: a search on the way. */
export const loading: Icon = [["path", { d: "M21 12a9 9 0 1 1-6.219-8.56" }]];

/** Lucide `x`: close. */
export const close: Icon = [
  ["path", { d: "M18 6 6 18" }],
  ["path", { d: "m6 6 12 12" }],
];

/** Lucide `external-link`: open in a new tab. */
export const external: Icon = [
  ["path", { d: "M15 3h6v6" }],
  ["path", { d: "M10 14 21 3" }],
  ["path", { d: "M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6" }],
];

/** Lucide `copy`: copy a link or a text. */
export const copy: Icon = [
  ["rect", { width: "14", height: "14", x: "8", y: "8", rx: "2", ry: "2" }],
  ["path", { d: "M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2" }],
];

/** Lucide `check`: done, and the chosen option. */
export const check: Icon = [["path", { d: "M20 6 9 17l-5-5" }]];

/** Lucide `clock`: a recent action. */
export const recent: Icon = [
  ["circle", { cx: "12", cy: "12", r: "10" }],
  ["path", { d: "M12 6v6l4 2" }],
];

/** Lucide `keyboard`: the keyboard shortcuts. */
export const keyboard: Icon = [
  ["path", { d: "M10 8h.01" }],
  ["path", { d: "M12 12h.01" }],
  ["path", { d: "M14 8h.01" }],
  ["path", { d: "M16 12h.01" }],
  ["path", { d: "M18 8h.01" }],
  ["path", { d: "M6 8h.01" }],
  ["path", { d: "M7 16h10" }],
  ["path", { d: "M8 12h.01" }],
  ["rect", { width: "20", height: "16", x: "2", y: "4", rx: "2" }],
];

/** Lucide `circle-alert`: an error. */
export const alert: Icon = [
  ["circle", { cx: "12", cy: "12", r: "10" }],
  ["line", { x1: "12", x2: "12", y1: "8", y2: "12" }],
  ["line", { x1: "12", x2: "12.01", y1: "16", y2: "16" }],
];

/** Lucide `trash-2`: remove from Recent. */
export const trash: Icon = [
  ["path", { d: "M10 11v6" }],
  ["path", { d: "M14 11v6" }],
  ["path", { d: "M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6" }],
  ["path", { d: "M3 6h18" }],
  ["path", { d: "M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2" }],
];

/** Lucide `ellipsis`: the actions of a result. */
export const more: Icon = [
  ["circle", { cx: "12", cy: "12", r: "1" }],
  ["circle", { cx: "19", cy: "12", r: "1" }],
  ["circle", { cx: "5", cy: "12", r: "1" }],
];

const SVG = "http://www.w3.org/2000/svg";

/** The SVG element of an icon, hidden from screen readers. */
export function renderIcon(icon: Icon, className = "jumon-icon"): SVGSVGElement {
  const svg = document.createElementNS(SVG, "svg");
  svg.setAttribute("viewBox", "0 0 24 24");
  svg.setAttribute("aria-hidden", "true");
  svg.setAttribute("focusable", "false");
  svg.setAttribute("class", className);
  for (const [tag, attributes] of icon) {
    const shape = document.createElementNS(SVG, tag);
    for (const [name, value] of Object.entries(attributes)) shape.setAttribute(name, value);
    svg.appendChild(shape);
  }
  return svg;
}
