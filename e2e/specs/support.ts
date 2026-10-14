// Helpers for the browser tests.

import { expect, type Locator, type Page } from "@playwright/test";

/** Opens a page and waits for the LiveView to connect and the palette to mount. */
export async function openPage(page: Page, path = "/"): Promise<void> {
  await page.goto(path);
  if (!path.startsWith("/plain")) await expect(page.locator("[data-phx-main].phx-connected")).toBeVisible();
  await expect(page.locator(".jumon.jumon-ready")).toBeAttached();
}

/** The modifier of `mod` in this browser's platform. */
export async function mod(page: Page): Promise<string> {
  return (await page.evaluate(() => /mac|iphone|ipad/i.test(navigator.platform))) ? "Meta" : "Control";
}

/** Opens the palette with its shortcut. */
export async function openPalette(page: Page): Promise<Locator> {
  await page.keyboard.press(`${await mod(page)}+k`);
  const dialog = page.locator(".jumon-dialog");
  await expect(dialog).toBeVisible();
  await expect(input(page)).toBeFocused();
  return dialog;
}

export const input = (page: Page): Locator => page.locator(".jumon-input");
export const options = (page: Page): Locator => page.locator(".jumon-list [role=option]");
export const active = (page: Page): Locator => page.locator(".jumon-list [role=option][aria-selected=true]");
export const option = (page: Page, name: string): Locator => page.locator(".jumon-list [role=option]", { has: page.locator(".jumon-item-name", { hasText: new RegExp(`^${name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}$`) }) });

/** The names of the options in view, in order. */
export async function names(page: Page): Promise<string[]> {
  return page.locator(".jumon-list [role=option] .jumon-item-name").allTextContents();
}

/** Types a query and waits for the option `name` to be the active one. */
export async function search(page: Page, query: string, name?: string): Promise<void> {
  await input(page).fill(query);
  if (name) await expect(active(page).locator(".jumon-item-name")).toHaveText(name);
}
