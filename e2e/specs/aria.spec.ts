import { expect, test } from "@playwright/test";
import { active, input, openPage, openPalette } from "./support";

test.beforeEach(async ({ page }) => openPage(page));

test("a modal dialog with a combobox and a listbox", async ({ page }) => {
  await openPalette(page);
  await expect(page.locator("dialog.jumon-dialog")).toHaveAttribute("aria-label", "Command palette");
  const box = input(page);
  await expect(box).toHaveAttribute("role", "combobox");
  await expect(box).toHaveAttribute("aria-expanded", "true");
  await expect(box).toHaveAttribute("aria-autocomplete", "list");
  const list = page.locator(".jumon-list");
  await expect(list).toHaveAttribute("role", "listbox");
  expect(await box.getAttribute("aria-controls")).toBe(await list.getAttribute("id"));
  const activeId = await active(page).getAttribute("id");
  await expect(box).toHaveAttribute("aria-activedescendant", activeId!);
  await expect(active(page)).toHaveAttribute("aria-posinset", "1");
});

test("the number of results is announced", async ({ page }) => {
  await openPalette(page);
  await input(page).fill("people");
  await expect(page.locator(".jumon-sr-only[aria-live]")).toHaveText(/\d+ results?/);
});

test("Tab keeps the focus in the box", async ({ page }) => {
  await openPalette(page);
  await page.keyboard.press("Tab");
  await expect(input(page)).toBeFocused();
});

test("the words of another locale", async ({ page }) => {
  await openPage(page, "/?locale=pt-PT");
  await openPalette(page);
  await expect(input(page)).toHaveAttribute("placeholder", "Escreva um comando ou pesquise…");
  await expect(page.locator(".jumon-footer")).toContainText("Fechar");
});
